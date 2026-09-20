import 'package:flutter/material.dart';
import '../theme/app_animations.dart';
import '../theme/app_icons.dart';
import '../theme/app_metrics.dart';
import '../theme/app_typography.dart';
import '../theme/kora_colors.dart';
import '../l10n/app_strings.dart';
import '../media/kora_image.dart';
import 'misc.dart';

/// Base white card: soft border, subtle shadow, rounded corners.
class KoraCard extends StatelessWidget {
  const KoraCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.cardPadding,
    this.onTap,
    this.elevated = false,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool elevated;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: KoraColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: KoraColors.softBorderC),
        boxShadow: elevated ? AppShadows.card : AppShadows.none,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return KoraPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: card,
    );
  }
}

/// Horizontal store list card: logo, name, rating, ETA, delivery fee.
class KoraStoreCard extends StatelessWidget {
  const KoraStoreCard({
    super.key,
    required this.name,
    required this.imageUrl,
    this.blurHash,
    this.category,
    this.rating,
    this.etaMinutes,
    this.deliveryFeeTiyn,
    this.isOpen = true,
    this.onTap,
    this.badge,
  });

  final String name;
  final String? imageUrl;
  final String? blurHash;
  final String? category;
  final double? rating;
  final int? etaMinutes;
  final int? deliveryFeeTiyn;
  final bool isOpen;
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return KoraCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: isOpen ? onTap : null,
      elevated: true,
      semanticLabel: '${S.t('a11y.store')} $name',
      child: Opacity(
        opacity: isOpen ? 1 : 0.55,
        child: Row(
          children: [
            KoraImage(
              url: imageUrl,
              blurHash: blurHash,
              width: 72,
              height: 72,
              borderRadius: AppRadius.md,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: AppTypography.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badge != null)
                        KoraBadge(label: badge!, filled: true),
                    ],
                  ),
                  if (category != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      category!,
                      style: AppTypography.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      if (rating != null) ...[
                        const Icon(AppIcons.star,
                            size: 15, color: KoraColors.primary,),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          rating!.toStringAsFixed(1),
                          style: AppTypography.caption
                              .copyWith(color: KoraColors.textPrimaryC),
                        ),
                        const _Dot(),
                      ],
                      if (etaMinutes != null) ...[
                        Icon(AppIcons.clock,
                            size: 15, color: KoraColors.textSecondaryC,),
                        const SizedBox(width: AppSpacing.xxs),
                        Text('$etaMinutes ${S.t('common.min')}',
                            style: AppTypography.caption,),
                        const _Dot(),
                      ],
                      if (deliveryFeeTiyn != null)
                        Text(
                          deliveryFeeTiyn == 0
                              ? S.t('common.free')
                              : KoraPrice.format(deliveryFeeTiyn!),
                          style: AppTypography.caption,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(AppIcons.chevronR,
                size: 20, color: KoraColors.placeholderC,),
          ],
        ),
      ),
    );
  }
}

/// Grid/list product card: image, name, price (+old price), add button.
class KoraProductCard extends StatelessWidget {
  const KoraProductCard({
    super.key,
    required this.name,
    required this.priceTiyn,
    this.oldPriceTiyn,
    this.imageUrl,
    this.blurHash,
    this.unit,
    this.available = true,
    this.isFavorite = false,
    this.onTap,
    this.onAdd,
    this.onFavorite,
  });

  final String name;
  final int priceTiyn;
  final int? oldPriceTiyn;
  final String? imageUrl;
  final String? blurHash;
  final String? unit;
  final bool available;
  final bool isFavorite;
  final VoidCallback? onTap;
  final VoidCallback? onAdd;
  final VoidCallback? onFavorite;

