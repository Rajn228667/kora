import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../auth/guard.js';
import type { Config } from '../config.js';
import { productSelect } from '../commerce/routes.js';
import { prisma } from '../plugins/prisma.js';
import { emitOrderEvent } from '../realtime/gateway.js';

async function managedStoreIds(
  userId: string,
  role: string,
): Promise<string[] | null> {
  if (role === 'admin') return null; // all stores
  const rows = await prisma.storeManager.findMany({ where: { userId } });
  return rows.map((r) => r.storeId);
}

export async function registerManagerRoutes(
  app: FastifyInstance,
  config: Config,
): Promise<void> {
  const staff = ['manager', 'admin'] as const;

  app.get('/v1/manager/dashboard', async (request, reply) => {
    const auth = await authenticate(request, reply, config, staff);
    if (!auth) return;
    const storeIds = await managedStoreIds(auth.sub, auth.role);
    const scope = storeIds ? { storeId: { in: storeIds } } : {};
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const [newOrders, preparing, ready, deliveredToday, cancelledToday, sales] =
      await Promise.all([
        prisma.order.count({ where: { ...scope, status: 'pending' } }),
        prisma.order.count({
          where: { ...scope, status: { in: ['accepted', 'preparing'] } },
        }),
        prisma.order.count({ where: { ...scope, status: 'ready_for_pickup' } }),
        prisma.order.count({
          where: { ...scope, status: 'delivered', updatedAt: { gte: today } },
        }),
        prisma.order.count({
          where: {
            ...scope,
            status: { in: ['cancelled', 'rejected'] },
            updatedAt: { gte: today },
          },
        }),
        prisma.order.aggregate({
          where: {
            ...scope,
            status: { notIn: ['cancelled', 'rejected'] },
            createdAt: { gte: today },
          },
          _sum: { totalTiyn: true },
        }),
      ]);
    return {
      newOrders,
      preparing,
      ready,
      deliveredToday,
      cancelledToday,
      salesTodayTiyn: sales._sum.totalTiyn ?? 0,
    };
  });

  app.get('/v1/manager/couriers', async (request, reply) => {
    const auth = await authenticate(request, reply, config, staff);
    if (!auth) return;
    const couriers = await prisma.courierProfile.findMany({
      include: { user: { select: { id: true, name: true, phone: true } } },
    });
    const active = await prisma.order.groupBy({
      by: ['courierId'],
      where: {
        courierId: { not: null },
        status: {
          in: ['courier_assigned', 'picked_up', 'delivering'],
        },
      },
      _count: true,
    });
    const countBy = new Map(active.map((a) => [a.courierId, a._count]));
    return {
      items: couriers.map((c) => ({
        id: c.userId,
        name: c.user.name,
        status: c.status,
        activeOrders: countBy.get(c.userId) ?? 0,
      })),
    };
  });

  app.get('/v1/manager/products', async (request, reply) => {
    const auth = await authenticate(request, reply, config, staff);
    if (!auth) return;
    const storeIds = await managedStoreIds(auth.sub, auth.role);
    return {
      items: await prisma.product.findMany({
        where: {
          active: true,
          ...(storeIds ? { storeId: { in: storeIds } } : {}),
        },
        select: productSelect,
        orderBy: { createdAt: 'desc' },
      }),
    };
  });

  app.get('/v1/manager/map', async (request, reply) => {
    const auth = await authenticate(request, reply, config, staff);
    if (!auth) return;
    const storeIds = await managedStoreIds(auth.sub, auth.role);
    const [stores, couriers, orders] = await Promise.all([
      prisma.store.findMany({
        where: { active: true, ...(storeIds ? { id: { in: storeIds } } : {}) },
        select: { name: true, lat: true, lng: true },
      }),
      prisma.courierProfile.findMany({
        where: { lastLat: { not: null }, status: { not: 'offline' } },
        select: { lastLat: true, lastLng: true },
      }),
      prisma.order.findMany({
        where: {
          status: {
            in: ['pending', 'accepted', 'preparing', 'ready_for_pickup',
              'courier_assigned', 'picked_up', 'delivering'],
          },
          ...(storeIds ? { storeId: { in: storeIds } } : {}),
        },
        select: {
          deliveryLat: true,
          deliveryLng: true,
          status: true,
        },
      }),
    ]);
    return {
      stores,
      couriers: couriers.map((c) => ({ lat: c.lastLat, lng: c.lastLng })),
      orders: orders.map((o) => ({
        lat: o.deliveryLat,
        lng: o.deliveryLng,
        status: o.status,
      })),
    };
  });

  // ── Store schedule ──
  app.get('/v1/manager/schedule', async (request, reply) => {
    const auth = await authenticate(request, reply, config, staff);
    if (!auth) return;
    const storeIds = await managedStoreIds(auth.sub, auth.role);
    const days: Record<string, { open: number; close: number } | null> = {};
    if (storeIds && storeIds.length > 0) {
      const rows = await prisma.storeSchedule.findMany({
        where: { storeId: storeIds[0] },
      });
      for (const r of rows) {
        days[String(r.weekday)] =
          r.openMin == null || r.closeMin == null
            ? null
            : { open: r.openMin, close: r.closeMin };
      }
    }
    return { days };
  });

  app.put('/v1/manager/schedule', async (request, reply) => {
    const auth = await authenticate(request, reply, config, staff);
    if (!auth) return;
    const { storeId, days } = z
      .object({
        storeId: z.string().optional(),
        days: z.record(
          z.string(),
          z
            .object({
              open: z.number().int().min(0).max(1439),
              close: z.number().int().min(0).max(1439),
            })
            .nullable(),
        ),
      })
      .parse(request.body);
    const storeIds = await managedStoreIds(auth.sub, auth.role);
    const target = storeId ?? storeIds?.[0];
    if (!target || (storeIds && !storeIds.includes(target))) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'Store access denied' },
      });
    }
    for (const [day, hours] of Object.entries(days)) {
      const weekday = Number(day);
      if (!Number.isInteger(weekday) || weekday < 0 || weekday > 6) continue;
      await prisma.storeSchedule.upsert({
        where: { storeId_weekday: { storeId: target, weekday } },
        create: {
          storeId: target,
          weekday,
          openMin: hours?.open ?? null,
          closeMin: hours?.close ?? null,
        },
        update: {
          openMin: hours?.open ?? null,
          closeMin: hours?.close ?? null,
        },
      });
    }
    await prisma.auditLog.create({
      data: {
        actorId: auth.sub,
        actorRole: auth.role,
        action: 'schedule_updated',
        resource: target,
        details: { days },
        ip: request.ip,
      },
    });
    return { ok: true };
  });

  // ── Bonus grants — manager credits a customer's wallet ──
  app.get('/v1/manager/users', async (request, reply) => {
    const auth = await authenticate(request, reply, config, staff);
    if (!auth) return;
    const { q } = z
      .object({ q: z.string().trim().min(2).max(100) })
      .parse(request.query);
    const users = await prisma.user.findMany({
      where: {
        deletedAt: null,
        OR: [
          { phone: { contains: q } },
          { name: { contains: q, mode: 'insensitive' } },
          { email: { contains: q, mode: 'insensitive' } },
        ],
      },
      select: { id: true, phone: true, name: true, email: true },
      take: 20,
    });
    return { items: users };
  });

  app.post('/v1/manager/users/:id/bonus', async (request, reply) => {
    const auth = await authenticate(request, reply, config, staff);
    if (!auth) return;
    const { id: userId } = request.params as { id: string };
    const { amountTiyn, title } = z
      .object({
        amountTiyn: z.number().int().min(1).max(100_000_00),
        title: z.string().trim().max(160).default('Bonus'),
      })
      .parse(request.body);
    const target = await prisma.user.findFirst({
      where: { id: userId, deletedAt: null },
    });
    if (!target) {
      return reply.code(404).send({
        error: { code: 'USER_NOT_FOUND', message: 'User not found' },
      });
    }
    await prisma.$transaction([
      prisma.walletAccount.upsert({
        where: { userId },
        create: { userId, balanceTiyn: amountTiyn },
        update: { balanceTiyn: { increment: amountTiyn } },
      }),
      prisma.walletTransaction.create({
        data: {
          accountId: userId,
          kind: 'promo_credit',
          amountTiyn,
          title,
        },
      }),
      prisma.auditLog.create({
        data: {
          actorId: auth.sub,
          actorRole: auth.role,
          action: 'bonus_granted',
          resource: userId,
          details: { amountTiyn, title },
          ip: request.ip,
        },
      }),
    ]);
    void app.notifications
      .send({
        userId,
        kind: 'promo',
        title,
        body: `+${amountTiyn}`,
      })
      .catch(() => {});
    return { ok: true };
  });

  // ── Order workflow actions ──
  app.post('/v1/manager/orders/:id/:action', async (request, reply) => {
    const auth = await authenticate(request, reply, config, staff);
    if (!auth) return;
    const { id: orderId, action } = z
      .object({
        id: z.string().min(1),
        action: z.enum(['accept', 'reject', 'ready', 'assign-courier']),
      })
      .parse(request.params);
    const { courierId } = z
      .object({ courierId: z.string().min(1).optional() })
      .parse(request.body ?? {});
    const order = await prisma.order.findUnique({ where: { id: orderId } });
    if (!order) {
      return reply.code(404).send({
        error: { code: 'ORDER_NOT_FOUND', message: 'Order not found' },
      });
    }
    const storeIds = await managedStoreIds(auth.sub, auth.role);
    if (storeIds && !storeIds.includes(order.storeId)) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'Store access denied' },
      });
    }

    const transitions: Record<string, string | null> = {
      accept: 'accepted',
      reject: 'rejected',
      ready: 'ready_for_pickup',
      'assign-courier': null,
    };
    const next = transitions[action];
    if (next) {
      await prisma.$transaction([
        prisma.order.update({ where: { id: orderId }, data: { status: next as never } }),
        prisma.orderStatusEntry.create({
          data: {
            orderId,
            status: next as never,
            actorId: auth.sub,
            actorRole: auth.role,
          },
        }),
        prisma.auditLog.create({
          data: {
            actorId: auth.sub,
            actorRole: auth.role,
            action: `order_${action}`,
            resource: orderId,
            details: {},
            ip: request.ip,
          },
        }),
      ]);
      void emitOrderEvent(app.realtime, orderId, 'order.status_changed', {
        status: next,
      }).catch(() => {});
    } else {
      // assign-courier: direct assignment + offer record.
      if (!courierId) {
        return reply.code(400).send({
          error: { code: 'COURIER_REQUIRED', message: 'courierId is required' },
        });
      }
      const courier = await prisma.user.findUnique({ where: { id: courierId } });
      if (!courier || courier.role !== 'courier') {
        return reply.code(404).send({
          error: { code: 'COURIER_NOT_FOUND', message: 'Courier not found' },
        });
      }
      await prisma.$transaction([
        prisma.order.update({
          where: { id: orderId },
          data: {
            courierId,
            courierName: courier.name,
            status: 'courier_assigned',
          },
        }),
        prisma.courierOffer.upsert({
          where: {
            orderId_courierId: { orderId, courierId },
          },
          create: {
            orderId,
            courierId,
            status: 'accepted',
            feeTiyn: order.deliveryTiyn,
            distanceKm: 0,
            expiresAt: new Date(Date.now() + 300_000),
          },
          update: { status: 'accepted' },
        }),
        prisma.courierProfile.upsert({
          where: { userId: courierId },
          create: {
            userId: courierId,
            status: 'busy',
            activeOrder: orderId,
          },
          update: { status: 'busy', activeOrder: orderId },
        }),
        prisma.orderStatusEntry.create({
          data: {
            orderId,
            status: 'courier_assigned',
            actorId: auth.sub,
            actorRole: auth.role,
          },
        }),
      ]);
      app.realtime.sendToUser(order.userId, 'courier.assigned', {
        orderId,
        courierId,
        courierName: courier.name,
      });
      void app.notifications
        .send({
          userId: order.userId,
          kind: 'courier_assigned',
          title: `Order ${order.number}`,
          body: 'Courier assigned',
          orderId,
        })
        .catch(() => {});
    }
    return { ok: true };
  });
}
