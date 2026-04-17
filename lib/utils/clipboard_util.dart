import 'package:flutter/services.dart';
import 'clipboard_util_stub.dart'
    if (dart.library.html) 'clipboard_util_web.dart' as platform;

class ClipboardUtil {
  static Future<void> copy(String text) async {
    try {
      await platform.copyToClipboard(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }
}
