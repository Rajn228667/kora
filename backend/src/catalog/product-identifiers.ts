import { randomInt } from 'node:crypto';
import { prisma } from '../plugins/prisma.js';

const normalizeSlug = (value: string): string => value
  .normalize('NFKD')
  .toLowerCase()
  .replace(/[^a-z0-9а-яё]+/giu, '-')
  .replace(/^-|-$/g, '')
  .slice(0, 72) || 'product';

const checkDigit = (digits: string): string => {
  const sum = [...digits].reduce((total, digit, index) =>
    total + Number(digit) * (index % 2 === 0 ? 1 : 3), 0);
  return String((10 - (sum % 10)) % 10);
};

async function uniqueCandidate(
  field: 'sku' | 'article' | 'internalBarcode' | 'qrIdentifier' | 'slug',
  create: () => string,
): Promise<string> {
  for (let attempt = 0; attempt < 12; attempt++) {
    const candidate = create();
    const found = await prisma.product.findFirst({ where: { [field]: candidate }, select: { id: true } });
    if (!found) return candidate;
  }
  throw new Error(`Could not generate unique ${field}`);
}

export async function generateProductIdentifiers(name: string) {
  const slugBase = normalizeSlug(name);
  const slug = await uniqueCandidate('slug', () => `${slugBase}-${randomInt(1000, 10000)}`);
  const sku = await uniqueCandidate('sku', () => `KORA-${randomInt(10000000, 100000000)}`);
  const article = await uniqueCandidate('article', () => `ART-${randomInt(10000000, 100000000)}`);
  const internalBarcode = await uniqueCandidate('internalBarcode', () => {
    const body = `20${randomInt(1000000000, 10000000000)}`;
    return `${body}${checkDigit(body)}`;
  });
  const qrIdentifier = await uniqueCandidate(
    'qrIdentifier',
    () => `kora:product:${randomInt(100000000, 1000000000)}`,
  );
  return { slug, sku, article, internalBarcode, qrIdentifier };
}

/// Validates syntax/check digit only; it never claims registration with GS1.
export function isValidGtin(value: string): boolean {
  if (!/^\d{8}$|^\d{12,14}$/.test(value)) return false;
  return checkDigit(value.slice(0, -1)) === value.slice(-1);
}
