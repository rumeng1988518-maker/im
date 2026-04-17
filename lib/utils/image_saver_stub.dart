import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';

Future<void> saveImageToDevice(String url) async {
  final response = await Dio().get<List<int>>(
    url,
    options: Options(responseType: ResponseType.bytes),
  );
  final bytes = Uint8List.fromList(response.data!);
  final dir = await getTemporaryDirectory();
  final ext = url.contains('.png') ? '.png' : '.jpg';
  final file = File('${dir.path}/save_${DateTime.now().millisecondsSinceEpoch}$ext');
  await file.writeAsBytes(bytes);
  await Gal.putImage(file.path);
}
