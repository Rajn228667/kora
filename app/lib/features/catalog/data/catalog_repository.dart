import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';

class Paged<T> {
  const Paged({required this.items, this.nextCursor});
  final List<T> items;
  final String? nextCursor;
}

class SearchResults {
  const SearchResults({required this.stores, required this.products});
  final List<Store> stores;
  final List<Product> products;
  bool get isEmpty => stores.isEmpty && products.isEmpty;
}

class CatalogRepository {
  CatalogRepository(this._api);

  final ApiClient _api;

  Future<List<Store>> stores({StoreKind? kind, String? query}) async {
    final res = await _api.get(
      '/stores',
      query: {
        if (kind != null) 'kind': kind.name,
        if (query != null && query.isNotEmpty) 'q': query,
      },
    ) as Map<String, dynamic>;
    return (res['items'] as List)
        .map((s) => Store.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<Store> store(String id) async =>
      Store.fromJson(await _api.get('/stores/$id') as Map<String, dynamic>);

  Future<List<Product>> storeProducts(String storeId) async {
    final res =
        await _api.get('/stores/$storeId/products') as Map<String, dynamic>;
    return (res['items'] as List)
        .map((p) => Product.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<Product> product(String id) async => Product.fromJson(
        await _api.get('/products/$id') as Map<String, dynamic>,
      );

  /// Full catalog of the single KORA store.
  Future<List<Product>> products() async {
    final res = await _api.get('/products') as Map<String, dynamic>;
    return (res['items'] as List)
        .map((p) => Product.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  /// All discounted products (oldPriceTiyn set) — for the deals rail.
  Future<List<Product>> deals() async {
    final res = await _api.get('/products') as Map<String, dynamic>;
    return (res['items'] as List)
        .map((p) => Product.fromJson(p as Map<String, dynamic>))
        .where((p) => p.oldPriceTiyn != null && p.available)
        .toList();
  }

  Future<List<Category>> categories() async {
    final res = await _api.get('/categories') as Map<String, dynamic>;
    return (res['items'] as List)
        .map((c) => Category.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<SearchResults> search(String query) async {
    final res =
        await _api.get('/search', query: {'q': query}) as Map<String, dynamic>;
    final stores = <Store>[];
    final products = <Product>[];
    for (final item in res['items'] as List) {
      final j = item as Map<String, dynamic>;
      if (j.containsKey('priceTiyn')) {
        products.add(Product.fromJson(j));
      } else {
        stores.add(Store.fromJson(j));
      }
    }
    return SearchResults(stores: stores, products: products);
  }

  Future<List<Store>> favorites() async {
    final res = await _api.get('/users/me/favorites') as Map<String, dynamic>;
    return (res['items'] as List)
        .map((s) => Store.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<void> addFavorite(String storeId) =>
      _api.post('/users/me/favorites', body: {'storeId': storeId});

  Future<void> removeFavorite(String storeId) =>
      _api.delete('/users/me/favorites/$storeId');

  Future<List<Product>> favoriteProducts() async {
    final res =
        await _api.get('/users/me/favorites/products') as Map<String, dynamic>;
    return (res['items'] as List)
        .map((p) => Product.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<void> addFavoriteProduct(String productId) => _api.post(
        '/users/me/favorites/products',
        body: {'productId': productId},
      );

  Future<void> removeFavoriteProduct(String productId) =>
      _api.delete('/users/me/favorites/products/$productId');

  Future<List<Product>> recentlyViewed() async {
    final res =
        await _api.get('/users/me/recently-viewed') as Map<String, dynamic>;
    return (res['items'] as List)
        .map((p) => Product.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<void> recordView(String productId) => _api.post(
        '/users/me/recently-viewed',
        body: {'productId': productId},
      );

  Future<List<Promotion>> promotions() async {
    final res = await _api.get('/promotions') as Map<String, dynamic>;
    return (res['items'] as List)
        .map(
          (p) => Promotion(
            id: p['id'] as String,
            title: p['title'] as String,
            subtitle: p['subtitle'] as String?,
            imageUrl: p['imageUrl'] as String?,
            storeId: p['storeId'] as String?,
            code: p['code'] as String?,
            discountPercent: (p['discountPercent'] as num?)?.toInt(),
          ),
        )
        .toList();
  }

  Future<({bool valid, int discountTiyn, String message})> validatePromo(
    String code,
    String storeId,
  ) async {
    final res = await _api.post(
      '/promo-codes/validate',
      body: {'code': code, 'storeId': storeId},
    ) as Map<String, dynamic>;
    return (
      valid: res['valid'] as bool? ?? false,
      discountTiyn: (res['discountTiyn'] as num?)?.toInt() ?? 0,
      message: res['message'] as String? ?? '',
    );
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(apiClientProvider)),
);

final categoriesProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(catalogRepositoryProvider).categories(),
);

final storesProvider = FutureProvider<List<Store>>(
  (ref) => ref.watch(catalogRepositoryProvider).stores(),
);

final promotionsProvider = FutureProvider<List<Promotion>>(
  (ref) => ref.watch(catalogRepositoryProvider).promotions(),
);

/// All products of the single store — drives the home catalog grid
/// and category pages.
final catalogProvider = FutureProvider<List<Product>>(
  (ref) => ref.watch(catalogRepositoryProvider).products(),);

final dealsProvider = FutureProvider<List<Product>>(
  (ref) => ref.watch(catalogRepositoryProvider).deals(),
);

final storeProvider = FutureProvider.family<Store, String>((ref, id) async {
  return ref.watch(catalogRepositoryProvider).store(id);
});

final storeProductsProvider =
    FutureProvider.family<List<Product>, String>((ref, storeId) async {
  return ref.watch(catalogRepositoryProvider).storeProducts(storeId);
});

final favoritesProvider =
    AsyncNotifierProvider<FavoritesController, Set<String>>(
  FavoritesController.new,
);

class FavoritesController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final favs = await ref.watch(catalogRepositoryProvider).favorites();
    return favs.map((s) => s.id).toSet();
  }

  Future<void> toggle(String storeId) async {
    final current = state.value ?? {};
    final repo = ref.read(catalogRepositoryProvider);
    if (current.contains(storeId)) {
      state = AsyncData({...current}..remove(storeId));
      await repo.removeFavorite(storeId);
    } else {
      state = AsyncData({...current, storeId});
      await repo.addFavorite(storeId);
    }
  }
}

/// Product favorites (heart on product cards / details).
final favoriteProductsProvider =
    AsyncNotifierProvider<FavoriteProductsController, Set<String>>(
  FavoriteProductsController.new,
);

class FavoriteProductsController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final favs = await ref.watch(catalogRepositoryProvider).favoriteProducts();
    return favs.map((p) => p.id).toSet();
  }

  Future<void> toggle(String productId) async {
    final current = state.value ?? {};
    final repo = ref.read(catalogRepositoryProvider);
    if (current.contains(productId)) {
      state = AsyncData({...current}..remove(productId));
      await repo.removeFavoriteProduct(productId);
    } else {
      state = AsyncData({...current, productId});
      await repo.addFavoriteProduct(productId);
    }
  }
}

final recentlyViewedProvider = FutureProvider<List<Product>>(
  (ref) => ref.watch(catalogRepositoryProvider).recentlyViewed(),
);
