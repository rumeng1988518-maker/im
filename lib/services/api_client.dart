import 'package:dio/dio.dart';
import 'package:im_client/services/auth_service.dart';
import 'package:im_client/utils/error_message.dart';

class ApiClient {
  late final Dio _dio;
  final AuthService _auth;

  String get baseUrl => _dio.options.baseUrl;

  ApiClient(this._auth, {required String baseUrl}) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
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
            // 仅当请求携带的 token 与当前 token 一致时才清除登录态
            // 防止旧会话的过期响应清除新 token
            final reqToken = response.requestOptions.headers['Authorization'];
            final curToken = _auth.token;
            if (curToken == null || reqToken == 'Bearer $curToken') {
              _auth.logout();
            }
            handler.reject(DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              message: '登录状态已失效，请重新登录',
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
      onError: (error, handler) {
        final body = error.response?.data;
        if (body is Map) {
          final code = body['code'];
          if (code == 40101 || code == 40102 || code == 40103) {
            final reqToken = error.requestOptions.headers['Authorization'];
            final curToken = _auth.token;
            if (curToken == null || reqToken == 'Bearer $curToken') {
              _auth.logout();
            }
          }
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
    try {
      final resp = await request();
      final data = resp.data;
      if (data is Map) {
        return data['data'];
      }
      return data;
    } on DioException catch (e) {
      throw AppException(ErrorMessage.fromDio(e));
    } catch (e) {
      throw AppException(ErrorMessage.from(e));
    }
  }
}
