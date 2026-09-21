import '../l10n/app_strings.dart';
import '../maps/map_provider.dart';

// ---------------------------------------------------------------------------
// Enums — mirror backend contract exactly.
// ---------------------------------------------------------------------------

enum UserRole { customer, manager, courier, admin }

enum OrderStatus {
  draft,
  pending,
  accepted,
  preparing,
  readyForPickup,
  courierAssigned,
  pickedUp,
  delivering,
  delivered,
  cancelled,
  rejected,
}

enum PaymentStatus {
  pending,
  initiated,
  awaitingConfirmation,
  paid,
  failed,
  cancelled,
  refunded,
  partiallyRefunded,
}

enum CourierStatus { offline, online, busy, delivering }

enum ChatMessageType { text, image, voice, location, system }

enum StoreKind {
  restaurant,
  supermarket,
  pharmacy,
  electronics,
  clothing,
  other
}

enum TicketStatus { open, inProgress, resolved, closed }

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  // snake_case → camelCase fallback for backend enums.
  final s = (name as String?) ?? '';
  final camel = s.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (m) => m.group(1)!.toUpperCase(),
  );
  for (final v in values) {
    if (v.name == camel) return v;
  }
  return fallback;
}

DateTime _ts(Object? v) =>
    DateTime.tryParse(v as String? ?? '')?.toLocal() ?? DateTime.now();

/// Localized via the active [S.lang] — keys `status.*` / `pay.*`.
String orderStatusLabel(OrderStatus s) => S.t('status.${S.snake(s.name)}');

String paymentStatusLabel(PaymentStatus s) => S.t('pay.${S.snake(s.name)}');

// ---------------------------------------------------------------------------
// Users / auth
// ---------------------------------------------------------------------------

class User {
  const User({
    required this.id,
    required this.phone,
    required this.name,
    this.avatarUrl,
    this.role = UserRole.customer,
    this.blocked = false,
  });

  final String id;
  final String phone;
  final String name;
  final String? avatarUrl;
  final UserRole role;
  final bool blocked;

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        phone: j['phone'] as String? ?? '',
        name: j['name'] as String? ?? '',
        avatarUrl: j['avatarUrl'] as String?,
        role: _enumByName(UserRole.values, j['role'], UserRole.customer),
        blocked: j['blocked'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'name': name,
        'avatarUrl': avatarUrl,
        'role': role.name,
      };

  User copyWith({String? name, String? avatarUrl, UserRole? role}) => User(
        id: id,
        phone: phone,
        name: name ?? this.name,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        role: role ?? this.role,
        blocked: blocked,
      );
}

