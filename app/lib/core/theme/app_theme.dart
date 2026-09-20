import 'package:flutter/material.dart';
import 'app_metrics.dart';
import 'app_typography.dart';
import 'kora_colors.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(
        brightness: Brightness.light,
        background: KoraColors.white,
        surface: KoraColors.white,
        surfaceAlt: KoraColors.veryLightPurple,
        selected: KoraColors.lightPurple,
        border: KoraColors.border,
        softBorder: KoraColors.softBorder,
        textPrimary: KoraColors.textPrimary,
        textSecondary: KoraColors.textSecondary,
        placeholder: KoraColors.placeholder,
        disabled: KoraColors.disabled,
      );

  /// KORA dark theme — deep-purple tinted surfaces, same brand accents.
  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        background: KoraColors.darkBackground,
        surface: KoraColors.darkCard,
        surfaceAlt: KoraColors.darkSurface,
        selected: KoraColors.darkElevated,
        border: KoraColors.darkBorder,
        softBorder: KoraColors.darkSoftBorder,
        textPrimary: KoraColors.darkTextPrimary,
        textSecondary: KoraColors.darkTextSecondary,
        placeholder: KoraColors.darkPlaceholder,
        disabled: KoraColors.darkDisabled,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceAlt,
    required Color selected,
    required Color border,
    required Color softBorder,
    required Color textPrimary,
    required Color textSecondary,
    required Color placeholder,
    required Color disabled,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: KoraColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: KoraColors.primary,
      onPrimary: KoraColors.onPrimary,
      primaryContainer: selected,
      onPrimaryContainer: brightness == Brightness.dark
          ? KoraColors.darkTextPrimary
          : KoraColors.onLightPurple,
      secondary: KoraColors.softPurple,
      secondaryContainer: surfaceAlt,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      error: KoraColors.error,
      outline: border,
      outlineVariant: softBorder,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: AppTypography.textTheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: softBorder),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        hintStyle: AppTypography.body.copyWith(color: placeholder),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: _fieldBorder(softBorder),
        enabledBorder: _fieldBorder(softBorder),
        focusedBorder: _fieldBorder(KoraColors.primary, width: 1.6),
        errorBorder: _fieldBorder(KoraColors.error),
        focusedErrorBorder: _fieldBorder(KoraColors.error, width: 1.6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: KoraColors.primary,
          foregroundColor: KoraColors.onPrimary,
          disabledBackgroundColor: disabled,
          disabledForegroundColor: KoraColors.white,
          textStyle: AppTypography.button,
          minimumSize: const Size(48, 52),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.field),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: KoraColors.primary,
          textStyle: AppTypography.button,
          minimumSize: const Size(48, 52),
          side: const BorderSide(color: KoraColors.primary),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.field),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: KoraColors.primary,
          textStyle: AppTypography.button,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: KoraColors.primary,
        unselectedItemColor: placeholder,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape:
            const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.dark
            ? KoraColors.darkElevated
            : KoraColors.textPrimary,
        contentTextStyle:
            AppTypography.body.copyWith(color: KoraColors.white),
        shape:
            const RoundedRectangleBorder(borderRadius: AppRadius.field),
      ),
      dividerTheme:
          DividerThemeData(color: softBorder, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        selectedColor: selected,
        labelStyle: AppTypography.label,
        side: BorderSide(color: softBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: KoraColors.primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? KoraColors.primary
                : placeholder,),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? KoraColors.softPurple
                : softBorder,),
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color,
      {double width = 1,}) {
    return OutlineInputBorder(
      borderRadius: AppRadius.field,
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
