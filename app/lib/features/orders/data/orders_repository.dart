import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/maps/map_provider.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/realtime/realtime.dart';

class OrdersRepository {
  OrdersRepository(this._api);

  final ApiClient _api;

  Future<List<Order>> orders() async {
    final res = await _api.get('/orders') as Map<String, dynamic>;
    return (res['items'] as List)
        .map((o) => Order.fromJson(o as Map<String, dynamic>))
        .toList();
  }

  Future<Order> order(String id) async =>
      Order.fromJson(await _api.get('/orders/$id') as Map<String, dynamic>);

  Future<Order> cancel(String id, {String? reason}) async =>
      Order.fromJson(await _api.post('/orders/$id/cancel',
          body: {if (reason != null) 'reason': reason},) as Map<String, dynamic>,);

  Future<({OrderStatus status, GeoPoint? courierLocation, String? courierName})>
      tracking(String orderId) async {
    final res = await _api.get('/tracking/orders/$orderId')
        as Map<String, dynamic>;
    return (
      status: OrderStatus.values.firstWhere(
        (s) => s.name == res['orderStatus'],
        orElse: () => OrderStatus.pending,
      ),
      courierLocation: res['courierLocation'] != null
          ? GeoPoint.fromJson(
              (res['courierLocation'] as Map).cast<String, dynamic>(),)
          : null,
      courierName: res['courierName'] as String?,
    );
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(ref.watch(apiClientProvider)),
);

final ordersProvider =
    AsyncNotifierProvider<OrdersController, List<Order>>(
        OrdersController.new,);

class OrdersController extends AsyncNotifier<List<Order>> {
  StreamSubscription<RealtimeEvent>? _sub;

  @override
  Future<List<Order>> build() async {
    // Live updates: order status + courier GPS via realtime channel.
    final rt = ref.watch(realtimeProvider);
    unawaited(_sub?.cancel());
    _sub = rt.events.listen(_onEvent);
    ref.onDispose(() => _sub?.cancel());
    return ref.watch(ordersRepositoryProvider).orders();
  }

  void _onEvent(RealtimeEvent e) {
    final orderId = e.data['orderId'] as String?;
    if (orderId == null) return;
    final list = state.value;
    if (list == null) return;
    final idx = list.indexWhere((o) => o.id == orderId);
    if (idx < 0) {
      if (e.type == 'order.created') refresh();
      return;
    }
    var order = list[idx];
    switch (e.type) {
      case 'order.status_changed':
        final name = e.data['status'] as String?;
        final status = OrderStatus.values.firstWhere(
          (s) => s.name == name,
          orElse: () => order.status,
        );
        if (status != order.status) {
          order = order.copyWith(
            status: status,
            statusHistory: [
              ...order.statusHistory,
              OrderStatusEntry(
                status: status,
                actorRole: UserRole.manager,
                at: DateTime.now(),
              ),
            ],
          );
        }
        break;
      case 'courier.assigned':
        order = order.copyWith(
          courierName: e.data['courierName'] as String?,
          courierId: e.data['courierId'] as String?,
        );
        break;
      case 'courier.location_updated':
        final lat = (e.data['lat'] as num?)?.toDouble();
        final lng = (e.data['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          order =
              order.copyWith(courierLocation: GeoPoint(lat: lat, lng: lng));
        }
        break;
      case 'payment.confirmed':
        order = order.copyWith(paymentStatus: PaymentStatus.paid);
        break;
    }
    if (!identical(order, list[idx])) {
      final next = [...list];
      next[idx] = order;
      state = AsyncData(next);
    }
  }

  Future<void> refresh() async {
    state = AsyncData(await ref.read(ordersRepositoryProvider).orders());
  }

  Future<void> cancel(String orderId) async {
    final updated =
        await ref.read(ordersRepositoryProvider).cancel(orderId);
    final list = state.value ?? [];
    state = AsyncData(
        list.map((o) => o.id == orderId ? updated : o).toList(),);
  }
}

final orderProvider = Provider.family<Order?, String>((ref, id) {
  final list = ref.watch(ordersProvider).value;
  if (list == null) return null;
  return list.where((o) => o.id == id).firstOrNull;
});
