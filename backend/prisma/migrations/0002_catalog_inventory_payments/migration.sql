-- Production catalog identifiers, inventory ledger, and payment idempotency.
CREATE TYPE "InventoryTxnKind" AS ENUM ('receipt', 'reservation', 'release', 'sale', 'refund', 'adjustment');
CREATE TYPE "PaymentTxnKind" AS ENUM ('create', 'authorize', 'capture', 'fail', 'refund', 'webhook');

CREATE TABLE "Subcategory" (
  "id" TEXT PRIMARY KEY,
  "categoryId" TEXT NOT NULL REFERENCES "Category"("id") ON DELETE CASCADE,
  "name" TEXT NOT NULL,
  "nameKk" TEXT,
  "nameEn" TEXT,
  "slug" TEXT NOT NULL UNIQUE,
  "sortOrder" INT NOT NULL DEFAULT 0,
  "active" BOOLEAN NOT NULL DEFAULT true
);
CREATE INDEX "Subcategory_categoryId_active_sortOrder_idx" ON "Subcategory"("categoryId", "active", "sortOrder");

CREATE TABLE "Brand" (
  "id" TEXT PRIMARY KEY,
  "name" TEXT NOT NULL,
  "slug" TEXT NOT NULL UNIQUE,
  "logoUrl" TEXT,
  "active" BOOLEAN NOT NULL DEFAULT true
);
CREATE INDEX "Brand_active_name_idx" ON "Brand"("active", "name");

ALTER TABLE "Product"
  ADD CONSTRAINT "Product_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "Category"("id"),
  ADD COLUMN "subcategoryId" TEXT REFERENCES "Subcategory"("id"),
  ADD COLUMN "brandId" TEXT REFERENCES "Brand"("id"),
  ADD COLUMN "slug" TEXT,
  ADD COLUMN "sku" TEXT,
  ADD COLUMN "article" TEXT,
  ADD COLUMN "gtin" TEXT,
  ADD COLUMN "internalBarcode" TEXT,
  ADD COLUMN "qrIdentifier" TEXT,
  ADD COLUMN "reservedStock" INT NOT NULL DEFAULT 0,
  ADD COLUMN "active" BOOLEAN NOT NULL DEFAULT true;

UPDATE "Product" SET
  "slug" = lower(regexp_replace("name", '[^a-zA-Z0-9]+', '-', 'g')) || '-' || substr("id", 1, 8),
  "sku" = 'SKU-' || upper(substr(md5("id"), 1, 10)),
  "article" = 'ART-' || upper(substr(md5('article:' || "id"), 1, 10)),
  "internalBarcode" = '20' || substr(('x' || substr(md5('barcode:' || "id"), 1, 8))::bit(32)::bigint::text, 1, 10),
  "qrIdentifier" = 'product:' || "id";
ALTER TABLE "Product"
  ALTER COLUMN "slug" SET NOT NULL,
  ALTER COLUMN "sku" SET NOT NULL,
  ALTER COLUMN "article" SET NOT NULL,
  ALTER COLUMN "internalBarcode" SET NOT NULL,
  ALTER COLUMN "qrIdentifier" SET NOT NULL;
CREATE UNIQUE INDEX "Product_slug_key" ON "Product"("slug");
CREATE UNIQUE INDEX "Product_sku_key" ON "Product"("sku");
CREATE UNIQUE INDEX "Product_article_key" ON "Product"("article");
CREATE UNIQUE INDEX "Product_gtin_key" ON "Product"("gtin") WHERE "gtin" IS NOT NULL;
CREATE UNIQUE INDEX "Product_internalBarcode_key" ON "Product"("internalBarcode");
CREATE UNIQUE INDEX "Product_qrIdentifier_key" ON "Product"("qrIdentifier");
CREATE INDEX "Product_categoryId_subcategoryId_idx" ON "Product"("categoryId", "subcategoryId");
CREATE INDEX "Product_brandId_idx" ON "Product"("brandId");
ALTER TABLE "Product" ADD CONSTRAINT "Product_stock_nonnegative" CHECK ("stock" >= 0);
ALTER TABLE "Product" ADD CONSTRAINT "Product_reserved_valid" CHECK ("reservedStock" >= 0 AND "reservedStock" <= "stock");

CREATE TABLE "ProductImage" (
  "id" TEXT PRIMARY KEY,
  "productId" TEXT NOT NULL REFERENCES "Product"("id") ON DELETE CASCADE,
  "url" TEXT NOT NULL,
  "blurHash" TEXT,
  "sortOrder" INT NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "ProductImage_productId_sortOrder_idx" ON "ProductImage"("productId", "sortOrder");

CREATE TABLE "InventoryTransaction" (
  "id" TEXT PRIMARY KEY,
  "productId" TEXT NOT NULL REFERENCES "Product"("id") ON DELETE RESTRICT,
  "kind" "InventoryTxnKind" NOT NULL,
  "quantity" INT NOT NULL,
  "stockAfter" INT NOT NULL,
  "reservedAfter" INT NOT NULL,
  "orderId" TEXT,
  "actorId" TEXT,
  "note" TEXT,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "InventoryTransaction_productId_createdAt_idx" ON "InventoryTransaction"("productId", "createdAt");
CREATE INDEX "InventoryTransaction_orderId_idx" ON "InventoryTransaction"("orderId");

CREATE TABLE "PaymentTransaction" (
  "id" TEXT PRIMARY KEY,
  "paymentId" TEXT NOT NULL REFERENCES "Payment"("id") ON DELETE CASCADE,
  "kind" "PaymentTxnKind" NOT NULL,
  "idempotencyKey" TEXT NOT NULL UNIQUE,
  "externalId" TEXT,
  "amountTiyn" INT NOT NULL,
  "status" "PaymentStatus" NOT NULL,
  "providerPayload" JSONB,
  "createdAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX "PaymentTransaction_paymentId_createdAt_idx" ON "PaymentTransaction"("paymentId", "createdAt");
CREATE INDEX "PaymentTransaction_externalId_idx" ON "PaymentTransaction"("externalId");
