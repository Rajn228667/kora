import 'package:flutter/material.dart';

/// 4pt spacing scale. Never use off-scale values.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  static const EdgeInsets screenPadding =
      EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
  static const EdgeInsets listPadding =
      EdgeInsets.symmetric(horizontal: lg, vertical: sm);
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius field = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheet =
      BorderRadius.vertical(top: Radius.circular(xl));
}

abstract final class AppShadows {
  /// Subtle elevation only — KORA avoids heavy shadows.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0A1E1B4B),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> raised = [
    BoxShadow(
      color: Color(0x141E1B4B),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> none = [];
}
