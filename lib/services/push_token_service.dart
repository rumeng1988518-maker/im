import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Manages push token registration.
/// - iOS: APNs device token via native MethodChannel
/// - Android: FCM token via firebase_messaging
class PushTokenService {
  static const _channel = MethodChannel('im.client/push');
  static String? _cachedToken;
  static String? _platform;

  /// Get the push token for the current platform.
  static Future<String?> getToken() async {
    if (kIsWeb) return null;
    try {
      if (Platform.isAndroid) {
        _platform = 'android';
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          _cachedToken = token;
        }
        return _cachedToken;
      } else if (Platform.isIOS) {
        _platform = 'ios';
        final token = await _channel.invokeMethod<String>('getDeviceToken');
        if (token != null && token.isNotEmpty) {
          _cachedToken = token;
        }
        return _cachedToken;
      }
    } catch (e) {
      debugPrint('[PushToken] getToken error: $e');
    }
    return _cachedToken;
  }

  /// Listen for token refresh (Android FCM can rotate tokens)
  static void onTokenRefresh(void Function(String token) callback) {
    if (kIsWeb) return;
    if (!kIsWeb && Platform.isAndroid) {
      FirebaseMessaging.instance.onTokenRefresh.listen(callback);
    }
  }

  static String? get cachedToken => _cachedToken;
  static String get platform => _platform ?? (Platform.isIOS ? 'ios' : 'android');
}
