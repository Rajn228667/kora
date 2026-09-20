import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Compact BlurHash decoder adapted from the open-source
/// woltapp/blurhash reference implementation (MIT license).
/// Decodes to a small [ui.Image] used as a placeholder while the
/// real image loads.
abstract final class KoraBlurHash {
  static const _alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#\$%*+,-.:;=?@[]^_{|}~';
  static final Map<String, ui.Image> _cache = {};

  static Future<ui.Image?> decode(String hash,
      {int width = 32, int height = 32,}) async {
    if (_cache.containsKey(hash)) return _cache[hash];
    try {
      final img = await _decode(hash, width, height);
      if (img != null) _cache[hash] = img;
      return img;
    } catch (_) {
      return null;
    }
  }

  static int _decode83(String s) {
    var v = 0;
    for (final ch in s.codeUnits) {
      v = v * 83 + _alphabet.indexOf(String.fromCharCode(ch));
    }
    return v;
  }

  static double _srgbToLinear(int v) {
    final x = v / 255;
    return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4).toDouble();
  }

  static int _linearToSrgb(double v) {
    final x = v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055;
    return (x * 255 + 0.5).clamp(0, 255).toInt();
  }

  static double _signPow(double v, double e) =>
      v.sign * pow(v.abs(), e).toDouble();

  static Future<ui.Image?> _decode(String hash, int w, int h) async {
    if (hash.length < 6) return null;
    final sizeFlag = _decode83(hash[0]);
    final numX = (sizeFlag % 9) + 1;
    final numY = (sizeFlag ~/ 9) + 1;
    if (hash.length != 4 + 2 * numX * numY) return null;
    final maxAc = (_decode83(hash[1]) + 1) / 166;

    final colors = List<List<double>>.filled(numX * numY, const [0, 0, 0]);
    final dc = _decode83(hash.substring(2, 6));
    colors[0] = [
      _srgbToLinear((dc >> 16) & 255),
      _srgbToLinear((dc >> 8) & 255),
      _srgbToLinear(dc & 255),
    ];
    for (var i = 1; i < colors.length; i++) {
      final v = _decode83(hash.substring(4 + i * 2, 6 + i * 2));
      final qr = v ~/ (19 * 19);
      final qg = (v ~/ 19) % 19;
      final qb = v % 19;
      colors[i] = [
        _signPow((qr - 9) / 9, 2) * maxAc,
        _signPow((qg - 9) / 9, 2) * maxAc,
        _signPow((qb - 9) / 9, 2) * maxAc,
      ];
    }

    final pixels = Uint8List(w * h * 4);
    var p = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var r = 0.0, g = 0.0, b = 0.0;
        for (var j = 0; j < numY; j++) {
          for (var i = 0; i < numX; i++) {
            final basis =
                cos(pi * x * i / w) * cos(pi * y * j / h);
            final c = colors[i + j * numX];
            final scale = (i == 0 && j == 0) ? 1.0 : 2.0;
            r += c[0] * basis * scale;
            g += c[1] * basis * scale;
            b += c[2] * basis * scale;
          }
        }
        pixels[p++] = _linearToSrgb(r);
        pixels[p++] = _linearToSrgb(g);
        pixels[p++] = _linearToSrgb(b);
        pixels[p++] = 255;
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
