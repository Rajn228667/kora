import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../maps/map_provider.dart';
import '../models/models.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../realtime/realtime.dart';
import 'mock_data.dart';

/// In-app backend simulation used when `APP_MODE=mock`.
///
/// Implements the same `/v1` contract as the real API: repositories
/// cannot tell the difference. Also simulates realtime: payment
/// confirmation, order progression, courier GPS and chat replies.
///
/// Dev role phones: any +7 → CUSTOMER; …002 → MANAGER; …003 → COURIER;
/// …004 → ADMIN. OTP accepts `123456` or any 6-digit code.
class MockApiClient implements ApiClient {
  MockApiClient({this.realtime});

  MockRealtimeClient? realtime;

  @override
  void Function()? onSessionExpired;

  final _rng = Random();
  final _products = List<Product>.from(MockData.products);
  final _stores = List<Store>.from(MockData.stores);
  final _addresses = List<Address>.from(MockData.addresses);
  final _favoriteIds = <String>{};
  final _orders = <Order>[];
  final _cartItems = <CartItem>[];
  final _chatMessages = <String, List<ChatMessage>>{};
  final _tickets = <SupportTicket>[];
  final _notifications = <AppNotification>[
    AppNotification(
      id: 'ntf-welcome',
      title: 'Добро пожаловать в KORA',
      body: 'Промокод KORA700 — скидка 700 ₸ на заказ от 2 000 ₸',
      kind: 'promo',
      at: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    AppNotification(
      id: 'ntf-promo',
      title: 'Бесплатная доставка',
      body: 'Сегодня в магазинах партнёрах доставка за наш счёт',
      kind: 'promo',
      at: DateTime.now().subtract(const Duration(days: 1)),
      read: true,
    ),
  ];
  final _notifPrefs = <String, dynamic>{
    'orders': true,
    'promos': true,
    'chat': true,
  };
  final _paymentIndex = <String, String>{}; // paymentId → orderId
  final _blockedUserIds = <String>{};
  final _courierOffers = <CourierOffer>[];
  String? _activeCourierOrderId;
  GeoPoint? _lastCourierPoint;
  final _promotions = List<Promotion>.from(MockData.promotions);

  /// Admin-managed promo codes: code → {discountTiyn, minOrderTiyn,
  /// productId?} — validated by `_validatePromo`, so codes created in
  /// the admin panel actually work at checkout.
  final _promoCodes = <String, Map<String, dynamic>>{
    'KORA700': {'discountTiyn': 70000, 'minOrderTiyn': 200000},
  };
  final _favoriteProductIds = <String>{};
  final _recentlyViewed = <String>[];

  /// Store working hours per weekday (0=Mon..6=Sun). open/close in
  /// minutes from midnight; null = closed. Editable in Manager Mode.
  final Map<String, Map<int, ({int open, int close})?>> _schedules = {
    'kora-market': {
      for (var d = 0; d < 6; d++) d: (open: 10 * 60, close: 21 * 60),
      6: null,
    },
  };

  int _walletBalanceTiyn = 250000;
  final _walletTxns = <Map<String, dynamic>>[];
  final _users = <User>[
    const User(
      id: 'u-manager',
      phone: '+77000000002',
      name: 'Мейірбан',
      role: UserRole.manager,
    ),
    const User(
      id: 'u-courier',
      phone: '+77000000003',
      name: 'Арман',
      role: UserRole.courier,
    ),
    const User(
      id: 'u-admin',
      phone: '+77000000004',
      name: 'Admin',
      role: UserRole.admin,
    ),
  ];
  final _audit = <AuditEntry>[];

  User? _user;
  String? _cartStoreId;
  CourierStatus _courierStatus = CourierStatus.offline;
  int _seq = 0;

  String _id(String prefix) => '$prefix-${(++_seq).toString().padLeft(4, '0')}';
  String get _uid => _user?.id ?? 'u-guest';

  /// Staff console login. Only the SHA-256 hash of
  /// `email:password` is stored — plaintext never lives in the repo.
  /// In `APP_MODE=api` the real backend validates this server-side.
  static const _staffEmail = 'hiwatchkz@mail.ru';
  static const _staffPasswordHash =
      '39dcc49843b33c447da69d02430153245e40eb1e1d71352c899a5a212d8bac1b';

  User _roleForPhone(String phone) {
    if (phone.endsWith('0002')) {
      return _users.firstWhere((u) => u.role == UserRole.manager);
    }
    if (phone.endsWith('0003')) {
      return _users.firstWhere((u) => u.role == UserRole.courier);
    }
    if (phone.endsWith('0004')) {
      return _users.firstWhere((u) => u.role == UserRole.admin);
    }
    return User(
      id: 'u-${phone.hashCode.abs() % 99999}',
      phone: phone,
      name: '',
    );
  }

  // -- transport ------------------------------------------------------------

  Future<dynamic> _handle(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
  }) async {
    await Future<void>.delayed(Duration(milliseconds: 120 + _rng.nextInt(280)));
    if (auth && _user == null && !path.startsWith('/auth')) {
      throw const ApiException(
        code: 'UNAUTHORIZED',
        message: 'Требуется вход',
        statusCode: 401,
      );
    }
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    final b = (body as Map?)?.cast<String, dynamic>() ?? const {};

    try {
      return _route(method, seg, b, query ?? const {});
    } on ApiException {
      rethrow;
    }
  }

  String _s(List<String> seg, int i) => i < seg.length ? seg[i] : '';

  dynamic _route(
    String method,
    List<String> seg,
    Map<String, dynamic> b,
    Map<String, dynamic> q,
  ) {
    if (seg.isEmpty) return {'status': 'ok'};
    // auth
    if (seg[0] == 'auth') return _auth(method, seg, b);
    // users
    if (seg[0] == 'users') return _users_(method, seg, b);
    if (seg[0] == 'stores') return _stores_(method, seg, q);
    if (seg[0] == 'categories') {
      return _wrap(MockData.categories.map((c) => _catJson(c)));
    }
    if (seg[0] == 'products' && seg.length == 1 && method == 'GET') {
      final items = _products.where(
        (p) => q['storeId'] == null || p.storeId == q['storeId'],
      );
      return _wrap(items.map((p) => _productJson(p)));
    }
    if (seg[0] == 'products' && seg.length == 2 && method == 'GET') {
      return _productJson(
        _products.firstWhere(
          (p) => p.id == seg[1],
          orElse: () => throw _notFound('Товар не найден'),
        ),
      );
    }
    if (seg[0] == 'search') return _search(q);
    if (seg[0] == 'cart') return _cart(method, seg, b);
    if (seg[0] == 'checkout') return _checkout(method, seg, b);
    if (seg[0] == 'payments') return _payments(method, seg, b);
    if (seg[0] == 'orders') return _ordersApi(method, seg, b);
    if (seg[0] == 'tracking') return _tracking(seg);
    if (seg[0] == 'chat') return _chat(method, seg, b, q);
    if (seg[0] == 'media' && _s(seg, 1) == 'uploads') {
      return {
        'mediaId': _id('med'),
        'uploadUrl': 'mock://upload/${_id('upl')}',
      };
    }
    if (seg[0] == 'couriers') return _courier(method, seg, b);
    if (seg[0] == 'manager') return _manager(method, seg, b, q);
    if (seg[0] == 'admin') return _admin(method, seg, b, q);
    if (seg[0] == 'support') return _support(method, seg, b);
    if (seg[0] == 'notifications') return _notifs(method, seg, b);
    if (seg[0] == 'promotions') {
      return _wrap(_promotions.map((p) => _promoJson(p)));
    }
    if (seg[0] == 'promo-codes' && _s(seg, 1) == 'validate') {
      return _validatePromo(b);
    }
    if (seg[0] == 'calls') return {'id': _id('call'), 'status': 'ringing'};
    if (seg[0] == 'health' || seg[0] == 'ready') return {'status': 'ok'};
    throw _notFound('Неизвестный ресурс: /${seg.join('/')}');
  }

  // -- auth -----------------------------------------------------------------

