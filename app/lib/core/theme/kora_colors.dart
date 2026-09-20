import 'package:flutter/material.dart';

/// Runtime brightness flag. Set once per frame in `app.dart` build;
/// all semantic getters below resolve through it, so every widget
/// using them adapts to light/dark automatically.
abstract final class KoraTheme {
  static bool dark = false;
}

/// KORA brand palette: WHITE + PURPLE + LIGHT PURPLE.
/// Every screen must source colors from here — no ad-hoc hex values.
abstract final class KoraColors {
  // Surfaces
  static const Color white = Color(0xFFFFFFFF);
  static const Color veryLightPurple = Color(0xFFF8F7FF);
  static const Color lightPurple = Color(0xFFEDE9FE);

  // Brand purples
  static const Color primary = Color(0xFF8B5CF6);
  static const Color softPurple = Color(0xFFA78BFA);
  static const Color darkPurple = Color(0xFF6D28D9);
  static const Color deepPurple = Color(0xFF5B21B6);

  // Text & borders
  static const Color textPrimary = Color(0xFF18181B);
  static const Color textSecondary = Color(0xFF52525B);
  static const Color placeholder = Color(0xFFA1A1AA);
  static const Color disabled = Color(0xFFD4D4D8);
  static const Color border = Color(0xFFE4E4E7);
  static const Color softBorder = Color(0xFFF4F4F5);

  // Functional only — used minimally, never as brand colors.
  static const Color error = Color(0xFFDC2626);
  static const Color errorSurface = Color(0xFFFEF2F2);
  static const Color success = Color(0xFF16A34A);
  static const Color successSurface = Color(0xFFF0FDF4);
  static const Color warning = Color(0xFFD97706);
  static const Color warningSurface = Color(0xFFFFFBEB);

  // Purple-on-purple readability
  static const Color onPrimary = white;
  static const Color onLightPurple = deepPurple;

  // ------------------------------------------------------------------
  // Dark tokens — KORA dark is deep-purple tinted, never black/blue.
  // ------------------------------------------------------------------
  static const Color darkBackground = Color(0xFF16111F);
  static const Color darkSurface = Color(0xFF1E1830);
  static const Color darkCard = Color(0xFF26203C);
  static const Color darkElevated = Color(0xFF2D2547);
  static const Color darkBorder = Color(0xFF3A2F5C);
  static const Color darkSoftBorder = Color(0xFF2C2445);
  static const Color darkTextPrimary = Color(0xFFF4F1FF);
  static const Color darkTextSecondary = Color(0xFFB6AED8);
  static const Color darkPlaceholder = Color(0xFF7E739F);
  static const Color darkDisabled = Color(0xFF4A4166);

  // ------------------------------------------------------------------
  // Semantic getters — resolve light/dark at build time.
  // Use these for surfaces/borders/text. Keep using the consts above
  // for brand accents (primary, gradients, on-primary white).
  // ------------------------------------------------------------------
  static Color get background => KoraTheme.dark ? darkBackground : white;
  static Color get surface => KoraTheme.dark ? darkCard : white;
  static Color get surfaceAlt => KoraTheme.dark ? darkSurface : veryLightPurple;
  static Color get selected => KoraTheme.dark ? darkElevated : lightPurple;
  static Color get borderC => KoraTheme.dark ? darkBorder : border;
  static Color get softBorderC => KoraTheme.dark ? darkSoftBorder : softBorder;
  static Color get textPrimaryC => KoraTheme.dark ? darkTextPrimary : textPrimary;
  static Color get textSecondaryC =>
      KoraTheme.dark ? darkTextSecondary : textSecondary;
  static Color get placeholderC => KoraTheme.dark ? darkPlaceholder : placeholder;
  static Color get disabledC => KoraTheme.dark ? darkDisabled : disabled;
  static Color get errorSurfaceC =>
      KoraTheme.dark ? const Color(0xFF3A1E24) : errorSurface;
  static Color get successSurfaceC =>
      KoraTheme.dark ? const Color(0xFF14291D) : successSurface;
  static Color get warningSurfaceC =>
      KoraTheme.dark ? const Color(0xFF33250F) : warningSurface;

  /// Purple accent text (deep purple in light, soft purple in dark).
  static Color get accentText => KoraTheme.dark ? softPurple : deepPurple;

  /// Snackbar / inverted surface.
  static Color get invertedSurface =>
      KoraTheme.dark ? darkElevated : textPrimary;

  /// Only white↔purple gradients are allowed in the product.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, softPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient softGradient = LinearGradient(
    colors: [softPurple, lightPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [white, veryLightPurple],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