class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.device,
    required this.createdAt,
    this.current = false,
  });

  final String id;
  final String device;
  final DateTime createdAt;
  final bool current;

  factory SessionInfo.fromJson(Map<String, dynamic> j) => SessionInfo(
        id: j['id'] as String,
        device: j['device'] as String? ?? S.t('common.device'),
        createdAt: _ts(j['createdAt']),
        current: j['current'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// Addresses / geo
// ---------------------------------------------------------------------------

class Address {
  const Address({
    required this.id,
    required this.label,
    required this.address,
    required this.point,
    this.comment,
    this.isDefault = false,
  });

  final String id;
  final String label;
  final String address;
  final GeoPoint point;
  final String? comment;
  final bool isDefault;

  factory Address.fromJson(Map<String, dynamic> j) => Address(
        id: j['id'] as String,
        label: j['label'] as String? ?? S.t('addresses.fallback'),
        address: j['address'] as String? ?? '',
        point: GeoPoint(
          lat: (j['lat'] as num?)?.toDouble() ?? 0,
          lng: (j['lng'] as num?)?.toDouble() ?? 0,
        ),
        comment: j['comment'] as String?,
        isDefault: j['isDefault'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// Catalog
// ---------------------------------------------------------------------------

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.kind,
    this.parentId,
  });

  final String id;
  final String name;
  final StoreKind kind;
  final String? parentId;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: _enumByName(StoreKind.values, j['kind'], StoreKind.other),
        parentId: j['parentId'] as String?,
      );
}

class Store {
  const Store({
    required this.id,
    required this.name,
    required this.kind,
    this.description = '',
    this.logoUrl,
    this.bannerUrl,
    this.blurHash,
    this.address = '',
    this.point,
    this.rating = 0,
    this.etaMinutes = 30,
    this.deliveryFeeTiyn = 0,
    this.minOrderTiyn = 0,
    this.isOpen = true,
    this.workingHours = '09:00–22:00',
  });

  final String id;
  final String name;
  final StoreKind kind;
  final String description;
  final String? logoUrl;
  final String? bannerUrl;
  final String? blurHash;
  final String address;
  final GeoPoint? point;
  final double rating;
  final int etaMinutes;
  final int deliveryFeeTiyn;
  final int minOrderTiyn;
  final bool isOpen;
  final String workingHours;

  factory Store.fromJson(Map<String, dynamic> j) => Store(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: _enumByName(StoreKind.values, j['kind'], StoreKind.restaurant),
        description: j['description'] as String? ?? '',
        logoUrl: j['logoUrl'] as String?,
        bannerUrl: j['bannerUrl'] as String?,
        blurHash: j['blurHash'] as String?,
        address: j['address'] as String? ?? '',
        point: j['lat'] != null
            ? GeoPoint(
                lat: (j['lat'] as num).toDouble(),
                lng: (j['lng'] as num).toDouble(),
              )
            : null,
        rating: (j['rating'] as num?)?.toDouble() ?? 0,
        etaMinutes: (j['etaMinutes'] as num?)?.toInt() ?? 30,
        deliveryFeeTiyn: (j['deliveryFeeTiyn'] as num?)?.toInt() ?? 0,
        minOrderTiyn: (j['minOrderTiyn'] as num?)?.toInt() ?? 0,
        isOpen: j['isOpen'] as bool? ?? true,
        workingHours: j['workingHours'] as String? ?? '09:00–22:00',
      );
}

class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.name,
    required this.priceTiyn,
  });

  final String id;
  final String name;
  final int priceTiyn;

  factory ProductVariant.fromJson(Map<String, dynamic> j) => ProductVariant(
        id: j['id'] as String,
        name: j['name'] as String,
        priceTiyn: (j['priceTiyn'] as num).toInt(),
      );
}

class Product {
  const Product({
    required this.id,
    required this.storeId,
    required this.name,
    this.description = '',
    this.imageUrl,
    this.blurHash,
    required this.priceTiyn,
    this.oldPriceTiyn,
    this.bonusPercent = 0,
    this.sku = '',
    this.slug = '',
    this.article = '',
    this.gtin,
    this.internalBarcode = '',
    this.qrIdentifier = '',
    this.categoryId,
    this.subcategoryId,
    this.brandId,
    this.unit,
    this.active = true,
    this.available = true,
    this.stock = 0,
    this.variants = const [],
    this.characteristics = const {},
  });

  final String id;
  final String storeId;
  final String name;
  final String description;
  final String? imageUrl;
  final String? blurHash;
  final int priceTiyn;
  final int? oldPriceTiyn;
  final int bonusPercent;
  final String sku;
  final String slug;
  final String article;
  final String? gtin;
  final String internalBarcode;
  final String qrIdentifier;
  final String? categoryId;
  final String? subcategoryId;
  final String? brandId;
  final String? unit;
  final bool active;
  final bool available;
  final int stock;
  final List<ProductVariant> variants;
  final Map<String, String> characteristics;

  int get discountPercent => oldPriceTiyn != null && oldPriceTiyn! > priceTiyn
      ? (((oldPriceTiyn! - priceTiyn) / oldPriceTiyn!) * 100).round()
      : 0;

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        storeId: j['storeId'] as String? ?? '',
        name: j['name'] as String,
        description: j['description'] as String? ?? '',
        imageUrl: j['imageUrl'] as String?,
        blurHash: j['blurHash'] as String?,
        priceTiyn: (j['priceTiyn'] as num).toInt(),
        oldPriceTiyn: (j['oldPriceTiyn'] as num?)?.toInt(),
        bonusPercent: (j['bonusPercent'] as num?)?.toInt() ?? 0,
        sku: j['sku'] as String? ?? '',
        slug: j['slug'] as String? ?? '',
        article: j['article'] as String? ?? '',
        gtin: j['gtin'] as String?,
        internalBarcode: j['internalBarcode'] as String? ?? '',
        qrIdentifier: j['qrIdentifier'] as String? ?? '',
        categoryId: j['categoryId'] as String?,
        subcategoryId: j['subcategoryId'] as String?,
        brandId: j['brandId'] as String?,
        unit: j['unit'] as String?,
        active: j['active'] as bool? ?? true,
        available: j['available'] as bool? ?? true,
        stock: (j['stock'] as num?)?.toInt() ?? 0,
        variants: ((j['variants'] as List?) ?? const [])
            .map((v) => ProductVariant.fromJson(v as Map<String, dynamic>))
            .toList(),
        characteristics: ((j['characteristics'] as Map?) ?? const {}).map(
          (k, v) => MapEntry('$k', '$v'),
        ),
      );
}

