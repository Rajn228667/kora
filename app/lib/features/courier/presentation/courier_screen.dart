import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/maps/map_provider.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/utils/debounce.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/misc.dart';

class CourierRepository {
  CourierRepository(this._ref);

  final Ref _ref;

  Future<void> setStatus(bool online) => _ref
      .read(apiClientProvider)
      .post('/couriers/status', body: {'status': online ? 'online' : 'offline'});

  Future<void> postLocation(GeoPoint p) => _ref
      .read(apiClientProvider)
      .post('/couriers/location', body: {...p.toJson(), 'ts': DateTime.now().toUtc().toIso8601String()});

  Future<List<CourierOffer>> offers() async {
    final res = await _ref
        .read(apiClientProvider)
        .get('/couriers/assignments') as Map<String, dynamic>;
    return (res['items'] as List).map((o) {
      final j = o as Map<String, dynamic>;
      return CourierOffer(
        id: j['id'] as String,
        orderId: j['orderId'] as String,
        orderNumber: j['orderNumber'] as String? ?? '',
        storeName: j['storeName'] as String? ?? '',
        pickupAddress: j['pickupAddress'] as String? ?? '',
        pickup:
            GeoPoint.fromJson((j['pickup'] as Map).cast<String, dynamic>()),
        dropoffAddress: j['dropoffAddress'] as String? ?? '',
        dropoff: GeoPoint.fromJson(
            (j['dropoff'] as Map).cast<String, dynamic>(),),
        feeTiyn: (j['feeTiyn'] as num?)?.toInt() ?? 0,
        distanceKm: (j['distanceKm'] as num?)?.toDouble() ?? 0,
        expiresAt: DateTime.tryParse(j['expiresAt'] as String? ?? '') ??
            DateTime.now(),
      );
    }).toList();
  }

  Future<void> respond(String offerId, bool accept) => _ref
      .read(apiClientProvider)
      .post('/couriers/assignments/$offerId/${accept ? 'accept' : 'reject'}');

  /// Courier advances the active delivery: pickedUp → delivering → delivered.
  Future<void> advanceOrder(String orderId, String status) => _ref
      .read(apiClientProvider)
      .post('/couriers/orders/$orderId/status', body: {'status': status});
}

final courierRepoProvider = Provider((ref) => CourierRepository(ref));

final courierOffersProvider = AsyncNotifierProvider<CourierOffersController,
    List<CourierOffer>>(CourierOffersController.new);

class CourierOffersController extends AsyncNotifier<List<CourierOffer>> {
  @override
  Future<List<CourierOffer>> build() =>
      ref.watch(courierRepoProvider).offers();

  Future<void> refresh() async {
    state = AsyncData(await ref.read(courierRepoProvider).offers());
  }
}

/// Courier mode: online toggle → order offers → active delivery flow.
class CourierScreen extends ConsumerStatefulWidget {
  const CourierScreen({super.key});

  @override
  ConsumerState<CourierScreen> createState() => _CourierScreenState();
}

class _CourierScreenState extends ConsumerState<CourierScreen> {
  bool _online = false;
  CourierOffer? _active;
  int _activeStep = 0; // 0 → to store, 1 → picked up, 2 → en route
  StreamSubscription<Position>? _gps;
  final _throttle = Throttler(const Duration(seconds: 5));

  @override
  void dispose() {
    _gps?.cancel();
    super.dispose();
  }

  Future<void> _toggleOnline(bool v) async {
    await ref.read(courierRepoProvider).setStatus(v);
    setState(() => _online = v);
    if (v) {
      await ref.read(courierOffersProvider.notifier).refresh();
      unawaited(_startGps());
    } else {
      await _gps?.cancel();
      setState(() {
        _active = null;
        _activeStep = 0;
      });
    }
  }

