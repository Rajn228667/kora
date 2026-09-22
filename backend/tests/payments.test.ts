import { describe, expect, it } from 'vitest';
import { MockPaymentAdapter } from '../src/payments/providers.js';

const adapter = new MockPaymentAdapter('test-secret');

describe('mock payment provider', () => {
  it('creates a pending payment with an external id', async () => {
    const result = await adapter.create({
      paymentId: 'p1',
      orderId: 'o1',
      amountTiyn: 1000,
      idempotencyKey: 'k1',
      callbackUrl: 'https://example.test/webhook',
    });
    expect(result.status).toBe('pending');
    expect(result.externalId).toBe('mock-p1');
  });

  it('verifies a signed webhook payload', async () => {
    const body = JSON.stringify({
      externalId: 'mock-p1',
      status: 'paid',
      amountTiyn: 1000,
    });
    const signature = adapter.signature(body);
    const result = await adapter.verifyCallback(Buffer.from(body), {
      'x-mock-signature': signature,
    });
    expect(result.status).toBe('paid');
    expect(result.amountTiyn).toBe(1000);
  });

  it('rejects a webhook with a bad signature', async () => {
    const body = JSON.stringify({ externalId: 'x', status: 'paid', amountTiyn: 1 });
    await expect(
      adapter.verifyCallback(Buffer.from(body), { 'x-mock-signature': 'bad' }),
    ).rejects.toMatchObject({ statusCode: 401 });
  });
});
