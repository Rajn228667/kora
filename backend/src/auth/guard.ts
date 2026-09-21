import type { FastifyReply, FastifyRequest } from 'fastify';
import type { UserRole } from '@prisma/client';
import type { Config } from '../config.js';
import { prisma } from '../plugins/prisma.js';
import { verifyAccessToken, type AccessClaims } from './tokens.js';

export async function authenticate(
  request: FastifyRequest,
  reply: FastifyReply,
  config: Config,
  roles?: readonly UserRole[],
): Promise<AccessClaims | undefined> {
  const header = request.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    await reply.code(401).send({ error: { code: 'UNAUTHORIZED', message: 'Authentication required' } });
    return;
  }
  try {
    const claims = await verifyAccessToken(config, header.slice(7));
    const session = await prisma.session.findFirst({
      where: {
        id: claims.sessionId,
        userId: claims.sub,
        revokedAt: null,
        expiresAt: { gt: new Date() },
        user: { deletedAt: null },
      },
    });
    if (!session) throw new Error('Session revoked');
    if (roles && !roles.includes(claims.role)) {
      await reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Insufficient permission' } });
      return;
    }
    return claims;
  } catch {
    await reply.code(401).send({ error: { code: 'UNAUTHORIZED', message: 'Invalid session' } });
    return;
  }
}
