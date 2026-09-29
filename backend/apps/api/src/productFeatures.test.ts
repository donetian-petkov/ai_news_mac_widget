import type { PrismaClient } from '@prisma/client';
import { describe, expect, it } from 'vitest';
import {
  ensureDefaultCollectionsForUser,
  ensureProductFeatureTables,
  forgetDefaultCollectionsForUser,
  selectCategoryStories,
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

describe('selectCategoryStories', () => {
  type Category = Parameters<typeof selectCategoryStories>[0];
  type News = Parameters<typeof selectCategoryStories>[1][number];

  // The previous implementation, kept verbatim as the reference.
  function legacySelect(category: Category, allNews: News[]) {
    const key = (id: string, feedUrl: string) => `${feedUrl}::${id}`;
    const feedUrlSet = new Set(category.feedUrls.map(url => String(url).trim()).filter(Boolean));
    const eligible = allNews
      .filter(item => feedUrlSet.size === 0 || feedUrlSet.has(item.feedUrl))
      .sort((a, b) => Number(b.publishedMs || 0) - Number(a.publishedMs || 0));
    const pinnedKey = key(category.pinnedStoryId, category.pinnedFeedUrl);
    return [...eligible].sort((left, right) => {
      const leftPinned = key(left.id, left.feedUrl) === pinnedKey ? 1 : 0;
      const rightPinned = key(right.id, right.feedUrl) === pinnedKey ? 1 : 0;
      return rightPinned - leftPinned;
    });
  }

  // Small deterministic PRNG so the fixture is stable across runs.
  function rng(seed: number) {
    return () => {
      seed = (seed * 1664525 + 1013904223) % 4294967296;
      return seed / 4294967296;
    };
  }

  function fixture(seed: number, count: number): News[] {
    const random = rng(seed);
    const feeds = ['https://a.example/rss', 'https://b.example/rss', 'https://c.example/rss'];
    return Array.from({ length: count }, (_, index) => ({
      id: `item-${Math.floor(random() * count)}`,
      feedUrl: feeds[Math.floor(random() * feeds.length)],
      title: `Story ${index}`,
      link: '',
      source: 'test',
      // Plenty of equal timestamps (and some missing) to exercise tie order.
      publishedMs: random() < 0.1 ? (undefined as unknown as number) : Math.floor(random() * 20) * 1000
    }));
  }

  function category(overrides: Partial<Category>): Category {
    return {
      name: 'Test',
      description: '',
      feedUrls: [],
      storyIds: [],
      sortOrder: 0,
      preferredCount: 5,
      expandedCount: 10,
      activeCount: 5,
      hidden: false,
      pinnedStoryId: '',
      pinnedFeedUrl: '',
      ...overrides
    } as Category;
  }

  it('matches the previous output on varied fixtures', () => {
    for (let seed = 1; seed <= 40; seed += 1) {
      const news = fixture(seed, 120);
      const pinned = news[seed % news.length];
      const cases: Category[] = [
        category({}),
        category({ feedUrls: ['https://a.example/rss'] }),
        category({ feedUrls: [' https://b.example/rss ', 'https://c.example/rss', ''] }),
        category({ pinnedStoryId: pinned.id, pinnedFeedUrl: pinned.feedUrl }),
        category({ feedUrls: ['https://a.example/rss'], pinnedStoryId: pinned.id, pinnedFeedUrl: pinned.feedUrl }),
        category({ pinnedStoryId: 'missing', pinnedFeedUrl: 'https://a.example/rss' })
      ];
      for (const cat of cases) {
        expect(selectCategoryStories(cat, news)).toEqual(legacySelect(cat, news));
      }
    }
  });

  it('puts the pinned story first and does not mutate the input', () => {
    const news = fixture(7, 30);
    const before = news.map(item => item.title);
    const pinned = news[12];
    const result = selectCategoryStories(category({ pinnedStoryId: pinned.id, pinnedFeedUrl: pinned.feedUrl }), news);
    expect(result[0].id).toBe(pinned.id);
    expect(result[0].feedUrl).toBe(pinned.feedUrl);
    expect(news.map(item => item.title)).toEqual(before);
  });
});
