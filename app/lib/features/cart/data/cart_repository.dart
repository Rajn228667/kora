import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';

class CartRepository {
  CartRepository(this._api);

  final ApiClient _api;

  Future<Cart> getCart() async {
    final res = await _api.get('/cart') as Map<String, dynamic>;
    return _parse(res);
  }

  Future<Cart> addItem(String productId, int qty, {String? variantId}) async {
    final res = await _api.post('/cart/items', body: {
      'productId': productId,
      'qty': qty,
      if (variantId != null) 'variantId': variantId,
    },) as Map<String, dynamic>;
    return _parse(res);
  }

  Future<Cart> updateItem(String itemId, int qty) async {
    final res = await _api.patch('/cart/items/$itemId', body: {'qty': qty})
        as Map<String, dynamic>;
    return _parse(res);
  }

  Future<Cart> removeItem(String itemId) async {
    final res = await _api.delete('/cart/items/$itemId')
        as Map<String, dynamic>;
    return _parse(res);
  }

  Future<void> clear() => _api.delete('/cart');

  Cart _parse(Map<String, dynamic> j) {
    final items = ((j['items'] as List?) ?? const []).map((i) {
      final m = i as Map<String, dynamic>;
      return CartItem(
        id: m['id'] as String,
        product: Product.fromJson(m['product'] as Map<String, dynamic>),
        quantity: (m['quantity'] as num).toInt(),
        variantId: m['variantId'] as String?,
      );
    }).toList();
    return Cart(
      storeId: j['storeId'] as String? ?? '',
      storeName: j['storeName'] as String? ?? '',
      items: items,
      subtotalTiyn: (j['subtotalTiyn'] as num?)?.toInt() ?? 0,
      deliveryTiyn: (j['deliveryTiyn'] as num?)?.toInt() ?? 0,
      discountTiyn: (j['discountTiyn'] as num?)?.toInt() ?? 0,
      totalTiyn: (j['totalTiyn'] as num?)?.toInt() ?? 0,
      promoCode: j['promoCode'] as String?,
    );
  }
}

final cartRepositoryProvider = Provider<CartRepository>(
  (ref) => CartRepository(ref.watch(apiClientProvider)),
);

/// Cart state — refreshed after every mutation; badge reads itemCount.
class CartController extends AsyncNotifier<Cart> {
  @override
  Future<Cart> build() => ref.watch(cartRepositoryProvider).getCart();

  Future<void> add(Product product, int qty, {String? variantId}) async {
    final repo = ref.read(cartRepositoryProvider);
    state = AsyncData(await repo.addItem(product.id, qty,
        variantId: variantId,),);
  }

  Future<void> setQty(String itemId, int qty) async {
    final repo = ref.read(cartRepositoryProvider);
    state = AsyncData(await repo.updateItem(itemId, qty));
  }

  Future<void> remove(String itemId) async {
    final repo = ref.read(cartRepositoryProvider);
    state = AsyncData(await repo.removeItem(itemId));
  }

  Future<void> refresh() async {
    state = AsyncData(await ref.read(cartRepositoryProvider).getCart());
  }
}

final cartProvider =
    AsyncNotifierProvider<CartController, Cart>(CartController.new);

final cartCountProvider = Provider<int>(
  (ref) => ref.watch(cartProvider).value?.itemCount ?? 0,
);
