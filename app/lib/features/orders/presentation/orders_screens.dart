import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/maps/map_provider.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_metrics.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/kora_colors.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/misc.dart';
import '../../../core/providers.dart';
import '../../cart/data/cart_repository.dart';
import '../data/orders_repository.dart';

// ---------------------------------------------------------------------------
// Order success — after checkout + payment initiation.
// ---------------------------------------------------------------------------

class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: Column(
            children: [
              const Spacer(),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutBack,
                builder: (_, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    gradient: KoraColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(AppIcons.check,
                      size: 48, color: KoraColors.white,),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(S.t('success.title'), style: AppTypography.headline),
              const SizedBox(height: AppSpacing.sm),
              Text(
                S.t('success.subtitle', {
                  'number': order.number,
                  'store': order.storeName,
                }),
                textAlign: TextAlign.center,
                style: AppTypography.bodySecondary,
              ),
              const Spacer(),
              KoraButton(
                label: S.t('success.track'),
                onPressed: () =>
                    context.pushReplacement('/orders/${order.id}'),
              ),
              const SizedBox(height: AppSpacing.sm),
              KoraGhostButton(
                label: S.t('success.home'),
                onPressed: () => context.go('/home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Orders list.
// ---------------------------------------------------------------------------

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(S.t('orders.title'))),
      body: orders.when(
        loading: () => const Column(
          children: [KoraCardSkeleton(), KoraCardSkeleton()],
        ),
        error: (_, __) => KoraErrorState(
          message: S.t('orders.load_error'),
          onRetry: () => ref.read(ordersProvider.notifier).refresh(),
        ),
        data: (list) => list.isEmpty
            ? KoraEmptyState(
                icon: AppIcons.orders,
                title: S.t('orders.empty'),
                message: S.t('orders.empty_sub'),
              )
            : RefreshIndicator(
                color: KoraColors.primary,
                onRefresh: () =>
                    ref.read(ordersProvider.notifier).refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) => _OrderTile(order: list[i]),
                ),
              ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    return KoraCard(
      onTap: () => context.push('/orders/${order.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    S.t('order.number', {'number': order.number}),
                    style: AppTypography.titleSmall,),
              ),
              _statusChip(order.status),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(order.storeName, style: AppTypography.bodySecondary),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Text(
                DateFormat('d MMM, HH:mm', S.lang.name)
                    .format(order.createdAt),
                style: AppTypography.caption,
              ),
              const Spacer(),
              KoraPrice(tiyn: order.totalTiyn),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _statusChip(OrderStatus s) {
  final tone = switch (s) {
    OrderStatus.delivered => KoraStatusTone.success,
    OrderStatus.cancelled || OrderStatus.rejected => KoraStatusTone.error,
    OrderStatus.pending => KoraStatusTone.warning,
    _ => KoraStatusTone.active,
  };
  return KoraStatusChip(label: orderStatusLabel(s), tone: tone);
}

// ---------------------------------------------------------------------------
// Order detail — timeline, items, cancel, live tracking, chat.
// ---------------------------------------------------------------------------

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(orderDetailProvider(orderId));
    final order = detail.value;
    if (order == null) {
      // Loading → spinner; loaded but missing → honest error state.
      if (detail.isLoading) {
        return Scaffold(
          appBar: AppBar(leading: const BackButton()),
          body: const KoraLoadingState(),
        );
      }
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: KoraErrorState(
          message: S.t('error.not_found'),
          onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
        ),
      );
    }
    final showMap = {
      OrderStatus.courierAssigned,
      OrderStatus.pickedUp,
      OrderStatus.delivering,
    }.contains(order.status);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(S.t('order.title', {'number': order.number})),
        actions: [
          IconButton(
            tooltip: S.t('order.chat'),
            icon: const Icon(AppIcons.chatOut),
            onPressed: () => context.push('/chat/${order.id}'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (showMap) ...[
            _DeliveryMapCard(order: order),
            const SizedBox(height: AppSpacing.lg),
          ],
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.storeName, style: AppTypography.titleLarge),
                    Text(
                      DateFormat('d MMMM, HH:mm', S.lang.name)
                          .format(order.createdAt),
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              _statusChip(order.status),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          KoraStatusChip(
            label: S.t('order.payment',
                {'status': paymentStatusLabel(order.paymentStatus)},),
            tone: order.paymentStatus == PaymentStatus.paid
                ? KoraStatusTone.success
                : KoraStatusTone.warning,
          ),
          const SizedBox(height: AppSpacing.xl),
          if (order.courierName != null) ...[
            KoraCard(
              child: Row(
                children: [
                  KoraAvatar(
                      initials: S.t('call.courier').substring(0, 1),
                      radius: 22,),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.courierName!,
                            style: AppTypography.label,),
                        Text(S.t('order.courier'),
                            style: AppTypography.caption,),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: S.t('order.call_courier'),
                    icon: const Icon(AppIcons.call,
                        color: KoraColors.primary,),
                    onPressed: () async {
                      final phone = order.courierPhone;
                      if (phone != null &&
                          phone.isNotEmpty &&
                          await launchUrl(Uri.parse('tel:$phone'))) {
                        return;
                      }
                      if (context.mounted) {
                        KoraSnackbar.show(
                            context, S.t('call.unavailable'),
                            isError: true,);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text(S.t('order.status'), style: AppTypography.title),
          const SizedBox(height: AppSpacing.sm),
          _Timeline(history: order.statusHistory, current: order.status),
          const SizedBox(height: AppSpacing.xl),
          Text(S.t('order.items'), style: AppTypography.title),
          const SizedBox(height: AppSpacing.sm),
          ...order.items.map(
            (i) => Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Text('${i.quantity}×', style: AppTypography.caption),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(i.name, style: AppTypography.body)),
                  KoraPrice(
                    tiyn: i.totalTiyn,
                    style: AppTypography.label,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: AppSpacing.xxl),
          _row(S.t('cart.delivery'),
              order.deliveryTiyn == 0
                  ? S.t('common.free')
                  : KoraPrice.format(order.deliveryTiyn),),
          if (order.discountTiyn > 0)
            _row(S.t('cart.discount'),
                '−${KoraPrice.format(order.discountTiyn)}',),
          _row(S.t('cart.total'), KoraPrice.format(order.totalTiyn),
              bold: true,),
          if (order.status == OrderStatus.delivered ||
              order.status == OrderStatus.cancelled) ...[
            const SizedBox(height: AppSpacing.lg),
            KoraOutlinedButton(
              label: S.t('order.repeat'),
              icon: AppIcons.cart,
              onPressed: () async {
                await ref
                    .read(apiClientProvider)
                    .post('/orders/${order.id}/repeat');
                if (!context.mounted) return;
                ref.invalidate(cartProvider);
                KoraSnackbar.show(
                    context, S.t('order.repeated'),);
                unawaited(context.push('/cart'));
              },
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          KoraCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(AppIcons.location,
                        size: 18, color: KoraColors.primary,),
                    const SizedBox(width: AppSpacing.xs),
                    Text(S.t('order.delivery_to'),
                        style: AppTypography.label,),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(order.delivery.address,
                    style: AppTypography.bodySecondary,),
                if (order.delivery.comment != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                      S.t('order.comment',
                          {'comment': order.delivery.comment!},),
                      style: AppTypography.caption,),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (order.canCancel)
            KoraOutlinedButton(
              label: S.t('order.cancel'),
              icon: AppIcons.close,
              onPressed: () async {
                final ok = await KoraDialog.confirm(
                  context,
                  title: S.t('order.cancel_title'),
                  message: S.t('order.cancel_msg'),
                  destructive: true,
                  confirmLabel: S.t('order.cancel'),
                );
                if (ok && context.mounted) {
                  await ref
                      .read(ordersProvider.notifier)
                      .cancel(order.id);
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _row(String l, String v, {bool bold = false}) {
    final s = bold ? AppTypography.titleSmall : AppTypography.bodySecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
          children: [Text(l, style: s), const Spacer(), Text(v, style: s)],),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.history, required this.current});

  final List<OrderStatusEntry> history;
  final OrderStatus current;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: history.reversed.map((h) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: KoraColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (h != history.first)
                  Container(
                    width: 2,
                    height: 28,
                    color: KoraColors.selected,
                  ),
              ],
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(orderStatusLabel(h.status),
                        style: AppTypography.label,),
                    Text(
                      DateFormat('HH:mm').format(h.at),
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

/// Live delivery card: courier > customer route with traffic-colored
/// segments (green/amber/red) plus distance and ETA � Wolt/Yandex style.
class _DeliveryMapCard extends StatelessWidget {
  const _DeliveryMapCard({required this.order});

  final Order order;

  /// Straight courier>customer path, gently curved � until a routing
  /// provider (2GIS/Yandex) supplies real road geometry.
  List<GeoPoint> _route(GeoPoint from, GeoPoint to) {
    const n = 10;
    final dx = to.lng - from.lng;
    final dy = to.lat - from.lat;
    // Perpendicular offset for a slight arc � reads like a road bend.
    final px = -dy * 0.12, py = dx * 0.12;
    return List.generate(n + 1, (i) {
      final t = i / n;
      final bend = math.sin(t * math.pi) * (1 - t * 0.5);
      return GeoPoint(
        lat: from.lat + dy * t + py * bend,
        lng: from.lng + dx * t + px * bend,
      );
    });
  }

  /// Deterministic congestion per segment � replaced by provider data
  /// once a traffic-capable routing API key is configured.
  List<double> _traffic(int segments) {
    final seed = order.id.codeUnits.fold(7, (a, c) => (a * 31 + c) & 0x7fffffff);
    final rnd = math.Random(seed);
    return List.generate(
      segments,
      (i) => (rnd.nextDouble() * 0.75 + i * 0.02).clamp(0.0, 1.0),
    );
  }

  double _km(GeoPoint a, GeoPoint b) {
    const r = 6371.0;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLng = (b.lng - a.lng) * math.pi / 180;
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(a.lat * math.pi / 180) *
            math.cos(b.lat * math.pi / 180) *
            math.pow(math.sin(dLng / 2), 2);
    return r * 2 * math.asin(math.sqrt(h));
  }

  @override
  Widget build(BuildContext context) {
    final courier = order.courierLocation;
    final dest = order.delivery.point;
    final route = courier == null ? const <GeoPoint>[] : _route(courier, dest);
    final km = courier == null ? 0.0 : _km(courier, dest);
    // ~25 km/h city average + traffic drag from mean congestion.
    final traffic = route.isEmpty ? const <double>[] : _traffic(route.length - 1);
    final drag = traffic.isEmpty
        ? 1.0
        : 1 + traffic.reduce((a, b) => a + b) / traffic.length;
    final etaMin = (km / 25 * 60 * drag).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 240,
          child: KoraMap(
            center: courier ?? dest,
            markers: [
              KoraMarker(
                point: dest,
                kind: KoraMarkerKind.deliveryPoint,
                label: S.t('map.you'),
              ),
              if (courier != null)
                KoraMarker(
                  point: courier,
                  kind: KoraMarkerKind.courier,
                  label: order.courierName ?? S.t('call.courier'),
                ),
            ],
            route: route,
            trafficLevels: traffic.isEmpty ? null : traffic,
            followMarker: KoraMarkerKind.courier,
          ),
        ),
        if (courier != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              KoraStatusChip(
                label: '~$etaMin ${S.t('common.min')}',
                tone: KoraStatusTone.active,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                S.t('order.km_left', {'km': km.toStringAsFixed(1)}),
                style: AppTypography.caption,
              ),
              const Spacer(),
              // Traffic legend � compact dots matching segment colors.
              const _TrafficLegend(),
            ],
          ),
        ],
      ],
    );
  }
}

class _TrafficLegend extends StatelessWidget {
  const _TrafficLegend();

  @override
  Widget build(BuildContext context) {
    const colors = [
      Color(0xFF22C55E),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(AppIcons.traffic, size: 14, color: KoraColors.placeholder),
        const SizedBox(width: 4),
        for (final c in colors)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(left: 3),
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
      ],
    );
  }
}
