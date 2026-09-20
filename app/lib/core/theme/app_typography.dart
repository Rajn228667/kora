import 'package:flutter/material.dart';
import 'kora_colors.dart';

/// Type hierarchy. Styles resolve text color through
/// [KoraColors.textPrimaryC]/[KoraColors.textSecondaryC], so they
/// follow the active light/dark theme automatically.
/// Do not skip levels and do not use heading styles for non-heading
/// content.
abstract final class AppTypography {
  static const String _family = 'Roboto';

  static TextStyle get displayLarge => TextStyle(
        fontFamily: _family,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: -0.5,
        color: KoraColors.textPrimaryC,
      );

  static TextStyle get headline => TextStyle(
        fontFamily: _family,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.3,
        color: KoraColors.textPrimaryC,
      );

  static TextStyle get titleLarge => TextStyle(
        fontFamily: _family,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: KoraColors.textPrimaryC,
      );

  static TextStyle get title => TextStyle(
        fontFamily: _family,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: KoraColors.textPrimaryC,
      );

  static TextStyle get titleSmall => TextStyle(
        fontFamily: _family,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: KoraColors.textPrimaryC,
      );

  static TextStyle get body => TextStyle(
        fontFamily: _family,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: KoraColors.textPrimaryC,
      );

  static TextStyle get bodySecondary => TextStyle(
        fontFamily: _family,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: KoraColors.textSecondaryC,
      );

  static TextStyle get label => TextStyle(
        fontFamily: _family,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: KoraColors.textPrimaryC,
      );

  static TextStyle get caption => TextStyle(
        fontFamily: _family,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.35,
        color: KoraColors.textSecondaryC,
      );

  static TextStyle get overline => TextStyle(
        fontFamily: _family,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0.6,
        color: KoraColors.textSecondaryC,
      );

  static const TextStyle button = TextStyle(
    fontFamily: _family,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: 0.1,
  );

  static TextStyle get price => TextStyle(
        fontFamily: _family,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: KoraColors.textPrimaryC,
      );

  static TextTheme get textTheme => TextTheme(
        displayLarge: displayLarge,
        headlineMedium: headline,
        titleLarge: titleLarge,
        titleMedium: title,
        titleSmall: titleSmall,
        bodyLarge: body,
        bodyMedium: bodySecondary,
        labelLarge: label,
        bodySmall: caption,
        labelSmall: overline,
      );
}
