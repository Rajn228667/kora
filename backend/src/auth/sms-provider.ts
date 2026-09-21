import type { Config } from '../config.js';

export type OtpChannel = 'sms' | 'whatsapp';

export interface OtpProvider {
  readonly id: string;
  /**
   * When true the provider generates and validates the code itself
   * (e.g. Twilio Verify) — the backend never sees the OTP value.
   */
  readonly providerManaged: boolean;
  readonly channels: readonly OtpChannel[];
  sendOtp(phone: string, code: string, channel: OtpChannel): Promise<void>;
  checkOtp?(phone: string, code: string): Promise<boolean>;
}

class DevelopmentOtpProvider implements OtpProvider {
  readonly id = 'dev';
  readonly providerManaged = false;
  readonly channels = ['sms', 'whatsapp'] as const;

  async sendOtp(
    _phone: string,
    _code: string,
    _channel: OtpChannel,
  ): Promise<void> {
    // Deliberately no logging: phone numbers and OTP codes are personal data.
  }
}

/**
 * Twilio Verify — managed OTP delivery over SMS and WhatsApp.
 * Codes are generated, rate-limited and checked by Twilio; the backend
 * stores only the request record for audit and attempt counting.
 * Requires TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN / TWILIO_VERIFY_SERVICE_SID.
 */
class TwilioVerifyOtpProvider implements OtpProvider {
  readonly id = 'twilio';
  readonly providerManaged = true;
  readonly channels = ['sms', 'whatsapp'] as const;

  constructor(
    private readonly accountSid: string,
    private readonly authToken: string,
    private readonly verifyServiceSid: string,
  ) {}

  private async post(
    path: string,
    params: Record<string, string>,
  ): Promise<Record<string, unknown>> {
    const res = await fetch(
      `https://verify.twilio.com/v2/Services/${this.verifyServiceSid}/${path}`,
      {
        method: 'POST',
        headers: {
          Authorization:
            'Basic ' +
            Buffer.from(`${this.accountSid}:${this.authToken}`).toString(
              'base64',
            ),
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams(params),
        signal: AbortSignal.timeout(10_000),
      },
    );
    const data = (await res.json().catch(() => ({}))) as Record<
      string,
      unknown
    >;
    if (!res.ok) {
      const err = new Error(
        `Twilio Verify ${path} failed (${res.status})`,
      ) as Error & { httpStatus?: number };
      err.httpStatus = res.status;
      throw err;
    }
    return data;
  }

  async sendOtp(
    phone: string,
    _code: string,
    channel: OtpChannel,
  ): Promise<void> {
    await this.post('Verifications', { To: phone, Channel: channel });
  }

  async checkOtp(phone: string, code: string): Promise<boolean> {
    try {
      const data = await this.post('VerificationCheck', {
        To: phone,
        Code: code,
      });
      return data['status'] === 'approved';
    } catch (e) {
      // Twilio returns 404 for an unknown/incorrect verification code.
      if ((e as { httpStatus?: number }).httpStatus === 404) return false;
      throw e;
    }
  }
}

/**
 * Mobizon (mobizon.kz) — Kazakhstan SMS provider, self-managed codes.
 * WhatsApp is not supported; the route rejects that channel for this
 * provider. Requires MOBIZON_API_KEY, optional MOBIZON_SENDER alphaname.
 */
class MobizonOtpProvider implements OtpProvider {
  readonly id = 'mobizon';
  readonly providerManaged = false;
  readonly channels = ['sms'] as const;

  constructor(
    private readonly apiKey: string,
    private readonly sender?: string,
  ) {}

  async sendOtp(phone: string, code: string, _channel: OtpChannel): Promise<void> {
    const params = new URLSearchParams({
      apiKey: this.apiKey,
      recipient: phone.replace(/\D/g, ''),
      text: `KORA: ${code}`,
    });
    if (this.sender) params.set('from', this.sender);
    const res = await fetch(
      `https://api.mobizon.kz/service/message/sendSmsMessage?${params}`,
      { method: 'POST', signal: AbortSignal.timeout(10_000) },
    );
    const data = (await res.json().catch(() => ({}))) as {
      code?: number;
      message?: string;
    };
    if (!res.ok || data.code !== 0) {
      throw new Error(`Mobizon sendSmsMessage failed (${res.status})`);
    }
  }
}

class UnconfiguredOtpProvider implements OtpProvider {
  readonly providerManaged = false;
  readonly channels = ['sms', 'whatsapp'] as const;

  constructor(readonly id: string) {}

  async sendOtp(): Promise<void> {
    throw new Error(`OTP provider "${this.id}" is not configured`);
  }
}

export function createOtpProvider(config: Config): OtpProvider {
  switch (config.SMS_PROVIDER) {
    case 'dev':
      return new DevelopmentOtpProvider();
    case 'twilio':
      return new TwilioVerifyOtpProvider(
        config.TWILIO_ACCOUNT_SID!,
        config.TWILIO_AUTH_TOKEN!,
        config.TWILIO_VERIFY_SERVICE_SID!,
      );
    case 'mobizon':
      return new MobizonOtpProvider(
        config.MOBIZON_API_KEY!,
        config.MOBIZON_SENDER,
      );
    default:
      return new UnconfiguredOtpProvider(config.SMS_PROVIDER);
  }
}