  dynamic _auth(String method, List<String> seg, Map<String, dynamic> b) {
    switch (_s(seg, 1)) {
      case 'request-otp':
        final phone = b['phone'] as String? ?? '';
        if (!RegExp(r'^\+7\d{10}$').hasMatch(phone)) {
          throw const ApiException(
            code: 'INVALID_PHONE',
            message: 'Введите номер в формате +7 XXX XXX XX XX',
            statusCode: 400,
          );
        }
        return {
          'requestId': _id('otp'),
          'ttlSeconds': 60,
          'devOtp': '123456',
          'phone': phone,
        };
      case 'verify-otp':
        final code = b['code'] as String? ?? '';
        if (code.length != 6) {
          throw const ApiException(
            code: 'INVALID_OTP',
            message: 'Неверный код',
            statusCode: 400,
          );
        }
        final phone = b['phone'] as String? ?? '+77000000001';
        _user = _roleForPhone(phone);
        return {
          'accessToken': 'mock-access-${_user!.id}',
          'refreshToken': 'mock-refresh-${_user!.id}',
          'isNewUser': _user!.name.isEmpty,
          'user': _user!.toJson(),
        };
      case 'refresh':
        return {
          'accessToken': 'mock-access-${_user?.id ?? 'x'}-${_seq++}',
          'refreshToken': 'mock-refresh-${_seq++}',
        };
      case 'login':
        final email = (b['email'] as String? ?? '').trim().toLowerCase();
        final password = b['password'] as String? ?? '';
        final digest =
            sha256.convert(utf8.encode('$email:$password')).toString();
        if (email != _staffEmail || digest != _staffPasswordHash) {
          throw const ApiException(
            code: 'INVALID_CREDENTIALS',
            message: 'Неверный email или пароль',
            statusCode: 401,
          );
        }
        _user = _users.firstWhere((u) => u.role == UserRole.admin);
        return {
          'accessToken': 'mock-access-${_user!.id}',
          'refreshToken': 'mock-refresh-${_user!.id}',
          'isNewUser': false,
          'user': _user!.toJson(),
        };
      case 'logout':
        _user = null;
        return {'ok': true};
      case 'logout-all':
        // Revokes *other* sessions — current session stays alive.
        return {'ok': true, 'revoked': 1};
    }
    throw _notFound('auth');
  }

  // -- users ----------------------------------------------------------------

  dynamic _users_(String method, List<String> seg, Map<String, dynamic> b) {
    if (seg.length == 2 && seg[1] == 'me') {
      if (method == 'GET') return _user!.toJson();
      if (method == 'PATCH') {
        _user = _user!.copyWith(
          name: b['name'] as String?,
          avatarUrl: b['avatarUrl'] as String?,
        );
        return _user!.toJson();
      }
      if (method == 'DELETE') {
        _user = null;
        _orders.clear();
        _cartItems.clear();
        return {'ok': true};
      }
    }
    if (_s(seg, 1) == 'me' && _s(seg, 2) == 'addresses') {
      if (method == 'GET') {
        return _wrap(_addresses.map(_addrJson));
      }
      if (method == 'POST') {
        final a = Address(
          id: _id('addr'),
          label: b['label'] as String? ?? 'Адрес',
          address: b['address'] as String? ?? '',
          point: GeoPoint(
            lat: (b['lat'] as num?)?.toDouble() ?? MockData.shymkent.lat,
            lng: (b['lng'] as num?)?.toDouble() ?? MockData.shymkent.lng,
          ),
          comment: b['comment'] as String?,
        );
        _addresses.add(a);
        return _addrJson(a);
      }
      if (seg.length == 4 && method == 'DELETE') {
        _addresses.removeWhere((a) => a.id == seg[3]);
        return {'ok': true};
      }
    }
    if (_s(seg, 1) == 'me' && _s(seg, 2) == 'favorites') {
      // Product favorites: /users/me/favorites/products[/:id]
      if (seg.length >= 4 && _s(seg, 3) == 'products') {
        if (method == 'GET') {
          return _wrap(
            _products
                .where((p) => _favoriteProductIds.contains(p.id))
                .map(_productJson),
          );
        }
        if (method == 'POST' && seg.length == 4) {
          _favoriteProductIds.add(b['productId'] as String? ?? '');
          return {'ok': true};
        }
        if (method == 'DELETE' && seg.length == 5) {
          _favoriteProductIds.remove(seg[4]);
          return {'ok': true};
        }
      }
      if (method == 'GET') {
        return _wrap(
          _stores.where((s) => _favoriteIds.contains(s.id)).map(_storeJson),
        );
      }
      if (method == 'POST') {
        _favoriteIds.add(b['storeId'] as String? ?? '');
        return {'ok': true};
      }
      if (seg.length == 4 && method == 'DELETE') {
        _favoriteIds.remove(seg[3]);
        return {'ok': true};
      }
    }
    if (_s(seg, 1) == 'me' && _s(seg, 2) == 'recently-viewed') {
      if (method == 'GET') {
        return _wrap(
          _recentlyViewed
              .map((id) => _products.where((p) => p.id == id).firstOrNull)
              .nonNulls
              .map(_productJson),
        );
      }
      if (method == 'POST') {
        final pid = b['productId'] as String? ?? '';
        _recentlyViewed
          ..remove(pid)
          ..insert(0, pid);
        if (_recentlyViewed.length > 12) _recentlyViewed.removeLast();
        return {'ok': true};
      }
    }
    if (_s(seg, 1) == 'me' && _s(seg, 2) == 'wallet') {
      if (_s(seg, 3) == 'transactions') return _wrap(_walletTxns);
      return {
        'balanceTiyn': _walletBalanceTiyn,
        'earnedTiyn': _walletTxns
            .where((t) => (t['amountTiyn'] as int) > 0)
            .fold<int>(0, (s, t) => s + (t['amountTiyn'] as int)),
        'spentTiyn': _walletTxns
            .where((t) => (t['amountTiyn'] as int) < 0)
            .fold<int>(0, (s, t) => s - (t['amountTiyn'] as int)),
      };
    }
    if (_s(seg, 1) == 'me' && _s(seg, 2) == 'referral') {
      return {
        'code': 'KORA-${(_user?.id.hashCode.abs() ?? 7) % 9000 + 1000}',
        'invited': 2,
        'bonusTiyn': 50000,
      };
    }
    if (_s(seg, 1) == 'me' && _s(seg, 2) == 'sessions') {
      return _wrap([
        {
          'id': 's-current',
          'device': 'Это устройство',
          'createdAt': DateTime.now().toIso8601String(),
          'current': true,
        },
        {
          'id': 's-old',
          'device': 'Samsung Galaxy S24',
          'createdAt': DateTime.now()
              .subtract(const Duration(days: 12))
              .toIso8601String(),
        },
      ]);
    }
    throw _notFound('users');
  }

  // -- catalog ---------------------------------------------------------------

  dynamic _stores_(String method, List<String> seg, Map<String, dynamic> q) {
    if (seg.length == 1) {
      var list = _stores;
      final kind = q['kind'] as String?;
      final query = (q['q'] as String? ?? '').toLowerCase();
      if (kind != null && kind.isNotEmpty) {
        list = list.where((s) => s.kind.name == kind).toList();
      }
      if (query.isNotEmpty) {
        list = list.where((s) => s.name.toLowerCase().contains(query)).toList();
      }
      return _wrap(list.map(_storeJson));
    }
    final store = _stores.firstWhere(
      (s) => s.id == seg[1],
      orElse: () => throw _notFound('Магазин не найден'),
    );
    if (seg.length == 2) return _storeJson(store);
    if (seg[2] == 'products') {
      return _wrap(
        _products.where((p) => p.storeId == store.id).map(_productJson),
      );
    }
    throw _notFound('stores');
  }

  dynamic _search(Map<String, dynamic> q) {
    final query = (q['q'] as String? ?? '').toLowerCase().trim();
    if (query.isEmpty) {
      return {'items': <dynamic>[], 'nextCursor': null};
    }
    // tiny typo-tolerance: match on substring of first 4+ chars.
    final stem =
        query.length > 4 ? query.substring(0, query.length - 1) : query;
    bool match(String s) =>
        s.toLowerCase().contains(query) || s.toLowerCase().contains(stem);
    final stores = _stores.where((s) => match(s.name)).map(_storeJson);
    final products = _products
        .where(
          (p) =>
              match(p.name) ||
              match(p.description) ||
              match(p.sku) ||
              match(p.article) ||
              match(p.gtin ?? '') ||
              match(p.internalBarcode),
        )
        .map(_productJson);
    return _wrap([...stores, ...products]);
  }

  // -- cart ------------------------------------------------------------------

