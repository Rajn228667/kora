import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_animations.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/utils/debounce.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/misc.dart';
import '../../../core/media/kora_image.dart';
import '../../cart/data/cart_repository.dart';
import '../data/catalog_repository.dart';

// ---------------------------------------------------------------------------
// Store screen — banner, info, product grid.
// ---------------------------------------------------------------------------

class StoreScreen extends ConsumerWidget {
  const StoreScreen({super.key, required this.storeId});

  final String storeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(storeProvider(storeId));
    final products = ref.watch(storeProductsProvider(storeId));
    final favorites = ref.watch(favoritesProvider).value ?? const <String>{};

    return Scaffold(
      body: store.when(
        loading: () => KoraLoadingState(message: S.t('store.loading')),
        error: (_, __) => KoraErrorState(
          message: S.t('store.load_error'),
          onRetry: () => ref.invalidate(storeProvider(storeId)),
        ),
        data: (s) => CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 160,
              pinned: true,
              leading: const BackButton(),
              actions: [
                IconButton(
                  tooltip: S.t('store.favorite'),
                  icon: Icon(
                    favorites.contains(s.id)
                        ? AppIcons.heart
                        : AppIcons.heartOut,
                    color: favorites.contains(s.id)
                        ? KoraColors.primary
                        : KoraColors.textSecondaryC,
                  ),
                  onPressed: () =>
                      ref.read(favoritesProvider.notifier).toggle(s.id),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: KoraColors.softGradient,
                  ),
                  child: s.bannerUrl != null
                      ? KoraImage(url: s.bannerUrl, blurHash: s.blurHash)
                      : const Center(
                          child: Icon(
                            AppIcons.store,
                            size: 56,
                            color: KoraColors.white,
                          ),
                        ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: AppSpacing.screenPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(s.name, style: AppTypography.headline),
                        ),
                        if (!s.isOpen)
                          KoraStatusChip(
                            label: S.t('store.closed'),
                            tone: KoraStatusTone.warning,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(s.description, style: AppTypography.bodySecondary),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.xs,
                      children: [
                        _InfoChip(
                          icon: AppIcons.star,
                          label: s.rating.toStringAsFixed(1),
                        ),
                        _InfoChip(
                          icon: AppIcons.clock,
                          label: '${s.etaMinutes} ${S.t('common.min')}',
                        ),
                        _InfoChip(
                          icon: AppIcons.bike,
                          label: s.deliveryFeeTiyn == 0
                              ? S.t('common.free')
                              : KoraPrice.format(s.deliveryFeeTiyn),
                        ),
                        _InfoChip(icon: AppIcons.clock, label: s.workingHours),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(S.t('store.menu'), style: AppTypography.title),
                  ],
                ),
              ),
            ),
            products.when(
              loading: () => const SliverToBoxAdapter(
                child: Column(
                  children: [KoraCardSkeleton(), KoraCardSkeleton()],
                ),
              ),
              error: (_, __) => SliverToBoxAdapter(
                child: KoraErrorState(
                  message: S.t('store.products_error'),
                ),
              ),
              data: (list) => list.isEmpty
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: AppSpacing.screenPadding,
                        child: KoraEmptyState(
                          icon: AppIcons.grocery,
                          title: S.t('catalog.empty'),
                          message: S.t('catalog.empty_sub'),
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: AppSpacing.md,
                          crossAxisSpacing: AppSpacing.md,
                          childAspectRatio: 0.72,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            final favIds =
                                ref.watch(favoriteProductsProvider).value ??
                                    const <String>{};
                            return KoraProductCard(
                              name: list[i].name,
                              priceTiyn: list[i].priceTiyn,
                              oldPriceTiyn: list[i].oldPriceTiyn,
                              imageUrl: list[i].imageUrl,
                              blurHash: list[i].blurHash,
                              available: list[i].available,
                              isFavorite: favIds.contains(list[i].id),
                              onFavorite: () => ref
                                  .read(favoriteProductsProvider.notifier)
                                  .toggle(list[i].id),
                              onTap: () => context.push(
                                '/store/$storeId/product/${list[i].id}',
                              ),
                              onAdd: () => ref
                                  .read(cartProvider.notifier)
                                  .add(list[i], 1)
                                  .then((_) {
                                if (context.mounted) {
                                  KoraSnackbar.show(
                                    context,
                                    S.t('product.added'),
                                  );
                                }
                              }),
                            );
                          },
                          childCount: list.length,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: KoraColors.primary),
        const SizedBox(width: AppSpacing.xxs),
        Text(label, style: AppTypography.caption),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Product screen — gallery, variants, characteristics, add-to-cart.
// ---------------------------------------------------------------------------

class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({
    super.key,
    required this.storeId,
    required this.productId,
  });

  final String storeId;
  final String productId;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  int _qty = 1;
  String? _variantId;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    // Recently viewed — recorded once per product screen open (§27).
    ref
        .read(catalogRepositoryProvider)
        .recordView(widget.productId)
        .then((_) => ref.invalidate(recentlyViewedProvider))
        .ignore();
  }

