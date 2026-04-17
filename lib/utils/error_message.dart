import 'dart:convert';

import 'package:dio/dio.dart';

class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ErrorMessage {
  static String from(Object error, {String fallback = '操作失败，请稍后重试'}) {
    if (error is AppException) {
      return _normalize(error.message, fallback: fallback);
    }
    if (error is DioException) {
      return fromDio(error, fallback: fallback);
    }

    final raw = error.toString().trim();
    if (raw.isEmpty) return fallback;

    return _normalize(raw, fallback: fallback);
  }

  static String fromDio(DioException error, {String fallback = '网络开小差了，请稍后重试'}) {
    final path = error.requestOptions.path;
    final statusCode = error.response?.statusCode;
    final respMessage = _extractResponseMessage(error.response?.data);

    if (respMessage != null && respMessage.isNotEmpty) {
      return _mapKnownMessages(respMessage, path: path, statusCode: statusCode, fallback: fallback);
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '网络超时，请检查网络后重试';
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络后重试';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.badCertificate:
        return '安全证书校验失败，请稍后重试';
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break;
    }

    if (statusCode != null) {
      final mapped = _mapByStatus(statusCode, path: path);
      if (mapped != null) return mapped;
    }

    final dioMessage = error.message?.trim();
    if (dioMessage != null && dioMessage.isNotEmpty) {
      return _mapKnownMessages(dioMessage, path: path, statusCode: statusCode, fallback: fallback);
    }

    return fallback;
  }

  static String? _extractResponseMessage(dynamic data) {
    if (data is Map) {
      final msg = data['message']?.toString().trim();
      if (msg != null && msg.isNotEmpty) return msg;
      final err = data['error']?.toString().trim();
      if (err != null && err.isNotEmpty) return err;
    }

    if (data is String) {
      final text = data.trim();
      if (text.isEmpty) return null;
      if (text.startsWith('{') && text.endsWith('}')) {
        try {
          final jsonData = jsonDecode(text);
          if (jsonData is Map) {
            final msg = jsonData['message']?.toString().trim();
            if (msg != null && msg.isNotEmpty) return msg;
          }
        } catch (_) {
          return text;
        }
      }
      return text;
    }

    return null;
  }

  static String _normalize(String text, {required String fallback}) {
    var msg = text.trim();
    msg = msg.replaceFirst(RegExp(r'^Unhandled Exception:\s*', caseSensitive: false), '');
    msg = msg.replaceFirst(RegExp(r'^Exception:\s*', caseSensitive: false), '');
    msg = msg.replaceFirst(RegExp(r'^DioException:\s*', caseSensitive: false), '');

    if (msg.isEmpty) return fallback;
    return _mapKnownMessages(msg, path: null, statusCode: null, fallback: fallback);
  }

  static String _mapKnownMessages(
    String message, {
    required String? path,
    required int? statusCode,
    required String fallback,
  }) {
    final msg = message.trim();
    if (msg.isEmpty) return fallback;

    final lower = msg.toLowerCase();

    if (lower.contains('d ioexception') || lower.startsWith('dioexception')) {
      return statusCode != null ? (_mapByStatus(statusCode, path: path) ?? fallback) : fallback;
    }

    if (lower.contains('xmlhttprequest error') ||
        lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable')) {
      return '网络连接失败，请检查网络后重试';
    }

    if (lower.contains('timed out') || lower.contains('timeout')) {
      return '网络超时，请检查网络后重试';
    }

    if (lower == 'unauthorized' || lower.contains('status code of 401')) {
      return _mapByStatus(401, path: path) ?? '登录状态已失效，请重新登录';
    }

    if (lower.contains('status code of 403')) {
      return _mapByStatus(403, path: path) ?? '当前操作无权限';
    }

    if (lower.contains('status code of 404')) {
      return _mapByStatus(404, path: path) ?? '请求的资源不存在';
    }

    if (lower.contains('status code of 429')) {
      return '操作过于频繁，请稍后再试';
    }

    if (lower.contains('status code of 500')) {
      return _mapByStatus(500, path: path) ?? '服务器开小差了，请稍后重试';
    }

    if (msg.length > 200) {
      return statusCode != null ? (_mapByStatus(statusCode, path: path) ?? fallback) : fallback;
    }

    return msg;
  }

  static String? _mapByStatus(int statusCode, {String? path}) {
    if (statusCode == 401) {
      if (path != null && path.contains('/auth/login')) {
        return '手机号或密码错误，请重新输入';
      }
      return '登录状态已失效，请重新登录';
    }

    switch (statusCode) {
      case 400:
        return '请求参数有误，请检查后重试';
      case 403:
        return '当前操作无权限';
      case 404:
        return '请求的资源不存在';
      case 409:
        return '数据状态冲突，请刷新后重试';
      case 429:
        return '操作过于频繁，请稍后再试';
      case 500:
      case 502:
      case 503:
      case 504:
        return '服务器开小差了，请稍后重试';
      default:
        return null;
    }
  }
}