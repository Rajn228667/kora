import 'dart:convert';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../config/env.dart';
import '../theme/app_icons.dart';
import '../theme/app_metrics.dart';
import '../theme/kora_colors.dart';
import 'blur_hash.dart';
import 'local_image.dart';

/// Image with BlurHash placeholder → cached network image →
/// graceful error tile. Used for products, stores, banners, avatars.
class KoraImage extends StatelessWidget {
  const KoraImage({
    super.key,
    this.url,
    this.blurHash,
    this.width,
    this.height,
    this.borderRadius = 0,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final String? blurHash;
  final double? width;
  final double? height;
  final double borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (url == null || url!.isEmpty) {
      child = _placeholder();
    } else if (url!.startsWith('asset:')) {
      child = Image.asset(
        url!.substring(6),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else if (url!.startsWith('file://')) {
      // Local file picked in the admin catalog editor (native only).
      child = koraLocalImage(
        url!.substring(7),
        width: width,
        height: height,
        fit: fit,
      );
    } else if (url!.startsWith('data:')) {
      // In-memory PNG produced by the card generator on web.
      child = Image.memory(
        base64Decode(url!.split(',').last),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else {
      // Relative media paths (`/v1/media/…`) resolve against the API host.
      final resolved = url!.startsWith('/') ? '${AppEnv.apiUrl}$url' : url!;
      child = CachedNetworkImage(
        imageUrl: resolved,
        width: width,
        height: height,
        fit: fit,
        placeholder: (_, __) => _blurOrTile(),
        errorWidget: (_, __, ___) => _placeholder(),
        fadeInDuration: const Duration(milliseconds: 200),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  Widget _blurOrTile() {
    if (blurHash == null) return _tile();
    return FutureBuilder<ui.Image?>(
      future: KoraBlurHash.decode(blurHash!),
      builder: (context, snap) {
        final img = snap.data;
        if (img == null) return _tile();
        return RawImage(image: img, fit: BoxFit.cover);
      },
    );
  }

  Widget _tile() => Container(
        color: KoraColors.surfaceAlt,
        width: width,
        height: height,
      );

  Widget _placeholder() => Container(
        width: width,
        height: height,
        decoration: const BoxDecoration(
          gradient: KoraColors.softGradient,
        ),
        child: Center(
          child: Icon(
            AppIcons.store,
            color: KoraColors.white.withValues(alpha: 0.85),
            size: (width != null && width! < 80) ? 22 : 34,
          ),
        ),
      );
}

/// Standard product tile placeholder with icon inside radius md.
class KoraImageTile extends StatelessWidget {
  const KoraImageTile({super.key, this.url, this.blurHash, this.size = 72});

  final String? url;
  final String? blurHash;
  final double size;

  @override
  Widget build(BuildContext context) {
    return KoraImage(
      url: url,
      blurHash: blurHash,
      width: size,
      height: size,
      borderRadius: AppRadius.md,
    );
  }
}