  dynamic _cart(String method, List<String> seg, Map<String, dynamic> b) {
    if (seg.length == 1) {
      if (method == 'GET') return _cartJson();
      if (method == 'DELETE') {
        _cartItems.clear();
        _cartStoreId = null;
        return {'ok': true};
      }
    }
    if (seg[1] == 'items') {
      if (method == 'POST' && seg.length == 2) {
        final product = _products.firstWhere(
          (p) => p.id == b['productId'],
          orElse: () => throw _notFound('Товар не найден'),
        );
        if (_cartStoreId != null && _cartStoreId != product.storeId) {
          throw const ApiException(
            code: 'CART_DIFFERENT_STORE',
            message: 'В корзине товары другого магазина',
            statusCode: 409,
          );
        }
        _cartStoreId ??= product.storeId;
        final idx = _cartItems.indexWhere(
          (i) => i.product.id == product.id && i.variantId == b['variantId'],
        );
        if (idx >= 0) {
          _cartItems[idx] = _cartItems[idx].copyWith(
            quantity:
                _cartItems[idx].quantity + ((b['qty'] as num?)?.toInt() ?? 1),
          );
        } else {
          _cartItems.add(
            CartItem(
              id: _id('ci'),
              product: product,
              quantity: (b['qty'] as num?)?.toInt() ?? 1,
              variantId: b['variantId'] as String?,
            ),
          );
        }
        return _cartJson();
      }
      if (seg.length == 3) {
        final idx = _cartItems.indexWhere((i) => i.id == seg[2]);
        if (idx < 0) throw _notFound('Позиция не найдена');
        if (method == 'PATCH') {
          final qty = (b['qty'] as num?)?.toInt() ?? 1;
          if (qty <= 0) {
            _cartItems.removeAt(idx);
          } else {
            _cartItems[idx] = _cartItems[idx].copyWith(quantity: qty);
          }
        } else if (method == 'DELETE') {
          _cartItems.removeAt(idx);
        }
        if (_cartItems.isEmpty) _cartStoreId = null;
        return _cartJson();
      }
    }
    throw _notFound('cart');
  }

  Map<String, dynamic> _cartJson() {
    final store = _stores.firstWhere(
      (s) => s.id == _cartStoreId,
      orElse: () => const Store(id: '', name: '', kind: StoreKind.other),
    );
    final subtotal = _cartItems.fold<int>(0, (s, i) => s + i.totalTiyn);
    final delivery = _cartItems.isEmpty ? 0 : store.deliveryFeeTiyn;
    return {
      'storeId': store.id,
      'storeName': store.name,
      'items': _cartItems
          .map(
            (i) => {
              'id': i.id,
              'quantity': i.quantity,
              'variantId': i.variantId,
              'product': _productJson(i.product),
            },
          )
          .toList(),
      'subtotalTiyn': subtotal,
      'deliveryTiyn': delivery,
      'discountTiyn': 0,
      'totalTiyn': subtotal + delivery,
    };
  }

  // -- checkout / payments ----------------------------------------------------

  dynamic _checkout(String method, List<String> seg, Map<String, dynamic> b) {
    if (_s(seg, 1) == 'validate') {
      final issues = <Map<String, dynamic>>[];
      for (final i in _cartItems) {
        if (!i.product.available || i.product.stock < i.quantity) {
          issues.add({
            'productId': i.product.id,
            'code': 'STOCK_CHANGED',
            'message': '${i.product.name}: осталось ${i.product.stock} шт',
          });
        }
      }
      return {
        'ok': issues.isEmpty,
        'issues': issues,
        'totals': _cartJson(),
      };
    }
    // POST /checkout
    if (_cartItems.isEmpty) {
      throw const ApiException(
        code: 'CART_EMPTY',
        message: 'Корзина пуста',
        statusCode: 400,
      );
    }
    final cart = _cartJson();
    final point = GeoPoint(
      lat: (b['lat'] as num?)?.toDouble() ?? MockData.shymkent.lat,
      lng: (b['lng'] as num?)?.toDouble() ?? MockData.shymkent.lng,
    );
    final method = b['paymentMethod'] as String? ?? 'kaspi';
    final promo = (b['promoCode'] as String?)?.toUpperCase();
    var discount = 0;
    if (promo != null && _promoCodes.containsKey(promo)) {
      final p = _promoCodes[promo]!;
      final subtotal = cart['subtotalTiyn'] as int;
      final scoped = p['productId'] as String?;
      final scopeOk =
          scoped == null || _cartItems.any((i) => i.product.id == scoped);
      if (subtotal >= (p['minOrderTiyn'] as int? ?? 0) && scopeOk) {
        if (p['bogo'] == true) {
          // 2+1: every 3rd unit of scoped products is free (cheapest).
          final units = <int>[];
          for (final i in _cartItems) {
            if (scoped == null || i.product.id == scoped) {
              units.addAll(List.filled(i.quantity, i.priceTiyn));
            }
          }
          units.sort();
          discount = units.take(units.length ~/ 3).fold(0, (s, v) => s + v);
        } else if (p['firstOrder'] == true &&
            _orders.any((o) => o.status == OrderStatus.delivered)) {
          discount = 0; // only for the first delivered order
        } else {
          final fixed = p['discountTiyn'] as int? ?? 0;
          final pct = p['percent'] as int?;
          discount = pct != null ? subtotal * pct ~/ 100 : fixed;
        }
      }
    }
    final order = Order(
      id: _id('ord'),
      number: 'K-${1000 + _seq}',
      storeId: cart['storeId'] as String,
      storeName: cart['storeName'] as String,
      items: _cartItems
          .map(
            (i) => OrderItem(
              productId: i.product.id,
              name: i.product.name,
              quantity: i.quantity,
              priceTiyn: i.priceTiyn,
            ),
          )
          .toList(),
      status: OrderStatus.pending,
      paymentStatus: PaymentStatus.initiated,
      delivery: DeliverySnapshot(
        address: b['address'] as String? ?? 'Шымкент',
        point: point,
        comment: b['comment'] as String?,
        capturedAt: DateTime.now(),
      ),
      subtotalTiyn: cart['subtotalTiyn'] as int,
      discountTiyn: discount,
      deliveryTiyn: cart['deliveryTiyn'] as int,
      totalTiyn: (cart['totalTiyn'] as int) - discount,
      createdAt: DateTime.now(),
      statusHistory: [
        OrderStatusEntry(
          status: OrderStatus.pending,
          actorRole: UserRole.customer,
          at: DateTime.now(),
        ),
      ],
      promoCode: promo,
    );
    // Wallet payment validates the balance BEFORE the cart is consumed.
    if (method == 'wallet' && _walletBalanceTiyn < order.totalTiyn) {
      throw const ApiException(
        code: 'INSUFFICIENT_FUNDS',
        message: 'Недостаточно бонусов на кошельке',
        statusCode: 402,
      );
    }
    _orders.insert(0, order);
    _cartItems.clear();
    _cartStoreId = null;
    if (method == 'wallet') {
      _walletBalanceTiyn -= order.totalTiyn;
      _walletTxns.insert(
        0,
        {
          'id': _id('txn'),
          'kind': 'spend',
          'amountTiyn': -order.totalTiyn,
          'title': 'Оплата заказа ${order.number}',
          'at': DateTime.now().toIso8601String(),
        },
      );
      final i = _orders.indexWhere((o) => o.id == order.id);
      _orders[i] = _orders[i].copyWith(paymentStatus: PaymentStatus.paid);
    }
    final placed = _orders.firstWhere((o) => o.id == order.id);
    // Wallet cashback — 2% of the paid total lands as bonus points.
    final cashback = order.totalTiyn ~/ 50;
    if (cashback > 0) {
      _walletBalanceTiyn += cashback;
      _walletTxns.insert(
        0,
        {
          'id': _id('txn'),
          'kind': 'cashback',
          'amountTiyn': cashback,
          'title': 'Кэшбэк за заказ ${order.number}',
          'at': DateTime.now().toIso8601String(),
        },
      );
    }
    _simulateOrder(order.id, method: method);
    final payId = _id('pay');
    _paymentIndex[payId] = order.id;
    return {
      'order': placed.toJsonSafe(),
      'payment': {
        'id': payId,
        'status': 'initiated',
        'clientPayload': {'deeplink': 'kaspi://kora/pay/${order.id}'},
      },
    };
  }

  dynamic _payments(String method, List<String> seg, Map<String, dynamic> b) {
    final pid = seg.length > 1 ? seg[1] : '';
    final orderId = _paymentIndex[pid];
    final order = orderId == null
        ? null
        : _orders.firstWhere(
            (o) => o.id == orderId,
            orElse: () => throw _notFound('Платёж не найден'),
          );
    if (order == null) throw _notFound('Платёж не найден');
    return {
      'id': pid,
      'orderId': order.id,
      'status': order.paymentStatus.name,
      'amountTiyn': order.totalTiyn,
    };
  }

