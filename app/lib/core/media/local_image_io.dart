import 'dart:io';
import 'package:flutter/material.dart';

/// Renders a `file://` image on platforms with dart:io.
Widget koraLocalImage(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) =>
    Image.file(
      File(path),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
