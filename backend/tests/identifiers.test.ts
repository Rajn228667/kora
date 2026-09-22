import { describe, expect, it } from 'vitest';
import { isValidGtin } from '../src/catalog/product-identifiers.js';

// EAN-13 check digit: digits * (1,3,1,3...) mod 10, (10 - sum%10) % 10.
describe('GTIN validation', () => {
  it('accepts a valid EAN-13', () => {
    // 460000000000 + check digit: sum = 4*1+6*3=22 → check 8
    expect(isValidGtin('4600000000008')).toBe(true);
  });

  it('rejects a wrong check digit', () => {
    expect(isValidGtin('4600000000000')).toBe(false);
  });

  it('rejects non-digit and wrong-length values', () => {
    expect(isValidGtin('abc')).toBe(false);
    expect(isValidGtin('12345')).toBe(false);
    expect(isValidGtin('')).toBe(false);
  });
});