  Future<void> _startGps() async {
    unawaited(_gps?.cancel());
    try {
      // Explicit permission prompt — couriers must grant location so the
      // live tracker and free-courier map actually work.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          KoraSnackbar.show(
            context,
            S.t('courier.gps_denied'),
            isError: true,
          );
        }
        return;
      }
      _gps = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        ),
      ).listen((pos) {
        // Post while online — free couriers show up on the manager map
        // and tracking stays warm for the next assignment.
        if (_throttle.ready) {
          _throttle.mark();
          unawaited(
            ref
                .read(courierRepoProvider)
                .postLocation(
                    GeoPoint(lat: pos.latitude, lng: pos.longitude),)
                .catchError((_) {}),
          );
        }
      });
    } catch (_) {/* location service unavailable — manual mode */}
  }

  @override
  Widget build(BuildContext context) {
    final offers = ref.watch(courierOffersProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('courier.title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          KoraCard(
            elevated: true,
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: _online
                        ? KoraColors.primaryGradient
                        : null,
                    color: _online ? null : KoraColors.softBorderC,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    AppIcons.courier,
                    color: _online
                        ? KoraColors.white
                        : KoraColors.placeholderC,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _online
                            ? S.t('courier.online')
                            : S.t('courier.offline'),
                        style: AppTypography.titleSmall,
                      ),
                      Text(
                        _online
                            ? S.t('courier.online_sub')
                            : S.t('courier.offline_sub'),
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _online,
                  onChanged: _toggleOnline,
                  activeThumbColor: KoraColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_active != null) ...[
            _ActiveDelivery(
              offer: _active!,
              step: _activeStep,
              onAdvance: _advance,
              onChat: () => context.push('/chat/${_active!.orderId}'),
              onOpenOrder: () =>
                  context.push('/orders/${_active!.orderId}'),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text(S.t('courier.offers'), style: AppTypography.title),
          const SizedBox(height: AppSpacing.sm),
          if (!_online)
            KoraEmptyState(
              icon: AppIcons.courier,
              title: S.t('courier.offline_title'),
              message: S.t('courier.offline_hint'),
            )
          else
            offers.when(
              loading: () => const KoraCardSkeleton(),
              error: (_, __) => KoraErrorState(
                message: S.t('courier.load_error'),
                onRetry: () => ref
                    .read(courierOffersProvider.notifier)
                    .refresh(),
              ),
              data: (list) => list.isEmpty
                  ? KoraEmptyState(
                      icon: AppIcons.clock,
                      title: S.t('courier.no_offers'),
                      message: S.t('courier.no_offers_sub'),
                    )
                  : Column(
                      children: list
                          .map((o) => Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm,),
                                child: _OfferCard(
                                  offer: o,
                                  onAccept: () async {
                                    await ref
                                        .read(courierRepoProvider)
                                        .respond(o.id, true);
                                    setState(() {
                                      _active = o;
                                      _activeStep = 0;
                                    });
                                    await ref
                                        .read(courierOffersProvider
                                            .notifier,)
                                        .refresh();
                                  },
                                  onReject: () async {
                                    await ref
                                        .read(courierRepoProvider)
                                        .respond(o.id, false);
                                    await ref
                                        .read(courierOffersProvider
                                            .notifier,)
                                        .refresh();
                                  },
                                ),
                              ),)
                          .toList(),
                    ),
            ),
        ],
      ),
    );
  }

  Future<void> _advance() async {
    final offer = _active;
    if (offer == null) return;
    const steps = ['pickedUp', 'delivering', 'delivered'];
    final status = steps[_activeStep];
    try {
      await ref
          .read(courierRepoProvider)
          .advanceOrder(offer.orderId, status);
      if (!mounted) return;
      if (status == 'delivered') {
        setState(() {
          _active = null;
          _activeStep = 0;
        });
        KoraSnackbar.show(context, S.t('courier.done'));
        await ref.read(courierOffersProvider.notifier).refresh();
      } else {
        setState(() => _activeStep++);
      }
    } catch (_) {
      if (mounted) {
        KoraSnackbar.show(context, S.t('common.error'), isError: true);
      }
    }
  }
}

