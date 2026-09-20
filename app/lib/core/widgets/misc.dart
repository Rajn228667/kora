import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_icons.dart';
import '../theme/app_metrics.dart';
import '../theme/app_typography.dart';
import '../theme/kora_colors.dart';
import '../media/kora_image.dart';

/// Circular avatar with image or initials fallback.
class KoraAvatar extends StatelessWidget {
  const KoraAvatar({
    super.key,
    this.imageUrl,
    this.initials,
    this.radius = 24,
    this.blurHash,
  });

  final String? imageUrl;
  final String? initials;
  final double radius;
  final String? blurHash;

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return ClipOval(
        child: KoraImage(
          url: imageUrl,
          blurHash: blurHash,
          width: radius * 2,
          height: radius * 2,
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: KoraColors.selected,
      child: Text(
        initials ?? '?',
        style: AppTypography.titleSmall
            .copyWith(color: KoraColors.accentText),
      ),
    );
  }
}

/// Small label chip — filled (primary) or outlined.
class KoraBadge extends StatelessWidget {
  const KoraBadge({
    super.key,
    required this.label,
    this.filled = false,
    this.color,
    this.icon,
  });

  final String label;
  final bool filled;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final bg = filled ? (color ?? KoraColors.primary) : KoraColors.selected;
    final fg =
        filled ? KoraColors.white : (color ?? KoraColors.accentText);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(
            label,
            style: AppTypography.overline.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

/// Numeric counter badge (cart, unread chat).
class KoraCountBadge extends StatelessWidget {
  const KoraCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final text = count > 99 ? '99+' : '$count';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
      child: Container(
        key: ValueKey(text),
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: const BoxDecoration(
          color: KoraColors.primary,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              color: KoraColors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Order / payment status chip with semantic purple-first styling.
class KoraStatusChip extends StatelessWidget {
  const KoraStatusChip({
    super.key,
    required this.label,
    this.tone = KoraStatusTone.neutral,
  });

  final String label;
  final KoraStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      KoraStatusTone.neutral =>
        (KoraColors.surfaceAlt, KoraColors.textSecondaryC),
      KoraStatusTone.active =>
        (KoraColors.selected, KoraColors.accentText),
      KoraStatusTone.success =>
        (KoraColors.successSurfaceC, KoraColors.success),
      KoraStatusTone.warning =>
        (KoraColors.warningSurfaceC, KoraColors.warning),
      KoraStatusTone.error =>
        (KoraColors.errorSurfaceC, KoraColors.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppTypography.caption
            .copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}

enum KoraStatusTone { neutral, active, success, warning, error }

/// KZT price rendering: integer tiyn → "1 990 ₸".
class KoraPrice extends StatelessWidget {
  const KoraPrice({super.key, required this.tiyn, this.style});

  final int tiyn;
  final TextStyle? style;

  static final _fmt = NumberFormat('#,###', 'ru_RU');

  static String format(int tiyn) {
    final tenge = tiyn ~/ 100;
    return '${_fmt.format(tenge).replaceAll(',', ' ')} ₸';
  }

  static String formatTenge(num tenge) =>
      '${_fmt.format(tenge).replaceAll(',', ' ')} ₸';

  @override
  Widget build(BuildContext context) {
    return Text(format(tiyn), style: style ?? AppTypography.price);
  }
}

/// Round map pin used by the stub map and any real map provider.
class KoraMapMarker extends StatelessWidget {
  const KoraMapMarker({
    super.key,
    this.icon = AppIcons.location,
    this.color = KoraColors.primary,
    this.label,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: KoraColors.white, width: 2.5),
            boxShadow: AppShadows.card,
          ),
          child: Icon(icon, size: size * 0.5, color: KoraColors.white),
        ),
        if (label != null)
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.xs),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: KoraColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: KoraColors.softBorderC),
            ),
            child: Text(label!, style: AppTypography.overline),
          ),
      ],
    );
  }
}

/// Section header row: title + optional "see all" action.
class KoraSectionHeader extends StatelessWidget {
  const KoraSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppTypography.title)),
          if (actionLabel != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: AppTypography.label
                    .copyWith(color: KoraColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}
