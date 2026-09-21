import '../maps/map_provider.dart';
import '../models/models.dart';

/// Seed data for standalone (mock) mode — KORA as a SINGLE store.
/// The catalog ships EMPTY on purpose: the assortment is filled by the
/// manager/admin via the product editor (Manager Mode → Товары), which
/// exercises the same code path as the production backend.
abstract final class MockData {
  static const shymkent = GeoPoint(lat: 42.3417, lng: 69.5901);

  /// The one and only venue behind the app.
  static const koraStoreId = 'kora-market';

  static String _u(String id) =>
      'https://images.unsplash.com/$id?auto=format&fit=crop&w=1920&q=90';

  /// Catalog sections (Wolt-style: venue page groups products by these).
  static final categories = <Category>[
    const Category(
      id: 'cat-food',
      name: 'Готовая еда',
      kind: StoreKind.restaurant,
    ),
    const Category(
      id: 'cat-grocery',
      name: 'Продукты',
      kind: StoreKind.supermarket,
    ),
    const Category(
      id: 'cat-drinks',
      name: 'Напитки',
      kind: StoreKind.other,
    ),
    const Category(
      id: 'cat-pharma',
      name: 'Аптека',
      kind: StoreKind.pharmacy,
    ),
    const Category(
      id: 'cat-tech',
      name: 'Электроника',
      kind: StoreKind.electronics,
    ),
    const Category(
      id: 'cat-clothes',
      name: 'Одежда',
      kind: StoreKind.clothing,
    ),
    const Category(
      id: 'cat-home',
      name: 'Дом и быт',
      kind: StoreKind.other,
    ),
  ];

  static final stores = <Store>[
    Store(
      id: koraStoreId,
      name: 'KORA Market',
      kind: StoreKind.supermarket,
      description: 'Единый магазин: еда, продукты, техника и товары для дома.',
      address: 'Шымкент, пр. Тауке хана 26',
      point: const GeoPoint(lat: 42.3564, lng: 69.5945),
      rating: 4.8,
      etaMinutes: 30,
      deliveryFeeTiyn: 49900,
      minOrderTiyn: 150000,
      workingHours: '09:00–23:00',
      bannerUrl: _u('photo-1555396273-367ea4eb4db5'),
      logoUrl: _u('photo-1607083206869-4c7672e72a8a'),
    ),
  ];

  /// Empty by design — filled at runtime via /admin/products.
  static final products = <Product>[];

  static final promotions = <Promotion>[
    Promotion(
      id: 'promo-welcome',
      title: 'KORA700 — скидка 700 ₸',
      subtitle: 'На первый заказ от 2 000 ₸',
      code: 'KORA700',
      imageUrl: _u('photo-1607083206869-4c7672e72a8a'),
    ),
    Promotion(
      id: 'promo-free',
      title: 'Бесплатная доставка',
      subtitle: 'На заказы от 5 000 ₸',
      storeId: koraStoreId,
      imageUrl: _u('photo-1504674900247-0877df9cc836'),
    ),
  ];

  static final faq = <FaqItem>[
    const FaqItem(
      question: 'Как оплатить заказ?',
      answer:
          'Оплата проходит через Kaspi на экране оформления. После подтверждения платежа заказ автоматически отправляется магазину.',
    ),
    const FaqItem(
      question: 'Как отменить заказ?',
      answer:
          'Заказ можно отменить в карточке заказа, пока магазин не начал его готовить. Деньги возвращаются на исходный способ оплаты.',
    ),
    const FaqItem(
      question: 'Как отследить курьера?',
      answer:
          'Когда курьер заберёт заказ, откройте заказ — на карте будет видно его местоположение и маршрут в реальном времени.',
    ),
    const FaqItem(
      question: 'Куда обратиться, если заказ не приехал?',
      answer:
          'Создайте обращение в разделе «Поддержка» — мы проверим заказ и вернём средства при подтверждении проблемы.',
    ),
  ];

  static final addresses = <Address>[
    const Address(
      id: 'addr-home',
      label: 'Дом',
      address: 'Шымкент, ул. Желтоксан 45, кв. 12',
      point: GeoPoint(lat: 42.3417, lng: 69.5901),
      comment: 'Домофон 12, 4 этаж',
      isDefault: true,
    ),
    const Address(
      id: 'addr-work',
      label: 'Работа',
      address: 'Шымкент, пр. Республики 8, БЦ «Орда»',
      point: GeoPoint(lat: 42.3500, lng: 69.5800),
    ),
  ];
}
