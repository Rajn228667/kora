import { randomInt } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../auth/guard.js';
import type { Config } from '../config.js';
import { prisma } from '../plugins/prisma.js';
import { emitOrderEvent } from '../realtime/gateway.js';

const id = z.string().min(1).max(100);
const idParams = z.object({ id });

export const productSelect = {
  id: true,
  storeId: true,
  categoryId: true,
  subcategoryId: true,
  brandId: true,
  name: true,
  slug: true,
  description: true,
  priceTiyn: true,
  oldPriceTiyn: true,
  bonusPercent: true,
  unit: true,
  sku: true,
  article: true,
  gtin: true,
  internalBarcode: true,
  qrIdentifier: true,
  stock: true,
  reservedStock: true,
  available: true,
  active: true,
  imageUrl: true,
  blurHash: true,
  characteristics: true,
} as const;

export const storeSelect = {
  id: true,
  name: true,
  kind: true,
  description: true,
  logoUrl: true,
  bannerUrl: true,
  blurHash: true,
  address: true,
  lat: true,
  lng: true,
  rating: true,
  etaMinutes: true,
  deliveryFeeTiyn: true,
  minOrderTiyn: true,
  active: true,
  schedule: true,
} as const;

type StoreRow = {
  id: string;
  name: string;
  kind: string;
  description: string;
  logoUrl: string | null;
  bannerUrl: string | null;
  blurHash: string | null;
  address: string;
  lat: number;
  lng: number;
  rating: number;
  etaMinutes: number;
  deliveryFeeTiyn: number;
  minOrderTiyn: number;
  active: boolean;
  schedule: { weekday: number; openMin: number | null; closeMin: number | null }[];
};

function isOpenNow(store: StoreRow): boolean {
  const now = new Date();
  const weekday = (now.getDay() + 6) % 7; // 0=Mon
  const day = store.schedule.find((s) => s.weekday === weekday);
  if (!day || day.openMin == null || day.closeMin == null) return store.active;
  const minutes = now.getHours() * 60 + now.getMinutes();
  return store.active && minutes >= day.openMin && minutes < day.closeMin;
}

export function storeJson(store: StoreRow) {
  const open = dayHours(store);
  return {
    id: store.id,
    name: store.name,
    kind: store.kind,
    description: store.description,
    logoUrl: store.logoUrl,
    bannerUrl: store.bannerUrl,
    blurHash: store.blurHash,
    address: store.address,
    lat: store.lat,
    lng: store.lng,
    rating: store.rating,
    etaMinutes: store.etaMinutes,
    deliveryFeeTiyn: store.deliveryFeeTiyn,
    minOrderTiyn: store.minOrderTiyn,
    isOpen: isOpenNow(store),
    workingHours: open,
  };
}

