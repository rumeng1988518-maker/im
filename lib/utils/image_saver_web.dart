// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> saveImageToDevice(String url) async {
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', 'image_${DateTime.now().millisecondsSinceEpoch}.jpg')
    ..setAttribute('target', '_blank');
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
}
