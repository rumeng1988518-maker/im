// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class PickedFileData {
  final String name;
  final Uint8List bytes;
  final String mimeType;
  PickedFileData({required this.name, required this.bytes, required this.mimeType});
}

Future<Uint8List> _readFileAsBytes(html.File file) {
  final completer = Completer<Uint8List>();
  final reader = html.FileReader();
  reader.onLoadEnd.listen((_) {
    final result = reader.result;
    if (result is ByteBuffer) {
      completer.complete(result.asUint8List());
    } else if (result is Uint8List) {
      completer.complete(result);
    } else {
      completer.completeError('FileReader returned unexpected type');
    }
  });
  reader.onError.listen((_) {
    completer.completeError('FileReader error: ${reader.error?.message}');
  });
  reader.readAsArrayBuffer(file);
  return completer.future;
}

Future<Uint8List> _readBlobAsBytes(html.Blob blob) {
  final completer = Completer<Uint8List>();
  final reader = html.FileReader();
  reader.onLoadEnd.listen((_) {
    final result = reader.result;
    if (result is ByteBuffer) {
      completer.complete(result.asUint8List());
    } else if (result is Uint8List) {
      completer.complete(result);
    } else {
      completer.completeError('FileReader returned unexpected blob result type');
    }
  });
  reader.onError.listen((_) {
    completer.completeError('FileReader error: ${reader.error?.message}');
  });
  reader.readAsArrayBuffer(blob);
  return completer.future;
}

Future<List<PickedFileData>> pickImagesFromWeb({int maxCount = 9}) async {
  final completer = Completer<List<html.File>>();
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..multiple = true;

  // Listen for file selection
  input.onChange.listen((_) {
    final files = input.files;
    completer.complete(files != null ? files.toList() : []);
  });

  // Handle cancel (blur event on window after a delay)
  bool selected = false;
  input.onChange.listen((_) => selected = true);
  // Use a focus listener as cancel detection
  html.window.addEventListener('focus', (_) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!selected && !completer.isCompleted) {
        completer.complete([]);
      }
    });
  });

  input.click();

  final htmlFiles = await completer.future;
  if (htmlFiles.isEmpty) return [];

  final capped = htmlFiles.take(maxCount).toList();
  final results = <PickedFileData>[];

  for (final file in capped) {
    final bytes = await _readFileAsBytes(file);
    results.add(PickedFileData(
      name: file.name,
      bytes: bytes,
      mimeType: file.type.isNotEmpty ? file.type : 'image/jpeg',
    ));
  }

  return results;
}

Future<PickedFileData?> pickVideoFromWeb() async {
  final completer = Completer<List<html.File>>();
  final input = html.FileUploadInputElement()
    ..accept = 'video/*';

  input.onChange.listen((_) {
    final files = input.files;
    completer.complete(files != null ? files.toList() : []);
  });

  bool selected = false;
  input.onChange.listen((_) => selected = true);
  html.window.addEventListener('focus', (_) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!selected && !completer.isCompleted) {
        completer.complete([]);
      }
    });
  });

  input.click();

  final htmlFiles = await completer.future;
  if (htmlFiles.isEmpty) return null;

  final file = htmlFiles.first;
  final bytes = await _readFileAsBytes(file);

  return PickedFileData(
    name: file.name,
    bytes: bytes,
    mimeType: file.type.isNotEmpty ? file.type : 'video/mp4',
  );
}

Future<PickedFileData?> readBinaryFromWebUrl(
  String source, {
  String defaultName = 'file.bin',
  String defaultMimeType = 'application/octet-stream',
}) async {
  if (source.isEmpty) return null;

  if (source.startsWith('data:')) {
    final uriData = Uri.tryParse(source)?.data;
    if (uriData == null) {
      throw Exception('无法解析录音数据');
    }
    final mime = uriData.mimeType.trim().isNotEmpty ? uriData.mimeType : defaultMimeType;
    return PickedFileData(
      name: _guessNameByMime(defaultName, mime),
      bytes: uriData.contentAsBytes(),
      mimeType: mime,
    );
  }

  try {
    final req = await html.HttpRequest.request(
      source,
      method: 'GET',
      responseType: 'blob',
    );

    final response = req.response;
    if (response is html.Blob) {
      final bytes = await _readBlobAsBytes(response);
      final headerMime = (req.getResponseHeader('content-type') ?? '').split(';').first.trim();
      final blobMime = response.type ?? '';
      final mime = blobMime.isNotEmpty
          ? blobMime
          : (headerMime.isNotEmpty ? headerMime : defaultMimeType);
      return PickedFileData(
        name: _guessNameByMime(defaultName, mime),
        bytes: bytes,
        mimeType: mime,
      );
    }

    if (response is ByteBuffer) {
      final bytes = response.asUint8List();
      return PickedFileData(
        name: _guessNameByMime(defaultName, defaultMimeType),
        bytes: bytes,
        mimeType: defaultMimeType,
      );
    }
  } catch (_) {
    // Fall through to fetch-based strategy.
  }

  try {
    final resp = await html.window.fetch(source);
    if (!resp.ok) {
      throw Exception('fetch failed with status ${resp.status}');
    }
    final blob = await resp.blob();
    final bytes = await _readBlobAsBytes(blob);
    final mime = (blob.type ?? '').trim().isNotEmpty ? blob.type! : defaultMimeType;
    return PickedFileData(
      name: _guessNameByMime(defaultName, mime),
      bytes: bytes,
      mimeType: mime,
    );
  } catch (e) {
    throw Exception('无法读取录音数据，请重试或关闭浏览器隐私限制');
  }
}

String _guessNameByMime(String defaultName, String mimeType) {
  final lower = mimeType.toLowerCase();
  if (lower.contains('webm')) return 'voice.webm';
  if (lower.contains('mp4') || lower.contains('m4a')) return 'voice.m4a';
  if (lower.contains('ogg')) return 'voice.ogg';
  if (lower.contains('mpeg') || lower.contains('mp3')) return 'voice.mp3';
  return defaultName;
}
