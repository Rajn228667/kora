import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/maps/map_provider.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/fields.dart';
import '../../../core/widgets/misc.dart';
import '../../cart/data/cart_repository.dart';
import '../../orders/data/orders_repository.dart';
import '../data/checkout_repository.dart';

// ---------------------------------------------------------------------------
// Checkout — validate → delivery point → comment → Kaspi → create order.
// ---------------------------------------------------------------------------

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, this.promoCode, this.discountTiyn = 0});

  final String? promoCode;
  final int discountTiyn;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  Address? _address;
  GeoPoint? _pickedPoint;
  String? _pickedAddress;
  final _comment = TextEditingController();
  bool _placing = false;
  List<CheckoutIssue>? _issues;

  @override
  void initState() {
    super.initState();
    _validate();
    _loadDefaultAddress();
  }

  Future<void> _loadDefaultAddress() async {
    try {
      final list =
          await ref.read(checkoutRepositoryProvider).addresses();
      if (!mounted || list.isEmpty) return;
      setState(() => _address =
          list.where((a) => a.isDefault).firstOrNull ?? list.first,);
    } catch (_) {/* address optional */}
  }

  Future<void> _validate() async {
    try {
      final issues = await ref.read(checkoutRepositoryProvider).validate();
      if (mounted) setState(() => _issues = issues);
    } catch (_) {/* validate again on submit */}
  }

  GeoPoint? get _deliveryPoint =>
      _pickedPoint ?? _address?.point;

  String? get _deliveryAddress =>
      _pickedAddress ?? _address?.address;

  Future<void> _pickOnMap() async {
    final result = await context.push<MapPickResult>('/map-picker');
    if (result != null && mounted) {
      setState(() {
        _pickedPoint = result.point;
        _pickedAddress = result.address;
      });
    }
  }

  Future<void> _placeOrder() async {
    if (_deliveryPoint == null) {
      KoraSnackbar.show(context, S.t('checkout.need_address'),
          isError: true,);
      return;
    }
    setState(() => _placing = true);
    try {
      final issues = await ref.read(checkoutRepositoryProvider).validate();
      if (issues.isNotEmpty) {
        setState(() {
          _issues = issues;
          _placing = false;
        });
        return;
      }
      final result = await ref.read(checkoutRepositoryProvider).checkout(
            addressId: _pickedPoint == null ? _address?.id : null,
            point: _deliveryPoint,
            address: _deliveryAddress,
            comment: _comment.text.trim(),
            promoCode: widget.promoCode,
          );
      ref.invalidate(cartProvider);
      ref.invalidate(ordersProvider);
      if (!mounted) return;
      context.pushReplacement('/order-success',
          extra: result.order,);
    } on ApiException catch (e) {
      KoraSnackbar.show(context, e.message, isError: true);
      setState(() => _placing = false);
    }
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider).value;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('checkout.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (_issues != null && _issues!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: KoraColors.warningSurfaceC,
                borderRadius: AppRadius.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.t('checkout.check_cart'),
                      style: AppTypography.titleSmall,),
                  ..._issues!.map((i) => Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text('• ${i.message}',
                            style: AppTypography.caption,),
                      ),),
                ],
              ),
            ),
          Text(S.t('checkout.address'), style: AppTypography.title),
          const SizedBox(height: AppSpacing.sm),
          _AddressSelector(
            selected: _address,
            pickedAddress: _pickedAddress,
            onSelect: (a) => setState(() {
              _address = a;
              _pickedPoint = null;
              _pickedAddress = null;
            }),
            onPickMap: _pickOnMap,
          ),
          const SizedBox(height: AppSpacing.xl),
          KoraTextField(
            controller: _comment,
            label: S.t('checkout.comment'),
            hint: S.t('checkout.comment_hint'),
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(S.t('checkout.payment'), style: AppTypography.title),
          const SizedBox(height: AppSpacing.sm),
          const KoraCard(
            child: Row(
              children: [
                Icon(AppIcons.wallet, color: KoraColors.primary),
                SizedBox(width: AppSpacing.md),
                Expanded(child: Text('Kaspi')),
                Icon(AppIcons.check, color: KoraColors.primary),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (cart != null)
            _Summary(
              cart: cart,
              discount: widget.discountTiyn,
            ),
          const SizedBox(height: AppSpacing.xl),
          KoraButton(
            label: S.t('checkout.pay'),
            icon: AppIcons.wallet,
            loading: _placing,
            onPressed: _placeOrder,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            S.t('checkout.terms_note'),
            style: AppTypography.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AddressSelector extends ConsumerWidget {
  const _AddressSelector({
    required this.selected,
    required this.pickedAddress,
    required this.onSelect,
    required this.onPickMap,
  });

  final Address? selected;
  final String? pickedAddress;
  final ValueChanged<Address> onSelect;
  final VoidCallback onPickMap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(addressesProvider);
    return Column(
      children: [
        addresses.when(
          loading: () => const KoraSkeleton(height: 64, radius: 16),
          error: (_, __) => const SizedBox.shrink(),
          data: (list) => Column(
            children: list
                .map(
                  (a) => Padding(
                    padding:
                        const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _AddressTile(
                      address: a,
                      selected:
                          pickedAddress == null && selected?.id == a.id,
                      onTap: () => onSelect(a),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        KoraCard(
          onTap: onPickMap,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: KoraColors.selected,
                  shape: BoxShape.circle,
                ),
                child: const Icon(AppIcons.map,
                    color: KoraColors.primary, size: 20,),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  pickedAddress ?? S.t('checkout.pick_map'),
                  style: AppTypography.label.copyWith(
                    color: pickedAddress != null
                        ? KoraColors.textPrimaryC
                        : KoraColors.primary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(AppIcons.chevronR,
                  color: KoraColors.placeholderC,),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({
    required this.address,
    required this.selected,
    required this.onTap,
  });

  final Address address;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KoraCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            selected ? AppIcons.location : AppIcons.locationOut,
            color: selected ? KoraColors.primary : KoraColors.placeholderC,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(address.label, style: AppTypography.label),
                Text(
                  address.address,
                  style: AppTypography.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (selected)
            const Icon(AppIcons.check, color: KoraColors.primary),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.cart, required this.discount});

  final Cart cart;
  final int discount;

  @override
  Widget build(BuildContext context) {
    final total = cart.totalTiyn - discount;
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: KoraColors.surfaceAlt,
        borderRadius: AppRadius.card,
      ),
      child: Column(
        children: [
          _row(S.t('cart.items_count', {'count': '${cart.itemCount}'}),
              KoraPrice.format(cart.subtotalTiyn),),
          _row(
            S.t('cart.delivery'),
            cart.deliveryTiyn == 0
                ? S.t('common.free')
                : KoraPrice.format(cart.deliveryTiyn),
          ),
          if (discount > 0)
            _row(S.t('promo.title'), '−${KoraPrice.format(discount)}'),
          const Divider(height: AppSpacing.xl),
          _row(S.t('checkout.to_pay'), KoraPrice.format(total), bold: true),
        ],
      ),
    );
  }

  Widget _row(String l, String v, {bool bold = false}) {
    final s = bold ? AppTypography.titleSmall : AppTypography.bodySecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(children: [Text(l, style: s), const Spacer(), Text(v, style: s)]),
    );
  }
}

// ---------------------------------------------------------------------------
// Map picker — permission explanation → locate → draggable point → confirm.
// ---------------------------------------------------------------------------

class MapPickResult {
  const MapPickResult({required this.point, this.address});
  final GeoPoint point;
  final String? address;
}

class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final GeoPoint _center = const GeoPoint(lat: 42.3417, lng: 69.5901);
  GeoPoint? _picked;
  final _address = TextEditingController();
  bool _locating = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          KoraSnackbar.show(
            context,
            S.t('map.no_gps'),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _picked = GeoPoint(lat: pos.latitude, lng: pos.longitude));
      }
    } catch (_) {
      if (mounted) {
        KoraSnackbar.show(context, S.t('map.locate_fail'));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('map.title')),
      ),
      body: Column(
        children: [
          Padding(
            padding: AppSpacing.screenPadding,
            child: Container(
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: KoraColors.selected,
                borderRadius: AppRadius.card,
              ),
              child: Row(
                children: [
                  Icon(AppIcons.info, color: KoraColors.accentText),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      S.t('map.info'),
                      style: AppTypography.caption
                          .copyWith(color: KoraColors.accentText),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,),
              child: KoraMap(
                center: _picked ?? _center,
                onTapPick: (p) => setState(() => _picked = p),
                picked: _picked,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                children: [
                  KoraTextField(
                    controller: _address,
                    hint: S.t('map.address_hint'),
                    prefixIcon: AppIcons.locationOut,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: KoraOutlinedButton(
                          label: S.t('map.my_location'),
                          icon: AppIcons.navigate,
                          onPressed: _locating ? null : _locate,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: KoraButton(
                          label: S.t('common.confirm'),
                          onPressed: _picked == null
                              ? null
                              : () => context.pop(
                                    MapPickResult(
                                      point: _picked!,
                                      address:
                                          _address.text.trim().isEmpty
                                              ? S.t('map.point_auto', {
                                                  'lat': _picked!.lat
                                                      .toStringAsFixed(4),
                                                  'lng': _picked!.lng
                                                      .toStringAsFixed(4),
                                                })
                                              : _address.text.trim(),
                                    ),
                                  ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
