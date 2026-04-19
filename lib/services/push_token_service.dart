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
  static void Function(String token)? _onTokenCallback;
  static bool _iOSListenerSetup = false;

  /// Get the push token for the current platform.
  static Future<String?> getToken() async {
    if (kIsWeb) return null;
    try {
      if (Platform.isAndroid) {
        _platform = 'android';
        final token = await FirebaseMessaging.instance.getToken();
        debugPrint('[PushToken] Android FCM token: ${token?.substring(0, 8) ?? 'null'}...');
        if (token != null && token.isNotEmpty) {
          _cachedToken = token;
        }
        return _cachedToken;
      } else if (Platform.isIOS) {
        _platform = 'ios';
        // Set up native → Flutter listener for token arrival
        _setupIOSListener();
        final token = await _channel.invokeMethod<String>('getDeviceToken');
        debugPrint('[PushToken] iOS APNs token: ${token != null ? '${token.substring(0, 8)}...' : 'null'}');
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

  /// Set up iOS native → Flutter listener for late token arrival
  static void _setupIOSListener() {
    if (_iOSListenerSetup) return;
    _iOSListenerSetup = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onTokenReceived') {
        final token = call.arguments as String?;
        if (token != null && token.isNotEmpty) {
          debugPrint('[PushToken] iOS native pushed token: ${token.substring(0, 8)}...');
          _cachedToken = token;
          _onTokenCallback?.call(token);
        }
      }
    });
  }

  /// Listen for token refresh (Android FCM can rotate tokens; iOS native push)
  static void onTokenRefresh(void Function(String token) callback) {
    _onTokenCallback = callback;
    if (kIsWeb) return;
    if (!kIsWeb && Platform.isAndroid) {
      FirebaseMessaging.instance.onTokenRefresh.listen(callback);
    }
    // iOS: _setupIOSListener handles native push via _onTokenCallback
  }

  static String? get cachedToken => _cachedToken;
  static String get platform => _platform ?? (Platform.isIOS ? 'ios' : 'android');
}
