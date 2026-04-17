import 'dart:js_interop';

@JS('window._playNotificationSound')
external void _playNotificationSound();

void playNotificationSound() {
  try {
    _playNotificationSound();
  } catch (_) {}
}
