import '../maps/map_provider.dart';
import '../models/models.dart';

/// Seed data for standalone (mock) mode — realistic Kazakhstan
/// catalog: Shymkent restaurants, supermarket, pharmacy, tech.
abstract final class MockData {
  static const shymkent = GeoPoint(lat: 42.3417, lng: 69.5901);

  static final categories = <Category>[
    const Category(id: 'cat-food', name: 'Рестораны', kind: StoreKind.restaurant),
    const Category(id: 'cat-grocery', name: 'Продукты', kind: StoreKind.supermarket),
    const Category(id: 'cat-pharma', name: 'Аптеки', kind: StoreKind.pharmacy),
    const Category(id: 'cat-tech', name: 'Электроника', kind: StoreKind.electronics),
    const Category(id: 'cat-clothes', name: 'Одежда', kind: StoreKind.clothing),
    const Category(id: 'cat-other', name: 'Другое', kind: StoreKind.other),
  ];

  static final stores = <Store>[
    const Store(
      id: 'st-handam',
      name: 'Хан-Дәм',
      kind: StoreKind.restaurant,
      description: 'Казахская и узбекская кухня: плов, лагман, манты.',
      address: 'Шымкент, пр. Тауке хана 26',
      point: GeoPoint(lat: 42.3564, lng: 69.5945),
      rating: 4.8,
      etaMinutes: 35,
      deliveryFeeTiyn: 49900,
      minOrderTiyn: 150000,
      workingHours: '10:00–23:00',
    ),
    const Store(
      id: 'st-bao',
      name: 'Bao House',
      kind: StoreKind.restaurant,
      description: 'Азиатский стритфуд: бао, рамен, вок.',
      address: 'Шымкент, ул. Байдибек би 20',
      point: GeoPoint(lat: 42.3300, lng: 69.5870),
      rating: 4.6,
      etaMinutes: 25,
      deliveryFeeTiyn: 0,
      minOrderTiyn: 100000,
      workingHours: '11:00–22:30',
    ),
    const Store(
      id: 'st-navat',
      name: 'Navat',
      kind: StoreKind.restaurant,
      description: 'Кыргызская кухня: бешбармак, шашлык, куурдак.',
      address: 'Шымкент, пр. Республики 15',
      point: GeoPoint(lat: 42.3480, lng: 69.5730),
      rating: 4.7,
      etaMinutes: 40,
      deliveryFeeTiyn: 59900,
      minOrderTiyn: 200000,
      workingHours: '10:00–00:00',
    ),
    const Store(
      id: 'st-grocery',
      name: 'Magnum Express',
      kind: StoreKind.supermarket,
      description: 'Продукты и товары для дома — доставка от 30 минут.',
      address: 'Шымкент, ул. Кунаева 12',
      point: GeoPoint(lat: 42.3350, lng: 69.6060),
      rating: 4.5,
      etaMinutes: 30,
      deliveryFeeTiyn: 29900,
      minOrderTiyn: 300000,
      workingHours: '08:00–23:00',
    ),
    const Store(
      id: 'st-pharma',
      name: 'Europharma',
      kind: StoreKind.pharmacy,
      description: 'Лекарства, витамины и товары для здоровья.',
      address: 'Шымкент, пр. Аль-Фараби 9',
      point: GeoPoint(lat: 42.3440, lng: 69.5780),
      rating: 4.9,
      etaMinutes: 20,
      deliveryFeeTiyn: 0,
      minOrderTiyn: 50000,
      workingHours: '24/7',
    ),
    const Store(
      id: 'st-tech',
      name: 'Sulpak',
      kind: StoreKind.electronics,
      description: 'Электроника и аксессуары с доставкой по городу.',
      address: 'Шымкент, ТРЦ «Shymkent Plaza»',
      point: GeoPoint(lat: 42.3180, lng: 69.6110),
      rating: 4.4,
      etaMinutes: 55,
      deliveryFeeTiyn: 99900,
      minOrderTiyn: 0,
      workingHours: '10:00–22:00',
    ),
  ];

  static Product _p(
    String id,
    String storeId,
    String name,
    int tiyn, {
    String desc = '',
    int? old,
    String? unit,
    int stock = 20,
    String? cat,
    List<ProductVariant> variants = const [],
    Map<String, String> chars = const {},
  }) =>
      Product(
        id: id,
        storeId: storeId,
        name: name,
        description: desc,
        priceTiyn: tiyn,
        oldPriceTiyn: old,
        unit: unit,
        stock: stock,
        categoryId: cat,
        variants: variants,
        characteristics: chars,
      );

