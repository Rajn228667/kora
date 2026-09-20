import 'dart:convert';
import 'dart:typed_data';

/// Web fallback — no filesystem; returns a `data:` URI that
/// [KoraImage] renders via Image.memory.
Future<String> koraSavePng(Uint8List bytes, String prefix) async =>
    'data:image/png;base64,${base64Encode(bytes)}';