function dayHours(store: StoreRow): string {
  const weekday = (new Date().getDay() + 6) % 7;
  const day = store.schedule.find((s) => s.weekday === weekday);
  if (!day || day.openMin == null || day.closeMin == null) return '09:00–22:00';
  const fmt = (m: number) =>
    `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
  return `${fmt(day.openMin)}–${fmt(day.closeMin)}`;
}

// ─── Cart helpers ──────────────────────────────────────────────────────────

async function cartPayload(userId: string) {
  const cart = await prisma.cart.findUnique({
    where: { userId },
    include: {
      items: {
        include: { product: { select: productSelect } },
        orderBy: { id: 'asc' },
      },
    },
  });
  if (!cart || cart.items.length === 0) {
    return {
      storeId: '',
      storeName: '',
      items: [],
      subtotalTiyn: 0,
      deliveryTiyn: 0,
      discountTiyn: 0,
      totalTiyn: 0,
      promoCode: null,
    };
  }
  const store = cart.storeId
    ? await prisma.store.findUnique({ where: { id: cart.storeId } })
    : null;
  const subtotal = cart.items.reduce(
    (sum, i) => sum + i.priceTiyn * i.quantity,
    0,
  );
  const deliveryTiyn = store?.deliveryFeeTiyn ?? 0;
  return {
    storeId: cart.storeId ?? '',
    storeName: store?.name ?? '',
    items: cart.items.map((i) => ({
      id: i.id,
      product: i.product,
      quantity: i.quantity,
      variantId: i.variantId,
    })),
    subtotalTiyn: subtotal,
    deliveryTiyn,
    discountTiyn: 0,
    totalTiyn: subtotal + deliveryTiyn,
    promoCode: null,
  };
}

// ─── Order JSON ────────────────────────────────────────────────────────────

type OrderWithRelations = NonNullable<
  Awaited<ReturnType<typeof loadOrder>>
>;

export async function loadOrder(orderId: string) {
  return prisma.order.findUnique({
    where: { id: orderId },
    include: {
      items: true,
      store: true,
      statusHistory: { orderBy: { at: 'asc' } },
      payments: { orderBy: { createdAt: 'desc' }, take: 1 },
    },
  });
}

async function courierPhone(order: OrderWithRelations): Promise<string | null> {
  if (!order.courierId) return null;
  const courier = await prisma.user.findUnique({
    where: { id: order.courierId },
    select: { phone: true },
  });
  return courier?.phone ?? null;
}

export async function orderJson(order: OrderWithRelations) {
  const payment = order.payments[0];
  return {
    id: order.id,
    number: order.number,
    storeId: order.storeId,
    storeName: order.store.name,
    items: order.items.map((i) => ({
      productId: i.productId ?? '',
      name: i.name,
      quantity: i.quantity,
      priceTiyn: i.priceTiyn,
    })),
    status: order.status,
    paymentStatus: payment?.status ?? 'pending',
    delivery: {
      address: order.deliveryAddress,
      lat: order.deliveryLat,
      lng: order.deliveryLng,
      comment: order.deliveryComment,
      capturedAt: order.createdAt.toISOString(),
    },
    subtotalTiyn: order.subtotalTiyn,
    discountTiyn: order.discountTiyn,
    deliveryTiyn: order.deliveryTiyn,
    totalTiyn: order.totalTiyn,
    createdAt: order.createdAt.toISOString(),
    statusHistory: order.statusHistory.map((h) => ({
      status: h.status,
      actorRole: h.actorRole,
      at: h.at.toISOString(),
      reason: h.reason,
    })),
    promoCode: order.promoCode,
    courierId: order.courierId,
    courierName: order.courierName,
    courierPhone: await courierPhone(order),
    courierLocation:
      order.courierLat != null && order.courierLng != null
        ? { lat: order.courierLat, lng: order.courierLng }
        : null,
  };
}

async function nextOrderNumber(): Promise<string> {
  for (let attempt = 0; attempt < 10; attempt++) {
    const number = `K-${randomInt(1000, 100000)}`;
    if (!(await prisma.order.findUnique({ where: { number } }))) {
      return number;
    }
  }
  return `K-${Date.now()}`;
}

// ─── Routes ────────────────────────────────────────────────────────────────

export async function registerCommerceRoutes(
  app: FastifyInstance,
  config: Config,
): Promise<void> {
  // ── Stores ──
  app.get('/v1/stores', async (request) => {
    const q = z
      .object({ kind: z.string().optional(), q: z.string().max(100).optional() })
      .parse(request.query);
    const stores = await prisma.store.findMany({
      where: {
        active: true,
        ...(q.kind ? { kind: q.kind as never } : {}),
        ...(q.q
          ? { name: { contains: q.q, mode: 'insensitive' as const } }
          : {}),
      },
      select: storeSelect,
      take: 50,
    });
    return { items: stores.map(storeJson) };
  });

  app.get('/v1/stores/:id', async (request, reply) => {
    const { id: storeId } = idParams.parse(request.params);
    const store = await prisma.store.findUnique({
      where: { id: storeId },
      select: storeSelect,
    });
    if (!store) {
      return reply.code(404).send({
        error: { code: 'STORE_NOT_FOUND', message: 'Store not found' },
      });
    }
    return storeJson(store);
  });

  app.get('/v1/stores/:id/products', async (request) => {
    const { id: storeId } = idParams.parse(request.params);
    return {
      items: await prisma.product.findMany({
        where: { storeId, active: true },
        select: productSelect,
        orderBy: { createdAt: 'desc' },
      }),
    };
  });

  // ── Promotions ──
  app.get('/v1/promotions', async () => {
    const items = await prisma.promotion.findMany({
      where: {
        active: true,
        OR: [{ startsAt: null }, { startsAt: { lte: new Date() } }],
        AND: [{ OR: [{ endsAt: null }, { endsAt: { gt: new Date() } }] }],
      },
      orderBy: { createdAt: 'desc' },
      take: 20,
    });
    return {
      items: items.map((p) => ({
        id: p.id,
        title: p.title,
        subtitle: p.subtitle,
        imageUrl: p.imageUrl,
        storeId: p.storeId,
        code: p.code,
        discountPercent: p.discountPercent,
      })),
    };
  });

  app.post('/v1/promo-codes/validate', async (request) => {
    const { code } = z
      .object({ code: z.string().trim().min(1).max(40), storeId: z.string().optional() })
      .parse(request.body);
    const promo = await prisma.promoCode.findUnique({
      where: { code: code.toUpperCase() },
    });
    const invalid = { valid: false, discountTiyn: 0, message: 'Promo code is not valid' };
    if (!promo) return invalid;
    if (promo.expiresAt && promo.expiresAt <= new Date()) return invalid;
    if (promo.maxUses != null && promo.usedCount >= promo.maxUses) return invalid;
    return {
      valid: true,
      discountTiyn: promo.discountTiyn,
      percent: promo.percent,
      minOrderTiyn: promo.minOrderTiyn,
      message: '',
    };
  });

  // ── Cart ──
  app.get('/v1/cart', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    return cartPayload(auth.sub);
  });

  app.post('/v1/cart/items', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const input = z
      .object({
        productId: id,
        qty: z.number().int().min(1).max(999),
        variantId: z.string().max(100).nullish(),
      })
      .parse(request.body);
    const product = await prisma.product.findFirst({
      where: { id: input.productId, active: true, available: true },
    });
    if (!product) {
      return reply.code(404).send({
        error: { code: 'PRODUCT_NOT_FOUND', message: 'Product not found' },
      });
    }
    await prisma.$transaction(async (tx) => {
      let cart = await tx.cart.findUnique({ where: { userId: auth.sub } });
      if (cart && cart.storeId && cart.storeId !== product.storeId) {
        // Single-store cart invariant: switching stores clears the cart.
        await tx.cartItem.deleteMany({ where: { cartId: cart.id } });
        cart = await tx.cart.update({
          where: { id: cart.id },
          data: { storeId: product.storeId },
        });
      }
      cart ??= await tx.cart.create({
        data: { userId: auth.sub, storeId: product.storeId },
      });
      if (!cart.storeId) {
        await tx.cart.update({
          where: { id: cart.id },
          data: { storeId: product.storeId },
        });
      }
      const existing = await tx.cartItem.findFirst({
        where: {
          cartId: cart.id,
          productId: product.id,
          variantId: input.variantId ?? null,
        },
      });
      if (existing) {
        await tx.cartItem.update({
          where: { id: existing.id },
          data: { quantity: existing.quantity + input.qty },
        });
      } else {
        await tx.cartItem.create({
          data: {
            cartId: cart.id,
            productId: product.id,
            variantId: input.variantId ?? null,
            quantity: input.qty,
            priceTiyn: product.priceTiyn,
          },
        });
      }
    });
    return cartPayload(auth.sub);
  });

  app.patch('/v1/cart/items/:id', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { id: itemId } = idParams.parse(request.params);
    const { qty } = z
      .object({ qty: z.number().int().min(0).max(999) })
      .parse(request.body);
    const item = await prisma.cartItem.findUnique({
      where: { id: itemId },
      include: { cart: true },
    });
    if (!item || item.cart.userId !== auth.sub) {
      return reply.code(404).send({
        error: { code: 'ITEM_NOT_FOUND', message: 'Cart item not found' },
      });
    }
    if (qty === 0) {
      await prisma.cartItem.delete({ where: { id: itemId } });
    } else {
      await prisma.cartItem.update({
        where: { id: itemId },
        data: { quantity: qty },
      });
    }
    return cartPayload(auth.sub);
  });

  app.delete('/v1/cart/items/:id', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { id: itemId } = idParams.parse(request.params);
    const item = await prisma.cartItem.findUnique({
      where: { id: itemId },
      include: { cart: true },
    });
    if (item && item.cart.userId === auth.sub) {
      await prisma.cartItem.delete({ where: { id: itemId } });
    }
    return cartPayload(auth.sub);
  });

  app.delete('/v1/cart', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const cart = await prisma.cart.findUnique({ where: { userId: auth.sub } });
    if (cart) {
      await prisma.$transaction([
        prisma.cartItem.deleteMany({ where: { cartId: cart.id } }),
        prisma.cart.update({ where: { id: cart.id }, data: { storeId: null } }),
      ]);
    }
    return cartPayload(auth.sub);
  });

  // ── Checkout ──
  app.post('/v1/checkout/validate', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    return { issues: await checkoutIssues(auth.sub) };
  });

  app.post('/v1/checkout', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const input = z
      .object({
        addressId: id.optional(),
        lat: z.number().min(-90).max(90).optional(),
        lng: z.number().min(-180).max(180).optional(),
        address: z.string().trim().max(300).optional(),
        comment: z.string().trim().max(500).optional(),
        promoCode: z.string().trim().max(40).optional(),
        paymentMethod: z.enum(['kaspi', 'card', 'wallet', 'cash']).default('kaspi'),
      })
      .parse(request.body);

    const issues = await checkoutIssues(auth.sub);
    if (issues.length > 0) {
      return reply.code(422).send({
        error: { code: 'CHECKOUT_INVALID', message: 'Checkout validation failed', details: issues },
      });
    }

    // Resolve delivery snapshot.
    let delivery: { address: string; lat: number; lng: number } | null = null;
    if (input.addressId) {
      const addr = await prisma.address.findUnique({
        where: { id: input.addressId },
      });
      if (!addr || addr.userId !== auth.sub) {
        return reply.code(400).send({
          error: { code: 'ADDRESS_INVALID', message: 'Address not found' },
        });
      }
      delivery = { address: addr.address, lat: addr.lat, lng: addr.lng };
    } else if (input.lat != null && input.lng != null && input.address) {
      delivery = { address: input.address, lat: input.lat, lng: input.lng };
    }
    if (!delivery) {
      return reply.code(400).send({
        error: { code: 'ADDRESS_REQUIRED', message: 'Delivery address required' },
      });
    }

    const cart = await prisma.cart.findUnique({
      where: { userId: auth.sub },
      include: { items: { include: { product: true } } },
    });
    if (!cart || cart.items.length === 0 || !cart.storeId) {
      return reply.code(422).send({
        error: { code: 'CART_EMPTY', message: 'Cart is empty' },
      });
    }
    const store = await prisma.store.findUniqueOrThrow({
      where: { id: cart.storeId },
    });
    const subtotal = cart.items.reduce(
      (sum, i) => sum + i.priceTiyn * i.quantity,
      0,
    );

    // Promo code.
    let discountTiyn = 0;
    let promoCode: string | null = null;
    if (input.promoCode) {
      const promo = await prisma.promoCode.findUnique({
        where: { code: input.promoCode.toUpperCase() },
      });
      const usable =
        promo &&
        (!promo.expiresAt || promo.expiresAt > new Date()) &&
        (promo.maxUses == null || promo.usedCount < promo.maxUses) &&
        subtotal >= promo.minOrderTiyn;
      if (usable) {
        discountTiyn = promo.percent
          ? Math.floor((subtotal * promo.percent) / 100)
          : promo.discountTiyn;
        promoCode = promo.code;
      }
    }
    // Distance-based delivery fee: base + per-km, free above a threshold,
    // and a hard service radius around the store.
    const distanceKm = haversineKm(
      store.lat,
      store.lng,
      delivery.lat,
      delivery.lng,
    );
    if (distanceKm > store.deliveryRadiusKm) {
      return reply.code(422).send({
        error: {
          code: 'DELIVERY_OUT_OF_ZONE',
          message: 'Address is outside the delivery zone',
        },
      });
    }
    const freeAbove = store.freeDeliveryAboveTiyn;
    const deliveryTiyn =
      freeAbove != null && subtotal >= freeAbove
        ? 0
        : store.deliveryFeeTiyn +
          Math.ceil(distanceKm) * store.deliveryPerKmTiyn;
    const totalTiyn = Math.max(0, subtotal - discountTiyn) + deliveryTiyn;

    // Wallet payment requires sufficient balance.
    if (input.paymentMethod === 'wallet') {
      const wallet = await prisma.walletAccount.findUnique({
        where: { userId: auth.sub },
      });
      if (!wallet || wallet.balanceTiyn < totalTiyn) {
        return reply.code(422).send({
          error: { code: 'WALLET_INSUFFICIENT', message: 'Insufficient wallet balance' },
        });
      }
    }

    const number = await nextOrderNumber();
    let order;
    try {
      order = await prisma.$transaction(async (tx) => {
      // Reserve-free checkout: decrement stock atomically.
      for (const item of cart.items) {
        const updated = await tx.product.updateMany({
          where: {
            id: item.productId,
            stock: { gte: item.quantity },
          },
          data: { stock: { decrement: item.quantity } },
        });
        if (updated.count === 0) {
          throw new Error(`OUT_OF_STOCK:${item.product.name}`);
        }
        await tx.inventoryTransaction.create({
          data: {
            productId: item.productId,
            kind: 'sale',
            quantity: -item.quantity,
            stockAfter: item.product.stock - item.quantity,
            reservedAfter: item.product.reservedStock,
            actorId: auth.sub,
            note: number,
          },
        });
      }
      const created = await tx.order.create({
        data: {
          number,
          userId: auth.sub,
          storeId: cart.storeId!,
          status: 'pending',
          deliveryAddress: delivery!.address,
          deliveryLat: delivery!.lat,
          deliveryLng: delivery!.lng,
          deliveryComment: input.comment ?? null,
          subtotalTiyn: subtotal,
          discountTiyn,
          deliveryTiyn,
          totalTiyn,
          promoCode,
          items: {
            create: cart.items.map((i) => ({
              productId: i.productId,
              variantId: i.variantId,
              name: i.product.name,
              priceTiyn: i.priceTiyn,
              quantity: i.quantity,
            })),
          },
          statusHistory: {
            create: {
              status: 'pending',
              actorId: auth.sub,
              actorRole: 'customer',
            },
          },
          payments: {
            create: {
              provider: input.paymentMethod === 'kaspi' ? 'kaspi' : 'mock',
              status:
                input.paymentMethod === 'wallet' || input.paymentMethod === 'cash'
                  ? 'paid'
                  : 'initiated',
              amountTiyn: totalTiyn,
            },
          },
          chatRoom: { create: {} },
        },
        include: {
          items: true,
          store: true,
          statusHistory: true,
          payments: { orderBy: { createdAt: 'desc' }, take: 1 },
        },
      });
      if (promoCode) {
        await tx.promoCode.update({
          where: { code: promoCode },
          data: { usedCount: { increment: 1 } },
        });
      }
      if (input.paymentMethod === 'wallet') {
        await tx.walletAccount.update({
          where: { userId: auth.sub },
          data: { balanceTiyn: { decrement: totalTiyn } },
        });
        await tx.walletTransaction.create({
          data: {
            accountId: auth.sub,
            kind: 'order_spend',
            amountTiyn: -totalTiyn,
            title: `Order ${number}`,
            orderId: created.id,
          },
        });
      }
        await tx.cartItem.deleteMany({ where: { cartId: cart.id } });
        await tx.cart.update({
          where: { id: cart.id },
          data: { storeId: null },
        });
        return created;
      });
    } catch (error) {
      const message = (error as Error).message;
      if (message.startsWith('OUT_OF_STOCK:')) {
        return reply.code(409).send({
          error: {
            code: 'OUT_OF_STOCK',
            message: `${message.slice(13)}: not enough stock`,
          },
        });
      }
      throw error;
    }

    app.realtime.sendToUser(auth.sub, 'order.created', {
      orderId: order.id,
    });
    void app.notifications
      .send({
        userId: auth.sub,
        kind: 'order_status',
        title: `Order ${order.number}`,
        body: 'Order placed',
        orderId: order.id,
      })
      .catch(() => {});

    return reply.code(201).send({
      order: await orderJson(order),
      payment: order.payments[0]
        ? {
            id: order.payments[0].id,
            status: order.payments[0].status,
            provider: order.payments[0].provider,
            amountTiyn: order.payments[0].amountTiyn,
          }
        : null,
    });
  });

  // ── Orders ──
  app.get('/v1/orders', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const orders = await prisma.order.findMany({
      where: orderScope(auth.sub, auth.role),
      include: {
        items: true,
        store: true,
        statusHistory: { orderBy: { at: 'asc' } },
        payments: { orderBy: { createdAt: 'desc' }, take: 1 },
      },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    return { items: await Promise.all(orders.map(orderJson)) };
  });

  app.get('/v1/orders/:id', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { id: orderId } = idParams.parse(request.params);
    const order = await loadOrder(orderId);
    if (!order || !canSeeOrder(auth.sub, auth.role, order)) {
      return reply.code(404).send({
        error: { code: 'ORDER_NOT_FOUND', message: 'Order not found' },
      });
    }
    return orderJson(order);
  });

  app.post('/v1/orders/:id/cancel', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { id: orderId } = idParams.parse(request.params);
    const { reason } = z
      .object({ reason: z.string().trim().max(300).optional() })
      .parse(request.body ?? {});
    const order = await prisma.order.findUnique({ where: { id: orderId } });
    if (!order || order.userId !== auth.sub) {
      return reply.code(404).send({
        error: { code: 'ORDER_NOT_FOUND', message: 'Order not found' },
      });
    }
    if (!['pending', 'accepted'].includes(order.status)) {
      return reply.code(409).send({
        error: { code: 'CANNOT_CANCEL', message: 'Order can no longer be cancelled' },
      });
    }
    const updated = await prisma.$transaction(async (tx) => {
      const o = await tx.order.update({
        where: { id: orderId },
        data: { status: 'cancelled' },
        include: {
          items: true,
          store: true,
          statusHistory: { orderBy: { at: 'asc' } },
          payments: { orderBy: { createdAt: 'desc' }, take: 1 },
        },
      });
      await tx.orderStatusEntry.create({
        data: {
          orderId,
          status: 'cancelled',
          actorId: auth.sub,
          actorRole: auth.role,
          reason: reason ?? null,
        },
      });
      // Restock items.
      for (const item of o.items) {
        if (!item.productId) continue;
        await tx.product.update({
          where: { id: item.productId },
          data: { stock: { increment: item.quantity } },
        });
      }
      // Wallet refund when it was a wallet-paid order.
      const payment = o.payments[0];
      if (payment && payment.status === 'paid' && payment.provider === 'mock') {
        await tx.payment.update({
          where: { id: payment.id },
          data: { status: 'refunded' },
        });
        await tx.walletAccount.upsert({
          where: { userId: auth.sub },
          create: { userId: auth.sub, balanceTiyn: o.totalTiyn },
          update: { balanceTiyn: { increment: o.totalTiyn } },
        });
        await tx.walletTransaction.create({
          data: {
            accountId: auth.sub,
            kind: 'refund',
            amountTiyn: o.totalTiyn,
            title: `Refund ${o.number}`,
            orderId: o.id,
          },
        });
      }
      return tx.order.findUniqueOrThrow({
        where: { id: orderId },
        include: {
          items: true,
          store: true,
          statusHistory: { orderBy: { at: 'asc' } },
          payments: { orderBy: { createdAt: 'desc' }, take: 1 },
        },
      });
    });
    void emitOrderEvent(app.realtime, orderId, 'order.status_changed', {
      status: 'cancelled',
    }).catch(() => {});
    return orderJson(updated);
  });

  app.post('/v1/orders/:id/repeat', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { id: orderId } = idParams.parse(request.params);
    const order = await prisma.order.findUnique({
      where: { id: orderId },
      include: { items: { include: { product: true } } },
    });
    if (!order || order.userId !== auth.sub) {
      return reply.code(404).send({
        error: { code: 'ORDER_NOT_FOUND', message: 'Order not found' },
      });
    }
    await prisma.$transaction(async (tx) => {
      let cart = await tx.cart.findUnique({ where: { userId: auth.sub } });
      if (cart) {
        await tx.cartItem.deleteMany({ where: { cartId: cart.id } });
        cart = await tx.cart.update({
          where: { id: cart.id },
          data: { storeId: order.storeId },
        });
      } else {
        cart = await tx.cart.create({
          data: { userId: auth.sub, storeId: order.storeId },
        });
      }
      for (const item of order.items) {
        if (!item.product || !item.product.available || !item.product.active) {
          continue;
        }
        await tx.cartItem.create({
          data: {
            cartId: cart.id,
            productId: item.product.id,
            quantity: item.quantity,
            priceTiyn: item.product.priceTiyn,
          },
        });
      }
    });
    return cartPayload(auth.sub);
  });

  // ── Tracking ──
  app.get('/v1/tracking/orders/:orderId', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { orderId } = z.object({ orderId: id }).parse(request.params);
    const order = await prisma.order.findUnique({ where: { id: orderId } });
    if (!order || !canSeeOrder(auth.sub, auth.role, order)) {
      return reply.code(404).send({
        error: { code: 'ORDER_NOT_FOUND', message: 'Order not found' },
      });
    }
    return {
      orderStatus: order.status,
      courierName: order.courierName,
      courierLocation:
        order.courierLat != null && order.courierLng != null
          ? { lat: order.courierLat, lng: order.courierLng }
          : null,
    };
  });
}

function orderScope(userId: string, role: string) {
  if (role === 'admin' || role === 'manager') return {};
  if (role === 'courier') return { courierId: userId };
  return { userId };
}

function canSeeOrder(
  userId: string,
  role: string,
  order: { userId: string; courierId: string | null; storeId: string },
): boolean {
  if (role === 'admin' || role === 'manager') return true;
  if (role === 'courier') return order.courierId === userId;
  return order.userId === userId;
}

async function checkoutIssues(userId: string) {
  const issues: { code: string; message: string }[] = [];
  const cart = await prisma.cart.findUnique({
    where: { userId },
    include: { items: { include: { product: true } } },
  });
  if (!cart || cart.items.length === 0) {
    issues.push({ code: 'CART_EMPTY', message: 'Cart is empty' });
    return issues;
  }
  const store = cart.storeId
    ? await prisma.store.findUnique({
        where: { id: cart.storeId },
        select: storeSelect,
      })
    : null;
  if (store && !isOpenNow(store)) {
    issues.push({ code: 'STORE_CLOSED', message: 'Store is closed' });
  }
  const subtotal = cart.items.reduce(
    (sum, i) => sum + i.priceTiyn * i.quantity,
    0,
  );
  if (store && subtotal < store.minOrderTiyn) {
    issues.push({
      code: 'MIN_ORDER',
      message: `Minimum order is ${store.minOrderTiyn} tiyn`,
    });
  }
  for (const item of cart.items) {
    const availableStock = item.product.stock - item.product.reservedStock;
    if (!item.product.available || !item.product.active) {
      issues.push({
        code: 'UNAVAILABLE',
        message: `${item.product.name} is unavailable`,
      });
    } else if (availableStock < item.quantity) {
      issues.push({
        code: 'OUT_OF_STOCK',
        message: `${item.product.name}: only ${availableStock} left`,
      });
    }
  }
  return issues;
}

/// Great-circle distance in kilometres (WGS84 mean radius).
function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const rad = (v: number) => (v * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
