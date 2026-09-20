import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_animations.dart';
import '../theme/app_icons.dart';
import '../theme/app_metrics.dart';
import '../theme/app_typography.dart';
import '../theme/kora_colors.dart';
import '../l10n/app_strings.dart';
import 'buttons.dart';

/// App-wide snackbar. [isError] switches to the functional error tint.
abstract final class KoraSnackbar {
  static void show(BuildContext context, String message,
      {bool isError = false,}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError ? AppIcons.error : AppIcons.check,
                color: KoraColors.white,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor:
              isError ? KoraColors.error : KoraColors.invertedSurface,
        ),
      );
  }
}

/// Consistent alert / confirm dialog.
abstract final class KoraDialog {
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: AppTypography.titleLarge),
        content: Text(message, style: AppTypography.bodySecondary),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel ?? S.t('common.cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  destructive ? KoraColors.error : KoraColors.primary,
              minimumSize: const Size(48, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel ?? S.t('common.confirm')),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static Future<void> info(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: AppTypography.titleLarge),
        content: Text(message, style: AppTypography.bodySecondary),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.t('common.got_it')),
          ),
        ],
      ),
    );
  }
}

/// Modal bottom sheet helper with KORA sheet styling.
abstract final class KoraBottomSheet {
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    bool isScrollControlled = true,
    bool isDismissible = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: child,
      ),
    );
  }
}

class KoraLoadingState extends StatelessWidget {
  const KoraLoadingState({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(message!, style: AppTypography.bodySecondary),
          ],
        ],
      ),
    );
  }
}

class KoraErrorState extends StatelessWidget {
  const KoraErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = AppIcons.wifiOff,
  });

  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: KoraColors.selected,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: KoraColors.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodySecondary,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              KoraOutlinedButton(
                label: S.t('common.retry'),
                icon: AppIcons.refresh,
                expanded: false,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class KoraEmptyState extends StatelessWidget {
  const KoraEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = AppIcons.info,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: KoraColors.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: KoraColors.softPurple),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(title,
                style: AppTypography.title, textAlign: TextAlign.center,),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                style: AppTypography.bodySecondary,
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              KoraButton(
                label: actionLabel!,
                onPressed: onAction,
                expanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shimmer placeholder block. Compose several to mirror the layout.
class KoraSkeleton extends StatelessWidget {
  const KoraSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = AppRadius.sm,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    Widget box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: KoraColors.softBorderC,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
    if (AppAnimations.reduceMotion(context)) return box;
    return Shimmer.fromColors(
      baseColor: KoraColors.softBorderC,
      highlightColor: KoraColors.surfaceAlt,
      period: const Duration(milliseconds: 1200),
      child: box,
    );
  }
}

/// Skeleton mimicking a store/product card row.
class KoraCardSkeleton extends StatelessWidget {
  const KoraCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          KoraSkeleton(width: 72, height: 72, radius: AppRadius.md),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KoraSkeleton(height: 16, width: 160),
                SizedBox(height: AppSpacing.sm),
                KoraSkeleton(height: 12, width: 110),
                SizedBox(height: AppSpacing.sm),
                KoraSkeleton(height: 12, width: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
