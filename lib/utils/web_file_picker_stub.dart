import 'dart:typed_data';

class PickedFileData {
  final String name;
  final Uint8List bytes;
  final String mimeType;
  PickedFileData({required this.name, required this.bytes, required this.mimeType});
}

Future<List<PickedFileData>> pickImagesFromWeb({int maxCount = 9}) async => [];

Future<PickedFileData?> pickVideoFromWeb() async => null;

Future<PickedFileData?> readBinaryFromWebUrl(
  String source, {
  String defaultName = 'file.bin',
  String defaultMimeType = 'application/octet-stream',
}) async => null;
