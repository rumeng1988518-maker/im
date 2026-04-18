import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'notification_sound_stub.dart'
    if (dart.library.html) 'notification_sound_web.dart' as platform;

class NotificationSound {
  static void play() {
    if (kIsWeb) {
      platform.playNotificationSound();
    } else {
      // 移动端：触发系统触觉反馈作为即时提示
      HapticFeedback.mediumImpact();
    }
  }
}
