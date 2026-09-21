import { describe, expect, it } from 'vitest';
import { hashToken, newRefreshToken, signAccessToken, verifyAccessToken } from '../src/auth/tokens.js';
import type { Config } from '../src/config.js';

const config = {
  JWT_SECRET: 'test-secret-with-more-than-thirty-two-characters',
  JWT_ACCESS_TTL: 900,
} as Config;

describe('auth tokens', () => {
  it('signs and verifies scoped access claims', async () => {
    const token = await signAccessToken(config, {
      sub: 'user-1',
      role: 'customer',
      sessionId: 'session-1',
    });
    await expect(verifyAccessToken(config, token)).resolves.toEqual({
      sub: 'user-1',
      role: 'customer',
      sessionId: 'session-1',
    });
  });

  it('generates high-entropy refresh tokens and deterministic hashes', () => {
    const first = newRefreshToken();
    const second = newRefreshToken();
    expect(first).not.toBe(second);
    expect(first.length).toBeGreaterThan(50);
    expect(hashToken(first)).toBe(hashToken(first));
    expect(hashToken(first)).not.toBe(first);
  });
});