// ---------------------------------------------------------------------------
// Cart
// ---------------------------------------------------------------------------

class CartItem {
  const CartItem({
    required this.id,
    required this.product,
    required this.quantity,
    this.variantId,
  });

  final String id;
  final Product product;
  final int quantity;
  final String? variantId;

  int get priceTiyn {
    if (variantId != null) {
      for (final v in product.variants) {
        if (v.id == variantId) return v.priceTiyn;
      }
    }
    return product.priceTiyn;
  }

  int get totalTiyn => priceTiyn * quantity;

  CartItem copyWith({int? quantity}) => CartItem(
        id: id,
        product: product,
        quantity: quantity ?? this.quantity,
        variantId: variantId,
      );
}

class Cart {
  const Cart({
    required this.storeId,
    required this.storeName,
    required this.items,
    required this.subtotalTiyn,
    required this.deliveryTiyn,
    required this.discountTiyn,
    required this.totalTiyn,
    this.promoCode,
  });

  final String storeId;
  final String storeName;
  final List<CartItem> items;
  final int subtotalTiyn;
  final int deliveryTiyn;
  final int discountTiyn;
  final int totalTiyn;
  final String? promoCode;

  int get itemCount => items.fold(0, (s, i) => s + i.quantity);
  bool get isEmpty => items.isEmpty;

  factory Cart.empty() => const Cart(
        storeId: '',
        storeName: '',
        items: [],
        subtotalTiyn: 0,
        deliveryTiyn: 0,
        discountTiyn: 0,
        totalTiyn: 0,
      );
}

// ---------------------------------------------------------------------------
// Orders
// ---------------------------------------------------------------------------

class OrderItem {
  const OrderItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.priceTiyn,
  });

  final String productId;
  final String name;
  final int quantity;
  final int priceTiyn;

  int get totalTiyn => priceTiyn * quantity;

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        productId: j['productId'] as String? ?? '',
        name: j['name'] as String? ?? '',
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        priceTiyn: (j['priceTiyn'] as num?)?.toInt() ?? 0,
      );
}

class OrderStatusEntry {
  const OrderStatusEntry({
    required this.status,
    required this.actorRole,
    required this.at,
    this.reason,
  });

  final OrderStatus status;
  final UserRole actorRole;
  final DateTime at;
  final String? reason;

  factory OrderStatusEntry.fromJson(Map<String, dynamic> j) => OrderStatusEntry(
        status: _enumByName(
          OrderStatus.values,
          j['newStatus'] ?? j['status'],
          OrderStatus.pending,
        ),
        actorRole:
            _enumByName(UserRole.values, j['actorRole'], UserRole.customer),
        at: _ts(j['at'] ?? j['createdAt']),
        reason: j['reason'] as String?,
      );
}

/// Immutable snapshot captured at checkout — later address edits
/// must not mutate it.
class DeliverySnapshot {
  const DeliverySnapshot({
    required this.address,
    required this.point,
    this.comment,
    required this.capturedAt,
  });

  final String address;
  final GeoPoint point;
  final String? comment;
  final DateTime capturedAt;

  factory DeliverySnapshot.fromJson(Map<String, dynamic> j) => DeliverySnapshot(
        address: j['address'] as String? ?? '',
        point: GeoPoint(
          lat: (j['lat'] as num?)?.toDouble() ?? 0,
          lng: (j['lng'] as num?)?.toDouble() ?? 0,
        ),
        comment: j['comment'] as String?,
        capturedAt: _ts(j['capturedAt']),
      );
}

