import 'package:flutter/foundation.dart' show kIsWeb;
import 'notification_sound_stub.dart'
    if (dart.library.html) 'notification_sound_web.dart' as platform;

class NotificationSound {
  static void play() {
    if (kIsWeb) {
      platform.playNotificationSound();
    }
  }
}