  /// Simulates payment confirm → order lifecycle → courier GPS.
  void _simulateOrder(String orderId, {String method = 'kaspi'}) {
    void mutate(Order Function(Order) f) {
      final i = _orders.indexWhere((o) => o.id == orderId);
      if (i >= 0) _orders[i] = f(_orders[i]);
    }

    OrderStatusEntry entry(OrderStatus s, UserRole role) =>
        OrderStatusEntry(status: s, actorRole: role, at: DateTime.now());

    void setStatus(
      OrderStatus s,
      UserRole role, {
      String? courierName,
      String? courierId,
      String? courierPhone,
    }) {
      final i0 = _orders.indexWhere((o) => o.id == orderId);
      if (i0 < 0 ||
          _orders[i0].status == OrderStatus.cancelled ||
          _orders[i0].status == OrderStatus.delivered) {
        return; // a cancelled/delivered order no longer progresses
      }
      mutate(
        (o) => o.copyWith(
          status: s,
          courierName: courierName,
          courierId: courierId,
          courierPhone: courierPhone,
          statusHistory: [...o.statusHistory, entry(s, role)],
        ),
      );
      realtime?.emit(
        'order.status_changed',
        {'orderId': orderId, 'status': s.name},
      );
    }

    final steps = <(Duration, String, Map<String, dynamic>)>[
      (
        const Duration(seconds: 4),
        'payment.confirmed',
        {'orderId': orderId, 'status': 'paid'}
      ),
    ];
    Timer(const Duration(seconds: 4), () {
      // Cash is settled on delivery; wallet already debited at checkout.
      if (method != 'cash') {
        mutate((o) => o.copyWith(paymentStatus: PaymentStatus.paid));
      }
      _pushNotif(
        'Оплата подтверждена',
        'Заказ передан в магазин',
        kind: 'order',
        orderId: orderId,
      );
    });
    Timer(const Duration(seconds: 8), () {
      realtime?.emit('order.created', {'orderId': orderId});
      setStatus(OrderStatus.accepted, UserRole.manager);
    });
    Timer(const Duration(seconds: 22), () {
      setStatus(OrderStatus.preparing, UserRole.manager);
    });
    Timer(const Duration(seconds: 38), () {
      setStatus(OrderStatus.readyForPickup, UserRole.manager);
    });
    Timer(const Duration(seconds: 48), () {
      setStatus(
        OrderStatus.courierAssigned,
        UserRole.admin,
        courierId: 'u-courier',
        courierName: 'Арман',
        courierPhone: '+77000000003',
      );
      realtime?.emit(
        'courier.assigned',
        {'orderId': orderId, 'courierName': 'Арман'},
      );
      _pushNotif(
        'Курьер назначен',
        'Арман уже забирает ваш заказ',
        kind: 'order',
        orderId: orderId,
      );
      _startCourierGps(orderId);
    });
    realtime?.schedule(steps);
  }

  void _startCourierGps(String orderId) {
    final i = _orders.indexWhere((o) => o.id == orderId);
    if (i < 0) return;
    final order = _orders[i];
    final store = _stores.firstWhere(
      (s) => s.id == order.storeId,
      orElse: () => MockData.stores.first,
    );
    final from = store.point ?? MockData.shymkent;
    final to = order.delivery.point;
    var tick = 0;
    const totalTicks = 8;
    Timer.periodic(const Duration(seconds: 5), (t) {
      tick++;
      final k = (tick / totalTicks).clamp(0.0, 1.0);
      final pos = GeoPoint(
        lat: from.lat + (to.lat - from.lat) * k,
        lng: from.lng + (to.lng - from.lng) * k,
      );
      final idx = _orders.indexWhere((o) => o.id == orderId);
      if (idx < 0 || _orders[idx].status == OrderStatus.cancelled) {
        t.cancel();
        return;
      }
      {
        _orders[idx] = _orders[idx].copyWith(courierLocation: pos);
        if (tick == 2) {
          _orders[idx] = _orders[idx].copyWith(
            status: OrderStatus.pickedUp,
            statusHistory: [
              ..._orders[idx].statusHistory,
              OrderStatusEntry(
                status: OrderStatus.pickedUp,
                actorRole: UserRole.courier,
                at: DateTime.now(),
              ),
            ],
          );
          realtime?.emit(
            'order.status_changed',
            {'orderId': orderId, 'status': 'pickedUp'},
          );
        }
        if (tick == 3) {
          _orders[idx] = _orders[idx].copyWith(
            status: OrderStatus.delivering,
            statusHistory: [
              ..._orders[idx].statusHistory,
              OrderStatusEntry(
                status: OrderStatus.delivering,
                actorRole: UserRole.courier,
                at: DateTime.now(),
              ),
            ],
          );
          realtime?.emit(
            'order.status_changed',
            {'orderId': orderId, 'status': 'delivering'},
          );
        }
      }
      realtime?.emit('courier.location_updated', {
        'orderId': orderId,
        'lat': pos.lat,
        'lng': pos.lng,
      });
      if (tick >= totalTicks) {
        t.cancel();
        final j = _orders.indexWhere((o) => o.id == orderId);
        if (j >= 0) {
          _orders[j] = _orders[j].copyWith(
            status: OrderStatus.delivered,
            paymentStatus: PaymentStatus.paid,
            statusHistory: [
              ..._orders[j].statusHistory,
              OrderStatusEntry(
                status: OrderStatus.delivered,
                actorRole: UserRole.courier,
                at: DateTime.now(),
              ),
            ],
          );
        }
        realtime?.emit(
          'order.status_changed',
          {'orderId': orderId, 'status': 'delivered'},
        );
        realtime?.emit('order.delivered', {'orderId': orderId});
        _pushNotif(
          'Заказ доставлен',
          'Приятного аппетита!',
          kind: 'order',
          orderId: orderId,
        );
      }
    });
  }

  // -- orders / tracking --------------------------------------------------------

  dynamic _ordersApi(String method, List<String> seg, Map<String, dynamic> b) {
    if (seg.length == 1) {
      return _wrap(_orders.map((o) => o.toJsonSafe()));
    }
    final order = _orders.firstWhere(
      (o) => o.id == seg[1],
      orElse: () => throw _notFound('Заказ не найден'),
    );
    if (seg.length == 2) return order.toJsonSafe();
    if (_s(seg, 2) == 'cancel' && method == 'POST') {
      if (!order.canCancel) {
        throw const ApiException(
          code: 'CANNOT_CANCEL',
          message: 'Заказ уже готовится — отмена недоступна',
          statusCode: 409,
        );
      }
      final i = _orders.indexWhere((o) => o.id == order.id);
      // Bonus payments go back to the wallet instantly.
      if (order.paymentStatus == PaymentStatus.paid &&
          _walletTxns.any(
            (t) =>
                t['kind'] == 'spend' &&
                (t['title'] as String).contains(order.number),
          )) {
        _walletBalanceTiyn += order.totalTiyn;
        _walletTxns.insert(
          0,
          {
            'id': _id('txn'),
            'kind': 'refund',
            'amountTiyn': order.totalTiyn,
            'title': 'Возврат за заказ ${order.number}',
            'at': DateTime.now().toIso8601String(),
          },
        );
      }
      _orders[i] = order.copyWith(
        status: OrderStatus.cancelled,
        paymentStatus: PaymentStatus.refunded,
        statusHistory: [
          ...order.statusHistory,
          OrderStatusEntry(
            status: OrderStatus.cancelled,
            actorRole: UserRole.customer,
            at: DateTime.now(),
            reason: b['reason'] as String?,
          ),
        ],
      );
      realtime?.emit(
        'order.status_changed',
        {'orderId': order.id, 'status': 'cancelled'},
      );
      return _orders[i].toJsonSafe();
    }
    if (_s(seg, 2) == 'repeat' && method == 'POST') {
      // Re-add items at current prices; skip out-of-stock.
      var added = 0;
      for (final item in order.items) {
        final p = _products.where((x) => x.id == item.productId).firstOrNull;
        if (p == null || !p.available || p.stock < item.quantity) {
          continue;
        }
        _cartItems.add(
          CartItem(
            id: _id('ci'),
            product: p,
            quantity: item.quantity,
          ),
        );
        added++;
      }
      _cartStoreId ??= order.storeId;
      return {'added': added, 'cart': _cartJson()};
    }
    throw _notFound('orders');
  }