/// Active delivery panel: pickup → deliver progression + shortcuts to
/// the order detail and customer chat.
class _ActiveDelivery extends StatelessWidget {
  const _ActiveDelivery({
    required this.offer,
    required this.step,
    required this.onAdvance,
    required this.onChat,
    required this.onOpenOrder,
  });

  final CourierOffer offer;
  final int step;
  final VoidCallback onAdvance;
  final VoidCallback onChat;
  final VoidCallback onOpenOrder;

  @override
  Widget build(BuildContext context) {
    final cta = switch (step) {
      0 => S.t('courier.picked_up'),
      1 => S.t('courier.en_route'),
      _ => S.t('courier.delivered_btn'),
    };
    return KoraCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  S.t('courier.active_order',
                      {'number': offer.orderNumber},),
                  style: AppTypography.titleSmall,
                ),
              ),
              IconButton(
                onPressed: onChat,
                icon: const Icon(AppIcons.chatOut,
                    color: KoraColors.primary,),
                tooltip: S.t('order.chat'),
              ),
              IconButton(
                onPressed: onOpenOrder,
                icon: const Icon(AppIcons.chevronR,
                    color: KoraColors.primary,),
                tooltip: S.t('orders.details'),
              ),
            ],
          ),
          _leg(AppIcons.store, offer.storeName, offer.pickupAddress),
          const SizedBox(height: AppSpacing.xs),
          _leg(AppIcons.location, S.t('courier.customer'),
              offer.dropoffAddress,),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 140,
            child: KoraMap(
              center: step >= 1 ? offer.dropoff : offer.pickup,
              markers: [
                KoraMarker(
                    point: offer.pickup,
                    kind: KoraMarkerKind.store,
                    label: offer.storeName,),
                KoraMarker(
                    point: offer.dropoff,
                    kind: KoraMarkerKind.deliveryPoint,),
              ],
              route: [offer.pickup, offer.dropoff],
              interactive: false,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: KoraButton(label: cta, onPressed: onAdvance),
          ),
        ],
      ),
    );
  }

  Widget _leg(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Icon(icon, size: 18, color: KoraColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.label),
              Text(subtitle,
                  style: AppTypography.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,),
            ],
          ),
        ),
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.onAccept,
    required this.onReject,
  });

  final CourierOffer offer;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return KoraCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    S.t('courier.order', {'number': offer.orderNumber}),
                    style: AppTypography.titleSmall,),
              ),
              KoraPrice(tiyn: offer.feeTiyn),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _leg(AppIcons.store, offer.storeName, offer.pickupAddress),
          const SizedBox(height: AppSpacing.xs),
          _leg(AppIcons.location, S.t('courier.customer'),
              offer.dropoffAddress,),
          const SizedBox(height: AppSpacing.sm),
          Text(
              S.t('courier.km',
                  {'km': offer.distanceKm.toStringAsFixed(1)},),
              style: AppTypography.caption,),
          SizedBox(
            height: 140,
            child: KoraMap(
              center: offer.pickup,
              markers: [
                KoraMarker(
                    point: offer.pickup,
                    kind: KoraMarkerKind.store,
                    label: offer.storeName,),
                KoraMarker(
                    point: offer.dropoff,
                    kind: KoraMarkerKind.deliveryPoint,),
              ],
              route: [offer.pickup, offer.dropoff],
              interactive: false,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: KoraOutlinedButton(
                  label: S.t('courier.reject'),
                  onPressed: onReject,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: KoraButton(
                  label: S.t('courier.accept'),
                  onPressed: onAccept,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _leg(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Icon(icon, size: 18, color: KoraColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.label),
              Text(subtitle,
                  style: AppTypography.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,),
            ],
          ),
        ),
      ],
    );
  }
}
