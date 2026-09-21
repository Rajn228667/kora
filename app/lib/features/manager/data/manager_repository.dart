import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';

class ManagerRepository {
  ManagerRepository(this._ref);

  final Ref _ref;

  Future<ManagerDashboard> dashboard() async {
    final res = await _ref
        .read(apiClientProvider)
        .get('/manager/dashboard') as Map<String, dynamic>;
    return ManagerDashboard(
      newOrders: (res['newOrders'] as num?)?.toInt() ?? 0,
      preparing: (res['preparing'] as num?)?.toInt() ?? 0,
      ready: (res['ready'] as num?)?.toInt() ?? 0,
      deliveredToday: (res['deliveredToday'] as num?)?.toInt() ?? 0,
      cancelledToday: (res['cancelledToday'] as num?)?.toInt() ?? 0,
      salesTodayTiyn: (res['salesTodayTiyn'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> act(String orderId, String action,
      {String? courierId,}) async {
    await _ref.read(apiClientProvider).post(
        '/manager/orders/$orderId/$action',
        body: {if (courierId != null) 'courierId': courierId},);
  }

  Future<List<CourierInfo>> couriers() async {
    final res = await _ref
        .read(apiClientProvider)
        .get('/manager/couriers') as Map<String, dynamic>;
    return (res['items'] as List)
        .map((c) => CourierInfo(
              id: (c as Map)['id'] as String,
              name: c['name'] as String? ?? S.t('call.courier'),
              status: CourierStatus.values.firstWhere(
                (s) => s.name == c['status'],
                orElse: () => CourierStatus.offline,
              ),
              activeOrders: (c['activeOrders'] as num?)?.toInt() ?? 0,
            ),)
        .toList();
  }

  Future<List<Product>> products() async {
    final res = await _ref
        .read(apiClientProvider)
        .get('/manager/products') as Map<String, dynamic>;
    return (res['items'] as List)
        .map((p) => Product.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveProduct(Product p) async {
    final body = {
      'name': p.name,
      'description': p.description,
      'priceTiyn': p.priceTiyn,
      'oldPriceTiyn': p.oldPriceTiyn,
      'bonusPercent': p.bonusPercent,
      'stock': p.stock,
      'available': p.available,
      'storeId': p.storeId,
      'imageUrl': p.imageUrl,
    };
    if (p.id.isEmpty) {
      await _ref.read(apiClientProvider).post('/manager/products', body: body);
    } else {
      await _ref
          .read(apiClientProvider)
          .patch('/manager/products/${p.id}', body: body);
    }
  }

  Future<Map<String, dynamic>> cityMap() async =>
      await _ref.read(apiClientProvider).get('/manager/map')
          as Map<String, dynamic>;
}

final managerRepoProvider = Provider((ref) => ManagerRepository(ref));

final managerDashboardProvider = FutureProvider(
    (ref) => ref.watch(managerRepoProvider).dashboard(),);

final managerCouriersProvider = FutureProvider(
    (ref) => ref.watch(managerRepoProvider).couriers(),);

final managerProductsProvider = AsyncNotifierProvider<
    ManagerProductsController, List<Product>>(ManagerProductsController.new);

class ManagerProductsController extends AsyncNotifier<List<Product>> {
  @override
  Future<List<Product>> build() =>
      ref.watch(managerRepoProvider).products();

  Future<void> save(Product p) async {
    await ref.read(managerRepoProvider).saveProduct(p);
    ref.invalidateSelf();
  }
}