  dynamic _tracking(List<String> seg) {
    final order = _orders.firstWhere(
      (o) => o.id == _s(seg, 2),
      orElse: () => throw _notFound('Заказ не найден'),
    );
    return {
      'orderId': order.id,
      'orderStatus': order.status.name,
      'courierLocation': order.courierLocation?.toJson(),
      'courierName': order.courierName,
    };
  }

  // -- chat ------------------------------------------------------------------

  String _roomFor(String orderId) => 'room-$orderId';

  dynamic _chat(
    String method,
    List<String> seg,
    Map<String, dynamic> b,
    Map<String, dynamic> q,
  ) {
    if (_s(seg, 1) == 'rooms') {
      if (seg.length == 2) {
        final orderId = q['orderId'] as String?;
        if (orderId != null) {
          final order = _orders.firstWhere(
            (o) => o.id == orderId,
            orElse: () => throw _notFound('Заказ не найден'),
          );
          return _wrap([
            {
              'id': _roomFor(order.id),
              'orderId': order.id,
              'title': order.storeName,
              'peerName': order.storeName,
              'unread': 0,
            }
          ]);
        }
        return _wrap(
          _chatMessages.keys.map(
            (id) => {
              'id': id,
              'orderId': id.replaceFirst('room-', ''),
              'title': 'Чат',
              'unread': 0,
            },
          ),
        );
      }
      final roomId = seg[2];
      _chatMessages.putIfAbsent(roomId, () => []);
      if (seg.length == 3) {
        return {
          'id': roomId,
          'orderId': roomId.replaceFirst('room-', ''),
          'title': 'Чат по заказу',
          'peerName': 'Поддержка магазина',
          'unread': 0,
        };
      }
      if (seg[3] == 'messages') {
        if (method == 'GET') {
          return _wrap(
            _chatMessages[roomId]!.map((m) => _msgJson(m)),
          );
        }
        if (method == 'POST') {
          final msg = ChatMessage(
            id: _id('msg'),
            roomId: roomId,
            senderId: _uid,
            type: switch (b['type']) {
              'image' => ChatMessageType.image,
              'voice' => ChatMessageType.voice,
              'location' => ChatMessageType.location,
              _ => ChatMessageType.text,
            },
            at: DateTime.now(),
            text: b['text'] as String?,
            mediaUrl: b['mediaUrl'] as String?,
            point: b['lat'] != null
                ? GeoPoint(
                    lat: (b['lat'] as num).toDouble(),
                    lng: (b['lng'] as num).toDouble(),
                  )
                : null,
          );
          _chatMessages[roomId]!.add(msg);
          // Simulated peer reply — typing indicator first.
          Timer(const Duration(milliseconds: 1200), () {
            realtime?.emit('chat.typing', {'roomId': roomId});
          });
          Timer(const Duration(seconds: 3), () {
            final reply = ChatMessage(
              id: _id('msg'),
              roomId: roomId,
              senderId: 'peer',
              type: ChatMessageType.text,
              at: DateTime.now(),
              text: 'Приняли, спасибо! Ответим в ближайшее время.',
              read: false,
            );
            _chatMessages[roomId]!.add(reply);
            realtime?.emit(
              'chat.message_created',
              {'roomId': roomId, 'message': _msgJson(reply)},
            );
          });
          return _msgJson(msg);
        }
      }
      if (seg[3] == 'read' || seg[3] == 'typing') {
        return {'ok': true};
      }
    }
    throw _notFound('chat');
  }

  // -- courier ----------------------------------------------------------------

  dynamic _courier(String method, List<String> seg, Map<String, dynamic> b) {
    switch (_s(seg, 1)) {
      case 'status':
        _courierStatus = switch (b['status']) {
          'online' => CourierStatus.online,
          _ => CourierStatus.offline,
        };
        if (_courierStatus == CourierStatus.online && _courierOffers.isEmpty) {
          _seedCourierOffer();
        }
        return {'status': _courierStatus.name};
      case 'location':
        final point = GeoPoint(
          lat: (b['lat'] as num?)?.toDouble() ?? MockData.shymkent.lat,
          lng: (b['lng'] as num?)?.toDouble() ?? MockData.shymkent.lng,
        );
        _lastCourierPoint = point;
        if (_activeCourierOrderId != null) {
          final i = _orders.indexWhere((o) => o.id == _activeCourierOrderId);
          if (i >= 0) {
            _orders[i] = _orders[i].copyWith(courierLocation: point);
            realtime?.emit('courier.location_updated', {
              'orderId': _activeCourierOrderId,
              'lat': point.lat,
              'lng': point.lng,
            });
          }
        }
        return {'ok': true};
      case 'assignments':
        if (seg.length == 2) {
          return _wrap(_courierOffers.map(_offerJson));
        }
        final offer = _courierOffers.firstWhere(
          (o) => o.id == seg[2],
          orElse: () => throw _notFound('Предложение не найдено'),
        );
        if (_s(seg, 3) == 'accept') {
          _courierOffers.remove(offer);
          _courierStatus = CourierStatus.delivering;
          _activeCourierOrderId = offer.orderId;
          return {'ok': true, 'orderId': offer.orderId};
        }
        if (_s(seg, 3) == 'reject') {
          _courierOffers.remove(offer);
          return {'ok': true};
        }
        break;
      case 'orders':
        // POST /couriers/orders/:id/status — courier advances delivery.
        if (seg.length == 4 && _s(seg, 3) == 'status' && method == 'POST') {
          final oid = _s(seg, 2);
          final i = _orders.indexWhere((o) => o.id == oid);
          if (i < 0) throw _notFound('Заказ не найден');
          final status = OrderStatus.values.firstWhere(
            (s) => s.name == b['status'],
            orElse: () => _orders[i].status,
          );
          _orders[i] = _orders[i].copyWith(
            status: status,
            courierLocation: _lastCourierPoint,
            courierId: _uid,
            courierName: _user?.name ?? 'Курьер',
            courierPhone: _user?.phone ?? '+77000000003',
            statusHistory: [
              ..._orders[i].statusHistory,
              OrderStatusEntry(
                status: status,
                actorRole: UserRole.courier,
                at: DateTime.now(),
              ),
            ],
          );
          realtime?.emit(
            'order.status_changed',
            {'orderId': oid, 'status': status.name},
          );
          if (status == OrderStatus.delivered) {
            _activeCourierOrderId = null;
            _courierStatus = CourierStatus.online;
            realtime?.emit('order.delivered', {'orderId': oid});
          }
          return _orders[i].toJsonSafe();
        }
        return {'ok': true};
    }
    throw _notFound('couriers');
  }

  void _pushNotif(
    String title,
    String body, {
    String kind = 'info',
    String? orderId,
  }) {
    _notifications.insert(
      0,
      AppNotification(
        id: _id('ntf'),
        title: title,
        body: body,
        kind: kind,
        at: DateTime.now(),
        orderId: orderId,
      ),
    );
    realtime?.emit(
      'notification.created',
      {'title': title, 'body': body, 'orderId': orderId},
    );
  }

  void _seedCourierOffer() {
    final store = MockData.stores.first;
    // Back the offer with a real order so tracking/chat/detail work.
    final products =
        _products.where((p) => p.storeId == store.id).take(2).toList();
    final orderId = _id('ord');
    final items = products
        .map(
          (p) => OrderItem(
            productId: p.id,
            name: p.name,
            quantity: 1,
            priceTiyn: p.priceTiyn,
          ),
        )
        .toList();
    final subtotal = items.fold<int>(0, (s, i) => s + i.priceTiyn);
    _orders.insert(
      0,
      Order(
        id: orderId,
        number: 'K-${1000 + _seq}',
        storeId: store.id,
        storeName: store.name,
        items: items,
        status: OrderStatus.readyForPickup,
        paymentStatus: PaymentStatus.paid,
        delivery: DeliverySnapshot(
          address: 'Шымкент, ул. Желтоксан 45',
          point: MockData.shymkent,
          capturedAt: DateTime.now(),
        ),
        subtotalTiyn: subtotal,
        discountTiyn: 0,
        deliveryTiyn: store.deliveryFeeTiyn,
        totalTiyn: subtotal + store.deliveryFeeTiyn,
        createdAt: DateTime.now(),
        statusHistory: [
          OrderStatusEntry(
            status: OrderStatus.readyForPickup,
            actorRole: UserRole.manager,
            at: DateTime.now(),
          ),
        ],
      ),
    );
    _courierOffers.add(
      CourierOffer(
        id: _id('off'),
        orderId: orderId,
        orderNumber: _orders.first.number,
        storeName: store.name,
        pickupAddress: store.address,
        pickup: store.point ?? MockData.shymkent,
        dropoffAddress: 'Шымкент, ул. Желтоксан 45',
        dropoff: MockData.shymkent,
        feeTiyn: 89000,
        distanceKm: 4.2,
        expiresAt: DateTime.now().add(const Duration(seconds: 60)),
      ),
    );
  }

