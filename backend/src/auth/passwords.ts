import { randomBytes, scrypt, timingSafeEqual } from 'node:crypto';

const N = 16384;
const R = 8;
const P = 1;
const KEY_LEN = 64;

/**
 * Staff password hashing — scrypt with per-password salt.
 * Stored format: `scrypt$N$r$p$saltB64$hashB64`. No external dependency.
 */
export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const hash = await new Promise<Buffer>((resolve, reject) => {
    scrypt(password, salt, KEY_LEN, { N, r: R, p: P }, (err, key) =>
      err ? reject(err) : resolve(key),
    );
  });
  return `scrypt$${N}$${R}$${P}$${salt.toString('base64')}$${hash.toString('base64')}`;
}

export async function verifyPassword(
  password: string,
  stored: string,
): Promise<boolean> {
  const parts = stored.split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
  const [, n, r, p, saltB64, hashB64] = parts;
  const salt = Buffer.from(saltB64, 'base64');
  const expected = Buffer.from(hashB64, 'base64');
  const hash = await new Promise<Buffer>((resolve, reject) => {
    scrypt(
      password,
      salt,
      expected.length,
      { N: Number(n), r: Number(r), p: Number(p) },
      (err, key) => (err ? reject(err) : resolve(key)),
    );
  });
  return hash.length === expected.length && timingSafeEqual(hash, expected);
}
