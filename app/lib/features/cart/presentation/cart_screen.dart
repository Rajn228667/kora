import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/media/kora_image.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/misc.dart';
import '../../catalog/data/catalog_repository.dart';
import '../data/cart_repository.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _promoController = TextEditingController();
  int _promoDiscount = 0;
  String? _promoCode;
  String? _promoMessage;
  bool _promoLoading = false;

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _applyPromo(Cart cart) async {
    final code = _promoController.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _promoLoading = true;
      _promoMessage = null;
    });
    final res = await ref
        .read(catalogRepositoryProvider)
        .validatePromo(code, cart.storeId);
    if (!mounted) return;
    setState(() {
      _promoLoading = false;
      _promoMessage = res.message;
      if (res.valid) {
        _promoDiscount = res.discountTiyn;
        _promoCode = code;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('cart.title')),
        actions: [
          if (cart.value?.isEmpty == false)
            IconButton(
              tooltip: S.t('cart.clear'),
              icon: const Icon(AppIcons.delete),
              onPressed: () async {
                final ok = await KoraDialog.confirm(
                  context,
                  title: S.t('cart.clear_title'),
                  message: S.t('cart.clear_msg'),
                  destructive: true,
                  confirmLabel: S.t('cart.clear_confirm'),
                );
                if (ok) {
                  await ref.read(cartRepositoryProvider).clear();
                  ref.invalidate(cartProvider);
                }
              },
            ),
        ],
      ),
      body: cart.when(
        loading: () => const KoraLoadingState(),
        error: (_, __) => KoraErrorState(
          message: S.t('cart.load_error'),
          onRetry: () => ref.invalidate(cartProvider),
        ),
        data: (c) => c.isEmpty
            ? KoraEmptyState(
                icon: AppIcons.cart,
                title: S.t('cart.empty'),
                message: S.t('cart.empty_sub'),
              )
            : _buildCart(context, c),
      ),
    );
  }

  Widget _buildCart(BuildContext context, Cart cart) {
    final total = cart.totalTiyn - _promoDiscount;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (cart.storeName.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    children: [
                      const Icon(AppIcons.store,
                          size: 18, color: KoraColors.primary,),
                      const SizedBox(width: AppSpacing.xs),
                      Text(cart.storeName, style: AppTypography.titleSmall),
                    ],
                  ),
                ),
              ...cart.items.map((item) => _CartItemTile(item: item)),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: KoraTextField(
                      controller: _promoController,
                      hint: S.t('cart.promo_hint'),
                      prefixIcon: AppIcons.promo,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  KoraOutlinedButton(
                    label: S.t('common.ok'),
                    expanded: false,
                    onPressed: _promoLoading ? null : () => _applyPromo(cart),
                  ),
                ],
              ),
              if (_promoMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _promoMessage!,
                    style: AppTypography.caption.copyWith(
                      color: _promoDiscount > 0
                          ? KoraColors.accentText
                          : KoraColors.error,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              _Totals(
                subtotal: cart.subtotalTiyn,
                delivery: cart.deliveryTiyn,
                discount: _promoDiscount,
                total: total,
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: AppSpacing.screenPadding,
            child: KoraButton(
              label: S.t('cart.checkout',
                  {'price': KoraPrice.format(total)},),
              icon: AppIcons.chevronR,
              onPressed: () => context.push('/checkout',
                  extra: {'promoCode': _promoCode, 'discount': _promoDiscount},),
            ),
          ),
        ),
      ],
    );
  }
}

class _CartItemTile extends ConsumerWidget {
  const _CartItemTile({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = item.variantId == null
        ? null
        : item.product.variants
            .where((v) => v.id == item.variantId)
            .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          KoraImage(
            url: item.product.imageUrl,
            blurHash: item.product.blurHash,
            width: 56,
            height: 56,
            borderRadius: AppRadius.md,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name +
                      (variant != null ? ' · ${variant.name}' : ''),
                  style: AppTypography.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                KoraPrice(
                  tiyn: item.totalTiyn,
                  style: AppTypography.caption
                      .copyWith(color: KoraColors.textPrimaryC),
                ),
              ],
            ),
          ),
          KoraQuantityStepper(
            quantity: item.quantity,
            compact: true,
            onChanged: (q) =>
                ref.read(cartProvider.notifier).setQty(item.id, q),
          ),
        ],
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({
    required this.subtotal,
    required this.delivery,
    required this.discount,
    required this.total,
  });

  final int subtotal;
  final int delivery;
  final int discount;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: KoraColors.surfaceAlt,
        borderRadius: AppRadius.card,
      ),
      child: Column(
        children: [
          _row(S.t('cart.items'), KoraPrice.format(subtotal)),
          _row(
            S.t('cart.delivery'),
            delivery == 0 ? S.t('common.free') : KoraPrice.format(delivery),
          ),
          if (discount > 0)
            _row(S.t('cart.discount'), '−${KoraPrice.format(discount)}',
                accent: true,),
          const Divider(height: AppSpacing.xl),
          _row(S.t('cart.total'), KoraPrice.format(total), bold: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, bool accent = false,}) {
    final style = bold
        ? AppTypography.titleSmall
        : AppTypography.bodySecondary.copyWith(
            color: accent ? KoraColors.accentText : KoraColors.textSecondaryC,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(value, style: style),
        ],
      ),
    );
  }
}
