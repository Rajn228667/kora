import { createHmac, timingSafeEqual } from 'node:crypto';
import type { Config } from '../config.js';
import type {
  PaymentCreateInput,
  PaymentCreateResult,
  PaymentProviderAdapter,
  PaymentVerificationResult,
} from './payment-provider.js';

/// Demo provider — used when PAYMENT_PROVIDER=mock. Never accepts state from
/// the client; confirmations are HMAC-verified against MOCK_PAYMENTS_SECRET
/// so the web/app layer cannot self-sign a paid state.
export class MockPaymentAdapter implements PaymentProviderAdapter {
  readonly id = 'mock';

  constructor(private readonly secret: string) {}

  signature(payload: string): string {
    return createHmac('sha256', this.secret).update(payload).digest('hex');
  }

  create(input: PaymentCreateInput): Promise<PaymentCreateResult> {
    const externalId = `mock-${input.paymentId}`;
    return Promise.resolve({
      externalId,
      status: 'pending',
      redirectUrl: `kora://pay/${input.paymentId}`,
      providerPayload: { externalId },
    });
  }

  async verifyCallback(
    rawBody: Buffer,
    headers: Readonly<Record<string, string | string[] | undefined>>,
  ): Promise<PaymentVerificationResult> {
    const signature = headers['x-mock-signature'];
    const expected = this.signature(rawBody.toString('utf8'));
    const provided = Array.isArray(signature) ? signature[0] : signature;
    const ok =
      typeof provided === 'string' &&
      provided.length === expected.length &&
      timingSafeEqual(Buffer.from(provided), Buffer.from(expected));
    if (!ok) throw Object.assign(new Error('Invalid signature'), { statusCode: 401 });

    const body = JSON.parse(rawBody.toString('utf8')) as {
      externalId?: string;
      status?: string;
      amountTiyn?: number;
    };
    const status =
      body.status === 'paid'
        ? 'paid'
        : body.status === 'refunded'
          ? 'refunded'
          : 'failed';
    return Promise.resolve({
      externalId: body.externalId ?? '',
      status,
      amountTiyn: body.amountTiyn ?? 0,
      providerPayload: body,
    });
  }

  refund(externalId: string, amountTiyn: number): Promise<PaymentVerificationResult> {
    return Promise.resolve({ externalId, status: 'refunded', amountTiyn });
  }
}

/// Kaspi adapter placeholder — the real acquiring contract (merchant id,
/// signed payloads, refund API) is applied after onboarding. It refuses all
/// operations until configured, so a misconfigured deploy fails loudly
/// instead of silently marking payments.
export class KaspiPaymentAdapter implements PaymentProviderAdapter {
  readonly id = 'kaspi';

  private notConfigured(): never {
    throw Object.assign(new Error('Kaspi acquiring is not configured'), {
      statusCode: 503,
    });
  }

  create(): Promise<PaymentCreateResult> {
    this.notConfigured();
  }

  verifyCallback(): Promise<PaymentVerificationResult> {
    this.notConfigured();
  }

  refund(): Promise<PaymentVerificationResult> {
    this.notConfigured();
  }
}

export function createPaymentProvider(config: Config): PaymentProviderAdapter {
  if (config.PAYMENT_PROVIDER === 'kaspi') return new KaspiPaymentAdapter();
  return new MockPaymentAdapter(config.MOCK_PAYMENTS_SECRET ?? 'dev-secret');
}
