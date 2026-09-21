import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../auth/guard.js';
import type { Config } from '../config.js';
import { prisma } from '../plugins/prisma.js';
import { emitOrderEvent } from '../realtime/gateway.js';

const messageJson = (
  m: {
    id: string;
    roomId: string;
    senderId: string;
    kind: string;
    body: string;
    mediaUrl: string | null;
    readAt: Date | null;
    createdAt: Date;
  },
  lat?: number | null,
  lng?: number | null,
) => ({
  id: m.id,
  roomId: m.roomId,
  senderId: m.senderId,
  type: m.kind,
  text: m.body || undefined,
  mediaUrl: m.mediaUrl,
  lat,
  lng,
  read: m.readAt !== null,
  at: m.createdAt.toISOString(),
});

export async function registerChatRoutes(
  app: FastifyInstance,
  config: Config,
): Promise<void> {
  // Room for an order — created at checkout; participants: customer, courier,
  // store staff.
  app.get('/v1/chat/rooms', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { orderId } = z
      .object({ orderId: z.string().min(1) })
      .parse(request.query);
    const order = await prisma.order.findUnique({ where: { id: orderId } });
    if (!order) return { items: [] };
    const participant =
      order.userId === auth.sub ||
      order.courierId === auth.sub ||
      auth.role === 'manager' ||
      auth.role === 'admin';
    if (!participant) return { items: [] };
    const room =
      (await prisma.chatRoom.findUnique({ where: { orderId } })) ??
      (await prisma.chatRoom.create({ data: { orderId } }));
    const peer = await prisma.user.findUnique({
      where: {
        id: order.userId === auth.sub ? (order.courierId ?? '') : order.userId,
      },
      select: { name: true },
    });
    const unread = await prisma.chatMessage.count({
      where: { roomId: room.id, senderId: { not: auth.sub }, readAt: null },
    });
    return {
      items: [
        {
          id: room.id,
          orderId: room.orderId,
          title: `Order ${order.number}`,
          peerName: peer?.name || order.courierName || null,
          unread,
        },
      ],
    };
  });

  app.get('/v1/chat/rooms/:id/messages', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { id } = request.params as { id: string };
    const room = await prisma.chatRoom.findUnique({ where: { id } });
    if (!room) {
      return reply.code(404).send({
        error: { code: 'ROOM_NOT_FOUND', message: 'Chat room not found' },
      });
    }
    const order = await prisma.order.findUnique({
      where: { id: room.orderId },
    });
    if (
      !order ||
      (order.userId !== auth.sub &&
        order.courierId !== auth.sub &&
        auth.role === 'customer')
    ) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'Not a participant' },
      });
    }
    const messages = await prisma.chatMessage.findMany({
      where: { roomId: id },
      orderBy: { createdAt: 'asc' },
      take: 200,
    });
    return { items: messages.map((m) => messageJson(m)) };
  });

  app.post('/v1/chat/rooms/:id/messages', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { id } = request.params as { id: string };
    const input = z
      .object({
        type: z.enum(['text', 'image', 'location']).default('text'),
        text: z.string().trim().max(4000).optional(),
        mediaUrl: z.string().max(2048).optional(),
        lat: z.number().optional(),
        lng: z.number().optional(),
      })
      .parse(request.body);
    const room = await prisma.chatRoom.findUnique({ where: { id } });
    if (!room) {
      return reply.code(404).send({
        error: { code: 'ROOM_NOT_FOUND', message: 'Chat room not found' },
      });
    }
    const order = await prisma.order.findUnique({
      where: { id: room.orderId },
    });
    if (
      !order ||
      (order.userId !== auth.sub &&
        order.courierId !== auth.sub &&
        !['manager', 'admin'].includes(auth.role))
    ) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'Not a participant' },
      });
    }
    const message = await prisma.chatMessage.create({
      data: {
        roomId: id,
        senderId: auth.sub,
        kind: input.type,
        body:
          input.type === 'location'
            ? `${input.lat},${input.lng}`
            : (input.text ?? ''),
        mediaUrl: input.mediaUrl ?? null,
      },
    });
    const json = messageJson(message, input.lat ?? null, input.lng ?? null);
    void emitOrderEvent(app.realtime, room.orderId, 'chat.message_created', {
      roomId: id,
      message: json as unknown as Record<string, unknown>,
    }).catch(() => {});
    return reply.code(201).send(json);
  });

  app.post('/v1/chat/rooms/:id/read', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { id } = request.params as { id: string };
    await prisma.chatMessage.updateMany({
      where: { roomId: id, senderId: { not: auth.sub }, readAt: null },
      data: { readAt: new Date() },
    });
    return { ok: true };
  });

  // Typing indicators are ephemeral realtime events; the endpoint exists so
  // polling clients don't break — the WebSocket fan-out is attached to the
  // realtime gateway.
  app.post('/v1/chat/rooms/:id/typing', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    return { ok: true };
  });
}