class Order {
  const Order({
    required this.id,
    required this.number,
    required this.storeId,
    required this.storeName,
    required this.items,
    required this.status,
    required this.paymentStatus,
    required this.delivery,
    required this.subtotalTiyn,
    required this.discountTiyn,
    required this.deliveryTiyn,
    required this.totalTiyn,
    required this.createdAt,
    this.statusHistory = const [],
    this.promoCode,
    this.courierId,
    this.courierName,
    this.courierPhone,
    this.courierLocation,
  });

  final String id;
  final String number;
  final String storeId;
  final String storeName;
  final List<OrderItem> items;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final DeliverySnapshot delivery;
  final int subtotalTiyn;
  final int discountTiyn;
  final int deliveryTiyn;
  final int totalTiyn;
  final DateTime createdAt;
  final List<OrderStatusEntry> statusHistory;
  final String? promoCode;
  final String? courierId;
  final String? courierName;
  final String? courierPhone;
  final GeoPoint? courierLocation;

  bool get isActive => !{
        OrderStatus.delivered,
        OrderStatus.cancelled,
        OrderStatus.rejected,
      }.contains(status);

  bool get canCancel => {
        OrderStatus.pending,
        OrderStatus.accepted,
      }.contains(status);

  Order copyWith({
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    GeoPoint? courierLocation,
    String? courierName,
    String? courierId,
    String? courierPhone,
    List<OrderStatusEntry>? statusHistory,
  }) =>
      Order(
        id: id,
        number: number,
        storeId: storeId,
        storeName: storeName,
        items: items,
        status: status ?? this.status,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        delivery: delivery,
        subtotalTiyn: subtotalTiyn,
        discountTiyn: discountTiyn,
        deliveryTiyn: deliveryTiyn,
        totalTiyn: totalTiyn,
        createdAt: createdAt,
        statusHistory: statusHistory ?? this.statusHistory,
        promoCode: promoCode,
        courierId: courierId ?? this.courierId,
        courierName: courierName ?? this.courierName,
        courierPhone: courierPhone ?? this.courierPhone,
        courierLocation: courierLocation ?? this.courierLocation,
      );

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: j['id'] as String,
        number: j['number'] as String? ?? j['id'] as String,
        storeId: j['storeId'] as String? ?? '',
        storeName: j['storeName'] as String? ?? '',
        items: ((j['items'] as List?) ?? const [])
            .map((i) => OrderItem.fromJson(i as Map<String, dynamic>))
            .toList(),
        status: _enumByName(
          OrderStatus.values,
          j['status'],
          OrderStatus.pending,
        ),
        paymentStatus: _enumByName(
          PaymentStatus.values,
          j['paymentStatus'],
          PaymentStatus.pending,
        ),
        delivery: DeliverySnapshot.fromJson(
          (j['delivery'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        subtotalTiyn: (j['subtotalTiyn'] as num?)?.toInt() ?? 0,
        discountTiyn: (j['discountTiyn'] as num?)?.toInt() ?? 0,
        deliveryTiyn: (j['deliveryTiyn'] as num?)?.toInt() ?? 0,
        totalTiyn: (j['totalTiyn'] as num?)?.toInt() ?? 0,
        createdAt: _ts(j['createdAt']),
        statusHistory: ((j['statusHistory'] as List?) ?? const [])
            .map(
              (h) => OrderStatusEntry.fromJson(h as Map<String, dynamic>),
            )
            .toList(),
        promoCode: j['promoCode'] as String?,
        courierId: j['courierId'] as String?,
        courierName: j['courierName'] as String?,
        courierPhone: j['courierPhone'] as String?,
        courierLocation: j['courierLocation'] != null
            ? GeoPoint.fromJson(
                (j['courierLocation'] as Map).cast<String, dynamic>(),
              )
            : null,
      );
}

// ---------------------------------------------------------------------------
// Chat / calls
// ---------------------------------------------------------------------------

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.type,
    required this.at,
    this.text,
    this.mediaUrl,
    this.point,
    this.read = false,
    this.sending = false,
    this.failed = false,
  });

  final String id;
  final String roomId;
  final String senderId;
  final ChatMessageType type;
  final DateTime at;
  final String? text;
  final String? mediaUrl;
  final GeoPoint? point;
  final bool read;
  final bool sending;
  final bool failed;

  ChatMessage copyWith({bool? read, bool? sending, bool? failed}) =>
      ChatMessage(
        id: id,
        roomId: roomId,
        senderId: senderId,
        type: type,
        at: at,
        text: text,
        mediaUrl: mediaUrl,
        point: point,
        read: read ?? this.read,
        sending: sending ?? this.sending,
        failed: failed ?? this.failed,
      );

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        roomId: j['roomId'] as String? ?? '',
        senderId: j['senderId'] as String? ?? '',
        type: _enumByName(
          ChatMessageType.values,
          j['type'],
          ChatMessageType.text,
        ),
        at: _ts(j['at'] ?? j['createdAt']),
        text: j['text'] as String?,
        mediaUrl: j['mediaUrl'] as String?,
        point: j['lat'] != null
            ? GeoPoint(
                lat: (j['lat'] as num).toDouble(),
                lng: (j['lng'] as num).toDouble(),
              )
            : null,
        read: j['read'] as bool? ?? false,
      );
}

