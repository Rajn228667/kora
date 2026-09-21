import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import sensible from '@fastify/sensible';
import Fastify, { type FastifyInstance } from 'fastify';
import { ZodError } from 'zod';
import { registerAuthRoutes } from './auth/routes.js';
import { registerCatalogRoutes } from './catalog/routes.js';
import { registerAdminRoutes } from './admin/routes.js';
import { registerChatRoutes } from './chat/routes.js';
import { registerCommerceRoutes } from './commerce/routes.js';
import { registerCourierRoutes } from './courier/routes.js';
import { registerManagerRoutes } from './manager/routes.js';
import { registerSupportRoutes } from './support/routes.js';
import type { Config } from './config.js';
import { NotificationService } from './notifications/notification-service.js';
import { createPushChannel } from './notifications/push-provider.js';
import { registerNotificationRoutes } from './notifications/routes.js';
import { prisma } from './plugins/prisma.js';
import { registerRealtimeGateway } from './realtime/gateway.js';
import { registerUserRoutes } from './users/routes.js';

export async function buildApp(config: Config): Promise<FastifyInstance> {
  const app = Fastify({
    logger: {
      level: config.LOG_LEVEL,
      redact: ['req.headers.authorization', 'req.body.code', 'req.body.password', 'req.body.refreshToken'],
    },
    trustProxy: true,
    bodyLimit: 1_048_576,
  });

  await app.register(sensible);
  await app.register(helmet, { contentSecurityPolicy: false });
  await app.register(rateLimit, { max: config.RATE_LIMIT_MAX, timeWindow: '1 minute' });
  const origins = config.CORS_ORIGINS.split(',').map((value) => value.trim()).filter(Boolean);
  await app.register(cors, {
    origin: config.APP_ENV === 'development' && config.CORS_ORIGINS === '*'
      ? true
      : (origin, callback) => callback(null, !origin || origins.includes(origin)),
    credentials: false,
    methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE'],
  });

  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof ZodError) {
      return reply.code(400).send({
        error: { code: 'VALIDATION_ERROR', message: 'Invalid request', details: error.flatten() },
      });
    }
    const httpError = error as Error & { statusCode?: number };
    const statusCode = httpError.statusCode ?? 500;
    app.log.error(httpError);
    return reply.code(statusCode).send({
      error: {
        code: statusCode < 500 ? 'REQUEST_ERROR' : 'INTERNAL_ERROR',
        message: statusCode < 500 ? httpError.message : 'Internal server error',
      },
    });
  });

  app.get('/health', async () => ({ status: 'ok' }));
  app.get('/ready', async (_request, reply) => {
    try {
      await prisma.$queryRaw`SELECT 1`;
      return { status: 'ready' };
    } catch {
      return reply.code(503).send({ status: 'unavailable' });
    }
  });
  const pushChannel = createPushChannel(config);
  const notifications = new NotificationService(
    pushChannel ? [pushChannel] : [],
  );
  app.decorate('notifications', notifications);

  await registerAuthRoutes(app, config);
  await registerUserRoutes(app, config);
  await registerCatalogRoutes(app, config);
  await registerCommerceRoutes(app, config);
  await registerNotificationRoutes(app, config);
  await registerSupportRoutes(app, config);
  await registerChatRoutes(app, config);
  await registerCourierRoutes(app, config);
  await registerManagerRoutes(app, config);
  await registerAdminRoutes(app, config);
  await registerRealtimeGateway(app, config);
  return app;
}
