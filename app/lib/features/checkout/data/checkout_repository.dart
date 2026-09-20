import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/maps/map_provider.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';

class CheckoutIssue {
  const CheckoutIssue({required this.code, required this.message});
  final String code;
  final String message;
}

class CheckoutResult {
  const CheckoutResult({required this.order, required this.paymentId});

  final Order order;
  final String paymentId;
}

class CheckoutRepository {
  CheckoutRepository(this._api);

  final ApiClient _api;

  Future<List<CheckoutIssue>> validate() async {
    final res = await _api.post('/checkout/validate')
        as Map<String, dynamic>;
    return ((res['issues'] as List?) ?? const [])
        .map((i) => CheckoutIssue(
              code: (i as Map)['code'] as String? ?? 'ISSUE',
              message: i['message'] as String? ?? '',
            ),)
        .toList();
  }

  Future<CheckoutResult> checkout({
    String? addressId,
    GeoPoint? point,
    String? address,
    String? comment,
    String? promoCode,
    String paymentMethod = 'kaspi',
  }) async {
    final res = await _api.post('/checkout', body: {
      if (addressId != null) 'addressId': addressId,
      if (point != null) ...point.toJson(),
      if (address != null) 'address': address,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
      if (promoCode != null) 'promoCode': promoCode,
      'paymentMethod': paymentMethod,
    },) as Map<String, dynamic>;
    final payment = res['payment'] as Map<String, dynamic>;
    return CheckoutResult(
      order: Order.fromJson(res['order'] as Map<String, dynamic>),
      paymentId: payment['id'] as String,
    );
  }

  Future<List<Address>> addresses() async {
    final res = await _api.get('/users/me/addresses')
        as Map<String, dynamic>;
    return (res['items'] as List)
        .map((a) => Address.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  Future<Address> createAddress({
    required String label,
    required String address,
    required GeoPoint point,
    String? comment,
  }) async {
    final res = await _api.post('/users/me/addresses', body: {
      'label': label,
      'address': address,
      ...point.toJson(),
      if (comment != null) 'comment': comment,
    },) as Map<String, dynamic>;
    return Address.fromJson(res);
  }
}

final checkoutRepositoryProvider = Provider<CheckoutRepository>(
  (ref) => CheckoutRepository(ref.watch(apiClientProvider)),
);

final addressesProvider = AsyncNotifierProvider<AddressesController,
    List<Address>>(AddressesController.new);

class AddressesController extends AsyncNotifier<List<Address>> {
  @override
  Future<List<Address>> build() =>
      ref.watch(checkoutRepositoryProvider).addresses();

  Future<void> add(Address address) async {
    final repo = ref.read(checkoutRepositoryProvider);
    final created = await repo.createAddress(
      label: address.label,
      address: address.address,
      point: address.point,
      comment: address.comment,
    );
    state = AsyncData([...state.value ?? [], created]);
  }

  Future<void> remove(String id) async {
    await ref.read(apiClientProvider).delete('/users/me/addresses/$id');
    state = AsyncData(
        (state.value ?? []).where((a) => a.id != id).toList(),);
  }
}