  // -- manager / admin ----------------------------------------------------------

  dynamic _manager(
    String method,
    List<String> seg,
    Map<String, dynamic> b,
    Map<String, dynamic> q,
  ) {
    switch (_s(seg, 1)) {
      case 'dashboard':
        return {
          'newOrders':
              _orders.where((o) => o.status == OrderStatus.pending).length,
          'preparing':
              _orders.where((o) => o.status == OrderStatus.preparing).length,
          'ready': _orders
              .where((o) => o.status == OrderStatus.readyForPickup)
              .length,
          'deliveredToday':
              _orders.where((o) => o.status == OrderStatus.delivered).length,
          'cancelledToday':
              _orders.where((o) => o.status == OrderStatus.cancelled).length,
          'salesTodayTiyn': _orders.fold<int>(0, (s, o) => s + o.totalTiyn),
        };
      case 'orders':
        if (seg.length == 2) return _wrap(_orders.map((o) => o.toJsonSafe()));
        final order = _orders.firstWhere(
          (o) => o.id == seg[2],
          orElse: () => throw _notFound('Заказ не найден'),
        );
        final action = _s(seg, 3);
        final next = switch (action) {
          'accept' => OrderStatus.accepted,
          'reject' => OrderStatus.rejected,
          'ready' => OrderStatus.readyForPickup,
          'assign-courier' => OrderStatus.courierAssigned,
          _ => order.status,
        };
        final i = _orders.indexWhere((o) => o.id == order.id);
        _orders[i] = order.copyWith(
          status: next,
          statusHistory: [
            ...order.statusHistory,
            OrderStatusEntry(
              status: next,
              actorRole: UserRole.manager,
              at: DateTime.now(),
            ),
          ],
        );
        _audit.add(
          AuditEntry(
            id: _id('aud'),
            actor: _user?.name ?? 'manager',
            role: UserRole.manager,
            action: 'order_$action',
            resource: order.id,
            at: DateTime.now(),
          ),
        );
        realtime?.emit(
          'order.status_changed',
          {'orderId': order.id, 'status': next.name},
        );
        return _orders[i].toJsonSafe();
      case 'products':
        if (method == 'GET') {
          return _wrap(_products.map(_productJson));
        }
        if (method == 'POST') {
          final p = Product(
            id: b['id'] as String? ?? _id('p'),
            storeId: b['storeId'] as String? ?? 'kora-market',
            name: b['name'] as String? ?? 'Новый товар',
            description: b['description'] as String? ?? '',
            priceTiyn: (b['priceTiyn'] as num?)?.toInt() ?? 0,
            oldPriceTiyn: (b['oldPriceTiyn'] as num?)?.toInt(),
            stock: (b['stock'] as num?)?.toInt() ?? 0,
            imageUrl: b['imageUrl'] as String?,
            categoryId: b['categoryId'] as String?,
          );
          _products.add(p);
          return _productJson(p);
        }
        if (seg.length == 3 && method == 'PATCH') {
          final i = _products.indexWhere((p) => p.id == _s(seg, 2));
          if (i < 0) throw _notFound('Товар не найден');
          final old = _products[i];
          _products[i] = Product(
            id: old.id,
            storeId: old.storeId,
            name: b['name'] as String? ?? old.name,
            description: b['description'] as String? ?? old.description,
            imageUrl: b.containsKey('imageUrl')
                ? b['imageUrl'] as String?
                : old.imageUrl,
            categoryId: b.containsKey('categoryId')
                ? b['categoryId'] as String?
                : old.categoryId,
            priceTiyn: (b['priceTiyn'] as num?)?.toInt() ?? old.priceTiyn,
            oldPriceTiyn:
                (b['oldPriceTiyn'] as num?)?.toInt() ?? old.oldPriceTiyn,
            stock: (b['stock'] as num?)?.toInt() ?? old.stock,
            available: b['available'] as bool? ?? old.available,
          );
          _audit.add(
            AuditEntry(
              id: _id('aud'),
              actor: _user?.name ?? 'manager',
              role: UserRole.manager,
              action: 'price_changed',
              resource: old.id,
              at: DateTime.now(),
            ),
          );
          return _productJson(_products[i]);
        }
        break;
      case 'couriers':
        return _wrap(const [
          {
            'id': 'u-courier',
            'name': 'Арман',
            'status': 'online',
            'activeOrders': 1,
          },
          {
            'id': 'u-courier2',
            'name': 'Даулет',
            'status': 'busy',
            'activeOrders': 2,
          },
        ]);
      case 'schedule':
        // GET/PUT /manager/schedule — working hours for own store.
        final storeId = b['storeId'] as String? ?? 'kora-market';
        if (method == 'PUT') {
          final days = <int, ({int open, int close})?>{};
          (b['days'] as Map?)?.forEach((k, v) {
            final d = int.tryParse('$k');
            if (d == null) return;
            if (v == null) {
              days[d] = null;
            } else {
              final m = v as Map;
              days[d] = (
                open: (m['open'] as num).toInt(),
                close: (m['close'] as num).toInt(),
              );
            }
          });
          _schedules[storeId] = days;
          return {'ok': true};
        }
        return {
          'storeId': storeId,
          'days': (_schedules[storeId] ?? {}).map(
            (d, v) => MapEntry(
              '$d',
              v == null ? null : {'open': v.open, 'close': v.close},
            ),
          ),
        };
      case 'map':
        return {
          'stores': _stores
              .map(
                (s) => {
                  'id': s.id,
                  'name': s.name,
                  'lat': s.point?.lat,
                  'lng': s.point?.lng,
                },
              )
              .toList(),
          'couriers': const [
            {'id': 'u-courier', 'lat': 42.345, 'lng': 69.585},
          ],
          'orders': _orders
              .map(
                (o) => {
                  'id': o.id,
                  'status': o.status.name,
                  'lat': o.delivery.point.lat,
                  'lng': o.delivery.point.lng,
                },
              )
              .toList(),
        };
    }
    throw _notFound('manager');
  }

