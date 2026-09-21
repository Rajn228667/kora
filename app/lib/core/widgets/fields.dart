import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_icons.dart';
import '../theme/app_metrics.dart';
import '../theme/app_typography.dart';
import '../l10n/app_strings.dart';
import '../theme/kora_colors.dart';

class KoraTextField extends StatelessWidget {
  const KoraTextField({
    super.key,
    this.controller,
    this.hint,
    this.label,
    this.prefixIcon,
    this.prefix,
    this.suffix,
    this.keyboardType,
    this.obscure = false,
    this.enabled = true,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.errorText,
    this.semanticLabel,
  });

  final TextEditingController? controller;
  final String? hint;
  final String? label;
  final IconData? prefixIcon;
  final Widget? prefix;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final bool obscure;
  final bool enabled;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final String? errorText;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      enabled: enabled,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      autofocus: autofocus,
      style: AppTypography.body,
      decoration: InputDecoration(
        hintText: hint,
        errorText: errorText,
        counterText: '',
        prefixIcon: prefix ??
            (prefixIcon == null
                ? null
                : Icon(prefixIcon, color: KoraColors.placeholderC, size: 22)),
        suffixIcon: suffix,
      ),
    );

    final wrapped = label == null
        ? field
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label!, style: AppTypography.label),
              const SizedBox(height: AppSpacing.sm),
              field,
            ],
          );

    return Semantics(
      label: semanticLabel ?? label ?? hint,
      textField: true,
      child: wrapped,
    );
  }
}

/// Search input with built-in debounce callback.
class KoraSearchField extends StatelessWidget {
  const KoraSearchField({
    super.key,
    this.controller,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.autofocus = false,
    this.readOnly = false,
    this.onTap,
  });

  final TextEditingController? controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool autofocus;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofocus: autofocus,
      readOnly: readOnly,
      onTap: onTap,
      textInputAction: TextInputAction.search,
      style: AppTypography.body,
      decoration: InputDecoration(
        hintText: hint ?? S.t('nav.search'),
        prefixIcon: Icon(
          AppIcons.search,
          color: KoraColors.placeholderC,
          size: 22,
        ),
        suffixIcon: (controller?.text.isNotEmpty ?? false)
            ? IconButton(
                icon: const Icon(AppIcons.close, size: 20),
                color: KoraColors.placeholderC,
                onPressed: () {
                  controller?.clear();
                  onClear?.call();
                },
                tooltip: S.t('search.clear'),
              )
            : null,
      ),
    );
  }
}

/// Formats a Kazakhstan phone number as "+7 7XX XXX XX XX".
class KzPhoneFormatter extends TextInputFormatter {
  const KzPhoneFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('8')) digits = '7${digits.substring(1)}';
    if (!digits.startsWith('7')) digits = '7$digits';
    digits = digits.substring(0, digits.length.clamp(0, 11));

    final buf = StringBuffer('+7');
    if (digits.length > 1) {
      buf.write(' ${digits.substring(1, digits.length.clamp(1, 4))}');
    }
    if (digits.length > 4) {
      buf.write(' ${digits.substring(4, digits.length.clamp(4, 7))}');
    }
    if (digits.length > 7) {
      buf.write(' ${digits.substring(7, digits.length.clamp(7, 9))}');
    }
    if (digits.length > 9) {
      buf.write(' ${digits.substring(9, digits.length.clamp(9, 11))}');
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  static String toE164(String formatted) =>
      '+${formatted.replaceAll(RegExp(r'\D'), '')}';

  /// Kazakhstan national numbering plan: country code +7 followed by a
  /// mobile prefix beginning with 6 or 7 and nine remaining digits.
  static bool isValid(String formatted) =>
      RegExp(r'^\+7[67]\d{9}$').hasMatch(toE164(formatted));
}

/// Compact Kazakhstan flag drawn locally; no emoji/font dependency and no
/// remote asset request on the authentication screen.
class KazakhstanFlag extends StatelessWidget {
  const KazakhstanFlag({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 24,
        height: 16,
        child: CustomPaint(painter: _KazakhstanFlagPainter()),
      );
}

class _KazakhstanFlagPainter extends CustomPainter {
  const _KazakhstanFlagPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = const Color(0xFF00AFCA),
    );
    final gold = Paint()..color = const Color(0xFFFFD700);
    final center = Offset(size.width * 0.53, size.height * 0.43);
    canvas.drawCircle(center, size.height * 0.16, gold);
    final ray = Paint()
      ..color = const Color(0xFFFFD700)
      ..strokeWidth = 0.8;
    for (var i = 0; i < 8; i++) {
      final angle = i * 3.141592653589793 / 4;
      canvas.drawLine(
        center + Offset.fromDirection(angle, size.height * 0.2),
        center + Offset.fromDirection(angle, size.height * 0.27),
        ray,
      );
    }
    final eagle = Path()
      ..moveTo(size.width * 0.32, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.53,
        size.height * 0.58,
        size.width * 0.74,
        size.height * 0.72,
      )
      ..quadraticBezierTo(
        size.width * 0.53,
        size.height * 0.67,
        size.width * 0.32,
        size.height * 0.72,
      );
    canvas.drawPath(eagle, gold);
  }

  @override
  bool shouldRepaint(_KazakhstanFlagPainter oldDelegate) => false;
}
