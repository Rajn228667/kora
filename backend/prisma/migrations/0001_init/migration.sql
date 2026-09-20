-- KORA 0001_init — full entity set.
-- Money is integer tiyn (1 ₸ = 100 tiyn). Timestamps are timestamptz.

CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid()

-- ─── Enums ──────────────────────────────────────────────────────────────

CREATE TYPE "UserRole" AS ENUM ('customer', 'manager', 'courier', 'admin');
CREATE TYPE "StoreKind" AS ENUM ('restaurant', 'supermarket', 'pharmacy', 'electronics', 'clothing', 'other');
CREATE TYPE "OrderStatus" AS ENUM ('draft', 'pending', 'accepted', 'rejected', 'preparing', 'ready_for_pickup', 'courier_assigned', 'picked_up', 'delivering', 'delivered', 'cancelled');
CREATE TYPE "PaymentStatus" AS ENUM ('initiated', 'pending', 'awaiting_confirmation', 'paid', 'failed', 'cancelled', 'refunded', 'partially_refunded');
CREATE TYPE "PaymentProvider" AS ENUM ('mock', 'kaspi');
CREATE TYPE "CourierStatus" AS ENUM ('offline', 'online', 'busy');
CREATE TYPE "OfferStatus" AS ENUM ('pending', 'accepted', 'rejected', 'expired');
CREATE TYPE "TicketStatus" AS ENUM ('open', 'in_progress', 'resolved', 'closed');
CREATE TYPE "NotificationKind" AS ENUM ('order_status', 'courier_assigned', 'promo', 'price_drop', 'chat', 'delivered');
CREATE TYPE "WalletTxnKind" AS ENUM ('cashback', 'promo_credit', 'referral_bonus', 'order_spend', 'refund', 'adjustment');
CREATE TYPE "PromotionKind" AS ENUM ('percent', 'fixed', 'bogo', 'first_order', 'free_delivery');

-- ─── Auth & users ───────────────────────────────────────────────────────

