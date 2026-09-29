import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import {
  ensureDefaultCollectionsForUser,
  ensureProductFeatureTables,
  forgetDefaultCollectionsForUser,
  widgetNewsOrFallback
} from './productFeatures.js';

type FakeOptions = { failFirstExecute?: boolean; existingCollections?: number };

function fakePrisma(options: FakeOptions = {}) {
  const calls = { execute: 0, query: 0, inserts: 0 };
  let failNext = !!options.failFirstExecute;
  let collections = options.existingCollections ?? 0;
  const prisma = {
    async $executeRawUnsafe(sql: string) {
      calls.execute += 1;
      if (failNext) {
        failNext = false;
        throw new Error('database is locked');
      }
      if (sql.startsWith('INSERT INTO "UserFeatureRecord"')) {
        calls.inserts += 1;
        collections += 1;
      }
      return 0;
    },
    async $queryRawUnsafe(sql: string) {
      calls.query += 1;
      if (sql.includes('last_insert_rowid')) return [{ id: collections }];
      if (sql.includes('"kind" = ?') && sql.includes('LIMIT ?')) {
        return Array.from({ length: Math.min(collections, 1) }, (_, i) => ({ id: i + 1 }));
      }
      return [];
    }
  };
  return {
    prisma: prisma as unknown as PrismaClient,
    calls,
    archiveAll: () => { collections = 0; }
  };
}

const feeds = [{ url: 'https://example.com/rss', label: 'Example', kind: 'rss' }];

describe('ensureProductFeatureTables', () => {
  it('runs the CREATE statements only once per client', async () => {
    const { prisma, calls } = fakePrisma();
    await ensureProductFeatureTables(prisma);
    const afterFirst = calls.execute;
    expect(afterFirst).toBeGreaterThan(0);
    await Promise.all([ensureProductFeatureTables(prisma), ensureProductFeatureTables(prisma)]);
    expect(calls.execute).toBe(afterFirst);
  });

  it('retries after a failure', async () => {
    const { prisma, calls } = fakePrisma({ failFirstExecute: true });
    await expect(ensureProductFeatureTables(prisma)).rejects.toThrow('database is locked');
    await ensureProductFeatureTables(prisma);
    expect(calls.execute).toBeGreaterThan(1);
    const settled = calls.execute;
    await ensureProductFeatureTables(prisma);
    expect(calls.execute).toBe(settled);
  });
});

describe('ensureDefaultCollectionsForUser', () => {
  it('checks the database once per user and recreates defaults after archiving', async () => {
    const { prisma, calls, archiveAll } = fakePrisma();
    await ensureDefaultCollectionsForUser(prisma, 1, feeds);
    expect(calls.inserts).toBe(1);
    const queries = calls.query;
    await ensureDefaultCollectionsForUser(prisma, 1, feeds);
    expect(calls.query).toBe(queries);

    // A different user is checked separately (the fake shares one table, so no insert).
    await ensureDefaultCollectionsForUser(prisma, 2, feeds);
    expect(calls.query).toBeGreaterThan(queries);

    // Archiving forgets the user, so defaults come back if everything is gone.
    archiveAll();
    forgetDefaultCollectionsForUser(prisma, 1);
    await ensureDefaultCollectionsForUser(prisma, 1, feeds);
    expect(calls.inserts).toBe(2);
  });
});

describe('widgetNewsOrFallback', () => {
  const fallbackItem = { id: 'mem-1', feedUrl: 'f', title: 'From memory', link: '', source: 's', publishedMs: 1 };
  const dbRow = { itemId: 'db-1', feedUrl: 'f', title: 'From db', link: '', source: 's', publishedMs: 2, isMatch: false, filteredOk: true };

  function prismaReturning(rows: unknown[]) {
    return { newsItemRecord: { findMany: async () => rows } } as unknown as PrismaClient;
  }

  it('does not build the in-memory list when the database has stories', async () => {
    let calls = 0;
    const news = await widgetNewsOrFallback(prismaReturning([dbRow]), () => { calls += 1; return [fallbackItem]; });
    expect(calls).toBe(0);
    expect(news.map(item => item.id)).toEqual(['db-1']);
  });

  it('falls back to the in-memory list when the database is empty, still hiding ids', async () => {
    let calls = 0;
    const second = { ...fallbackItem, id: 'mem-2' };
    const news = await widgetNewsOrFallback(
      prismaReturning([]),
      () => { calls += 1; return [fallbackItem, second]; },
      { hiddenIds: new Set(['mem-1']) }
    );
    expect(calls).toBe(1);
    expect(news.map(item => item.id)).toEqual(['mem-2']);
  });
});
