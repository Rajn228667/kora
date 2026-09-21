import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../auth/guard.js';
import type { Config } from '../config.js';
import {
  orderJson,
  productSelect,
  storeJson,
  storeSelect,
} from '../commerce/routes.js';
import { prisma } from '../plugins/prisma.js';

export async function registerAdminRoutes(
  app: FastifyInstance,
  config: Config,
): Promise<void> {
  const adminOnly = ['admin'] as const;

  app.get('/v1/admin/users', async (request, reply) => {
    const auth = await authenticate(request, reply, config, adminOnly);
    if (!auth) return;
    const users = await prisma.user.findMany({
      orderBy: { createdAt: 'desc' },
      take: 200,
    });
    return {
      items: users.map((u) => ({
        id: u.id,
        phone: u.phone,
        email: u.email,
        name: u.name,
        role: u.role,
        blocked: u.blockedAt !== null,
      })),
    };
  });

  app.post('/v1/admin/users/:id/block', async (request, reply) => {
    const auth = await authenticate(request, reply, config, adminOnly);
    if (!auth) return;
    const { id } = request.params as { id: string };
    const { blocked } = z.object({ blocked: z.boolean() }).parse(request.body);
    const user = await prisma.user.findUnique({ where: { id } });
    if (!user || user.role === 'admin') {
      return reply.code(404).send({
        error: { code: 'USER_NOT_FOUND', message: 'User not found' },
      });
    }
    await prisma.$transaction([
      prisma.user.update({
        where: { id },
        data: { blockedAt: blocked ? new Date() : null },
      }),
      ...(blocked
        ? [
            prisma.session.updateMany({
              where: { userId: id, revokedAt: null },
              data: { revokedAt: new Date() },
            }),
          ]
        : []),
      prisma.auditLog.create({
        data: {
          actorId: auth.sub,
          actorRole: auth.role,
          action: blocked ? 'user_blocked' : 'user_unblocked',
          resource: id,
          details: {},
          ip: request.ip,
        },
      }),
    ]);
    return { ok: true };
  });

  app.get('/v1/admin/orders', async (request, reply) => {
    const auth = await authenticate(request, reply, config, adminOnly);
    if (!auth) return;
    const orders = await prisma.order.findMany({
      include: {
        items: true,
        store: true,
        statusHistory: { orderBy: { at: 'asc' } },
        payments: { orderBy: { createdAt: 'desc' }, take: 1 },
      },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return { items: await Promise.all(orders.map(orderJson)) };
  });

  app.get('/v1/admin/payments', async (request, reply) => {
    const auth = await authenticate(request, reply, config, adminOnly);
    if (!auth) return;
    const payments = await prisma.payment.findMany({
      include: { order: { select: { number: true } } },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return {
      items: payments.map((p) => ({
        id: p.id,
        orderId: p.orderId,
        orderNumber: p.order.number,
        provider: p.provider,
        status: p.status,
        amountTiyn: p.amountTiyn,
        createdAt: p.createdAt.toISOString(),
      })),
    };
  });

  app.get('/v1/admin/stores', async (request, reply) => {
    const auth = await authenticate(request, reply, config, adminOnly);
    if (!auth) return;
    const stores = await prisma.store.findMany({ select: storeSelect });
    return { items: stores.map(storeJson) };
  });

  app.get('/v1/admin/products', async (request, reply) => {
    const auth = await authenticate(request, reply, config, adminOnly);
    if (!auth) return;
    return {
      items: await prisma.product.findMany({
        select: productSelect,
        orderBy: { createdAt: 'desc' },
        take: 500,
      }),
    };
  });

  // ── Promo codes ──
  app.get('/v1/admin/promo-codes', async (request, reply) => {
    const auth = await authenticate(request, reply, config, adminOnly);
    if (!auth) return;
    const items = await prisma.promoCode.findMany({
      orderBy: { createdAt: 'desc' },
    });
    return {
      items: items.map((p) => ({
        code: p.code,
        discountTiyn: p.discountTiyn,
        percent: p.percent,
        minOrderTiyn: p.minOrderTiyn,
        maxUses: p.maxUses,
        usedCount: p.usedCount,
        expiresAt: p.expiresAt?.toISOString() ?? null,
      })),
    };
  });

  app.post('/v1/admin/promo-codes', async (request, reply) => {
    const auth = await authenticate(request, reply, config, adminOnly);
    if (!auth) return;
    const input = z
      .object({
        code: z.string().trim().min(3).max(40),
        discountTiyn: z.number().int().nonnegative().default(0),
        percent: z.number().int().min(1).max(90).optional(),
        minOrderTiyn: z.number().int().nonnegative().default(0),
        maxUses: z.number().int().positive().optional(),
        expiresAt: z.string().datetime().optional(),
      })
      .parse(request.body);
    const promo = await prisma.promoCode.upsert({
      where: { code: input.code.toUpperCase() },
      create: {
        code: input.code.toUpperCase(),
        discountTiyn: input.discountTiyn,
        percent: input.percent ?? null,
        minOrderTiyn: input.minOrderTiyn,
        maxUses: input.maxUses ?? null,
        expiresAt: input.expiresAt ? new Date(input.expiresAt) : null,
      },
      update: {
        discountTiyn: input.discountTiyn,
        percent: input.percent ?? null,
        minOrderTiyn: input.minOrderTiyn,
        maxUses: input.maxUses ?? null,
        expiresAt: input.expiresAt ? new Date(input.expiresAt) : null,
      },
    });
    await prisma.auditLog.create({
      data: {
        actorId: auth.sub,
        actorRole: auth.role,
        action: 'promo_code_saved',
        resource: promo.code,
        details: {},
        ip: request.ip,
      },
    });
    return reply.code(201).send({ code: promo.code });
  });

  app.delete('/v1/admin/promo-codes/:code', async (request, reply) => {
    const auth = await authenticate(request, reply, config, adminOnly);
    if (!auth) return;
    const { code } = request.params as { code: string };
    await prisma.promoCode.deleteMany({ where: { code: code.toUpperCase() } });
    return reply.code(204).send();
  });

  // ── Promotions ──
  app.get('/v1/admin/promotions', async (request, reply) => {
    const auth = await authenticate(request, reply, config, adminOnly);
    if (!auth) return;
    const items = await prisma.promotion.findMany({
      orderBy: { createdAt: 'desc' },
    });
    return { items };
  });

  app.post('/v1/admin/promotions', async (request, reply) => {
    const auth = await authenticate(request, reply, config, adminOnly);
    if (!auth) return;
    const input = z
      .object({
        title: z.string().trim().min(2).max(160),
        subtitle: z.string().trim().max(300).optional(),
        imageUrl: z.string().url().max(2048).optional(),
        storeId: z.string().min(1).optional(),
        code: z.string().trim().max(40).optional(),
        discountPercent: z.number().int().min(1).max(90).optional(),
        discountTiyn: z.number().int().nonnegative().optional(),
        minOrderTiyn: z.number().int().nonnegative().default(0),
        kind: z
          .enum(['percent', 'fixed', 'bogo', 'first_order', 'free_delivery'])
          .default('percent'),
      })
      .parse(request.body);
    const promo = await prisma.promotion.create({ data: input });
    await prisma.auditLog.create({
      data: {
        actorId: auth.sub,
        actorRole: auth.role,
        action: 'promotion_created',
        resource: promo.id,
        details: { title: promo.title },
        ip: request.ip,
      },
    });
    return reply.code(201).send(promo);
  });

  app.delete('/v1/admin/promotions/:id', async (request, reply) => {
    const auth = await authenticate(request, reply, config, adminOnly);
    if (!auth) return;
    const { id } = request.params as { id: string };
    await prisma.promotion.updateMany({
      where: { id },
      data: { active: false },
    });
    return reply.code(204).send();
  });

  // ── Audit log ──
  app.get('/v1/admin/audit-logs', async (request, reply) => {
    const auth = await authenticate(request, reply, config, adminOnly);
    if (!auth) return;
    const logs = await prisma.auditLog.findMany({
      include: { actor: { select: { name: true, phone: true } } },
      orderBy: { at: 'desc' },
      take: 200,
    });
    return {
      items: logs.map((l) => ({
        id: l.id,
        actor: l.actor?.name || l.actor?.phone || 'system',
        role: l.actorRole,
        action: l.action,
        resource: l.resource,
        at: l.at.toISOString(),
      })),
    };
  });
}
