import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';

Future<void> saveImageToDevice(String url, {bool isVideo = false}) async {
  final response = await Dio().get<List<int>>(
    url,
    options: Options(responseType: ResponseType.bytes),
  );
  final bytes = Uint8List.fromList(response.data!);
  final dir = await getTemporaryDirectory();
  final String ext;
  if (isVideo) {
    ext = url.contains('.mov') ? '.mov' : '.mp4';
  } else {
    ext = url.contains('.png') ? '.png' : '.jpg';
  }
  final file = File('${dir.path}/save_${DateTime.now().millisecondsSinceEpoch}$ext');
  await file.writeAsBytes(bytes);
  if (isVideo) {
    await Gal.putVideo(file.path);
  } else {
    await Gal.putImage(file.path);
  }
}
