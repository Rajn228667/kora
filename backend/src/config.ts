import 'dotenv/config';
import { z } from 'zod';

const schema = z.object({
  APP_ENV: z.enum(['development', 'staging', 'production']).default('development'),
  HOST: z.string().default('0.0.0.0'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  DATABASE_URL: z.string().min(1),
  JWT_SECRET: z.string().min(32),
  JWT_ACCESS_TTL: z.coerce.number().int().min(60).default(900),
  JWT_REFRESH_TTL: z.coerce.number().int().min(3600).default(2592000),
  SMS_PROVIDER: z.enum(['dev', 'twilio', 'mobizon']).default('dev'),
  TWILIO_ACCOUNT_SID: z.string().optional(),
  TWILIO_AUTH_TOKEN: z.string().optional(),
  TWILIO_VERIFY_SERVICE_SID: z.string().optional(),
  MOBIZON_API_KEY: z.string().optional(),
  MOBIZON_SENDER: z.string().max(11).optional(),
  PUSH_PROVIDER: z.enum(['none', 'fcm']).default('none'),
  FCM_PROJECT_ID: z.string().optional(),
  FCM_CLIENT_EMAIL: z.string().optional(),
  FCM_PRIVATE_KEY: z.string().optional(),
  OTP_DEV_CODE: z.string().regex(/^\d{6}$/).optional(),
  OTP_TTL_SECONDS: z.coerce.number().int().min(60).max(900).default(300),
  OTP_MAX_ATTEMPTS: z.coerce.number().int().min(1).max(10).default(5),
  OTP_RESEND_SECONDS: z.coerce.number().int().min(30).default(60),
  OTP_RATE_LIMIT_PER_HOUR: z.coerce.number().int().min(1).default(10),
  CORS_ORIGINS: z.string().default(''),
  ADMIN_EMAIL: z.string().email().optional(),
  ADMIN_PASSWORD: z.string().min(6).optional(),
  RATE_LIMIT_MAX: z.coerce.number().int().min(10).default(300),
  RATE_LIMIT_AUTH_MAX: z.coerce.number().int().min(1).default(20),
  PAYMENT_PROVIDER: z.enum(['mock', 'kaspi']).default('mock'),
  MOCK_PAYMENTS_SECRET: z.string().min(8).optional(),
  KASPI_MERCHANT_ID: z.string().optional(),
  KASPI_SECRET_KEY: z.string().optional(),
});

export type Config = z.infer<typeof schema>;

export function loadConfig(): Config {
  const config = schema.parse(process.env);
  if (config.APP_ENV !== 'development' && config.SMS_PROVIDER === 'dev') {
    throw new Error('SMS_PROVIDER=dev is forbidden outside development');
  }
  if (
    config.SMS_PROVIDER === 'twilio' &&
    (!config.TWILIO_ACCOUNT_SID ||
      !config.TWILIO_AUTH_TOKEN ||
      !config.TWILIO_VERIFY_SERVICE_SID)
  ) {
    throw new Error(
      'SMS_PROVIDER=twilio requires TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_VERIFY_SERVICE_SID',
    );
  }
  if (config.SMS_PROVIDER === 'mobizon' && !config.MOBIZON_API_KEY) {
    throw new Error('SMS_PROVIDER=mobizon requires MOBIZON_API_KEY');
  }
  if (
    config.PUSH_PROVIDER === 'fcm' &&
    (!config.FCM_PROJECT_ID ||
      !config.FCM_CLIENT_EMAIL ||
      !config.FCM_PRIVATE_KEY)
  ) {
    throw new Error(
      'PUSH_PROVIDER=fcm requires FCM_PROJECT_ID, FCM_CLIENT_EMAIL and FCM_PRIVATE_KEY',
    );
  }
  if (config.APP_ENV === 'production' && (!config.CORS_ORIGINS || config.CORS_ORIGINS === '*')) {
    throw new Error('Production CORS_ORIGINS must be an explicit allowlist');
  }
  if (config.APP_ENV === 'production' && config.PAYMENT_PROVIDER === 'mock') {
    throw new Error('PAYMENT_PROVIDER=mock is forbidden in production');
  }
  if (config.PAYMENT_PROVIDER === 'kaspi' && (!config.KASPI_MERCHANT_ID || !config.KASPI_SECRET_KEY)) {
    throw new Error('PAYMENT_PROVIDER=kaspi requires KASPI_MERCHANT_ID and KASPI_SECRET_KEY');
  }
  if (config.APP_ENV !== 'development' && config.PAYMENT_PROVIDER === 'mock' && !config.MOCK_PAYMENTS_SECRET) {
    throw new Error('MOCK_PAYMENTS_SECRET is required outside development');
  }
  return config;
}