  @override
  Widget build(BuildContext context) {
    final product = ref.watch(productProvider(widget.productId));
    final favIds =
        ref.watch(favoriteProductsProvider).value ?? const <String>{};
    final isFav = favIds.contains(widget.productId);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        actions: [
          IconButton(
            tooltip: S.t('nav.favorites'),
            icon: Icon(
              isFav ? AppIcons.heart : AppIcons.heartOut,
              color: isFav ? KoraColors.primary : null,
            ),
            onPressed: () => ref
                .read(favoriteProductsProvider.notifier)
                .toggle(widget.productId),
          ),
        ],
      ),
      body: product.when(
        loading: () => const KoraLoadingState(),
        error: (_, __) => KoraErrorState(message: S.t('product.not_found')),
        data: (p) {
          final price = _variantId != null
              ? p.variants
                  .firstWhere(
                    (v) => v.id == _variantId,
                    orElse: () => p.variants.first,
                  )
                  .priceTiyn
              : p.priceTiyn;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: AppSpacing.screenPadding,
                  children: [
                    AspectRatio(
                      aspectRatio: 1.4,
                      child: Hero(
                        tag: 'product-${p.name}-${p.imageUrl}',
                        child: KoraImage(
                          url: p.imageUrl,
                          blurHash: p.blurHash,
                          borderRadius: AppRadius.lg,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(p.name, style: AppTypography.titleLarge),
                        ),
                        if (p.discountPercent > 0)
                          KoraBadge(
                            label: '−${p.discountPercent}%',
                            filled: true,
                          ),
                      ],
                    ),
                    if (p.description.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(p.description, style: AppTypography.bodySecondary),
                    ],
                    if (p.variants.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        S.t('product.variant'),
                        style: AppTypography.label,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: p.variants
                            .map(
                              (v) => ChoiceChip(
                                label: Text(
                                  '${v.name} · ${KoraPrice.format(v.priceTiyn)}',
                                ),
                                selected:
                                    (_variantId ?? p.variants.first.id) == v.id,
                                onSelected: (_) =>
                                    setState(() => _variantId = v.id),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    if (p.characteristics.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        S.t('product.characteristics'),
                        style: AppTypography.label,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...p.characteristics.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xxs,
                          ),
                          child: Row(
                            children: [
                              Text(e.key, style: AppTypography.caption),
                              const Spacer(),
                              Text(e.value, style: AppTypography.label),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SafeArea(
                child: Container(
                  padding: AppSpacing.cardPadding,
                  decoration: BoxDecoration(
                    color: KoraColors.surface,
                    border: Border(
                      top: BorderSide(color: KoraColors.softBorderC),
                    ),
                  ),
                  child: Row(
                    children: [
                      KoraQuantityStepper(
                        quantity: _qty,
                        onChanged: (q) => setState(() => _qty = q),
                        min: 1,
                        max: p.stock.clamp(1, 99),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: KoraButton(
                          label: S.t('product.add_to_cart', {
                            'price': KoraPrice.format(price * _qty),
                          }),
                          loading: _adding,
                          onPressed: p.available
                              ? () async {
                                  setState(() => _adding = true);
                                  await ref.read(cartProvider.notifier).add(
                                        p,
                                        _qty,
                                        variantId: _variantId,
                                      );
                                  if (context.mounted) {
                                    setState(() => _adding = false);
                                    KoraSnackbar.show(
                                      context,
                                      S.t('product.added'),
                                    );
                                  }
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

final productProvider = FutureProvider.family<Product, String>((ref, id) async {
  return ref.watch(catalogRepositoryProvider).product(id);
});

// ---------------------------------------------------------------------------
// Search — debounced, sections stores/products.
// ---------------------------------------------------------------------------

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _debouncer = Debouncer(const Duration(milliseconds: 350));
  SearchResults? _results;
  bool _loading = false;

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debouncer.run(() async {
      if (q.trim().isEmpty) {
        setState(() => _results = null);
        return;
      }
      setState(() => _loading = true);
      try {
        final res = await ref.read(catalogRepositoryProvider).search(q.trim());
        if (mounted) {
          setState(() {
            _results = res;
            _loading = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _loading = false;
            _results = const SearchResults(stores: [], products: []);
          });
          KoraSnackbar.show(context, S.t('common.error'), isError: true);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: KoraSearchField(
          controller: _controller,
          autofocus: true,
          onChanged: _onQuery,
          onClear: () => setState(() => _results = null),
        ),
        titleSpacing: 0,
      ),
      body: _loading
          ? const Column(
              children: [KoraCardSkeleton(), KoraCardSkeleton()],
            )
          : _results == null
              ? _SearchSuggestions(
                  onPick: (q) {
                    _controller.text = q;
                    _controller.selection =
                        TextSelection.collapsed(offset: q.length);
                    _onQuery(q);
                  },
                )
              : _results!.isEmpty
                  ? KoraEmptyState(
                      icon: AppIcons.search,
                      title: S.t('search.no_results'),
                      message: S.t('search.try_other'),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        if (_results!.products.isNotEmpty) ...[
                          Text(
                            S.t('search.products'),
                            style: AppTypography.title,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          ..._results!.products.map(
                            (p) => KoraCard(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              onTap: () => context.push(
                                '/store/${p.storeId}/product/${p.id}',
                              ),
                              child: Row(
                                children: [
                                  KoraImage(
                                    url: p.imageUrl,
                                    blurHash: p.blurHash,
                                    width: 52,
                                    height: 52,
                                    borderRadius: AppRadius.md,
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Text(
                                      p.name,
                                      style: AppTypography.label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  KoraPrice(tiyn: p.priceTiyn),
                                  const SizedBox(width: AppSpacing.sm),
                                  if (p.available)
                                    _QuickAddButton(
                                      onTap: () => ref
                                          .read(cartProvider.notifier)
                                          .add(p, 1)
                                          .then((_) {
                                        if (context.mounted) {
                                          KoraSnackbar.show(
                                            context,
                                            S.t('product.added'),
                                          );
                                        }
                                      }),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category — stores filtered by kind.
// ---------------------------------------------------------------------------

class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key, required this.categoryId, this.name});

  final String categoryId;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider).value ?? const [];
    final cat = cats.where((c) => c.id == categoryId).firstOrNull;
    final products = ref.watch(catalogProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(name ?? cat?.name ?? S.t('category.title')),
      ),
      body: products.when(
        loading: () => const Column(
          children: [KoraCardSkeleton(), KoraCardSkeleton()],
        ),
        error: (_, __) => KoraErrorState(
          message: S.t('category.load_error'),
          onRetry: () => ref.invalidate(catalogProvider),
        ),
        data: (list) {
          final filtered = cat == null
              ? list
              : list.where((p) => p.categoryId == cat.id).toList();
          if (filtered.isEmpty) {
            return KoraEmptyState(
              icon: AppIcons.category,
              title: S.t('catalog.empty'),
              message: S.t('catalog.empty_sub'),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 0.78,
            ),
            itemCount: filtered.length,
            itemBuilder: (_, i) => _GridProductTile(p: filtered[i]),
          );
        },
      ),
    );
  }
}

/// Grid tile shared by the category page — image, badge, price, add.
class _GridProductTile extends ConsumerWidget {
  const _GridProductTile({required this.p});

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
                  child: KoraImage(
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
                        '-$pct%',
                        style: AppTypography.caption.copyWith(
                          color: KoraColors.white,
                          fontWeight: FontWeight.w700,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          KoraPrice(
                            tiyn: p.priceTiyn,
                            style: AppTypography.label,
                          ),
                          if (old != null)
                            KoraPrice(
                              tiyn: old,
                              style: AppTypography.caption.copyWith(
                                color: KoraColors.placeholderC,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (p.available)
                      _QuickAddButton(
                        onTap: () =>
                            ref.read(cartProvider.notifier).add(p, 1).then((_) {
                          if (context.mounted) {
                            KoraSnackbar.show(
                              context,
                              S.t('product.added'),
                            );
                          }
                        }),
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

class _SearchSuggestions extends ConsumerWidget {
  const _SearchSuggestions({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider).value ?? const [];
    final recent = ref.watch(recentlyViewedProvider).value ?? const [];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (cats.isNotEmpty) ...[
          Text(S.t('home.categories'), style: AppTypography.title),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: cats
                .map(
                  (c) => ActionChip(
                    label: Text(c.name),
                    onPressed: () => onPick(c.name),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        if (recent.isNotEmpty) ...[
          Text(S.t('home.recent'), style: AppTypography.title),
          const SizedBox(height: AppSpacing.sm),
          ...recent.take(5).map(
                (p) => KoraCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  onTap: () =>
                      context.push('/store/${p.storeId}/product/${p.id}'),
                  child: Row(
                    children: [
                      KoraImage(
                        url: p.imageUrl,
                        blurHash: p.blurHash,
                        width: 44,
                        height: 44,
                        borderRadius: AppRadius.md,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          p.name,
                          style: AppTypography.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      KoraPrice(tiyn: p.priceTiyn),
                    ],
                  ),
                ),
              ),
        ] else
          KoraEmptyState(
            icon: AppIcons.search,
            title: S.t('search.title'),
            message: S.t('search.empty'),
          ),
      ],
    );
  }
}

class _QuickAddButton extends StatelessWidget {
  const _QuickAddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KoraPressable(
      onTap: onTap,
      semanticLabel: S.t('product.add_to_cart_short'),
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          gradient: KoraColors.primaryGradient,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          AppIcons.add,
          color: KoraColors.white,
          size: 20,
        ),
      ),
    );
  }
}
