import 'dart:io';
import 'dart:typed_data';

/// Saves PNG bytes to the temp dir, returns a `file://` URL.
Future<String> koraSavePng(Uint8List bytes, String prefix) async {
  final f = File(
    '${Directory.systemTemp.path}/'
    '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png',
  );
  await f.writeAsBytes(bytes);
  return 'file://${f.path}';
}
