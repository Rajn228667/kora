import 'package:flutter/material.dart';
import '../theme/kora_colors.dart';

/// Web fallback — `file://` URLs don't exist in the browser.
Widget koraLocalImage(
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
}) =>
    Container(
      width: width,
      height: height,
      color: KoraColors.surfaceAlt,
    );
