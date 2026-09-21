import type { PaymentProvider, PaymentStatus, PaymentTxnKind } from '@prisma/client';
import { prisma } from '../plugins/prisma.js';
import type { PaymentProviderAdapter } from './payment-provider.js';

export class PaymentService {
  constructor(
    private readonly providerName: PaymentProvider,
    private readonly provider: PaymentProviderAdapter,
  ) {}

  async create(paymentId: string, callbackUrl: string, idempotencyKey: string) {
    const existing = await prisma.paymentTransaction.findUnique({ where: { idempotencyKey } });
    if (existing) return existing;
    const payment = await prisma.payment.findUniqueOrThrow({ where: { id: paymentId } });
    const result = await this.provider.create({
      paymentId,
      orderId: payment.orderId,
      amountTiyn: payment.amountTiyn,
      idempotencyKey,
      callbackUrl,
    });
    return prisma.$transaction(async (tx) => {
      const transaction = await tx.paymentTransaction.create({
        data: {
          paymentId,
          kind: 'create',
          idempotencyKey,
          externalId: result.externalId,
          amountTiyn: payment.amountTiyn,
          status: result.status,
          providerPayload: result.providerPayload ?? undefined,
        },
      });
      await tx.payment.update({
        where: { id: paymentId },
        data: {
          provider: this.providerName,
          externalId: result.externalId,
          status: result.status,
        },
      });
      return transaction;
    });
  }

  async recordVerified(
    paymentId: string,
    input: {
      kind: PaymentTxnKind;
      idempotencyKey: string;
      externalId: string;
      amountTiyn: number;
      status: PaymentStatus;
      providerPayload?: object;
    },
  ) {
    return prisma.paymentTransaction.upsert({
      where: { idempotencyKey: input.idempotencyKey },
      create: { paymentId, ...input },
      update: {},
    });
  }
}
