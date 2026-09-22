import { describe, expect, it } from 'vitest';
import { hashPassword, verifyPassword } from '../src/auth/passwords.js';

describe('password hashing', () => {
  it('hashes and verifies a password (scrypt roundtrip)', async () => {
    const hash = await hashPassword('s3cret-password');
    expect(hash.startsWith('scrypt$')).toBe(true);
    expect(hash).not.toContain('s3cret-password');
    await expect(verifyPassword('s3cret-password', hash)).resolves.toBe(true);
  });

  it('rejects a wrong password', async () => {
    const hash = await hashPassword('correct-horse');
    await expect(verifyPassword('wrong-horse', hash)).resolves.toBe(false);
  });

  it('produces unique salts per password', async () => {
    const a = await hashPassword('same-input');
    const b = await hashPassword('same-input');
    expect(a).not.toBe(b);
  });

  it('rejects malformed stored hashes', async () => {
    await expect(verifyPassword('x', 'plain-text')).resolves.toBe(false);
    await expect(verifyPassword('x', 'scrypt$bad')).resolves.toBe(false);
  });
});
