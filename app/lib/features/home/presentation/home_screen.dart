import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/media/kora_image.dart' as kora_media;
import '../../../core/models/models.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/misc.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../cart/data/cart_repository.dart';
import '../../checkout/data/checkout_repository.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askLocation());
  }

  /// First-launch location consent sheet (§22). Shown once — the
  /// answer is persisted in SharedPreferences; declining keeps the
  /// app fully functional.
  Future<void> _askLocation() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || (prefs.getBool('location_asked') ?? false)) {
      return;
    }
    await prefs.setBool('location_asked', true);
    if (!mounted) return;
    final granted = await KoraBottomSheet.show<bool>(
          context,
          isDismissible: false,
          child: const LocationPermissionSheet(),
        ) ??
        false;
    if (!granted || !mounted) return;
    await Permission.locationWhenInUse.request();
    // Reading the position is best-effort — the city selector works
    // regardless; coordinates refine "stores nearby".
    if (await Permission.locationWhenInUse.isGranted) {
      try {
        await Geolocator.getCurrentPosition();
      } catch (_) {/* GPS off / emulator — fine */}
    }
  }

  IconData _kindIcon(StoreKind kind) => switch (kind) {
        StoreKind.restaurant => AppIcons.restaurant,
        StoreKind.supermarket => AppIcons.grocery,
        StoreKind.pharmacy => AppIcons.pharmacy,
        StoreKind.electronics => AppIcons.electronics,
        StoreKind.clothing => AppIcons.clothing,
        StoreKind.other => AppIcons.category,
      };

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final name = switch (auth) {
      Authenticated(user: final u) => u.name,
      _ => '',
    };
    final categories = ref.watch(categoriesProvider);
    final stores = ref.watch(storesProvider);
    final catalog = ref.watch(catalogProvider);
    final promos = ref.watch(promotionsProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: KoraColors.primary,
          onRefresh: () async {
            ref.invalidate(storesProvider);
            ref.invalidate(categoriesProvider);
            ref.invalidate(promotionsProvider);
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: AppSpacing.screenPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty
                                      ? S.t('home.greeting_default')
                                      : S.t('home.greeting', {'name': name}),
                                  style: AppTypography.headline,
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                GestureDetector(
                                  onTap: () => context.push('/addresses'),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        AppIcons.locationOut,
                                        size: 16,
                                        color: KoraColors.primary,
                                      ),
                                      const SizedBox(width: AppSpacing.xxs),
                                      Text(
                                        S.t(
                                          'home.address',
                                          {'city': S.t('home.city')},
                                        ),
                                        style: AppTypography.caption.copyWith(
                                          color: KoraColors.primary,
                                        ),
                                      ),
                                      const Icon(
                                        AppIcons.chevronD,
                                        size: 16,
                                        color: KoraColors.primary,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => context.push('/notifications'),
                            icon: const Icon(AppIcons.notificationOut),
                            tooltip: S.t('home.notifications'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      KoraSearchField(
                        hint: S.t('home.search_hint'),
                        readOnly: true,
                        onTap: () => context.push('/search'),
                      ),
                    ],
                  ),
                ),
              ),
              // Promo banners — swipeable image carousel with dots.
              promos.when(
                data: (list) => list.isEmpty
                    ? const SliverToBoxAdapter()
                    : SliverToBoxAdapter(
                        child: _PromoCarousel(promos: list),
                      ),
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: KoraSkeleton(height: 96, radius: AppRadius.lg),
                  ),
                ),
                error: (_, __) => const SliverToBoxAdapter(),
              ),
              // Categories
              categories.when(
                data: (cats) => SliverToBoxAdapter(
                  child: SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      itemCount: cats.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: AppSpacing.sm),
                      itemBuilder: (_, i) => _CategoryTile(
                        category: cats[i],
                        icon: _kindIcon(cats[i].kind),
                      ),
                    ),
                  ),
                ),
                loading: () => const SliverToBoxAdapter(
                  child: SizedBox(height: 96),
                ),
                error: (_, __) => const SliverToBoxAdapter(),
              ),
              // Deals rail — discounted products.
              ref.watch(dealsProvider).when(
                    data: (deals) => deals.isEmpty
                        ? const SliverToBoxAdapter()
                        : SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: AppSpacing.lg),
                                KoraSectionHeader(title: S.t('home.deals')),
                                const SizedBox(height: AppSpacing.sm),
                                SizedBox(
                                  height: 210,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.lg,
                                    ),
                                    itemCount: deals.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: AppSpacing.md),
                                    itemBuilder: (_, i) =>
                                        _DealCard(p: deals[i]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                    loading: () => const SliverToBoxAdapter(),
                    error: (_, __) => const SliverToBoxAdapter(),
                  ),
              // Store strip — the single KORA venue (info → /store page).
              stores.when(
                data: (list) => list.isEmpty
                    ? const SliverToBoxAdapter()
                    : SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: AppSpacing.lg,
                            left: AppSpacing.lg,
                            right: AppSpacing.lg,
                          ),
                          child: _StoreStrip(store: list.first),
                        ),
                      ),
                loading: () => const SliverToBoxAdapter(),
                error: (_, __) => const SliverToBoxAdapter(),
              ),
              // Catalog — product grid, grouped sections come from
              // category pages; here everything of the single store.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.lg,
                    bottom: AppSpacing.sm,
                  ),
                  child: KoraSectionHeader(title: S.t('home.catalog')),
                ),
              ),
              catalog.when(
                data: (items) => items.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                          ),
                          child: KoraEmptyState(
                            icon: AppIcons.grocery,
                            title: S.t('catalog.empty'),
                            message: S.t('catalog.empty_sub'),
                          ),
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: AppSpacing.md,
                            crossAxisSpacing: AppSpacing.md,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _ProductTile(p: items[i]),
                        ),
                      ),
                loading: () => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: AppSpacing.md,
                      crossAxisSpacing: AppSpacing.md,
                      childAspectRatio: 0.78,
                      children: const [
                        KoraSkeleton(radius: AppRadius.lg),
                        KoraSkeleton(radius: AppRadius.lg),
                        KoraSkeleton(radius: AppRadius.lg),
                        KoraSkeleton(radius: AppRadius.lg),
                      ],
                    ),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: KoraErrorState(
                    message: S.t('home.load_error'),
                    onRetry: () => ref.invalidate(catalogProvider),
                  ),
                ),
              ),
              // Recently viewed — horizontal rail (§27).
              ref.watch(recentlyViewedProvider).when(
                    data: (list) => list.isEmpty
                        ? const SliverToBoxAdapter()
                        : SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: AppSpacing.lg),
                                KoraSectionHeader(
                                  title: S.t('recent.title'),
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                SizedBox(
                                  height: 168,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.lg,
                                    ),
                                    itemCount: list.length,
                                    separatorBuilder: (_, __) => const SizedBox(
                                      width: AppSpacing.sm,
                                    ),
                                    itemBuilder: (_, i) =>
                                        _RecentTile(p: list[i]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                    loading: () => const SliverToBoxAdapter(),
                    error: (_, __) => const SliverToBoxAdapter(),
                  ),
              const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.huge),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromoCarousel extends ConsumerStatefulWidget {
  const _PromoCarousel({required this.promos});

  final List<Promotion> promos;

  @override
  ConsumerState<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends ConsumerState<_PromoCarousel> {
  final _pager = PageController(viewportFraction: 0.88);
  int _page = 0;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _open(Promotion promo) {
    if (promo.storeId != null) {
      context.push('/store/${promo.storeId}');
    } else if (promo.code != null) {
      ref.read(appliedPromoProvider.notifier).state = (
        code: promo.code!,
        discountTiyn: 0,
      );
      KoraSnackbar.show(
        context,
        S.t('promo.applied_code', {'code': promo.code!}),
      );
      context.push('/cart');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 156,
          child: PageView.builder(
            controller: _pager,
            padEnds: false,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: widget.promos.length,
            itemBuilder: (_, i) => Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? AppSpacing.lg : AppSpacing.sm,
                right: i == widget.promos.length - 1 ? AppSpacing.lg : 0,
                top: AppSpacing.sm,
                bottom: AppSpacing.sm,
              ),
              child: _PromoBanner(
                promo: widget.promos[i],
                onTap: () => _open(widget.promos[i]),
              ),
            ),
          ),
        ),
        if (widget.promos.length > 1) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.promos.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _page == i ? 18 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: _page == i
                        ? KoraColors.primary
                        : KoraColors.softBorderC,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.promo, required this.onTap});

  final Promotion promo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AppRadius.card,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (promo.imageUrl != null)
              kora_media.KoraImage(
                url: promo.imageUrl,
                fit: BoxFit.cover,
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: KoraColors.primaryGradient,
                ),
              ),
            // Readability scrim.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    KoraColors.brandNavy.withValues(alpha: 0.85),
                    KoraColors.deepPurple.withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: KoraColors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          AppIcons.promo,
                          color: KoraColors.white,
                          size: 14,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          S.t('home.promo_tag'),
                          style: AppTypography.caption.copyWith(
                            color: KoraColors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    promo.title,
                    style:
                        AppTypography.title.copyWith(color: KoraColors.white),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (promo.subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      promo.subtitle!,
                      style: AppTypography.caption
                          .copyWith(color: KoraColors.lightPurple),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DealCard extends ConsumerWidget {
  const _DealCard({required this.p});

  final Product p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final old = p.oldPriceTiyn!;
    final pct = (1 - p.priceTiyn / old) * 100;
    return GestureDetector(
      onTap: () => context.push('/store/${p.storeId}/product/${p.id}'),
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: kora_media.KoraImage(
                    url: p.imageUrl,
                    blurHash: p.blurHash,
                    width: 140,
                    height: 110,
                    borderRadius: AppRadius.lg,
                  ),
                ),
                Positioned(
                  top: AppSpacing.sm,
                  left: AppSpacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: KoraColors.error,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '−${pct.round()}%',
                      style: AppTypography.caption.copyWith(
                        color: KoraColors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              p.name,
              style: AppTypography.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                KoraPrice(
                  tiyn: p.priceTiyn,
                  style: AppTypography.label,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    KoraPrice.format(old),
                    style: AppTypography.caption.copyWith(
                      color: KoraColors.placeholderC,
                      decoration: TextDecoration.lineThrough,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.icon});

  final Category category;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(
        '/category/${category.id}?name=${Uri.encodeComponent(category.name)}',
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: KoraColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: KoraColors.softBorderC),
            ),
            child: Icon(icon, color: KoraColors.primary, size: 26),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            width: 72,
            child: Text(
              category.name,
              style: AppTypography.caption,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Location consent sheet shown once after first login (§22).
class LocationPermissionSheet extends StatelessWidget {
  const LocationPermissionSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppSpacing.cardPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                gradient: KoraColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                AppIcons.location,
                color: KoraColors.white,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            S.t('location.title'),
            style: AppTypography.title,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            S.t('location.body'),
            style: AppTypography.bodySecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          KoraButton(
            label: S.t('location.allow'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: KoraGhostButton(
              label: S.t('location.later'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact recently-viewed product tile for the home rail.
class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.p});

  final Product p;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/store/${p.storeId}/product/${p.id}'),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: kora_media.KoraImage(
                url: p.imageUrl,
                blurHash: p.blurHash,
                width: 120,
                height: 100,
                borderRadius: AppRadius.md,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              p.name,
              style: AppTypography.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            KoraPrice(tiyn: p.priceTiyn, style: AppTypography.label),
          ],
        ),
      ),
    );
  }
}

class _StoreStrip extends StatelessWidget {
  const _StoreStrip({required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    return KoraCard(
      padding: EdgeInsets.zero,
      onTap: () => context.push('/store/${store.id}'),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(AppRadius.lg),
            ),
            child: kora_media.KoraImage(
              url: store.logoUrl,
              width: 88,
              height: 88,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(store.name, style: AppTypography.titleSmall),
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: [
                    const Icon(
                      AppIcons.clock,
                      size: 13,
                      color: KoraColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      '${store.etaMinutes} ${S.t('common.min')}',
                      style: AppTypography.caption,
                    ),
                    Text(' · ', style: AppTypography.caption),
                    const Icon(
                      AppIcons.bike,
                      size: 13,
                      color: KoraColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      store.deliveryFeeTiyn == 0
                          ? S.t('common.free')
                          : KoraPrice.format(store.deliveryFeeTiyn),
                      style: AppTypography.caption,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(store.workingHours, style: AppTypography.caption),
              ],
            ),
          ),
          Icon(AppIcons.chevronR, color: KoraColors.placeholderC),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// Catalog grid card — image, discount badge, name, price, quick add.
class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.p});

  final Product p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final old = p.oldPriceTiyn;
    final pct = old == null ? 0 : ((1 - p.priceTiyn / old) * 100).round();
    return KoraCard(
      padding: EdgeInsets.zero,
      onTap: () => context.push('/store/${p.storeId}/product/${p.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.lg),
                  ),
                  child: kora_media.KoraImage(
                    url: p.imageUrl,
                    blurHash: p.blurHash,
                  ),
                ),
                if (pct > 0)
                  Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: KoraColors.error,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        '−$pct%',
                        style: AppTypography.caption.copyWith(
                          color: KoraColors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (!p.available)
                  Positioned.fill(
                    child: Container(
                      color: KoraColors.white.withValues(alpha: 0.6),
                      child: Center(
                        child: Text(
                          S.t('product.out_of_stock'),
                          style: AppTypography.caption,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: AppTypography.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: KoraPrice(
                        tiyn: p.priceTiyn,
                        style: AppTypography.label,
                      ),
                    ),
                    if (p.available)
                      KoraPressable(
                        onTap: () =>
                            ref.read(cartProvider.notifier).add(p, 1).then((_) {
                          if (context.mounted) {
                            KoraSnackbar.show(
                              context,
                              S.t('product.added'),
                            );
                          }
                        }),
                        semanticLabel: S.t('product.add_to_cart_short'),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            gradient: KoraColors.primaryGradient,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            AppIcons.add,
                            color: KoraColors.white,
                            size: 18,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
