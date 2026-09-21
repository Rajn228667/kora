import websocket from '@fastify/websocket';
import type { FastifyInstance } from 'fastify';
import type { WebSocket } from 'ws';
import { verifyAccessToken } from '../auth/tokens.js';
import type { Config } from '../config.js';
import { prisma } from '../plugins/prisma.js';

/**
 * Realtime gateway — `GET /v1/ws?token=<accessToken>`.
 * Event envelope matches the Flutter client: `{id?, type, data, ts}`.
 * Delivery is in-process; a Redis pub/sub fan-out can sit behind
 * [RealtimeHub] when the deployment scales to multiple nodes.
 */
export interface RealtimeHub {
  sendToUser(
    userId: string,
    type: string,
    data?: Record<string, unknown>,
  ): void;
}

class InProcessHub implements RealtimeHub {
  private readonly sockets = new Map<string, Set<WebSocket>>();

  add(userId: string, socket: WebSocket): void {
    let set = this.sockets.get(userId);
    if (!set) {
      set = new Set();
      this.sockets.set(userId, set);
    }
    set.add(socket);
    socket.on('close', () => {
      set.delete(socket);
      if (set.size === 0) this.sockets.delete(userId);
    });
  }

  sendToUser(
    userId: string,
    type: string,
    data: Record<string, unknown> = {},
  ): void {
    const frame = JSON.stringify({
      type,
      data,
      ts: new Date().toISOString(),
    });
    for (const socket of this.sockets.get(userId) ?? []) {
      if (socket.readyState === socket.OPEN) socket.send(frame);
    }
  }
}

declare module 'fastify' {
  interface FastifyInstance {
    realtime: RealtimeHub;
  }
}

export async function registerRealtimeGateway(
  app: FastifyInstance,
  config: Config,
): Promise<void> {
  await app.register(websocket);
  app.decorate('realtime', new InProcessHub());

  app.get('/v1/ws', { websocket: true }, (socket, request) => {
    const token = (request.query as { token?: string }).token;
    if (!token) {
      socket.close(4401, 'unauthorized');
      return;
    }
    void (async () => {
      try {
        const claims = await verifyAccessToken(config, token);
        const session = await prisma.session.findFirst({
          where: {
            id: claims.sessionId,
            userId: claims.sub,
            revokedAt: null,
            expiresAt: { gt: new Date() },
            user: { deletedAt: null, blockedAt: null },
          },
        });
        if (!session) {
          socket.close(4401, 'session expired');
          return;
        }
        app.realtime instanceof InProcessHub &&
          (app.realtime as InProcessHub).add(claims.sub, socket);
      } catch {
        socket.close(4401, 'invalid token');
      }
    })();
  });
}

/** Fans an order event out to the customer and the assigned courier. */
export async function emitOrderEvent(
  hub: RealtimeHub,
  orderId: string,
  type: string,
  data: Record<string, unknown> = {},
): Promise<void> {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    select: { userId: true, courierId: true },
  });
  if (!order) return;
  const payload = { orderId, ...data };
  hub.sendToUser(order.userId, type, payload);
  if (order.courierId) hub.sendToUser(order.courierId, type, payload);
}
