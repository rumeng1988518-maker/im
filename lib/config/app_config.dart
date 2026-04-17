import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

class AppConfig {
  static const String _serverHost = 'http://localhost:3000';

  static const String _prodHost = 'https://im.excoin.one';

  static String get serverHost {
    if (kIsWeb) return kDebugMode ? _serverHost : Uri.base.origin;
    return kDebugMode ? 'http://10.0.2.2:3000' : _prodHost;
  }

  static String get baseUrl {
    if (kIsWeb) {
      // 开发模式用完整地址（Flutter dev server 端口不同），生产模式用相对路径
      return kDebugMode ? '$_serverHost/api/v1' : '/api/v1';
    }
    return kDebugMode
        ? 'http://10.0.2.2:3000/api/v1'
        : '$_prodHost/api/v1';
  }

  static String get wsUrl {
    if (kIsWeb) return kDebugMode ? _serverHost : Uri.base.origin;
    return kDebugMode ? 'http://10.0.2.2:3000' : _prodHost;
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