  dynamic _admin(
    String method,
    List<String> seg,
    Map<String, dynamic> b,
    Map<String, dynamic> q,
  ) {
    switch (_s(seg, 1)) {
      case 'users':
        if (seg.length == 4 && _s(seg, 3) == 'block' && method == 'POST') {
          final uid = _s(seg, 2);
          final blocked = b['blocked'] as bool? ?? true;
          if (blocked) {
            _blockedUserIds.add(uid);
          } else {
            _blockedUserIds.remove(uid);
          }
          _audit.add(
            AuditEntry(
              id: _id('aud'),
              actor: _user?.name ?? 'admin',
              role: UserRole.admin,
              action: blocked ? 'user_blocked' : 'user_unblocked',
              resource: uid,
              at: DateTime.now(),
            ),
          );
          return {'id': uid, 'blocked': blocked};
        }
        final all = [
          if (_user != null) _user!,
          ..._users,
        ];
        return _wrap(
          all.map(
            (u) => {
              ...u.toJson(),
              'blocked': u.blocked || _blockedUserIds.contains(u.id),
            },
          ),
        );
      case 'stores':
        return _wrap(_stores.map(_storeJson));
      case 'orders':
        return _wrap(_orders.map((o) => o.toJsonSafe()));
      case 'payments':
        return _wrap(
          _orders.map(
            (o) => {
              'id': 'pay-${o.id}',
              'orderId': o.id,
              'status': o.paymentStatus.name,
              'amountTiyn': o.totalTiyn,
            },
          ),
        );
      case 'audit-logs':
        return _wrap(
          _audit.map(
            (a) => {
              'id': a.id,
              'actor': a.actor,
              'role': a.role.name,
              'action': a.action,
              'resource': a.resource,
              'at': a.at.toIso8601String(),
              'result': a.result,
            },
          ),
        );
      case 'support':
        return _wrap(_tickets.map(_ticketJson));
      case 'products':
        if (method == 'GET') {
          return _wrap(_products.map(_productJson));
        }
        if (method == 'POST') {
          final p = Product(
            id: b['id'] as String? ?? _id('p'),
            storeId: b['storeId'] as String? ?? _stores.first.id,
            name: b['name'] as String? ?? 'Новый товар',
            description: b['description'] as String? ?? '',
            imageUrl: b['imageUrl'] as String?,
            categoryId: b['categoryId'] as String?,
            priceTiyn: (b['priceTiyn'] as num?)?.toInt() ?? 0,
            oldPriceTiyn: (b['oldPriceTiyn'] as num?)?.toInt(),
            stock: (b['stock'] as num?)?.toInt() ?? 0,
            available: b['available'] as bool? ?? true,
          );
          _products.add(p);
          _audit.add(
            AuditEntry(
              id: _id('aud'),
              actor: _user?.name ?? 'admin',
              role: UserRole.admin,
              action: 'product_created',
              resource: p.id,
              at: DateTime.now(),
            ),
          );
          return _productJson(p);
        }
        if (seg.length == 3 && method == 'PATCH') {
          final i = _products.indexWhere((p) => p.id == _s(seg, 2));
          if (i < 0) throw _notFound('Товар не найден');
          final old = _products[i];
          _products[i] = Product(
            id: old.id,
            storeId: b['storeId'] as String? ?? old.storeId,
            name: b['name'] as String? ?? old.name,
            description: b['description'] as String? ?? old.description,
            imageUrl: b.containsKey('imageUrl')
                ? b['imageUrl'] as String?
                : old.imageUrl,
            priceTiyn: (b['priceTiyn'] as num?)?.toInt() ?? old.priceTiyn,
            oldPriceTiyn: b.containsKey('oldPriceTiyn')
                ? (b['oldPriceTiyn'] as num?)?.toInt()
                : old.oldPriceTiyn,
            stock: (b['stock'] as num?)?.toInt() ?? old.stock,
            available: b['available'] as bool? ?? old.available,
            sku: old.sku,
            categoryId: b.containsKey('categoryId')
                ? b['categoryId'] as String?
                : old.categoryId,
            unit: old.unit,
            variants: old.variants,
            characteristics: old.characteristics,
          );
          _audit.add(
            AuditEntry(
              id: _id('aud'),
              actor: _user?.name ?? 'admin',
              role: UserRole.admin,
              action: 'product_updated',
              resource: old.id,
              at: DateTime.now(),
            ),
          );
          // Price-drop: favorited product got cheaper → notify.
          final newPrice = (b['priceTiyn'] as num?)?.toInt() ?? old.priceTiyn;
          if (newPrice < old.priceTiyn &&
              _favoriteProductIds.contains(old.id)) {
            _pushNotif(
              'Цена снизилась',
              '${old.name} — теперь ${(newPrice ~/ 100)} ₸',
              kind: 'price_drop',
            );
          }
          return _productJson(_products[i]);
        }
        if (seg.length == 3 && method == 'DELETE') {
          _products.removeWhere((p) => p.id == _s(seg, 2));
          return {'ok': true};
        }
        break;
      case 'promo-codes':
        if (method == 'GET') {
          return _wrap(
            _promoCodes.entries.map(
              (e) => {
                'code': e.key,
                ...e.value,
              },
            ),
          );
        }
        if (method == 'POST') {
          final code = (b['code'] as String? ?? '').trim().toUpperCase();
          if (code.isEmpty) {
            throw const ApiException(
              code: 'INVALID_CODE',
              message: 'Укажите код промокода',
              statusCode: 400,
            );
          }
          _promoCodes[code] = {
            if ((b['discountTiyn'] as num?) != null)
              'discountTiyn': (b['discountTiyn'] as num).toInt(),
            if ((b['percent'] as num?) != null)
              'percent': (b['percent'] as num).toInt(),
            'minOrderTiyn': (b['minOrderTiyn'] as num?)?.toInt() ?? 0,
            if (b['productId'] != null) 'productId': b['productId'] as String,
            if (b['bogo'] == true) 'bogo': true,
            if (b['firstOrder'] == true) 'firstOrder': true,
          };
          return {'code': code, ..._promoCodes[code]!};
        }
        if (seg.length == 3 && method == 'DELETE') {
          _promoCodes.remove(_s(seg, 2).toUpperCase());
          return {'ok': true};
        }
        break;
      case 'promotions':
        if (method == 'GET') {
          return _wrap(_promotions.map(_promoJson));
        }
        if (method == 'POST') {
          final p = Promotion(
            id: _id('promo'),
            title: b['title'] as String? ?? '',
            subtitle: b['subtitle'] as String?,
            imageUrl: b['imageUrl'] as String?,
            storeId: b['storeId'] as String?,
            code: b['code'] as String?,
            discountPercent: (b['discountPercent'] as num?)?.toInt(),
          );
          _promotions.insert(0, p);
          return _promoJson(p);
        }
        if (seg.length == 3 && method == 'DELETE') {
          _promotions.removeWhere((p) => p.id == _s(seg, 2));
          return {'ok': true};
        }
        break;
    }
    throw _notFound('admin');
  }

  // -- support / notifications -------------------------------------------------

  dynamic _support(String method, List<String> seg, Map<String, dynamic> b) {
    if (_s(seg, 1) == 'faq') {
      return _wrap(
        MockData.faq.map((f) => {'question': f.question, 'answer': f.answer}),
      );
    }
    if (_s(seg, 1) == 'tickets') {
      if (method == 'GET') {
        if (seg.length == 2) return _wrap(_tickets.map(_ticketJson));
        return _ticketJson(
          _tickets.firstWhere(
            (t) => t.id == seg[2],
            orElse: () => throw _notFound('Обращение не найдено'),
          ),
        );
      }
      if (method == 'POST' && seg.length == 2) {
        final text = b['message'] as String? ?? '';
        final t = SupportTicket(
          id: _id('tick'),
          subject: b['subject'] as String? ?? 'Обращение',
          status: TicketStatus.open,
          createdAt: DateTime.now(),
          messages: [
            if (text.isNotEmpty)
              ChatMessage(
                id: _id('msg'),
                roomId: '',
                senderId: _uid,
                type: ChatMessageType.text,
                text: text,
                at: DateTime.now(),
              ),
          ],
        );
        _tickets.insert(0, t);
        _simulateSupportReply(t.id);
        return _ticketJson(t);
      }
      if (seg.length == 4 && seg[3] == 'messages' && method == 'POST') {
        final i = _tickets.indexWhere((t) => t.id == seg[2]);
        if (i < 0) throw _notFound('Обращение не найдено');
        final old = _tickets[i];
        final msg = ChatMessage(
          id: _id('msg'),
          roomId: old.id,
          senderId: _uid,
          type: ChatMessageType.text,
          text: b['text'] as String? ?? b['message'] as String? ?? '',
          at: DateTime.now(),
        );
        _tickets[i] = SupportTicket(
          id: old.id,
          subject: old.subject,
          status: old.status,
          createdAt: old.createdAt,
          messages: [...old.messages, msg],
        );
        _simulateSupportReply(old.id);
        return _ticketJson(_tickets[i]);
      }
    }
    throw _notFound('support');
  }

  void _simulateSupportReply(String ticketId) {
    Timer(const Duration(seconds: 6), () {
      final i = _tickets.indexWhere((t) => t.id == ticketId);
      if (i < 0) return;
      final old = _tickets[i];
      _tickets[i] = SupportTicket(
        id: old.id,
        subject: old.subject,
        status: TicketStatus.inProgress,
        createdAt: old.createdAt,
        messages: [
          ...old.messages,
          ChatMessage(
            id: _id('msg'),
            roomId: old.id,
            senderId: 'support',
            type: ChatMessageType.text,
            text: 'Здравствуйте! Оператор KORA уже смотрит ваше '
                'обращение — ответим в течение пары минут.',
            at: DateTime.now(),
          ),
        ],
      );
      realtime?.emit(
        'support.message',
        {'ticketId': ticketId, 'status': 'inProgress'},
      );
    });
  }

  dynamic _notifs(String method, List<String> seg, Map<String, dynamic> b) {
    if (_s(seg, 1) == 'devices') return {'ok': true};
    if (_s(seg, 1) == 'preferences') {
      if (method == 'POST') _notifPrefs.addAll(b);
      return {'ok': true, 'preferences': _notifPrefs};
    }
    if (_s(seg, 1) == 'read') {
      for (var i = 0; i < _notifications.length; i++) {
        final n = _notifications[i];
        if (!n.read && (b['id'] == null || b['id'] == n.id)) {
          _notifications[i] = AppNotification(
            id: n.id,
            title: n.title,
            body: n.body,
            kind: n.kind,
            at: n.at,
            read: true,
            orderId: n.orderId,
          );
        }
      }
      return {'ok': true};
    }
    return _wrap(
      _notifications.map(
        (n) => {
          'id': n.id,
          'title': n.title,
          'body': n.body,
          'kind': n.kind,
          'at': n.at.toIso8601String(),
          'read': n.read,
          'orderId': n.orderId,
        },
      ),
    );
  }

