import type { Config } from '../config.js';

export interface SmsProvider {
  readonly id: string;
  sendOtp(phone: string, code: string): Promise<void>;
}

class DevelopmentSmsProvider implements SmsProvider {
  readonly id = 'dev';

  async sendOtp(_phone: string, _code: string): Promise<void> {
    // Deliberately no logging: phone numbers and OTP codes are personal data.
  }
}

class UnconfiguredSmsProvider implements SmsProvider {
  constructor(readonly id: string) {}

  async sendOtp(): Promise<void> {
    throw new Error(`SMS provider "${this.id}" is not configured`);
  }
}

export function createSmsProvider(config: Config): SmsProvider {
  if (config.SMS_PROVIDER === 'dev') return new DevelopmentSmsProvider();
  // Real providers are implemented here after contractual credentials and
  // official API documentation are supplied. Business logic stays unchanged.
  return new UnconfiguredSmsProvider(config.SMS_PROVIDER);
}
