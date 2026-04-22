import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String _devHost = 'http://localhost:3000';

  /// 按优先级排列的生产服务器地址，依次尝试直到某个 /health 可达
  static const List<String> prodHosts = [
    'https://im.excoin.one',
    // 备用域名（注册后在此追加，无需改其他代码）：
    'https://im.pocoin.top',
    // 直接 IP 兜底：
    // 'http://194.41.37.151:3201',
  ];

  static String _resolvedHost = prodHosts.first;

  /// 当前使用的线路编号（1-based），0 表示未检测完
  static int resolvedLineIndex = 0;

  /// 当前线路延迟（毫秒），-1 表示未检测完
  static int resolvedLatencyMs = -1;

  /// 由 main() 在 runApp 前写入探活结果
  static void setHost(String host) {
    _resolvedHost = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
  }

  /// 启动时顺序探活，5s 超时，记录线路编号和延迟
  static Future<void> resolveHost() async {
    if (kIsWeb || kDebugMode) return;

    // 先用上次缓存的地址（加速冷启动）
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('resolved_host');
      if (cached != null && cached.isNotEmpty) _resolvedHost = cached;
    } catch (_) {}

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ));

    for (int i = 0; i < prodHosts.length; i++) {
      final host = prodHosts[i];
      try {
        final sw = Stopwatch()..start();
        final res = await dio.get('$host/health');
        sw.stop();
        if (res.statusCode == 200) {
          setHost(host);
          resolvedLineIndex = i + 1;
          resolvedLatencyMs = sw.elapsedMilliseconds;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('resolved_host', host);
          return;
        }
      } catch (_) {
        continue;
      }
    }
    // 全部失败：沿用已有的 _resolvedHost（缓存或第一个地址）
    resolvedLineIndex = 0;
    resolvedLatencyMs = -1;
  }

  static String get serverHost {
    if (kIsWeb) return kDebugMode ? _devHost : Uri.base.origin;
    return kDebugMode ? 'http://10.0.2.2:3000' : _resolvedHost;
  }

  static String get baseUrl {
    if (kIsWeb) {
      return kDebugMode ? '$_devHost/api/v1' : '/api/v1';
    }
    return kDebugMode ? 'http://10.0.2.2:3000/api/v1' : '$_resolvedHost/api/v1';
  }

  static String get wsUrl {
    if (kIsWeb) return kDebugMode ? _devHost : Uri.base.origin;
    return kDebugMode ? 'http://10.0.2.2:3000' : _resolvedHost;
  }

  static String resolveFileUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '$serverHost$url';
    return '$serverHost/$url';
  }

  static const String appName = '内部通';
  static const String version = '1.0.0';
}
