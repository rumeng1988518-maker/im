// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> saveImageToDevice(String url, {bool isVideo = false}) async {
  final ext = isVideo ? 'mp4' : 'jpg';
  final prefix = isVideo ? 'video' : 'image';
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext')
    ..setAttribute('target', '_blank');
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
