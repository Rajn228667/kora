import { createHash, randomBytes } from 'node:crypto';
import { SignJWT, jwtVerify } from 'jose';
import type { UserRole } from '@prisma/client';
import type { Config } from '../config.js';

export interface AccessClaims {
  sub: string;
  role: UserRole;
  sessionId: string;
}

const encoder = new TextEncoder();

export const hashToken = (value: string): string =>
  createHash('sha256').update(value).digest('hex');

export const newRefreshToken = (): string => randomBytes(48).toString('base64url');

export async function signAccessToken(
  config: Config,
  claims: AccessClaims,
): Promise<string> {
  return new SignJWT({ role: claims.role, sessionId: claims.sessionId })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setSubject(claims.sub)
    .setIssuer('kora-api')
    .setAudience('kora-app')
    .setIssuedAt()
    .setExpirationTime(`${config.JWT_ACCESS_TTL}s`)
    .sign(encoder.encode(config.JWT_SECRET));
}

export async function verifyAccessToken(
  config: Config,
  token: string,
): Promise<AccessClaims> {
  const { payload } = await jwtVerify(token, encoder.encode(config.JWT_SECRET), {
    issuer: 'kora-api',
    audience: 'kora-app',
  });
  if (!payload.sub || typeof payload.role !== 'string' || typeof payload.sessionId !== 'string') {
    throw new Error('Invalid access token claims');
  }
  return {
    sub: payload.sub,
    role: payload.role as UserRole,
    sessionId: payload.sessionId,
  };
}