  @override
  Widget build(BuildContext context) {
    return KoraCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      onTap: available ? onTap : null,
      semanticLabel: '${S.t('a11y.product')} $name',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Hero(
                    tag: 'product-$name-$imageUrl',
                    child: KoraImage(
                      url: imageUrl,
                      blurHash: blurHash,
                      borderRadius: AppRadius.md,
                    ),
                  ),
                ),
                if (!available)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: KoraColors.surface.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Center(
                        child: Text(
                          S.t('product.out_of_stock'),
                          style: AppTypography.caption
                              .copyWith(color: KoraColors.textSecondaryC),
                        ),
                      ),
                    ),
                  ),
                if (onFavorite != null)
                  Positioned(
                    top: AppSpacing.xs,
                    right: AppSpacing.xs,
                    child: _FavoriteDot(
                      active: isFavorite,
                      onTap: onFavorite!,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            name,
            style: AppTypography.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KoraPrice(
                      tiyn: priceTiyn,
                      style: AppTypography.price,
                    ),
                    if (oldPriceTiyn != null)
                      KoraPrice(
                        tiyn: oldPriceTiyn!,
                        style: AppTypography.caption.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: KoraColors.placeholderC,
                        ),
                      ),
                  ],
                ),
              ),
              if (onAdd != null && available)
                _AddButton(onTap: onAdd!),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KoraPressable(
      onTap: onTap,
      semanticLabel: S.t('a11y.add_to_cart'),
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          gradient: KoraColors.primaryGradient,
          shape: BoxShape.circle,
        ),
        child: const Icon(AppIcons.add,
            size: 20, color: KoraColors.white,),
      ),
    );
  }
}

/// Hero venue card — full-width banner image with floating ETA badge,
/// name, rating and delivery fee below. Wolt-style storefront tile.
class KoraStoreHeroCard extends StatelessWidget {
  const KoraStoreHeroCard({
    super.key,
    required this.name,
    this.imageUrl,
    this.blurHash,
    this.category,
    this.rating,
    this.etaMinutes,
    this.deliveryFeeTiyn,
    this.isOpen = true,
    this.onTap,
    this.badge,
  });

  final String name;
  final String? imageUrl;
  final String? blurHash;
  final String? category;
  final double? rating;
  final int? etaMinutes;
  final int? deliveryFeeTiyn;
  final bool isOpen;
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return KoraPressable(
      onTap: isOpen ? onTap : null,
      semanticLabel: '${S.t('a11y.store')} $name',
      child: Opacity(
        opacity: isOpen ? 1 : 0.55,
        child: Container(
          decoration: BoxDecoration(
            color: KoraColors.surface,
            borderRadius: AppRadius.card,
            border: Border.all(color: KoraColors.softBorderC),
            boxShadow: AppShadows.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  KoraImage(
                    url: imageUrl,
                    blurHash: blurHash,
                    width: double.infinity,
                    height: 140,
                  ),
                  if (etaMinutes != null)
                    Positioned(
                      left: AppSpacing.md,
                      bottom: AppSpacing.md,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xxs,
                        ),
                        decoration: BoxDecoration(
                          color: KoraColors.white,
                          borderRadius:
                              BorderRadius.circular(AppRadius.sm),
                          boxShadow: AppShadows.card,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(AppIcons.clock,
                                size: 13, color: KoraColors.primary,),
                            const SizedBox(width: 3),
                            Text(
                              '$etaMinutes ${S.t('common.min')}',
                              style: AppTypography.caption.copyWith(
                                color: KoraColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (badge != null)
                    Positioned(
                      top: AppSpacing.md,
                      right: AppSpacing.md,
                      child: KoraBadge(label: badge!, filled: true),
                    ),
                  if (!isOpen)
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: KoraColors.white,
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            S.t('store.closed'),
                            style: AppTypography.label,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md,
                    AppSpacing.sm, AppSpacing.md, AppSpacing.md,),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: AppTypography.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (rating != null) ...[
                          const Icon(AppIcons.star,
                              size: 15, color: KoraColors.primary,),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(
                            rating!.toStringAsFixed(1),
                            style: AppTypography.label,
                          ),
                        ],
                      ],
                    ),
                    if (category != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        category!,
                        style: AppTypography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (deliveryFeeTiyn != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        children: [
                          const Icon(AppIcons.bike,
                              size: 14, color: KoraColors.primary,),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(
                            deliveryFeeTiyn == 0
                                ? S.t('common.free')
                                : KoraPrice.format(deliveryFeeTiyn!),
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Text('·', style: AppTypography.caption),
    );
  }
}


/// Floating heart toggle on product images — animated fill.
class _FavoriteDot extends StatelessWidget {
  const _FavoriteDot({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: KoraColors.surface,
          shape: BoxShape.circle,
          boxShadow: AppShadows.card,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: Icon(
            active ? AppIcons.heart : AppIcons.heartOut,
            key: ValueKey(active),
            size: 17,
            color: active ? KoraColors.primary : KoraColors.placeholderC,
          ),
        ),
      ),
    );
  }
}
