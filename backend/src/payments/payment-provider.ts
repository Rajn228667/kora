export interface PaymentCreateInput {
  paymentId: string;
  orderId: string;
  amountTiyn: number;
  idempotencyKey: string;
  callbackUrl: string;
}

export interface PaymentCreateResult {
  externalId: string;
  status: 'pending' | 'awaiting_confirmation';
  redirectUrl?: string;
  providerPayload?: unknown;
}

export interface PaymentVerificationResult {
  externalId: string;
  status: 'paid' | 'failed' | 'refunded';
  amountTiyn: number;
  providerPayload?: unknown;
}

/// Adapter boundary for an official acquiring contract. No provider URLs,
/// credentials or request shapes are guessed in core business logic.
export interface PaymentProviderAdapter {
  readonly id: string;
  create(input: PaymentCreateInput): Promise<PaymentCreateResult>;
  verifyCallback(rawBody: Buffer, headers: Readonly<Record<string, string | string[] | undefined>>):
    Promise<PaymentVerificationResult>;
  refund(externalId: string, amountTiyn: number, idempotencyKey: string):
    Promise<PaymentVerificationResult>;
}
