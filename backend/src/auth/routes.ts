import { createHash, randomInt, randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import type { Config } from '../config.js';
import { prisma } from '../plugins/prisma.js';
import { authenticate } from './guard.js';
import { createOtpProvider } from './sms-provider.js';
import { hashToken, newRefreshToken, signAccessToken } from './tokens.js';

const phoneSchema = z.string().regex(/^\+7[67]\d{9}$/, 'Invalid Kazakhstan mobile number');
const requestSchema = z.object({
  phone: phoneSchema,
  channel: z.enum(['sms', 'whatsapp']).default('sms'),
});
const verifySchema = z.object({
  requestId: z.string().min(1),
  phone: phoneSchema,
  code: z.string().regex(/^\d{6}$/),
});
const refreshSchema = z.object({ refreshToken: z.string().min(32) });

const otpHash = (requestId: string, code: string, secret: string): string =>
  createHash('sha256').update(`${requestId}:${code}:${secret}`).digest('hex');

const publicUser = (user: {
  id: string;
  phone: string;
  email: string | null;
  name: string;
  avatarUrl: string | null;
  role: string;
}) => ({
  id: user.id,
  phone: user.phone,
  email: user.email,
  name: user.name,
  avatarUrl: user.avatarUrl,
  role: user.role,
});

export async function registerAuthRoutes(app: FastifyInstance, config: Config): Promise<void> {
  const otpProvider = createOtpProvider(config);

  app.post('/v1/auth/request-otp', {
    config: { rateLimit: { max: config.RATE_LIMIT_AUTH_MAX, timeWindow: '1 minute' } },
  }, async (request, reply) => {
    const { phone, channel } = requestSchema.parse(request.body);
    if (!otpProvider.channels.includes(channel)) {
      return reply.code(400).send({
        error: {
          code: 'OTP_CHANNEL_UNSUPPORTED',
          message: `Channel "${channel}" is not supported`,
        },
      });
    }
    const hourAgo = new Date(Date.now() - 3_600_000);
    const recentCount = await prisma.otpRequest.count({
      where: { phone, createdAt: { gte: hourAgo } },
    });
    if (recentCount >= config.OTP_RATE_LIMIT_PER_HOUR) {
      return reply.code(429).send({
        error: { code: 'OTP_RATE_LIMIT', message: 'Too many OTP requests' },
      });
    }
    const previous = await prisma.otpRequest.findFirst({
      where: { phone },
      orderBy: { createdAt: 'desc' },
    });
    if (previous && Date.now() - previous.createdAt.getTime() < config.OTP_RESEND_SECONDS * 1000) {
      return reply.code(429).send({
        error: { code: 'OTP_RESEND_WAIT', message: 'Wait before requesting another code' },
      });
    }

    const requestId = randomUUID();
    // Provider-managed OTPs (Twilio Verify) are generated remotely — the
    // code never exists in our database.
    const code = otpProvider.providerManaged
      ? ''
      : config.SMS_PROVIDER === 'dev' && config.OTP_DEV_CODE
        ? config.OTP_DEV_CODE
        : randomInt(100000, 1000000).toString();
    await prisma.otpRequest.create({
      data: {
        id: requestId,
        phone,
        codeHash: otpProvider.providerManaged
          ? 'provider'
          : otpHash(requestId, code, config.JWT_SECRET),
        expiresAt: new Date(Date.now() + config.OTP_TTL_SECONDS * 1000),
      },
    });
    await otpProvider.sendOtp(phone, code, channel);
    return reply.code(202).send({
      requestId,
      channel,
      ttlSeconds: config.OTP_TTL_SECONDS,
      ...(config.APP_ENV === 'development' && config.SMS_PROVIDER === 'dev'
        ? { devOtp: code }
        : {}),
    });
  });

  app.post('/v1/auth/verify-otp', async (request, reply) => {
    const input = verifySchema.parse(request.body);
    const otp = await prisma.otpRequest.findUnique({ where: { id: input.requestId } });
    if (!otp || otp.phone !== input.phone || otp.verifiedAt || otp.expiresAt <= new Date()) {
      return reply.code(400).send({ error: { code: 'OTP_INVALID', message: 'OTP is invalid or expired' } });
    }
    if (otp.attempts >= config.OTP_MAX_ATTEMPTS) {
      return reply.code(429).send({ error: { code: 'OTP_ATTEMPTS_EXCEEDED', message: 'OTP attempts exceeded' } });
    }
    const valid = otpProvider.providerManaged
      ? await otpProvider.checkOtp!(input.phone, input.code)
      : otp.codeHash === otpHash(otp.id, input.code, config.JWT_SECRET);
    if (!valid) {
      await prisma.otpRequest.update({ where: { id: otp.id }, data: { attempts: { increment: 1 } } });
      return reply.code(400).send({ error: { code: 'OTP_INVALID', message: 'OTP is invalid or expired' } });
    }

    const result = await prisma.$transaction(async (tx) => {
      await tx.otpRequest.update({ where: { id: otp.id }, data: { verifiedAt: new Date() } });
      const existing = await tx.user.findUnique({ where: { phone: input.phone } });
      const user = existing ?? await tx.user.create({
        data: {
          phone: input.phone,
          referralCode: randomUUID().replaceAll('-', '').slice(0, 10).toUpperCase(),
        },
      });
      const refreshToken = newRefreshToken();
      const session = await tx.session.create({
        data: {
          userId: user.id,
          refreshTokenHash: hashToken(refreshToken),
          ip: request.ip,
          device: String(request.headers['user-agent'] ?? '').slice(0, 250),
          expiresAt: new Date(Date.now() + config.JWT_REFRESH_TTL * 1000),
        },
      });
      return { user, session, refreshToken, isNewUser: !existing };
    });
    const accessToken = await signAccessToken(config, {
      sub: result.user.id,
      role: result.user.role,
      sessionId: result.session.id,
    });
    return {
      user: publicUser(result.user),
      accessToken,
      refreshToken: result.refreshToken,
      isNewUser: result.isNewUser,
    };
  });

  app.post('/v1/auth/logout', async (request, reply) => {
    const auth = await authenticate(request, reply, config);
    if (!auth) return;
    await prisma.session.update({
      where: { id: auth.sessionId },
      data: { revokedAt: new Date() },
    });
    return reply.code(204).send();
  });

  app.post('/v1/auth/refresh', async (request, reply) => {
    const { refreshToken } = refreshSchema.parse(request.body);
    const session = await prisma.session.findUnique({
      where: { refreshTokenHash: hashToken(refreshToken) },
      include: { user: true },
    });
    if (!session || session.revokedAt || session.expiresAt <= new Date() || session.user.deletedAt) {
      return reply.code(401).send({ error: { code: 'SESSION_INVALID', message: 'Session expired' } });
    }
    const rotated = newRefreshToken();
    await prisma.session.update({
      where: { id: session.id },
      data: { refreshTokenHash: hashToken(rotated) },
    });
    const accessToken = await signAccessToken(config, {
      sub: session.user.id,
      role: session.user.role,
      sessionId: session.id,
    });
    return { accessToken, refreshToken: rotated };
  });
}
