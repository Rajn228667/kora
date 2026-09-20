import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kora/core/theme/kora_colors.dart';
import 'package:kora/core/widgets/fields.dart';
import 'package:kora/core/widgets/misc.dart';
import 'package:kora/core/models/models.dart';
import 'package:kora/core/maps/map_provider.dart';
import 'package:kora/core/mock/mock_api.dart';
import 'package:kora/core/network/api_exception.dart';

void main() {
  group('KoraColors', () {
    test('brand palette is white + purple only', () {
      expect(KoraColors.primary, const Color(0xFF8B5CF6));
      expect(KoraColors.lightPurple, const Color(0xFFEDE9FE));
      expect(KoraColors.veryLightPurple, const Color(0xFFF8F7FF));
      expect(KoraColors.softPurple, const Color(0xFFA78BFA));
      expect(KoraColors.darkPurple, const Color(0xFF6D28D9));
      expect(KoraColors.deepPurple, const Color(0xFF5B21B6));
      expect(KoraColors.white, const Color(0xFFFFFFFF));
      // Gradients must stay within white↔purple.
      for (final g in [
        KoraColors.primaryGradient,
        KoraColors.softGradient,
        KoraColors.surfaceGradient,
      ]) {
        for (final c in g.colors) {
          expect(
            c,
            isIn([
              KoraColors.white,
              KoraColors.veryLightPurple,
              KoraColors.lightPurple,
              KoraColors.softPurple,
              KoraColors.primary,
            ]),
          );
        }
      }
    });
  });

  group('KoraPrice', () {
    test('formats tiyn to tenge with nbsp grouping (KZ style)', () {
      const nbsp = ' ';
      expect(KoraPrice.format(199000), '1${nbsp}990 ₸');
      expect(KoraPrice.format(0), '0 ₸');
      expect(KoraPrice.format(70000), '700 ₸');
      expect(KoraPrice.format(123456789), '1${nbsp}234${nbsp}567 ₸');
    });
  });

  group('KzPhoneFormatter', () {
    test('toE164 strips formatting', () {
      expect(
          KzPhoneFormatter.toE164('+7 700 123 45 67'), '+77001234567',);
    });

    test('masks input to +7 format', () {
      const f = KzPhoneFormatter();
      final res = f.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '87001234567'),
      );
      expect(res.text, '+7 700 123 45 67');
    });

    test('clamps to 11 digits', () {
      const f = KzPhoneFormatter();
      final res = f.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '770012345678999'),
      );
      expect(res.text, '+7 700 123 45 67');
    });
  });

  group('Models', () {
    test('Order.fromJson maps snake_case backend enums', () {
      final order = Order.fromJson({
        'id': 'o1',
        'number': 'K-1',
        'storeId': 's1',
        'storeName': 'Test',
        'items': const <Map<String, dynamic>>[],
        'status': 'ready_for_pickup',
        'paymentStatus': 'awaiting_confirmation',
        'delivery': {
          'address': 'A',
          'lat': 43.2,
          'lng': 76.9,
          'capturedAt': '2026-01-01T00:00:00Z',
        },
        'totalTiyn': 100000,
        'createdAt': '2026-01-01T00:00:00Z',
      });
      expect(order.status, OrderStatus.readyForPickup);
      expect(order.paymentStatus, PaymentStatus.awaitingConfirmation);
      expect(order.delivery.point, const GeoPoint(lat: 43.2, lng: 76.9));
    });

    test('CartItem uses variant price when set', () {
      const product = Product(
        id: 'p',
        storeId: 's',
        name: 'n',
        priceTiyn: 100000,
        variants: [
          ProductVariant(id: 'v1', name: 'S', priceTiyn: 90000),
          ProductVariant(id: 'v2', name: 'L', priceTiyn: 120000),
        ],
      );
      const item =
          CartItem(id: 'i', product: product, quantity: 2, variantId: 'v2');
      expect(item.priceTiyn, 120000);
      expect(item.totalTiyn, 240000);
    });

    test('order canCancel only before preparing', () {
      Order o(OrderStatus s) => Order(
            id: 'x',
            number: 'n',
            storeId: 's',
            storeName: 's',
            items: const [],
            status: s,
            paymentStatus: PaymentStatus.paid,
            delivery: DeliverySnapshot(
              address: '',
              point: const GeoPoint(lat: 0, lng: 0),
              capturedAt: DateTime(2026),
            ),
            subtotalTiyn: 0,
            discountTiyn: 0,
            deliveryTiyn: 0,
            totalTiyn: 0,
            createdAt: DateTime(2026),
          );
      expect(o(OrderStatus.pending).canCancel, isTrue);
      expect(o(OrderStatus.accepted).canCancel, isTrue);
      expect(o(OrderStatus.preparing).canCancel, isFalse);
      expect(o(OrderStatus.delivered).isActive, isFalse);
      expect(o(OrderStatus.delivering).isActive, isTrue);
    });
  });

  group('MockApiClient staff login', () {
    test('correct credentials → admin user with tokens', () async {
      final api = MockApiClient();
      final res = await api.post('/auth/login', auth: false, body: {
        'email': 'hiwatchkz@mail.ru',
        'password': '667228',
      },) as Map<String, dynamic>;
      expect((res['user'] as Map)['role'], 'admin');
      expect(res['accessToken'], isNotEmpty);
      expect(res['refreshToken'], isNotEmpty);
    });

    test('wrong password → 401 INVALID_CREDENTIALS', () async {
      final api = MockApiClient();
      try {
        await api.post('/auth/login', auth: false, body: {
          'email': 'hiwatchkz@mail.ru',
          'password': 'wrong',
        },);
        fail('should have thrown');
      } on ApiException catch (e) {
        expect(e.code, 'INVALID_CREDENTIALS');
        expect(e.statusCode, 401);
      }
    });
  });

  group('MockApiClient retention & wallet endpoints', () {
    Future<MockApiClient> loggedIn() async {
      final api = MockApiClient();
      await api.post('/auth/verify-otp', auth: false, body: {
        'phone': '+77001234567',
        'code': '123456',
      },);
      return api;
    }

    test('recently-viewed records and returns products, newest first',
        () async {
      final api = await loggedIn();
      await api.post('/users/me/recently-viewed',
          body: {'productId': 'p-lagman'},);
      await api.post('/users/me/recently-viewed',
          body: {'productId': 'p-plov'},);
      final res = await api.get('/users/me/recently-viewed')
          as Map<String, dynamic>;
      final items = res['items'] as List;
      expect((items.first as Map)['id'], 'p-plov');
      // Re-view moves to front without duplicating.
      await api.post('/users/me/recently-viewed',
          body: {'productId': 'p-lagman'},);
      final res2 = await api.get('/users/me/recently-viewed')
          as Map<String, dynamic>;
      final items2 = res2['items'] as List;
      expect(items2.length, 2);
      expect((items2.first as Map)['id'], 'p-lagman');
    });

    test('product favorites round-trip', () async {
      final api = await loggedIn();
      await api.post('/users/me/favorites/products',
          body: {'productId': 'p-plov'},);
      var res = await api.get('/users/me/favorites/products')
          as Map<String, dynamic>;
      expect((res['items'] as List).length, 1);
      await api.delete('/users/me/favorites/products/p-plov');
      res = await api.get('/users/me/favorites/products')
          as Map<String, dynamic>;
      expect((res['items'] as List), isEmpty);
    });

    test('wallet: balance + cashback txn on checkout', () async {
      final api = await loggedIn();
      final before = (await api.get('/users/me/wallet')
          as Map<String, dynamic>)['balanceTiyn'] as int;
      await api.post('/cart/items',
          body: {'productId': 'p-plov', 'qty': 1},);
      await api.post('/checkout',
          body: {'address': 'Шымкент, ул. Тестовая 1'},);
      final after = (await api.get('/users/me/wallet')
          as Map<String, dynamic>)['balanceTiyn'] as int;
      expect(after, greaterThan(before));
      final txns = await api.get('/users/me/wallet/transactions')
          as Map<String, dynamic>;
      expect((txns['items'] as List).first['kind'], 'cashback');
    });

    test('repeat order re-adds items to cart', () async {
      final api = await loggedIn();
      await api.post('/cart/items',
          body: {'productId': 'p-samsa', 'qty': 2},);
      final checkout = await api.post('/checkout',
          body: {'address': 'A'},) as Map<String, dynamic>;
      final orderId =
          (checkout['order'] as Map)['id'] as String;
      final res = await api.post('/orders/$orderId/repeat')
          as Map<String, dynamic>;
      expect(res['added'], 1);
      final cart = await api.get('/cart') as Map<String, dynamic>;
      expect((cart['items'] as List).length, 1);
    });

    test('manager schedule get/put round-trip', () async {
      final api = await loggedIn();
      await api.put('/manager/schedule', body: {
        'storeId': 'st-handam',
        'days': {
          '0': {'open': 540, 'close': 1260},
          '6': null,
        },
      },);
      final res = await api.get('/manager/schedule')
          as Map<String, dynamic>;
      final days = res['days'] as Map;
      expect((days['0'] as Map)['open'], 540);
      expect(days['6'], isNull);
    });

    test('price drop on favorited product creates notification', () async {
      final api = await loggedIn();
      await api.post('/users/me/favorites/products',
          body: {'productId': 'p-plov'},);
      await api.patch('/admin/products/p-plov',
          body: {'priceTiyn': 199000},);
      final notifs = await api.get('/notifications')
          as Map<String, dynamic>;
      final items = notifs['items'] as List;
      expect(
        items.any((n) => (n as Map)['kind'] == 'price_drop'),
        isTrue,
      );
    });

    test('wallet payment debits balance and adds spend txn', () async {
      final api = await loggedIn();
      final before = (await api.get('/users/me/wallet')
          as Map<String, dynamic>)['balanceTiyn'] as int;
      await api.post('/cart/items',
          body: {'productId': 'p-samsa', 'qty': 1},);
      final checkout = await api.post('/checkout', body: {
        'address': 'A',
        'paymentMethod': 'wallet',
      },) as Map<String, dynamic>;
      final order = checkout['order'] as Map;
      expect(order['paymentStatus'], 'paid');
      final after = (await api.get('/users/me/wallet')
          as Map<String, dynamic>)['balanceTiyn'] as int;
      expect(after, lessThan(before));
      final txns = await api.get('/users/me/wallet/transactions')
          as Map<String, dynamic>;
      expect((txns['items'] as List).any(
          (t) => (t as Map)['kind'] == 'spend',), isTrue,);
    });

    test('wallet payment with insufficient funds → 402', () async {
      final api = await loggedIn();
      await api.post('/cart/items',
          body: {'productId': 'p-plov', 'qty': 40},);
      try {
        await api.post('/checkout', body: {
          'address': 'A',
          'paymentMethod': 'wallet',
        },);
        fail('should have thrown');
      } on ApiException catch (e) {
        expect(e.code, 'INSUFFICIENT_FUNDS');
      }
    });

    test('support ticket keeps first message + thread replies', () async {
      final api = await loggedIn();
      final created = await api.post('/support/tickets', body: {
        'subject': 'Тест',
        'message': 'Первое сообщение',
      },) as Map<String, dynamic>;
      final id = created['id'] as String;
      expect((created['messages'] as List).length, 1);
      await api.post('/support/tickets/$id/messages',
          body: {'text': 'Ещё вопрос'},);
      final detail = await api.get('/support/tickets/$id')
          as Map<String, dynamic>;
      expect((detail['messages'] as List).length, 2);
    });

    test('notifications: mark-read + persisted preferences', () async {
      final api = await loggedIn();
      await api.post('/notifications/read', body: const {});
      final feed = await api.get('/notifications') as Map<String, dynamic>;
      expect((feed['items'] as List)
          .every((n) => (n as Map)['read'] == true), isTrue,);
      await api.post('/notifications/preferences',
          body: {'promos': false},);
      final prefs = await api.get('/notifications/preferences')
          as Map<String, dynamic>;
      expect((prefs['preferences'] as Map)['promos'], false);
      expect((prefs['preferences'] as Map)['orders'], true);
    });

    test('admin can block and unblock a user', () async {
      final api = await loggedIn();
      final users = await api.get('/admin/users') as Map<String, dynamic>;
      final uid = ((users['items'] as List).last as Map)['id'] as String;
      await api.post('/admin/users/$uid/block', body: {'blocked': true});
      var res = await api.get('/admin/users') as Map<String, dynamic>;
      final blocked = (res['items'] as List)
          .firstWhere((u) => (u as Map)['id'] == uid) as Map;
      expect(blocked['blocked'], isTrue);
      await api.post('/admin/users/$uid/block', body: {'blocked': false});
      res = await api.get('/admin/users') as Map<String, dynamic>;
      final unblocked = (res['items'] as List)
          .firstWhere((u) => (u as Map)['id'] == uid) as Map;
      expect(unblocked['blocked'], isFalse);
    });

    test('courier assignment advances a real order', () async {
      final api = await loggedIn();
      await api.post('/couriers/status', body: {'status': 'online'});
      final offers = await api.get('/couriers/assignments')
          as Map<String, dynamic>;
      final offer = (offers['items'] as List).first as Map;
      await api
          .post('/couriers/assignments/${offer['id']}/accept');
      final updated = await api.post(
          '/couriers/orders/${offer['orderId']}/status',
          body: {'status': 'pickedUp'},) as Map<String, dynamic>;
      expect(updated['status'], 'pickedUp');
      final detail = await api.get('/orders/${offer['orderId']}')
          as Map<String, dynamic>;
      expect(detail['id'], offer['orderId']);
    });
  });
}
