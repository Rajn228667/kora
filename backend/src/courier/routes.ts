import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../auth/guard.js';
import type { Config } from '../config.js';
import { prisma } from '../plugins/prisma.js';

export async function registerCourierRoutes(
  app: FastifyInstance,
  config: Config,
): Promise<void> {
  app.post('/v1/couriers/status', async (request, reply) => {
    const auth = await authenticate(request, reply, config, ['courier']);
    if (!auth) return;
    const { status } = z
      .object({ status: z.enum(['online', 'offline']) })
      .parse(request.body);
    await prisma.courierProfile.upsert({
      where: { userId: auth.sub },
      create: { userId: auth.sub, status },
      update: { status },
    });
    return { ok: true, status };
  });

  app.post('/v1/couriers/location', async (request, reply) => {
    const auth = await authenticate(request, reply, config, ['courier']);
    if (!auth) return;
    const { lat, lng } = z
      .object({
        lat: z.number().min(-90).max(90),
        lng: z.number().min(-180).max(180),
        ts: z.string().optional(),
      })
      .parse(request.body);
    const profile = await prisma.courierProfile.upsert({
      where: { userId: auth.sub },
      create: { userId: auth.sub },
      update: {},
    });
    await prisma.$transaction([
      prisma.courierProfile.update({
        where: { userId: auth.sub },
        data: { lastLat: lat, lastLng: lng, lastSeenAt: new Date() },
      }),
      prisma.courierLocation.create({
        data: {
          courierId: auth.sub,
          orderId: profile.activeOrder,
          lat,
          lng,
        },
      }),
      // Reflect the courier position on the active order for tracking.
      ...(profile.activeOrder
        ? [
            prisma.order.updateMany({
              where: { id: profile.activeOrder, courierId: auth.sub },
              data: { courierLat: lat, courierLng: lng },
            }),
          ]
        : []),
    ]);
    return { ok: true };
  });

  app.get('/v1/couriers/assignments', async (request, reply) => {
    const auth = await authenticate(request, reply, config, ['courier']);
    if (!auth) return;
    const offers = await prisma.courierOffer.findMany({
      where: { courierId: auth.sub, status: 'pending', expiresAt: { gt: new Date() } },
      include: { order: { include: { store: true } } },
      orderBy: { createdAt: 'desc' },
    });
    return {
      items: offers.map((o) => ({
        id: o.id,
        orderId: o.orderId,
        orderNumber: o.order.number,
        storeName: o.order.store.name,
        address: o.order.deliveryAddress,
        feeTiyn: o.feeTiyn,
        distanceKm: o.distanceKm,
        expiresAt: o.expiresAt.toISOString(),
      })),
    };
  });

  app.post('/v1/couriers/assignments/:offerId/:action', async (request, reply) => {
    const auth = await authenticate(request, reply, config, ['courier']);
    if (!auth) return;
    const { offerId, action } = z
      .object({
        offerId: z.string().min(1),
        action: z.enum(['accept', 'reject']),
      })
      .parse(request.params);
    const offer = await prisma.courierOffer.findUnique({
      where: { id: offerId },
    });
    if (!offer || offer.courierId !== auth.sub || offer.status !== 'pending') {
      return reply.code(404).send({
        error: { code: 'OFFER_NOT_FOUND', message: 'Offer not found' },
      });
    }
    if (action === 'reject') {
      await prisma.courierOffer.update({
        where: { id: offerId },
        data: { status: 'rejected' },
      });
      return { ok: true };
    }
    await prisma.$transaction([
      prisma.courierOffer.update({
        where: { id: offerId },
        data: { status: 'accepted' },
      }),
      prisma.order.update({
        where: { id: offer.orderId },
        data: {
          courierId: auth.sub,
          courierName:
            (await prisma.user
              .findUnique({ where: { id: auth.sub }, select: { name: true } })
              .then((u) => u?.name)) ?? null,
          status: 'courier_assigned',
        },
      }),
      prisma.courierProfile.update({
        where: { userId: auth.sub },
        data: { status: 'busy', activeOrder: offer.orderId },
      }),
      prisma.orderStatusEntry.create({
        data: {
          orderId: offer.orderId,
          status: 'courier_assigned',
          actorId: auth.sub,
          actorRole: 'courier',
        },
      }),
    ]);
    return { ok: true };
  });

  app.post('/v1/couriers/orders/:orderId/status', async (request, reply) => {
    const auth = await authenticate(request, reply, config, ['courier']);
    if (!auth) return;
    const { orderId } = request.params as { orderId: string };
    const { status } = z
      .object({
        status: z.enum(['picked_up', 'delivering', 'delivered']),
      })
      .parse(request.body);
    const order = await prisma.order.findUnique({ where: { id: orderId } });
    if (!order || order.courierId !== auth.sub) {
      return reply.code(404).send({
        error: { code: 'ORDER_NOT_FOUND', message: 'Order not found' },
      });
    }
    await prisma.$transaction([
      prisma.order.update({ where: { id: orderId }, data: { status } }),
      prisma.orderStatusEntry.create({
        data: {
          orderId,
          status,
          actorId: auth.sub,
          actorRole: 'courier',
        },
      }),
      ...(status === 'delivered'
        ? [
            prisma.courierProfile.update({
              where: { userId: auth.sub },
              data: { status: 'online', activeOrder: null },
            }),
          ]
        : []),
    ]);
    return { ok: true };
  });
}
