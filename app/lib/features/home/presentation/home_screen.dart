import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/media/kora_image.dart' as kora_media;
import '../../../core/models/models.dart';
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
                                      const Icon(AppIcons.locationOut,
                                          size: 16,
                                          color: KoraColors.primary,),
                                      const SizedBox(width: AppSpacing.xxs),
                                      Text(
                                        S.t('home.address',
                                            {'city': S.t('home.city')},),
                                        style: AppTypography.caption.copyWith(
                                          color: KoraColors.primary,
                                        ),
                                      ),
                                      const Icon(AppIcons.chevronD,
                                          size: 16,
                                          color: KoraColors.primary,),
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
              // Promo banners
              promos.when(
                data: (list) => list.isEmpty
                    ? const SliverToBoxAdapter()
                    : SliverToBoxAdapter(
                        child: SizedBox(
                          height: 120,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md,
                            ),
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: AppSpacing.md),
                            itemBuilder: (_, i) => _PromoBanner(promo: list[i]),
                          ),
                        ),
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
                          horizontal: AppSpacing.lg,),
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.lg,
                    bottom: AppSpacing.sm,
                  ),
                  child: KoraSectionHeader(title: S.t('home.stores')),
                ),
              ),
              stores.when(
                data: (list) => SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) {
                    final s = list[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,),
                      child: KoraStoreCard(
                        name: s.name,
                        imageUrl: s.logoUrl,
                        blurHash: s.blurHash,
                        category: s.description,
                        rating: s.rating,
                        etaMinutes: s.etaMinutes,
                        deliveryFeeTiyn: s.deliveryFeeTiyn,
                        isOpen: s.isOpen,
                        badge: s.deliveryFeeTiyn == 0
                            ? S.t('home.free_delivery')
                            : null,
                        onTap: () => context.push('/store/${s.id}'),
                      ),
                    );
                  },
                ),
                loading: () => const SliverToBoxAdapter(
                  child: Column(
                    children: [
                      KoraCardSkeleton(),
                      KoraCardSkeleton(),
                      KoraCardSkeleton(),
                    ],
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: KoraErrorState(
                    message: S.t('home.load_error'),
                    onRetry: () => ref.invalidate(storesProvider),
                  ),
                ),
              ),
              // Recently viewed — horizontal rail (§27).
              ref.watch(recentlyViewedProvider).when(
                    data: (list) => list.isEmpty
                        ? const SliverToBoxAdapter()
                        : SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: AppSpacing.lg),
                                KoraSectionHeader(
                                    title: S.t('recent.title'),),
                                const SizedBox(height: AppSpacing.sm),
                                SizedBox(
                                  height: 168,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    padding:
                                        const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.lg,
                                    ),
                                    itemCount: list.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(
                                            width: AppSpacing.sm,),
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
                  child: SizedBox(height: AppSpacing.huge),),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.promo});

  final Promotion promo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      padding: AppSpacing.cardPadding,
      decoration: const BoxDecoration(
        gradient: KoraColors.primaryGradient,
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              const Icon(AppIcons.promo,
                  color: KoraColors.white, size: 18,),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  promo.title,
                  style: AppTypography.titleSmall
                      .copyWith(color: KoraColors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (promo.subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              promo.subtitle!,
              style: AppTypography.caption
                  .copyWith(color: KoraColors.lightPurple),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
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
      onTap: () => context.push('/category/${category.id}?name=${Uri.encodeComponent(category.name)}'),
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
              child: const Icon(AppIcons.location,
                  color: KoraColors.white, size: 34,),
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
      onTap: () =>
          context.push('/store/${p.storeId}/product/${p.id}'),
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