class ChatRoom {
  ChatRoom({
    required this.id,
    this.orderId,
    String? title,
    this.peerName,
    this.messages = const [],
    this.unread = 0,
    this.peerTyping = false,
  }) : title = title ?? '';

  final String id;
  final String? orderId;
  final String title;
  final String? peerName;
  final List<ChatMessage> messages;
  final int unread;
  final bool peerTyping;

  ChatRoom copyWith({
    List<ChatMessage>? messages,
    int? unread,
    bool? peerTyping,
    String? peerName,
  }) =>
      ChatRoom(
        id: id,
        orderId: orderId,
        title: title,
        peerName: peerName ?? this.peerName,
        messages: messages ?? this.messages,
        unread: unread ?? this.unread,
        peerTyping: peerTyping ?? this.peerTyping,
      );
}

// ---------------------------------------------------------------------------
// Notifications / support / promos
// ---------------------------------------------------------------------------

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.at,
    this.read = false,
    this.orderId,
  });

  final String id;
  final String title;
  final String body;
  final String kind;
  final DateTime at;
  final bool read;
  final String? orderId;
}

class Promotion {
  const Promotion({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.blurHash,
    this.storeId,
    this.code,
    this.discountPercent,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? blurHash;
  final String? storeId;
  final String? code;
  final int? discountPercent;
}

class FaqItem {
  const FaqItem({required this.question, required this.answer});
  final String question;
  final String answer;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.status,
    required this.createdAt,
    this.messages = const [],
  });

  final String id;
  final String subject;
  final TicketStatus status;
  final DateTime createdAt;
  final List<ChatMessage> messages;
}

// ---------------------------------------------------------------------------
// Courier / manager / admin
// ---------------------------------------------------------------------------

class CourierOffer {
  const CourierOffer({
    required this.id,
    required this.orderId,
    required this.orderNumber,
    required this.storeName,
    required this.pickupAddress,
    required this.pickup,
    required this.dropoffAddress,
    required this.dropoff,
    required this.feeTiyn,
    required this.distanceKm,
    required this.expiresAt,
  });

  final String id;
  final String orderId;
  final String orderNumber;
  final String storeName;
  final String pickupAddress;
  final GeoPoint pickup;
  final String dropoffAddress;
  final GeoPoint dropoff;
  final int feeTiyn;
  final double distanceKm;
  final DateTime expiresAt;
}

class CourierInfo {
  const CourierInfo({
    required this.id,
    required this.name,
    required this.status,
    this.location,
    this.activeOrders = 0,
  });

  final String id;
  final String name;
  final CourierStatus status;
  final GeoPoint? location;
  final int activeOrders;
}

class ManagerDashboard {
  const ManagerDashboard({
    required this.newOrders,
    required this.preparing,
    required this.ready,
    required this.deliveredToday,
    required this.cancelledToday,
    required this.salesTodayTiyn,
  });

  final int newOrders;
  final int preparing;
  final int ready;
  final int deliveredToday;
  final int cancelledToday;
  final int salesTodayTiyn;
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.actor,
    required this.role,
    required this.action,
    required this.resource,
    required this.at,
    this.result = 'ok',
  });

  final String id;
  final String actor;
  final UserRole role;
  final String action;
  final String resource;
  final DateTime at;
  final String result;
}