  static final products = <Product>[
    _p('p-plov', 'st-handam', 'Плов по-фергански', 249000,
        desc: 'Баранина, жёлтая морковь, зира, казан 800 г.',
        old: 299000,
        chars: {'Вес': '800 г', 'Калорийность': '720 ккал'},),
    _p('p-lagman', 'st-handam', 'Лагман домашний', 199000,
        desc: 'Вытяжная лапша, говядина, овощи.',
        chars: {'Вес': '650 г'},),
    _p('p-manty', 'st-handam', 'Манты с бараниной (8 шт)', 189000,
        desc: 'Тонкое тесто, сочная начинка, соус на выбор.',
        variants: const [
          ProductVariant(id: 'v-manty-4', name: '4 шт', priceTiyn: 99000),
          ProductVariant(id: 'v-manty-8', name: '8 шт', priceTiyn: 189000),
          ProductVariant(id: 'v-manty-12', name: '12 шт', priceTiyn: 269000),
        ],),
    _p('p-samsa', 'st-handam', 'Самса с говядиной', 69000,
        desc: 'Из тандыра, слоёное тесто.', stock: 40,),
    _p('p-shashlik', 'st-handam', 'Шашлык из баранины', 259000,
        desc: 'Мякоть мякиша, лаваш, маринованный лук.', stock: 12,),
    _p('p-bao-chicken', 'st-bao', 'Бао с курицей терияки', 149000,
        desc: 'Паровая булочка, курица, огурцы, соус терияки.',),
    _p('p-ramen', 'st-bao', 'Рамен с говядиной', 219000,
        desc: 'Наваристый бульон, яйцо аджитама, нори.',
        old: 259000,),
    _p('p-wok', 'st-bao', 'Вок удон с овощами', 169000,
        desc: 'Удон, болгарский перец, брокколи, кунжут.',),
    _p('p-bao-tom', 'st-bao', 'Том-ям с креветками', 239000,
        desc: 'Кокосовое молоко, лемонграсс, креветки.', stock: 8,),
    _p('p-besh', 'st-navat', 'Бешбармак классический', 299000,
        desc: 'Конина, сочпы, лук, бульон.',),
    _p('p-kuurdak', 'st-navat', 'Куурдак из говядины', 239000,
        desc: 'Жареное мясо с картофелем и луком.',),
    _p('p-chuchvara', 'st-navat', 'Чучвара в бульоне', 179000,
        desc: 'Мини-пельмени, зелень, сметана.', stock: 15,),
    _p('p-milk', 'st-grocery', 'Молоко «Родина» 3,2% 900 мл', 64900,
        unit: 'шт', stock: 100,),
    _p('p-bread', 'st-grocery', 'Хлеб «Дар нан» тандырный', 34900,
        unit: 'шт', stock: 60,),
    _p('p-eggs', 'st-grocery', 'Яйца С1 (10 шт)', 89900,
        unit: 'уп', stock: 80,),
    _p('p-apples', 'st-grocery', 'Яблоки апорт, 1 кг', 79900,
        unit: 'кг', stock: 50,),
    _p('p-bananas', 'st-grocery', 'Бананы, 1 кг', 69900,
        unit: 'кг', stock: 70,),
    _p('p-cheese', 'st-grocery', 'Сыр «Ирбитский» 45% 400 г', 279000,
        unit: 'шт', stock: 25, old: 329000,),
    _p('p-water', 'st-grocery', 'Вода Asu 1,5 л', 29900,
        unit: 'шт', stock: 200,),
    _p('p-vitc', 'st-pharma', 'Витамин C 1000 мг (20 табл.)', 189000,
        desc: 'Шипучие таблетки со вкусом апельсина.',),
    _p('p-parac', 'st-pharma', 'Парацетамол 500 мг (10 табл.)', 34900,
        desc: 'Жаропонижающее и обезболивающее.',),
    _p('p-mask', 'st-pharma', 'Маски медицинские (10 шт)', 59900),
    _p('p-therm', 'st-pharma', 'Термометр электронный', 399000,
        old: 499000,),
    _p('p-cable', 'st-tech', 'Кабель USB-C 1 м, 60 Вт', 499000,
        desc: 'Быстрая зарядка, нейлоновая оплётка.',),
    _p('p-charger', 'st-tech', 'Зарядное устройство 25 Вт', 899000,
        desc: 'USB-C, поддержка PD.',),
    _p('p-earbuds', 'st-tech', 'Наушники TWS беспроводные', 1499000,
        old: 1999000,
        desc: 'Bluetooth 5.3, до 24 часов с кейсом.',),
    _p('p-powerbank', 'st-tech', 'Power Bank 10 000 мАч', 999000,
        desc: 'Два порта USB-A + USB-C.',),
  ];

  static final promotions = <Promotion>[
    const Promotion(
      id: 'promo-welcome',
      title: 'KORA700 — скидка 700 ₸',
      subtitle: 'На первый заказ от 2 000 ₸',
      code: 'KORA700',
      discountPercent: null,
    ),
    const Promotion(
      id: 'promo-bao',
      title: '−20% в Bao House',
      subtitle: 'На всё меню до конца недели',
      storeId: 'st-bao',
      discountPercent: 20,
    ),
    const Promotion(
      id: 'promo-free',
      title: 'Бесплатная доставка',
      subtitle: 'В Europharma и Bao House',
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
