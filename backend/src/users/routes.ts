import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../auth/guard.js';
import type { Config } from '../config.js';
import { prisma } from '../plugins/prisma.js';

const profileSchema = z.object({
  name: z.string().trim().min(1).max(80).optional(),
  avatarUrl: z.string().url().max(2048).nullable().optional(),
}).refine((value) => value.name !== undefined || value.avatarUrl !== undefined);

const publicUser = (user: {
  id: string;
  phone: string;
  email: string | null;
  name: string;
  avatarUrl: string | null;
  role: string;
}) => ({
  id: user.id,
  phone: user.phone,
  email: user.email,
  name: user.name,
  avatarUrl: user.avatarUrl,
  role: user.role,
});

export async function registerUserRoutes(app: FastifyInstance, config: Config): Promise<void> {
  app.get('/v1/users/me', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const user = await prisma.user.findUnique({ where: { id: auth.sub } });
    if (!user || user.deletedAt) {
      return reply.code(404).send({ error: { code: 'USER_NOT_FOUND', message: 'User not found' } });
    }
    return publicUser(user);
  });

  app.patch('/v1/users/me', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const input = profileSchema.parse(request.body);
    const user = await prisma.user.update({
      where: { id: auth.sub },
      data: input,
    });
    return publicUser(user);
  });

  app.delete('/v1/users/me', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    await prisma.$transaction([
      prisma.session.updateMany({
        where: { userId: auth.sub, revokedAt: null },
        data: { revokedAt: new Date() },
      }),
      prisma.user.update({
        where: { id: auth.sub },
        data: {
          deletedAt: new Date(),
          name: '',
          email: null,
          avatarUrl: null,
          phone: `deleted-${auth.sub}`,
        },
      }),
      prisma.auditLog.create({
        data: {
          actorId: auth.sub,
          actorRole: auth.role,
          action: 'account_deleted',
          resource: auth.sub,
          details: { result: 'success' },
        },
      }),
    ]);
    return reply.code(204).send();
  });
}