CREATE TABLE "User" (
  "id"            TEXT PRIMARY KEY,
  "phone"         TEXT NOT NULL UNIQUE,
  "email"         TEXT UNIQUE,
  "name"          TEXT NOT NULL DEFAULT '',
  "avatarUrl"     TEXT,
  "role"          "UserRole" NOT NULL DEFAULT 'customer',
  "passwordHash"  TEXT,
  "referralCode"  TEXT NOT NULL UNIQUE,
  "referredById"  TEXT REFERENCES "User"("id"),
  "deletedAt"     TIMESTAMPTZ,
  "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "User_role_idx" ON "User"("role");
CREATE INDEX "User_referredById_idx" ON "User"("referredById");

CREATE TABLE "Session" (
  "id"               TEXT PRIMARY KEY,
  "userId"           TEXT NOT NULL REFERENCES "User"("id") ON DELETE CASCADE,
  "refreshTokenHash" TEXT NOT NULL UNIQUE,
  "device"           TEXT NOT NULL DEFAULT '',
  "ip"               TEXT,
  "biometricEnabled" BOOLEAN NOT NULL DEFAULT false,
  "revokedAt"        TIMESTAMPTZ,
  "expiresAt"        TIMESTAMPTZ NOT NULL,
  "createdAt"        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "Session_userId_idx" ON "Session"("userId");

CREATE TABLE "OtpRequest" (
  "id"         TEXT PRIMARY KEY,
  "phone"      TEXT NOT NULL,
  "codeHash"   TEXT NOT NULL,
  "attempts"   INT NOT NULL DEFAULT 0,
  "verifiedAt" TIMESTAMPTZ,
  "expiresAt"  TIMESTAMPTZ NOT NULL,
  "createdAt"  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "OtpRequest_phone_createdAt_idx" ON "OtpRequest"("phone", "createdAt");

CREATE TABLE "Address" (
  "id"        TEXT PRIMARY KEY,
  "userId"    TEXT NOT NULL REFERENCES "User"("id") ON DELETE CASCADE,
  "label"     TEXT NOT NULL,
  "address"   TEXT NOT NULL,
  "lat"       DOUBLE PRECISION NOT NULL,
  "lng"       DOUBLE PRECISION NOT NULL,
  "comment"   TEXT,
  "isDefault" BOOLEAN NOT NULL DEFAULT false,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "Address_userId_idx" ON "Address"("userId");

-- ─── Catalog ────────────────────────────────────────────────────────────

CREATE TABLE "Category" (
  "id"        TEXT PRIMARY KEY,
  "name"      TEXT NOT NULL,
  "nameKk"    TEXT,
  "nameEn"    TEXT,
  "kind"      "StoreKind" NOT NULL,
  "sortOrder" INT NOT NULL DEFAULT 0
);
CREATE INDEX "Category_kind_sortOrder_idx" ON "Category"("kind", "sortOrder");

CREATE TABLE "Store" (
  "id"              TEXT PRIMARY KEY,
  "categoryId"      TEXT REFERENCES "Category"("id"),
  "name"            TEXT NOT NULL,
  "description"     TEXT NOT NULL DEFAULT '',
  "kind"            "StoreKind" NOT NULL,
  "address"         TEXT NOT NULL,
  "lat"             DOUBLE PRECISION NOT NULL,
  "lng"             DOUBLE PRECISION NOT NULL,
  "rating"          DOUBLE PRECISION NOT NULL DEFAULT 0,
  "ratingCount"     INT NOT NULL DEFAULT 0,
  "etaMinutes"      INT NOT NULL DEFAULT 30,
  "deliveryFeeTiyn" INT NOT NULL DEFAULT 0,
  "minOrderTiyn"    INT NOT NULL DEFAULT 0,
  "logoUrl"         TEXT,
  "bannerUrl"       TEXT,
  "blurHash"        TEXT,
  "active"          BOOLEAN NOT NULL DEFAULT true,
  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "Store_kind_active_idx" ON "Store"("kind", "active");
CREATE INDEX "Store_lat_lng_idx" ON "Store"("lat", "lng");

CREATE TABLE "StoreSchedule" (
  "id"       TEXT PRIMARY KEY,
  "storeId"  TEXT NOT NULL REFERENCES "Store"("id") ON DELETE CASCADE,
  "weekday"  INT NOT NULL CHECK ("weekday" BETWEEN 0 AND 6),
  "openMin"  INT,
  "closeMin" INT,
  UNIQUE ("storeId", "weekday")
);

CREATE TABLE "StoreManager" (
  "userId"  TEXT NOT NULL REFERENCES "User"("id") ON DELETE CASCADE,
  "storeId" TEXT NOT NULL REFERENCES "Store"("id") ON DELETE CASCADE,
  PRIMARY KEY ("userId", "storeId")
);

CREATE TABLE "Product" (
  "id"              TEXT PRIMARY KEY,
  "storeId"         TEXT NOT NULL REFERENCES "Store"("id") ON DELETE CASCADE,
  "categoryId"      TEXT,
  "name"            TEXT NOT NULL,
  "nameKk"          TEXT,
  "description"     TEXT NOT NULL DEFAULT '',
  "priceTiyn"       INT NOT NULL,
  "oldPriceTiyn"    INT,
  "unit"            TEXT,
  "stock"           INT NOT NULL DEFAULT 0,
  "available"       BOOLEAN NOT NULL DEFAULT true,
  "imageUrl"        TEXT,
  "blurHash"        TEXT,
  "characteristics" JSONB NOT NULL DEFAULT '{}',
  "searchVector"    TSVECTOR,
  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt"       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "Product_storeId_available_idx" ON "Product"("storeId", "available");
CREATE INDEX "Product_categoryId_idx" ON "Product"("categoryId");
CREATE INDEX "Product_searchVector_idx" ON "Product" USING GIN ("searchVector");

-- Keep the full-text search vector fresh (ru + simple fallback).
CREATE FUNCTION product_search_vector() RETURNS trigger AS $$
BEGIN
  NEW."searchVector" :=
    to_tsvector('russian', coalesce(NEW."name", '') || ' ' ||
                coalesce(NEW."description", ''));
  RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER product_search_vector_trg
  BEFORE INSERT OR UPDATE OF "name", "description" ON "Product"
  FOR EACH ROW EXECUTE FUNCTION product_search_vector();

CREATE TABLE "ProductVariant" (
  "id"        TEXT PRIMARY KEY,
  "productId" TEXT NOT NULL REFERENCES "Product"("id") ON DELETE CASCADE,
  "name"      TEXT NOT NULL,
  "priceTiyn" INT NOT NULL,
  "stock"     INT NOT NULL DEFAULT 0
);
CREATE INDEX "ProductVariant_productId_idx" ON "ProductVariant"("productId");

CREATE TABLE "Favorite" (
  "id"        TEXT PRIMARY KEY,
  "userId"    TEXT NOT NULL REFERENCES "User"("id") ON DELETE CASCADE,
  "productId" TEXT,
  "storeId"   TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (("productId" IS NULL) <> ("storeId" IS NULL))
);
CREATE INDEX "Favorite_userId_idx" ON "Favorite"("userId");
CREATE UNIQUE INDEX "Favorite_user_product_key"
  ON "Favorite"("userId", "productId") WHERE "productId" IS NOT NULL;
CREATE UNIQUE INDEX "Favorite_user_store_key"
  ON "Favorite"("userId", "storeId") WHERE "storeId" IS NOT NULL;

CREATE TABLE "RecentlyViewed" (
  "userId"    TEXT NOT NULL REFERENCES "User"("id") ON DELETE CASCADE,
  "productId" TEXT NOT NULL,
  "viewedAt"  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY ("userId", "productId")
);
CREATE INDEX "RecentlyViewed_userId_viewedAt_idx" ON "RecentlyViewed"("userId", "viewedAt" DESC);

CREATE TABLE "StoreReview" (
  "id"        TEXT PRIMARY KEY,
  "storeId"   TEXT NOT NULL REFERENCES "Store"("id") ON DELETE CASCADE,
  "userId"    TEXT NOT NULL,
  "rating"    INT NOT NULL CHECK ("rating" BETWEEN 1 AND 5),
  "text"      TEXT NOT NULL DEFAULT '',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("storeId", "userId")
);

-- ─── Cart ───────────────────────────────────────────────────────────────

CREATE TABLE "Cart" (
  "id"        TEXT PRIMARY KEY,
  "userId"    TEXT NOT NULL UNIQUE,
  "storeId"   TEXT,
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE "CartItem" (
  "id"        TEXT PRIMARY KEY,
  "cartId"    TEXT NOT NULL REFERENCES "Cart"("id") ON DELETE CASCADE,
  "productId" TEXT NOT NULL REFERENCES "Product"("id"),
  "variantId" TEXT,
  "quantity"  INT NOT NULL DEFAULT 1,
  "priceTiyn" INT NOT NULL,
  UNIQUE ("cartId", "productId", "variantId")
);

-- ─── Promotions ─────────────────────────────────────────────────────────

CREATE TABLE "Promotion" (
  "id"              TEXT PRIMARY KEY,
  "kind"            "PromotionKind" NOT NULL DEFAULT 'percent',
  "title"           TEXT NOT NULL,
  "subtitle"        TEXT,
  "imageUrl"        TEXT,
  "storeId"         TEXT REFERENCES "Store"("id"),
  "productId"       TEXT,
  "discountPercent" INT,
  "discountTiyn"    INT,
  "minOrderTiyn"    INT NOT NULL DEFAULT 0,
  "code"            TEXT,
  "startsAt"        TIMESTAMPTZ,
  "endsAt"          TIMESTAMPTZ,
  "active"          BOOLEAN NOT NULL DEFAULT true,
  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "Promotion_active_storeId_idx" ON "Promotion"("active", "storeId");

CREATE TABLE "PromoCode" (
  "id"           TEXT PRIMARY KEY,
  "code"         TEXT NOT NULL UNIQUE,
  "discountTiyn" INT NOT NULL DEFAULT 0,
  "percent"      INT,
  "minOrderTiyn" INT NOT NULL DEFAULT 0,
  "productId"    TEXT,
  "maxUses"      INT,
  "usedCount"    INT NOT NULL DEFAULT 0,
  "expiresAt"    TIMESTAMPTZ,
  "createdAt"    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─── Orders & payments ──────────────────────────────────────────────────

CREATE TABLE "Order" (
  "id"              TEXT PRIMARY KEY,
  "number"          TEXT NOT NULL UNIQUE,
  "userId"          TEXT NOT NULL REFERENCES "User"("id"),
  "storeId"         TEXT NOT NULL REFERENCES "Store"("id"),
  "courierId"       TEXT,
  "courierName"     TEXT,
  "status"          "OrderStatus" NOT NULL DEFAULT 'pending',
  "deliveryAddress" TEXT NOT NULL,
  "deliveryLat"     DOUBLE PRECISION NOT NULL,
  "deliveryLng"     DOUBLE PRECISION NOT NULL,
  "deliveryComment" TEXT,
  "deliveryAt"      TIMESTAMPTZ,
  "subtotalTiyn"    INT NOT NULL,
  "discountTiyn"    INT NOT NULL DEFAULT 0,
  "deliveryTiyn"    INT NOT NULL DEFAULT 0,
  "totalTiyn"       INT NOT NULL,
  "promoCode"       TEXT,
  "courierLat"      DOUBLE PRECISION,
  "courierLng"      DOUBLE PRECISION,
  "createdAt"       TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt"       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "Order_userId_createdAt_idx" ON "Order"("userId", "createdAt" DESC);
CREATE INDEX "Order_storeId_status_idx" ON "Order"("storeId", "status");
CREATE INDEX "Order_courierId_status_idx" ON "Order"("courierId", "status");

CREATE TABLE "OrderItem" (
  "id"        TEXT PRIMARY KEY,
  "orderId"   TEXT NOT NULL REFERENCES "Order"("id") ON DELETE CASCADE,
  "productId" TEXT REFERENCES "Product"("id"),
  "variantId" TEXT,
  "name"      TEXT NOT NULL,
  "priceTiyn" INT NOT NULL,
  "quantity"  INT NOT NULL
);
CREATE INDEX "OrderItem_orderId_idx" ON "OrderItem"("orderId");

CREATE TABLE "OrderStatusEntry" (
  "id"        TEXT PRIMARY KEY,
  "orderId"   TEXT NOT NULL REFERENCES "Order"("id") ON DELETE CASCADE,
  "status"    "OrderStatus" NOT NULL,
  "actorId"   TEXT REFERENCES "User"("id"),
  "actorRole" "UserRole" NOT NULL,
  "reason"    TEXT,
  "at"        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "OrderStatusEntry_orderId_at_idx" ON "OrderStatusEntry"("orderId", "at");

CREATE TABLE "Payment" (
  "id"            TEXT PRIMARY KEY,
  "orderId"       TEXT NOT NULL REFERENCES "Order"("id"),
  "provider"      "PaymentProvider" NOT NULL DEFAULT 'mock',
  "status"        "PaymentStatus" NOT NULL DEFAULT 'initiated',
  "amountTiyn"    INT NOT NULL,
  "externalId"    TEXT,
  "clientPayload" JSONB,
  "webhookEvents" JSONB NOT NULL DEFAULT '[]',
  "createdAt"     TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt"     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "Payment_orderId_idx" ON "Payment"("orderId");
CREATE INDEX "Payment_externalId_idx" ON "Payment"("externalId");

-- ─── Courier / dispatch ─────────────────────────────────────────────────

CREATE TABLE "CourierProfile" (
  "userId"      TEXT PRIMARY KEY REFERENCES "User"("id") ON DELETE CASCADE,
  "status"      "CourierStatus" NOT NULL DEFAULT 'offline',
  "lastLat"     DOUBLE PRECISION,
  "lastLng"     DOUBLE PRECISION,
  "lastSeenAt"  TIMESTAMPTZ,
  "activeOrder" TEXT
);

CREATE TABLE "CourierOffer" (
  "id"         TEXT PRIMARY KEY,
  "orderId"    TEXT NOT NULL REFERENCES "Order"("id") ON DELETE CASCADE,
  "courierId"  TEXT NOT NULL REFERENCES "CourierProfile"("userId"),
  "status"     "OfferStatus" NOT NULL DEFAULT 'pending',
  "feeTiyn"    INT NOT NULL,
  "distanceKm" DOUBLE PRECISION NOT NULL,
  "expiresAt"  TIMESTAMPTZ NOT NULL,
  "createdAt"  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("orderId", "courierId")
);
CREATE INDEX "CourierOffer_courierId_status_idx" ON "CourierOffer"("courierId", "status");

CREATE TABLE "CourierLocation" (
  "id"        TEXT PRIMARY KEY,
  "courierId" TEXT NOT NULL,
  "orderId"   TEXT,
  "lat"       DOUBLE PRECISION NOT NULL,
  "lng"       DOUBLE PRECISION NOT NULL,
  "at"        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "CourierLocation_courierId_at_idx" ON "CourierLocation"("courierId", "at");
CREATE INDEX "CourierLocation_orderId_idx" ON "CourierLocation"("orderId");

-- ─── Chat, notifications ────────────────────────────────────────────────

CREATE TABLE "ChatRoom" (
  "id"        TEXT PRIMARY KEY,
  "orderId"   TEXT NOT NULL UNIQUE REFERENCES "Order"("id"),
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE "ChatMessage" (
  "id"        TEXT PRIMARY KEY,
  "roomId"    TEXT NOT NULL REFERENCES "ChatRoom"("id") ON DELETE CASCADE,
  "senderId"  TEXT NOT NULL REFERENCES "User"("id"),
  "kind"      TEXT NOT NULL DEFAULT 'text',
  "body"      TEXT NOT NULL DEFAULT '',
  "mediaUrl"  TEXT,
  "readAt"    TIMESTAMPTZ,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "ChatMessage_roomId_createdAt_idx" ON "ChatMessage"("roomId", "createdAt");

CREATE TABLE "Notification" (
  "id"        TEXT PRIMARY KEY,
  "userId"    TEXT NOT NULL REFERENCES "User"("id") ON DELETE CASCADE,
  "kind"      "NotificationKind" NOT NULL,
  "title"     TEXT NOT NULL,
  "body"      TEXT NOT NULL DEFAULT '',
  "orderId"   TEXT,
  "readAt"    TIMESTAMPTZ,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "Notification_userId_readAt_idx" ON "Notification"("userId", "readAt");

-- ─── Wallet & referral ──────────────────────────────────────────────────

CREATE TABLE "WalletAccount" (
  "userId"      TEXT PRIMARY KEY REFERENCES "User"("id") ON DELETE CASCADE,
  "balanceTiyn" INT NOT NULL DEFAULT 0
);

CREATE TABLE "WalletTransaction" (
  "id"         TEXT PRIMARY KEY,
  "accountId"  TEXT NOT NULL REFERENCES "WalletAccount"("userId") ON DELETE CASCADE,
  "kind"       "WalletTxnKind" NOT NULL,
  "amountTiyn" INT NOT NULL,
  "title"      TEXT NOT NULL,
  "orderId"    TEXT,
  "createdAt"  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "WalletTransaction_accountId_createdAt_idx"
  ON "WalletTransaction"("accountId", "createdAt" DESC);

-- ─── Support, media, audit ──────────────────────────────────────────────

CREATE TABLE "SupportTicket" (
  "id"        TEXT PRIMARY KEY,
  "userId"    TEXT NOT NULL REFERENCES "User"("id"),
  "orderId"   TEXT,
  "subject"   TEXT NOT NULL,
  "status"    "TicketStatus" NOT NULL DEFAULT 'open',
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE "TicketMessage" (
  "id"        TEXT PRIMARY KEY,
  "ticketId"  TEXT NOT NULL REFERENCES "SupportTicket"("id") ON DELETE CASCADE,
  "fromStaff" BOOLEAN NOT NULL DEFAULT false,
  "body"      TEXT NOT NULL,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "TicketMessage_ticketId_createdAt_idx" ON "TicketMessage"("ticketId", "createdAt");

CREATE TABLE "MediaAsset" (
  "id"         TEXT PRIMARY KEY,
  "ownerId"    TEXT,
  "kind"       TEXT NOT NULL DEFAULT 'product',
  "storageKey" TEXT NOT NULL UNIQUE,
  "publicUrl"  TEXT,
  "width"      INT,
  "height"     INT,
  "sizeBytes"  INT,
  "createdAt"  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE "AuditLog" (
  "id"        TEXT PRIMARY KEY,
  "actorId"   TEXT REFERENCES "User"("id"),
  "actorRole" "UserRole" NOT NULL,
  "action"    TEXT NOT NULL,
  "resource"  TEXT NOT NULL,
  "details"   JSONB NOT NULL DEFAULT '{}',
  "ip"        TEXT,
  "at"        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "AuditLog_at_idx" ON "AuditLog"("at" DESC);
CREATE INDEX "AuditLog_actorId_idx" ON "AuditLog"("actorId");
