import 'dart:async';
import 'package:dio/dio.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/utils/error_message.dart';

class ApiClient {
  late final Dio _dio;
  final AuthService _auth;
  bool _refreshing = false;
  final List<_QueuedRequest> _pendingRequests = [];

  String get baseUrl => _dio.options.baseUrl;

  ApiClient(this._auth, {required String baseUrl}) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'IMClient/1.0',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _auth.token;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        final data = response.data;
        if (data is Map) {
          final code = data['code'];
          if (code == 40101 || code == 40102 || code == 40103) {
            // Token 过期/无效 → 尝试刷新
            handler.reject(DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              message: data['message']?.toString() ?? '登录状态已失效',
            ));
            return;
          }
          if (code != 200) {
            handler.reject(DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              message: data['message']?.toString() ?? '请求失败',
            ));
            return;
          }
        }
        handler.next(response);
      },
      onError: (error, handler) async {
        // 检查是否是 token 过期错误（需要刷新）
        final isAuthError = _isTokenExpiredError(error);
        // 排除刷新请求本身，避免循环
        final isRefreshCall = error.requestOptions.path.contains('/auth/token/refresh');

        if (isAuthError && !isRefreshCall && _auth.refreshToken != null) {
          try {
            final retryResponse = await _retryWithRefresh(error.requestOptions);
            handler.resolve(retryResponse);
            return;
          } catch (_) {
            // 刷新失败 → 走 logout 流程
            _auth.logout();
            handler.reject(
              error.copyWith(
                message: '登录已过期，请重新登录',
                error: AppException('登录已过期，请重新登录'),
              ),
            );
            return;
          }
        }

        // 非 token 错误，正常处理
        if (isAuthError) {
          _auth.logout();
        }

        final message = ErrorMessage.fromDio(error);
        handler.reject(
          error.copyWith(
            message: message,
            error: AppException(message),
          ),
        );
      },
    ));
  }

  bool _isTokenExpiredError(DioException error) {
    final body = error.response?.data;
    if (body is Map) {
      final code = body['code'];
      return code == 40101 || code == 40102 || code == 40103;
    }
    return false;
  }

  Future<Response> _retryWithRefresh(RequestOptions requestOptions) async {
    if (_refreshing) {
      // 另一个请求已在刷新，排队等待
      final completer = Completer<Response>();
      _pendingRequests.add(_QueuedRequest(requestOptions, completer));
      return completer.future;
    }

    _refreshing = true;
    try {
      // 用独立 Dio 实例发送 refresh 请求，避免被拦截器递归
      final refreshDio = Dio(BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

      final resp = await refreshDio.post('/auth/token/refresh', data: {
        'refreshToken': _auth.refreshToken,
      });

      final data = resp.data;
      if (data is Map && data['code'] == 200 && data['data'] != null) {
        final newAccess = data['data']['accessToken'] as String;
        final newRefresh = data['data']['refreshToken'] as String;
        await _auth.updateTokens(newAccess, newRefresh);

        // 重试原始请求
        requestOptions.headers['Authorization'] = 'Bearer $newAccess';
        final retryResp = await _dio.fetch(requestOptions);

        // 处理排队的请求
        for (final queued in _pendingRequests) {
          queued.options.headers['Authorization'] = 'Bearer $newAccess';
          _dio.fetch(queued.options).then(
            (r) => queued.completer.complete(r),
            onError: (e) => queued.completer.completeError(e),
          );
        }
        _pendingRequests.clear();

        return retryResp;
      } else {
        throw Exception('Refresh failed');
      }
    } catch (e) {
      // 刷新失败，拒绝所有排队请求
      for (final queued in _pendingRequests) {
        queued.completer.completeError(e);
      }
      _pendingRequests.clear();
      rethrow;
    } finally {
      _refreshing = false;
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? params}) async {
    return _safeRequest(() => _dio.get(path, queryParameters: params));
  }

  Future<dynamic> post(String path, {dynamic data}) async {
    return _safeRequest(() => _dio.post(path, data: data));
  }

  Future<dynamic> upload(String path, FormData formData, {void Function(int, int)? onSendProgress}) async {
    return _safeRequest(
      () => _dio.post(
        path,
        data: formData,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
        onSendProgress: onSendProgress,
      ),
    );
  }

  Future<dynamic> put(String path, {dynamic data}) async {
    return _safeRequest(() => _dio.put(path, data: data));
  }

  Future<dynamic> delete(String path) async {
    return _safeRequest(() => _dio.delete(path));
  }

  Future<dynamic> _safeRequest(Future<Response<dynamic>> Function() request) async {
    // 网络超时/连接错误自动重试 1 次（对 POST 也安全，服务端有 clientMsgId 幂等）
    for (int attempt = 0; attempt <= 1; attempt++) {
      try {
        final resp = await request();
        final data = resp.data;
        if (data is Map) {
          return data['data'];
        }
        return data;
      } on DioException catch (e) {
        if (attempt < 1 && _isRetryable(e)) {
          await Future.delayed(const Duration(milliseconds: 800));
          continue;
        }
        throw AppException(ErrorMessage.fromDio(e));
      } catch (e) {
        throw AppException(ErrorMessage.from(e));
      }
    }
    throw AppException('请求失败');
  }

  bool _isRetryable(DioException e) {
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError;
  }
}

class _QueuedRequest {
  final RequestOptions options;
  final Completer<Response> completer;
  _QueuedRequest(this.options, this.completer);
}
