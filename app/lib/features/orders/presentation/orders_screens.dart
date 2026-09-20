import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
                DateFormat('d MMM, HH:mm', 'ru').format(order.createdAt),
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
    final orders = ref.watch(ordersProvider);
    final order = ref.watch(orderProvider(orderId));
    if (order == null) {
      // Loading → spinner; loaded but missing → honest error state.
      if (orders.isLoading) {
        return Scaffold(
          appBar: AppBar(leading: const BackButton()),
          body: const KoraLoadingState(),
        );
      }
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: KoraErrorState(
          message: S.t('error.not_found'),
          onRetry: () => ref.invalidate(ordersProvider),
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
            SizedBox(
              height: 240,
              child: KoraMap(
                center: order.courierLocation ??
                    order.delivery.point,
                markers: [
                  KoraMarker(
                    point: order.delivery.point,
                    kind: KoraMarkerKind.deliveryPoint,
                    label: S.t('map.you'),
                  ),
                  if (order.courierLocation != null)
                    KoraMarker(
                      point: order.courierLocation!,
                      kind: KoraMarkerKind.courier,
                      label: order.courierName ?? S.t('call.courier'),
                    ),
                ],
              ),
            ),
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
                      DateFormat('d MMMM, HH:mm', 'ru')
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
                    onPressed: () =>
                        context.push('/call/${order.id}?to=courier'),
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
