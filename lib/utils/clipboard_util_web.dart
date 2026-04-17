import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<void> copyToClipboard(String text) async {
  await web.window.navigator.clipboard.writeText(text).toDart;
}
