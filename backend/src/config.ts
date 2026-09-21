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
  SMS_PROVIDER: z.string().default('dev'),
  OTP_DEV_CODE: z.string().regex(/^\d{6}$/).optional(),
  OTP_TTL_SECONDS: z.coerce.number().int().min(60).max(900).default(300),
  OTP_MAX_ATTEMPTS: z.coerce.number().int().min(1).max(10).default(5),
  OTP_RESEND_SECONDS: z.coerce.number().int().min(30).default(60),
  OTP_RATE_LIMIT_PER_HOUR: z.coerce.number().int().min(1).default(10),
  CORS_ORIGINS: z.string().default(''),
  RATE_LIMIT_MAX: z.coerce.number().int().min(10).default(300),
  RATE_LIMIT_AUTH_MAX: z.coerce.number().int().min(1).default(20),
});

export type Config = z.infer<typeof schema>;

export function loadConfig(): Config {
  const config = schema.parse(process.env);
  if (config.APP_ENV !== 'development' && config.SMS_PROVIDER === 'dev') {
    throw new Error('SMS_PROVIDER=dev is forbidden outside development');
  }
  if (config.APP_ENV === 'production' && (!config.CORS_ORIGINS || config.CORS_ORIGINS === '*')) {
    throw new Error('Production CORS_ORIGINS must be an explicit allowlist');
  }
  return config;
}
