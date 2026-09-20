import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../theme/app_animations.dart';
import '../theme/app_metrics.dart';
import '../theme/app_typography.dart';
import '../theme/kora_colors.dart';

/// Primary CTA — press-scale (Uiverse-style bounce), loading spinner
/// replaces the label, optional success flash.
class KoraButton extends StatelessWidget {
  const KoraButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.success = false,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool success;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final child = KoraPressable(
      onTap: enabled ? onPressed : null,
      scaleDown: 0.96,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: AppAnimations.fast,
        width: expanded ? double.infinity : null,
        height: 52,
        decoration: BoxDecoration(
          gradient: enabled || loading
              ? (success ? null : KoraColors.primaryGradient)
              : null,
          color: success
              ? KoraColors.success
              : (enabled || loading ? null : KoraColors.disabledC),
          borderRadius: AppRadius.field,
          boxShadow: enabled
              ? const [
                  BoxShadow(
                    color: Color(0x338B5CF6),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: AppAnimations.fast,
            child: _content(),
          ),
        ),
      ),
    );
    return child;
  }

  Widget _content() {
    if (loading) {
      return const SizedBox(
        key: ValueKey('loading'),
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: KoraColors.white,
        ),
      );
    }
    if (success) {
      return const Icon(
        Icons.check_rounded,
        key: ValueKey('success'),
        color: KoraColors.white,
        size: 24,
      );
    }
    return Row(
      key: const ValueKey('label'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: KoraColors.white),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.button
                .copyWith(color: KoraColors.white),
          ),
        ),
      ],
    );
  }
}

class KoraOutlinedButton extends StatelessWidget {
  const KoraOutlinedButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return KoraPressable(
      onTap: onPressed,
      scaleDown: 0.97,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: AppAnimations.fast,
        width: expanded ? double.infinity : null,
        height: 52,
        decoration: BoxDecoration(
          color: onPressed == null
              ? KoraColors.surfaceAlt
              : KoraColors.selected,
          borderRadius: AppRadius.field,
          border: Border.all(
            color: onPressed == null
                ? KoraColors.borderC
                : KoraColors.primary,
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: KoraColors.primary),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.button.copyWith(
                    color: onPressed == null
                        ? KoraColors.placeholderC
                        : KoraColors.primary,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KoraGhostButton extends StatelessWidget {
  const KoraGhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.color = KoraColors.primary,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: color),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(label),
        ],
      ),
    );
  }
}

/// Compact quantity stepper used in cart and product screens.
class KoraQuantityStepper extends StatelessWidget {
  const KoraQuantityStepper({
    super.key,
    required this.quantity,
    required this.onChanged,
    this.min = 0,
    this.max = 99,
    this.compact = false,
  });

  final int quantity;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 30.0 : 38.0;
    return Container(
      decoration: BoxDecoration(
        color: KoraColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: KoraColors.softBorderC),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepBtn(
            icon: Icons.remove_rounded,
            size: size,
            enabled: quantity > min,
            onTap: () => onChanged(quantity - 1),
            semantic: S.t('product.qty_minus'),
          ),
          AnimatedSwitcher(
            duration: AppAnimations.fast,
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: SizedBox(
              key: ValueKey(quantity),
              width: compact ? 28 : 36,
              child: Text(
                '$quantity',
                textAlign: TextAlign.center,
                style: AppTypography.titleSmall,
              ),
            ),
          ),
          _stepBtn(
            icon: Icons.add_rounded,
            size: size,
            enabled: quantity < max,
            onTap: () => onChanged(quantity + 1),
            semantic: S.t('product.qty_plus'),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn({
    required IconData icon,
    required double size,
    required bool enabled,
    required VoidCallback onTap,
    required String semantic,
  }) {
    return Semantics(
      button: true,
      label: semantic,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.55,
            color: enabled ? KoraColors.primary : KoraColors.disabledC,
          ),
        ),
      ),
    );
  }
}
