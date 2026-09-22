import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { authenticate } from '../auth/guard.js';
import type { Config } from '../config.js';
import { prisma } from '../plugins/prisma.js';
import { PaymentService } from './payment-service.js';
import type { PaymentProviderAdapter } from './payment-provider.js';
import { createPaymentProvider } from './providers.js';

const idParams = z.object({ id: z.string().min(1) });
const confirmSchema = z.object({
  outcome: z.enum(['paid', 'failed']).default('paid'),
});

async function loadScopedPayment(
  paymentId: string,
  userId: string,
  role: string,
) {
  const payment = await prisma.payment.findUnique({
    where: { id: paymentId },
    include: { order: { select: { userId: true, status: true, number: true } } },
  });
  if (!payment) return null;
  const staff = role === 'manager' || role === 'admin';
  if (!staff && payment.order.userId !== userId) return null;
  return payment;
}

/// Marks a payment state server-side: transaction record, payment row,
/// notification + audit. Only callable after provider verification.
async function applyVerifiedState(
  app: FastifyInstance,
  provider: PaymentProviderAdapter,
  paymentId: string,
  verified: { externalId: string; status: 'paid' | 'failed' | 'refunded'; amountTiyn: number; providerPayload?: unknown },
  kind: 'capture' | 'fail' | 'refund' | 'webhook',
) {
  const payment = await prisma.payment.findUniqueOrThrow({
    where: { id: paymentId },
    include: { order: { select: { userId: true, number: true } } },
  });
  const service = new PaymentService(
    provider.id === 'kaspi' ? 'kaspi' : 'mock',
    provider,
  );
  await service.recordVerified(paymentId, {
    kind,
    idempotencyKey: `${kind}:${paymentId}:${verified.externalId}`,
    externalId: verified.externalId,
    amountTiyn: verified.amountTiyn,
    status: verified.status,
    providerPayload:
      verified.providerPayload !== undefined
        ? (verified.providerPayload as object)
        : undefined,
  });
  await prisma.payment.update({
    where: { id: paymentId },
    data: { status: verified.status, externalId: verified.externalId },
  });
  await prisma.auditLog.create({
    data: {
      actorId: payment.order.userId,
      actorRole: 'customer',
      action: `payment_${verified.status}`,
      resource: paymentId,
      details: { orderId: payment.orderId, amountTiyn: verified.amountTiyn },
    },
  });
  void app.notifications
    ?.send({
      userId: payment.order.userId,
      kind: 'order_status',
      title: `Order ${payment.order.number}`,
      body:
        verified.status === 'paid'
          ? 'Payment confirmed'
          : verified.status === 'refunded'
            ? 'Payment refunded'
            : 'Payment failed',
      orderId: payment.orderId,
    })
    .catch(() => {});
  return { id: paymentId, status: verified.status };
}

export async function registerPaymentRoutes(
  app: FastifyInstance,
  config: Config,
): Promise<void> {
  const provider = createPaymentProvider(config);

  // Payment state for the order owner or staff.
  app.get('/v1/payments/:id', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { id } = idParams.parse(request.params);
    const payment = await loadScopedPayment(id, auth.sub, auth.role);
    if (!payment) {
      return reply.code(404).send({
        error: { code: 'PAYMENT_NOT_FOUND', message: 'Payment not found' },
      });
    }
    return {
      id: payment.id,
      orderId: payment.orderId,
      provider: payment.provider,
      status: payment.status,
      amountTiyn: payment.amountTiyn,
    };
  });

  // Demo confirmation — only when PAYMENT_PROVIDER=mock. With a real
  // provider, `paid` arrives exclusively through the signed webhook.
  app.post('/v1/payments/:id/confirm', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    const { id } = idParams.parse(request.params);
    const { outcome } = confirmSchema.parse(request.body ?? {});

    const payment = await loadScopedPayment(id, auth.sub, auth.role);
    if (!payment) {
      return reply.code(404).send({
        error: { code: 'PAYMENT_NOT_FOUND', message: 'Payment not found' },
      });
    }
    if (payment.provider !== 'mock' || provider.id !== 'mock') {
      return reply.code(403).send({
        error: {
          code: 'PROVIDER_CONFIRM_REQUIRED',
          message: 'This payment is confirmed by the provider',
        },
      });
    }
    if (payment.status === 'paid' || payment.status === 'refunded') {
      return { id: payment.id, status: payment.status };
    }
    const externalId = `mock-${payment.id}`;
    return applyVerifiedState(app, provider, payment.id, {
      externalId,
      status: outcome,
      amountTiyn: payment.amountTiyn,
      providerPayload: { channel: 'client-demo' },
    }, outcome === 'paid' ? 'capture' : 'fail');
  });

  // Signed provider webhook. Raw body is required for HMAC verification.
  app.post('/v1/payments/webhook/:provider', async (request, reply) => {
    const { provider: providerId } = z
      .object({ provider: z.enum(['mock', 'kaspi']) })
      .parse(request.params);
    if (providerId !== provider.id) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND' } });
    }
    let verified;
    try {
      verified = await provider.verifyCallback(
        Buffer.from(JSON.stringify(request.body ?? {})),
        request.headers as Record<string, string | string[] | undefined>,
      );
    } catch (error) {
      const e = error as Error & { statusCode?: number };
      return reply.code(e.statusCode ?? 400).send({
        error: { code: 'WEBHOOK_INVALID', message: e.message },
      });
    }
    const payment = await prisma.payment.findFirst({
      where: { externalId: verified.externalId },
    });
    if (!payment) {
      return reply.code(404).send({
        error: { code: 'PAYMENT_NOT_FOUND', message: 'Payment not found' },
      });
    }
    if (payment.amountTiyn !== verified.amountTiyn) {
      return reply.code(409).send({
        error: { code: 'AMOUNT_MISMATCH', message: 'Amount mismatch' },
      });
    }
    return applyVerifiedState(app, provider, payment.id, verified, 'webhook');
  });

  // Refund — staff only, idempotent per payment.
  app.post('/v1/payments/:id/refund', async (request, reply) => {
    const auth = await authenticate(request, reply, config, ['manager', 'admin']);
    if (!auth) return;
    const { id } = idParams.parse(request.params);
    const payment = await prisma.payment.findUnique({ where: { id } });
    if (!payment) {
      return reply.code(404).send({
        error: { code: 'PAYMENT_NOT_FOUND', message: 'Payment not found' },
      });
    }
    if (payment.status !== 'paid') {
      return reply.code(409).send({
        error: { code: 'NOT_REFUNDABLE', message: 'Payment is not refundable' },
      });
    }
    const result = await provider.refund(
      payment.externalId ?? `mock-${payment.id}`,
      payment.amountTiyn,
      `refund:${payment.id}`,
    );
    await applyVerifiedState(app, provider, payment.id, result, 'refund');
    await prisma.auditLog.create({
      data: {
        actorId: auth.sub,
        actorRole: auth.role,
        action: 'payment_refund_issued',
        resource: payment.id,
        details: { amountTiyn: payment.amountTiyn },
      },
    });
    return { id: payment.id, status: 'refunded' };
  });
}
