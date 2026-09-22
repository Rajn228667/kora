import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../auth/guard.js';
import { hashPassword, verifyPassword } from '../auth/passwords.js';
import type { Config } from '../config.js';
import { prisma } from '../plugins/prisma.js';

const PROFILE_BGS = ['lavender', 'white', 'purple', 'mist'] as const;

const profileSchema = z.object({
  name: z.string().trim().min(1).max(80).optional(),
  lastName: z.string().trim().min(1).max(80).optional(),
  nickname: z
    .string()
    .trim()
    .regex(/^[a-zA-Z0-9_]{2,30}$/, 'Nickname: letters, digits, underscore')
    .nullable()
    .optional(),
  profileBg: z.enum(PROFILE_BGS).optional(),
  email: z.string().email().max(254).nullable().optional(),
  avatarUrl: z
    .union([
      z.string().url().max(2048),
      z.string().regex(/^\/v1\/media\//),
    ])
    .nullable()
    .optional(),
  acceptTerms: z.literal(true).optional(),
  acceptPrivacy: z.literal(true).optional(),
}).refine(
  (v) => Object.values(v).some((x) => x !== undefined),
);

const addressSchema = z.object({
  label: z.string().trim().min(1).max(60),
  address: z.string().trim().min(1).max(300),
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  comment: z.string().trim().max(500).optional(),
});

const addressJson = (a: {
  id: string;
  label: string;
  address: string;
  lat: number;
  lng: number;
  comment: string | null;
  isDefault: boolean;
}) => ({
  id: a.id,
  label: a.label,
  address: a.address,
  lat: a.lat,
  lng: a.lng,
  comment: a.comment,
  isDefault: a.isDefault,
});

const publicUser = (user: {
  id: string;
  phone: string;
  email: string | null;
  name: string;
  lastName?: string;
  nickname?: string | null;
  profileBg?: string;
  avatarUrl: string | null;
  role: string;
}) => ({
  id: user.id,
  phone: user.phone,
  email: user.email,
  name: user.name,
  lastName: user.lastName ?? '',
  nickname: user.nickname ?? null,
  profileBg: user.profileBg ?? 'lavender',
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
    if (input.email) {
      const taken = await prisma.user.findFirst({
        where: { email: input.email, id: { not: auth.sub } },
      });
      if (taken) {
        return reply.code(409).send({
          error: { code: 'EMAIL_TAKEN', message: 'Email already registered' },
        });
      }
    }
    const { acceptTerms, acceptPrivacy, ...fields } = input;
    const now = new Date();
    const user = await prisma.user.update({
      where: { id: auth.sub },
      data: {
        ...fields,
        ...(acceptTerms ? { acceptedTermsAt: now } : {}),
        ...(acceptPrivacy ? { acceptedPrivacyAt: now } : {}),
      },
    });
    return publicUser(user);
  });

  // Set or change account password. When a password already exists the
  // current one must be supplied — prevents session-token-only takeover.
  app.post('/v1/users/me/password', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const input = z
      .object({
        currentPassword: z.string().min(1).max(200).optional(),
        newPassword: z.string().min(8).max(200),
      })
      .parse(request.body);
    const user = await prisma.user.findUniqueOrThrow({
      where: { id: auth.sub },
    });
    if (user.passwordHash) {
      const ok = input.currentPassword
        ? await verifyPassword(input.currentPassword, user.passwordHash)
        : false;
      if (!ok) {
        return reply.code(403).send({
          error: { code: 'PASSWORD_MISMATCH', message: 'Current password is wrong' },
        });
      }
    }
    const passwordHash = await hashPassword(input.newPassword);
    await prisma.$transaction([
      prisma.user.update({ where: { id: auth.sub }, data: { passwordHash } }),
      prisma.auditLog.create({
        data: {
          actorId: auth.sub,
          actorRole: auth.role,
          action: user.passwordHash ? 'password_changed' : 'password_set',
          resource: auth.sub,
          details: {},
        },
      }),
    ]);
    return { ok: true };
  });

  app.delete('/v1/users/me', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const input = z
      .object({ password: z.string().min(1).max(200).optional() })
      .parse(request.body ?? {});

    const user = await prisma.user.findUniqueOrThrow({
      where: { id: auth.sub },
    });
    // Re-authentication: accounts with a password must confirm it.
    if (user.passwordHash) {
      const ok = input.password
        ? await verifyPassword(input.password, user.passwordHash)
        : false;
      if (!ok) {
        return reply.code(403).send({
          error: { code: 'PASSWORD_REQUIRED', message: 'Password confirmation required' },
        });
      }
    }
    // Active orders block deletion — they carry legal/delivery obligations.
    const activeOrders = await prisma.order.count({
      where: {
        userId: auth.sub,
        status: {
          in: [
            'pending',
            'accepted',
            'preparing',
            'ready_for_pickup',
            'courier_assigned',
            'picked_up',
            'delivering',
          ],
        },
      },
    });
    if (activeOrders > 0) {
      return reply.code(409).send({
        error: {
          code: 'ACCOUNT_HAS_ACTIVE_ORDERS',
          message: 'Finish or cancel active orders first',
        },
      });
    }
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

  // ── Addresses ──
  app.get('/v1/users/me/addresses', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const items = await prisma.address.findMany({
      where: { userId: auth.sub },
      orderBy: { createdAt: 'desc' },
    });
    return { items: items.map(addressJson) };
  });

  app.post('/v1/users/me/addresses', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const input = addressSchema.parse(request.body);
    const count = await prisma.address.count({ where: { userId: auth.sub } });
    const created = await prisma.address.create({
      data: { ...input, userId: auth.sub, isDefault: count === 0 },
    });
    return reply.code(201).send(addressJson(created));
  });

  app.delete('/v1/users/me/addresses/:id', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { id } = request.params as { id: string };
    await prisma.address.deleteMany({
      where: { id, userId: auth.sub },
    });
    return reply.code(204).send();
  });

  // ── Favorites ──
  app.get('/v1/users/me/favorites', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const favs = await prisma.favorite.findMany({
      where: { userId: auth.sub, storeId: { not: null } },
      orderBy: { createdAt: 'desc' },
    });
    const stores = await prisma.store.findMany({
      where: { id: { in: favs.map((f) => f.storeId!) } },
      include: { schedule: true },
    });
    return { items: stores.map((s) => ({ ...s, isOpen: s.active })) };
  });

  app.post('/v1/users/me/favorites', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { storeId } = z
      .object({ storeId: z.string().min(1) })
      .parse(request.body);
    const exists = await prisma.favorite.findFirst({
      where: { userId: auth.sub, storeId },
    });
    if (!exists) {
      await prisma.favorite.create({ data: { userId: auth.sub, storeId } });
    }
    return { ok: true };
  });

  app.delete('/v1/users/me/favorites/:storeId', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { storeId } = request.params as { storeId: string };
    await prisma.favorite.deleteMany({
      where: { userId: auth.sub, storeId },
    });
    return reply.code(204).send();
  });

  app.get('/v1/users/me/favorites/products', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const favs = await prisma.favorite.findMany({
      where: { userId: auth.sub, productId: { not: null } },
      orderBy: { createdAt: 'desc' },
    });
    const products = await prisma.product.findMany({
      where: { id: { in: favs.map((f) => f.productId!) }, active: true },
    });
    return { items: products };
  });

  app.post('/v1/users/me/favorites/products', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { productId } = z
      .object({ productId: z.string().min(1) })
      .parse(request.body);
    const exists = await prisma.favorite.findFirst({
      where: { userId: auth.sub, productId },
    });
    if (!exists) {
      await prisma.favorite.create({ data: { userId: auth.sub, productId } });
    }
    return { ok: true };
  });

  app.delete(
    '/v1/users/me/favorites/products/:productId',
    async (request, reply) => {
      const auth = await authenticate(request, reply, config);
      if (!auth) return;
      const { productId } = request.params as { productId: string };
      await prisma.favorite.deleteMany({
        where: { userId: auth.sub, productId },
      });
      return reply.code(204).send();
    },
  );

  // ── Recently viewed ──
  app.get('/v1/users/me/recently-viewed', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const views = await prisma.recentlyViewed.findMany({
      where: { userId: auth.sub },
      orderBy: { viewedAt: 'desc' },
      take: 30,
    });
    const products = await prisma.product.findMany({
      where: { id: { in: views.map((v) => v.productId) }, active: true },
    });
    const byId = new Map(products.map((p) => [p.id, p]));
    return {
      items: views
        .map((v) => byId.get(v.productId))
        .filter((p) => p !== undefined),
    };
  });

  app.post('/v1/users/me/recently-viewed', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { productId } = z
      .object({ productId: z.string().min(1) })
      .parse(request.body);
    await prisma.recentlyViewed.upsert({
      where: { userId_productId: { userId: auth.sub, productId } },
      create: { userId: auth.sub, productId },
      update: { viewedAt: new Date() },
    });
    return { ok: true };
  });

  // ── Sessions ──
  app.get('/v1/users/me/sessions', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const sessions = await prisma.session.findMany({
      where: { userId: auth.sub, revokedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });
    return {
      items: sessions.map((s) => ({
        id: s.id,
        device: s.device,
        createdAt: s.createdAt.toISOString(),
        current: s.id === auth.sessionId,
      })),
    };
  });

  // Revoke a single session (other device) — ownership enforced by userId.
  app.post('/v1/users/me/sessions/:id/revoke', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { id } = request.params as { id: string };
    await prisma.session.updateMany({
      where: { id, userId: auth.sub },
      data: { revokedAt: new Date() },
    });
    return { ok: true };
  });

  // Logout all devices except the current session.
  app.post('/v1/users/me/sessions/revoke-all', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    await prisma.session.updateMany({
      where: {
        userId: auth.sub,
        revokedAt: null,
        id: { not: auth.sessionId },
      },
      data: { revokedAt: new Date() },
    });
    return { ok: true };
  });

  // ── Wallet & referral ──
  app.get('/v1/users/me/wallet', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const wallet = await prisma.walletAccount.upsert({
      where: { userId: auth.sub },
      create: { userId: auth.sub },
      update: {},
      include: { txns: true },
    });
    const earned = wallet.txns
      .filter((t) => t.amountTiyn > 0)
      .reduce((s, t) => s + t.amountTiyn, 0);
    const spent = wallet.txns
      .filter((t) => t.amountTiyn < 0)
      .reduce((s, t) => s - t.amountTiyn, 0);
    return {
      balanceTiyn: wallet.balanceTiyn,
      earnedTiyn: earned,
      spentTiyn: spent,
    };
  });

  app.get('/v1/users/me/wallet/transactions', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const txns = await prisma.walletTransaction.findMany({
      where: { accountId: auth.sub },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return {
      items: txns.map((t) => ({
        id: t.id,
        kind: t.kind,
        amountTiyn: t.amountTiyn,
        title: t.title,
        orderId: t.orderId,
        createdAt: t.createdAt.toISOString(),
      })),
    };
  });

  app.get('/v1/users/me/referral', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const user = await prisma.user.findUniqueOrThrow({
      where: { id: auth.sub },
      select: { referralCode: true, referrals: { select: { id: true } } },
    });
    const bonus = await prisma.walletTransaction.aggregate({
      where: { accountId: auth.sub, kind: 'referral_bonus' },
      _sum: { amountTiyn: true },
    });
    return {
      code: user.referralCode,
      invited: user.referrals.length,
      bonusTiyn: bonus._sum.amountTiyn ?? 0,
    };
  });
}
