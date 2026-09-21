import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../auth/guard.js';
import type { Config } from '../config.js';
import { prisma } from '../plugins/prisma.js';

const deviceSchema = z.object({
  token: z.string().min(10).max(512),
  platform: z.enum(['android', 'ios', 'web']),
});

const prefsSchema = z.record(z.string(), z.boolean());

export async function registerNotificationRoutes(
  app: FastifyInstance,
  config: Config,
): Promise<void> {
  app.get('/v1/notifications', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const items = await prisma.notification.findMany({
      where: { userId: auth.sub },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return {
      items: items.map((n) => ({
        id: n.id,
        title: n.title,
        body: n.body,
        kind: n.kind,
        orderId: n.orderId,
        read: n.readAt !== null,
        at: n.createdAt.toISOString(),
      })),
    };
  });

  app.post('/v1/notifications/read', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    await prisma.notification.updateMany({
      where: { userId: auth.sub, readAt: null },
      data: { readAt: new Date() },
    });
    return { ok: true };
  });

  app.get('/v1/notifications/preferences', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const user = await prisma.user.findUniqueOrThrow({
      where: { id: auth.sub },
      select: { notificationPrefs: true },
    });
    return { preferences: user.notificationPrefs ?? {} };
  });

  app.post('/v1/notifications/preferences', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const prefs = prefsSchema.parse(request.body);
    await prisma.user.update({
      where: { id: auth.sub },
      data: { notificationPrefs: prefs },
    });
    return { ok: true };
  });

  app.post('/v1/users/me/devices', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { token, platform } = deviceSchema.parse(request.body);
    await prisma.deviceToken.upsert({
      where: { token },
      create: { token, platform, userId: auth.sub },
      update: { userId: auth.sub, platform, lastSeenAt: new Date() },
    });
    return { ok: true };
  });

  app.delete('/v1/users/me/devices/:token', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { token } = request.params as { token: string };
    await prisma.deviceToken.deleteMany({
      where: { token, userId: auth.sub },
    });
    return reply.code(204).send();
  });
}
