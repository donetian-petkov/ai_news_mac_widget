import crypto from 'crypto';

/**
 * Helpers for writing news records in bulk without rewriting rows that have not
 * changed since this process last wrote them.
 */

/** Stable-enough fingerprint of a record as it would be written (BigInt-safe). */
export function fingerprintRecord(record: unknown): string {
  const json = JSON.stringify(record, (_key, value) => (typeof value === 'bigint' ? `${value.toString()}n` : value));
  return crypto.createHash('sha1').update(json ?? '').digest('hex');
}

/**
 * Returns the records whose fingerprint differs from the one last written for
 * the same key, and records the new fingerprints in `lastWritten` straight away
 * (so overlapping bulk runs do not queue the same write twice). Callers must
 * `lastWritten.delete(key)` for any record whose write then fails.
 * Later duplicates of a key win, matching sequential upserts.
 */
export function takeChangedRecords<T extends { key: string }>(
  records: T[],
  lastWritten: Map<string, string>
): T[] {
  const latestByKey = new Map<string, T>();
  for (const record of records) {
    latestByKey.delete(record.key);
    latestByKey.set(record.key, record);
  }
  const changed: T[] = [];
  for (const record of latestByKey.values()) {
    const fingerprint = fingerprintRecord(record);
    if (lastWritten.get(record.key) === fingerprint) continue;
    lastWritten.set(record.key, fingerprint);
    changed.push(record);
  }
  return changed;
}

export function chunk<T>(items: T[], size: number): T[][] {
  const step = Math.max(1, Math.floor(size));
  const chunks: T[][] = [];
  for (let index = 0; index < items.length; index += step) {
    chunks.push(items.slice(index, index + step));
  }
  return chunks;
}