  Map<String, dynamic> _validatePromo(Map<String, dynamic> b) {
    final code = (b['code'] as String? ?? '').toUpperCase();
    final promo = _promoCodes[code];
    if (promo == null) {
      return {
        'valid': false,
        'message': 'Промокод не найден или истёк',
      };
    }
    final productId = promo['productId'] as String?;
    if (productId != null &&
        !_cartItems.any((i) => i.product.id == productId)) {
      return {
        'valid': false,
        'message': 'Промокод действует только на выбранный товар',
      };
    }
    if (promo['firstOrder'] == true &&
        _orders.any((o) => o.status == OrderStatus.delivered)) {
      return {
        'valid': false,
        'message': 'Промокод действует только на первый заказ',
      };
    }
    var discountTiyn = promo['discountTiyn'] as int? ?? 0;
    if (promo['bogo'] == true) {
      final units = <int>[];
      for (final i in _cartItems) {
        if (productId == null || i.product.id == productId) {
          units.addAll(List.filled(i.quantity, i.priceTiyn));
        }
      }
      units.sort();
      discountTiyn = units.take(units.length ~/ 3).fold(0, (s, v) => s + v);
      if (discountTiyn == 0) {
        return {
          'valid': false,
          'message': 'Добавьте минимум 3 товара — третий будет бесплатным',
        };
      }
    }
    return {
      'valid': true,
      'discountTiyn': discountTiyn,
      'percent': promo['percent'] as int?,
      'minOrderTiyn': promo['minOrderTiyn'] as int? ?? 0,
      'bogo': promo['bogo'] == true,
      'message': promo['bogo'] == true
          ? '2+1 — третий товар бесплатно'
          : 'Промокод $code применён',
    };
  }

  // -- json helpers ------------------------------------------------------------

  Map<String, dynamic> _wrap(Iterable<Map<String, dynamic>> items) =>
      {'items': items.toList(), 'nextCursor': null};

  Map<String, dynamic> _catJson(Category c) => {
        'id': c.id,
        'name': c.name,
        'kind': c.kind.name,
        'parentId': c.parentId,
      };

  Map<String, dynamic> _addrJson(Address a) => {
        'id': a.id,
        'label': a.label,
        'address': a.address,
        'lat': a.point.lat,
        'lng': a.point.lng,
        'comment': a.comment,
        'isDefault': a.isDefault,
      };

  Map<String, dynamic> _storeJson(Store s) => {
        'id': s.id,
        'name': s.name,
        'kind': s.kind.name,
        'description': s.description,
        'logoUrl': s.logoUrl,
        'bannerUrl': s.bannerUrl,
        'blurHash': s.blurHash,
        'address': s.address,
        'lat': s.point?.lat,
        'lng': s.point?.lng,
        'rating': s.rating,
        'etaMinutes': s.etaMinutes,
        'deliveryFeeTiyn': s.deliveryFeeTiyn,
        'minOrderTiyn': s.minOrderTiyn,
        'isOpen': s.isOpen,
        'workingHours': s.workingHours,
        'isFavorite': _favoriteIds.contains(s.id),
      };

  Map<String, dynamic> _productJson(Product p) => {
        'id': p.id,
        'storeId': p.storeId,
        'name': p.name,
        'description': p.description,
        'imageUrl': p.imageUrl,
        'blurHash': p.blurHash,
        'priceTiyn': p.priceTiyn,
        'oldPriceTiyn': p.oldPriceTiyn,
        'sku': p.sku,
        'slug': p.slug,
        'article': p.article,
        'gtin': p.gtin,
        'internalBarcode': p.internalBarcode,
        'qrIdentifier': p.qrIdentifier,
        'categoryId': p.categoryId,
        'subcategoryId': p.subcategoryId,
        'brandId': p.brandId,
        'unit': p.unit,
        'active': p.active,
        'available': p.available && p.stock > 0,
        'stock': p.stock,
        'variants': p.variants
            .map(
              (v) => {
                'id': v.id,
                'name': v.name,
                'priceTiyn': v.priceTiyn,
              },
            )
            .toList(),
        'characteristics': p.characteristics,
      };

  Map<String, dynamic> _msgJson(ChatMessage m) => {
        'id': m.id,
        'roomId': m.roomId,
        'senderId': m.senderId,
        'type': m.type.name,
        'at': m.at.toIso8601String(),
        'text': m.text,
        'mediaUrl': m.mediaUrl,
        'lat': m.point?.lat,
        'lng': m.point?.lng,
        'read': m.read,
      };

  Map<String, dynamic> _offerJson(CourierOffer o) => {
        'id': o.id,
        'orderId': o.orderId,
        'orderNumber': o.orderNumber,
        'storeName': o.storeName,
        'pickupAddress': o.pickupAddress,
        'pickup': o.pickup.toJson(),
        'dropoffAddress': o.dropoffAddress,
        'dropoff': o.dropoff.toJson(),
        'feeTiyn': o.feeTiyn,
        'distanceKm': o.distanceKm,
        'expiresAt': o.expiresAt.toIso8601String(),
      };

  Map<String, dynamic> _promoJson(Promotion p) => {
        'id': p.id,
        'title': p.title,
        'subtitle': p.subtitle,
        'imageUrl': p.imageUrl,
        'storeId': p.storeId,
        'code': p.code,
        'discountPercent': p.discountPercent,
      };

  Map<String, dynamic> _ticketJson(SupportTicket t) => {
        'id': t.id,
        'subject': t.subject,
        'status': t.status.name,
        'createdAt': t.createdAt.toIso8601String(),
        'messages': t.messages
            .map(
              (m) => {
                'id': m.id,
                'senderId': m.senderId,
                'text': m.text,
                'type': m.type.name,
                'at': m.at.toIso8601String(),
              },
            )
            .toList(),
      };

  ApiException _notFound(String what) => ApiException(
        code: 'NOT_FOUND',
        message: what,
        statusCode: 404,
      );

  // -- ApiClient interface -------------------------------------------------------

  @override
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
  }) =>
      _handle('GET', path, query: query, auth: auth);

  @override
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
  }) =>
      _handle('POST', path, body: body, query: query, auth: auth);

  @override
  Future<dynamic> patch(String path, {Object? body, bool auth = true}) =>
      _handle('PATCH', path, body: body, auth: auth);

  @override
  Future<dynamic> put(String path, {Object? body, bool auth = true}) =>
      _handle('PUT', path, body: body, auth: auth);

  @override
  Future<dynamic> delete(String path, {Object? body, bool auth = true}) =>
      _handle('DELETE', path, body: body, auth: auth);
}

/// Order → plain JSON (used by both repos & manager/admin endpoints).
extension OrderJson on Order {
  Map<String, dynamic> toJsonSafe() => {
        'id': id,
        'number': number,
        'storeId': storeId,
        'storeName': storeName,
        'items': items
            .map(
              (i) => {
                'productId': i.productId,
                'name': i.name,
                'quantity': i.quantity,
                'priceTiyn': i.priceTiyn,
              },
            )
            .toList(),
        'status': status.name,
        'paymentStatus': paymentStatus.name,
        'delivery': {
          'address': delivery.address,
          'lat': delivery.point.lat,
          'lng': delivery.point.lng,
          'comment': delivery.comment,
          'capturedAt': delivery.capturedAt.toIso8601String(),
        },
        'subtotalTiyn': subtotalTiyn,
        'discountTiyn': discountTiyn,
        'deliveryTiyn': deliveryTiyn,
        'totalTiyn': totalTiyn,
        'createdAt': createdAt.toIso8601String(),
        'statusHistory': statusHistory
            .map(
              (h) => {
                'newStatus': h.status.name,
                'actorRole': h.actorRole.name,
                'createdAt': h.at.toIso8601String(),
                'reason': h.reason,
              },
            )
            .toList(),
        'promoCode': promoCode,
        'courierId': courierId,
        'courierName': courierName,
        'courierPhone': courierPhone,
        'courierLocation': courierLocation?.toJson(),
      };
}
