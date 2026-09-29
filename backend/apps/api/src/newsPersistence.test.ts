import { describe, expect, it } from 'vitest';
import { chunk, fingerprintRecord, takeChangedRecords } from './newsPersistence.js';

describe('takeChangedRecords', () => {
  it('skips records identical to the last write and remembers new ones', () => {
    const lastWritten = new Map<string, string>();
    const a = { key: 'f::1', title: 'One', publishedMs: 5n, isMatch: false };
    const b = { key: 'f::2', title: 'Two', publishedMs: 6n, isMatch: true };

    expect(takeChangedRecords([a, b], lastWritten)).toEqual([a, b]);
    expect(takeChangedRecords([{ ...a }, { ...b }], lastWritten)).toEqual([]);

    const flipped = { ...a, isMatch: true };
    expect(takeChangedRecords([flipped, b], lastWritten)).toEqual([flipped]);
  });

  it('writes again after the caller forgets a failed key', () => {
    const lastWritten = new Map<string, string>();
    const a = { key: 'f::1', title: 'One' };
    takeChangedRecords([a], lastWritten);
    lastWritten.delete(a.key);
    expect(takeChangedRecords([a], lastWritten)).toEqual([a]);
  });

  it('keeps only the last record for a duplicated key', () => {
    const lastWritten = new Map<string, string>();
    const first = { key: 'f::1', title: 'Old' };
    const second = { key: 'f::1', title: 'New' };
    expect(takeChangedRecords([first, second], lastWritten)).toEqual([second]);
  });

  it('fingerprints BigInt values and distinguishes them from numbers', () => {
    expect(fingerprintRecord({ a: 1n })).toBe(fingerprintRecord({ a: 1n }));
    expect(fingerprintRecord({ a: 1n })).not.toBe(fingerprintRecord({ a: 1 }));
  });
});

describe('chunk', () => {
  it('splits into fixed-size groups', () => {
    expect(chunk([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
    expect(chunk([], 3)).toEqual([]);
  });
});
