import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Manages APNs device token registration on iOS.
/// Uses a native MethodChannel to register for remote notifications
/// and retrieve the device token.
class PushTokenService {
  static const _channel = MethodChannel('im.client/push');
  static String? _cachedToken;

  /// Get the APNs device token. Returns null on non-iOS platforms or if unavailable.
  static Future<String?> getToken() async {
    if (kIsWeb || !Platform.isIOS) return null;
    try {
      final token = await _channel.invokeMethod<String>('getDeviceToken');
      if (token != null && token.isNotEmpty) {
        _cachedToken = token;
      }
      return _cachedToken;
    } catch (e) {
      debugPrint('[PushToken] getToken error: $e');
      return _cachedToken;
    }
  }

  /// Get cached token without calling native
  static String? get cachedToken => _cachedToken;
}
