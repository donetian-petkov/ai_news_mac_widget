import type express from 'express';
import crypto from 'crypto';
import type { PrismaClient } from '@prisma/client';
import { z } from 'zod';
import {
  alertRulePayloadSchema,
  digestPayloadSchema,
  opmlFeedSchema,
  savedStoryPayloadSchema,
  schedulePayloadSchema,
  shareKindSchema
} from '@ai-news/shared';

type AuthUser = { id: number; username: string };
type RequireAuthUser = (req: express.Request, res: express.Response) => Promise<AuthUser | null>;

type ProductFeed = {
  url: string;
  label: string;
  kind: string;
  intervalSec?: number;
  discordWebhookUrl?: string;
};

type ProductNews = {
  id: string;
  feedUrl: string;
  title: string;
  titleBg?: string;
  titleEn?: string;
  neutralTitle?: string;
  neutralTitleBg?: string;
  neutralTitleEn?: string;
  link?: string;
  source?: string;
  publishedMs?: number;
  summary?: string;
  research?: string;
  mood?: string;
  newsType?: string;
  isMatch?: boolean;
  filteredOk?: boolean;
  summaryPending?: boolean;
  researchPending?: boolean;
  titleTranslatePending?: boolean;
  neutralTitlePending?: boolean;
  coverUrl?: string;
};

type PersistedProductNews = {
  itemId: string;
  feedUrl: string;
  title: string;
  titleBg: string | null;
  titleEn: string | null;
  neutralTitle: string | null;
  neutralTitleBg: string | null;
  neutralTitleEn: string | null;
  link: string;
  source: string;
  publishedMs: bigint | number;
  summary: string | null;
  research: string | null;
  mood: string | null;
  newsType: string | null;
  isMatch: boolean;
  filteredOk: boolean;
  coverUrl: string | null;
};

type AiUsagePayload = {
  aiUsageInputTokens: number;
  aiUsageOutputTokens: number;
  aiUsageTotalTokens: number;
  aiUsageRuntimeStartedAt: number;
  aiUsageByKind: Record<string, { requests: number; inputTokens: number; outputTokens: number; totalTokens: number }>;
  aiUsageRecent: Array<Record<string, unknown>>;
};

export type ProductHistoryEntry = {
  userId?: number | null;
  feedUrl?: string;
  itemId?: string;
  title?: string;
  source?: string;
  stage: string;
  status: string;
  reason?: string;
  details?: Record<string, unknown>;
};

export type ProductFeatureRuntime = {
  recordHistory: (entry: ProductHistoryEntry) => Promise<void>;
  stop: () => void;
};

type RegisterProductFeatureApiArgs = {
  app: express.Express;
  prisma: PrismaClient;
  requireAuthUser: RequireAuthUser;
  getFeeds: () => ProductFeed[];
  getRecentNews: () => ProductNews[];
  getAiUsage: () => AiUsagePayload;
  resetAiUsage: () => AiUsagePayload;
  importFeeds?: (feeds: Array<{ title: string; xmlUrl: string; htmlUrl?: string }>) => number;
  requestStoryAction?: (action: WidgetStoryActionKind, itemId: string, feedUrl: string) => Promise<boolean> | boolean;
  refreshFeed?: (feedUrl: string) => Promise<boolean> | boolean;
};

type FeatureKind = 'saved_story' | 'collection' | 'alert_rule' | 'schedule' | 'digest';

type FeatureRow = {
  id: number;
  userId: number;
  kind: FeatureKind;
  title: string;
  payloadJson: string;
  archived: number | boolean;
  createdAt: string;
  updatedAt: string;
};

const collectionPayloadSchema = z.object({
  name: z.string().trim().min(1).max(120),
  description: z.string().trim().max(2000).default(''),
  feedUrls: z.array(z.string().trim().min(1)).max(100).default([]),
  storyIds: z.array(z.string().trim().min(1)).max(200).default([]),
  tags: z.array(z.string().trim().min(1).max(80)).max(40).default([]),
  hidden: z.boolean().default(false),
  sortOrder: z.number().int().min(0).max(10_000).default(0),
  preferredCount: z.number().int().min(1).max(10).default(5),
  expandedCount: z.number().int().min(5).max(20).default(10),
  activeCount: z.number().int().min(1).max(20).default(5),
  pinnedStoryId: z.string().trim().max(200).default(''),
  pinnedFeedUrl: z.string().trim().max(1000).default('')
});

type WidgetStoryActionKind = 'summary' | 'research' | 'translation' | 'neutral_title' | 'refresh';

type WidgetCollectionPayload = z.infer<typeof collectionPayloadSchema>;

const shareBodySchema = z.object({
  kind: shareKindSchema,
  title: z.string().trim().min(1).max(180),
  payload: z.record(z.unknown()).default({})
});

function parseJsonObject(raw: unknown): Record<string, unknown> {
  if (!raw) return {};
  if (typeof raw === 'object' && !Array.isArray(raw)) return raw as Record<string, unknown>;
  if (typeof raw !== 'string') return {};
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : {};
  } catch {
    return {};
  }
}

function normalizeLimit(raw: unknown, fallback = 80, max = 500) {
  const value = Number(raw);
  return Number.isFinite(value) ? Math.max(1, Math.min(max, Math.floor(value))) : fallback;
}

function persistedNewsToProductNews(row: PersistedProductNews): ProductNews {
  return {
    id: row.itemId,
    feedUrl: row.feedUrl,
    title: row.title,
    titleBg: row.titleBg || undefined,
    titleEn: row.titleEn || undefined,
    neutralTitle: row.neutralTitle || undefined,
    neutralTitleBg: row.neutralTitleBg || undefined,
    neutralTitleEn: row.neutralTitleEn || undefined,
    link: row.link,
    source: row.source,
    publishedMs: Number(row.publishedMs),
    summary: row.summary || undefined,
    research: row.research || undefined,
    mood: row.mood || undefined,
    newsType: row.newsType || undefined,
    isMatch: row.isMatch,
    filteredOk: row.filteredOk,
    coverUrl: row.coverUrl || undefined
  };
}

async function listPersistedWidgetNews(
  prisma: PrismaClient,
  options: { limit?: number; feedUrls?: string[]; filteredOnly?: boolean } = {}
) {
  const feedUrls = (options.feedUrls || []).map(url => url.trim()).filter(Boolean);
  const where: Record<string, unknown> = {};
  if (feedUrls.length > 0) where.feedUrl = { in: feedUrls };
  if (options.filteredOnly) {
    where.isMatch = true;
    where.filteredOk = true;
  }
  const rows = await prisma.newsItemRecord.findMany({
    where,
    orderBy: [{ publishedMs: 'desc' }, { itemId: 'desc' }],
    take: Math.max(1, Math.min(1000, options.limit || 300))
  });
  return rows.map(persistedNewsToProductNews);
}

async function widgetNewsOrFallback(
  prisma: PrismaClient,
  fallback: ProductNews[],
  options: { limit?: number; feedUrls?: string[]; filteredOnly?: boolean } = {}
) {
  const persisted = await listPersistedWidgetNews(prisma, options);
  return persisted.length > 0 ? persisted : fallback;
}

function safeTitle(raw: unknown, fallback: string) {
  const value = String(raw || '').replace(/\s+/g, ' ').trim();
  return value ? value.slice(0, 180) : fallback;
}

function rowToFeature(row: FeatureRow) {
  return {
    id: Number(row.id),
    userId: Number(row.userId),
    kind: row.kind,
    title: row.title,
    payload: parseJsonObject(row.payloadJson),
    archived: !!row.archived,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt
  };
}

function normalizeCollectionPayload(rawPayload: unknown): WidgetCollectionPayload {
  return collectionPayloadSchema.parse(parseJsonObject(rawPayload));
}

function mapCollectionRow(row: FeatureRow) {
  const payload = normalizeCollectionPayload(row.payloadJson);
  return {
    id: Number(row.id),
    name: row.title,
    description: payload.description,
    feedUrls: payload.feedUrls,
    storyIds: payload.storyIds,
    tags: payload.tags,
    hidden: payload.hidden,
    sortOrder: payload.sortOrder,
    preferredCount: payload.preferredCount,
    expandedCount: payload.expandedCount,
    activeCount: payload.activeCount,
    pinnedStoryId: payload.pinnedStoryId,
    pinnedFeedUrl: payload.pinnedFeedUrl,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt
  };
}

function buildStoryLookupKey(itemId: string, feedUrl: string) {
  return `${feedUrl}::${itemId}`;
}

function trimStoryText(raw: unknown, fallback = '') {
  return String(raw || fallback).replace(/\s+/g, ' ').trim();
}

function toWidgetStory(news: ProductNews) {
  const neutralOriginal = trimStoryText(news.neutralTitle);
  const neutralTranslated = trimStoryText(news.neutralTitleBg) || trimStoryText(news.neutralTitleEn);
  const translatedTitle = neutralTranslated || trimStoryText(news.titleBg) || trimStoryText(news.titleEn);
  const displayTitle = neutralOriginal || neutralTranslated || trimStoryText(news.title);
  return {
    id: news.id,
    feedUrl: news.feedUrl,
    title: displayTitle,
    translatedTitle: translatedTitle || null,
    link: trimStoryText(news.link) || null,
    source: trimStoryText(news.source) || null,
    publishedMs: Number(news.publishedMs || 0) || 0,
    summary: trimStoryText(news.summary) || null,
    research: trimStoryText(news.research) || null,
    mood: trimStoryText(news.mood) || null,
    newsType: trimStoryText(news.newsType) || null,
    isMatch: news.isMatch !== false,
    filteredOk: news.filteredOk !== false,
    summaryPending: !!news.summaryPending,
    researchPending: !!news.researchPending,
    translationPending: !!news.titleTranslatePending,
    neutralTitlePending: !!news.neutralTitlePending,
    hasSummary: !!trimStoryText(news.summary),
    hasResearch: !!trimStoryText(news.research),
    hasTranslation: !!translatedTitle,
    hasNeutralTitle: !!(neutralOriginal || neutralTranslated),
    coverUrl: trimStoryText(news.coverUrl) || null,
    imagesEnabled: false
  };
}

async function ensureDefaultCollectionsForUser(prisma: PrismaClient, userId: number, feeds: ProductFeed[]) {
  const existing = await listFeatureRows(prisma, userId, 'collection', 1);
  if (existing.length > 0) return;
  for (const [index, feed] of feeds.entries()) {
    const payload = collectionPayloadSchema.parse({
      name: feed.label,
      description: `${feed.label} widget category`,
      feedUrls: [feed.url],
      sortOrder: index,
      preferredCount: 5,
      expandedCount: 10,
      activeCount: 5
    });
    await createFeatureRecord(prisma, userId, 'collection', safeTitle(feed.label, feed.url), payload);
  }
}

function selectCategoryStories(category: WidgetCollectionPayload, allNews: ProductNews[]) {
  const feedUrlSet = new Set(category.feedUrls.map(url => String(url).trim()).filter(Boolean));
  const eligible = allNews
    .filter(item => feedUrlSet.size === 0 || feedUrlSet.has(item.feedUrl))
    .sort((a, b) => Number(b.publishedMs || 0) - Number(a.publishedMs || 0));
  const pinnedKey = buildStoryLookupKey(category.pinnedStoryId, category.pinnedFeedUrl);
  const withPinnedFirst = [...eligible].sort((left, right) => {
    const leftPinned = buildStoryLookupKey(left.id, left.feedUrl) === pinnedKey ? 1 : 0;
    const rightPinned = buildStoryLookupKey(right.id, right.feedUrl) === pinnedKey ? 1 : 0;
    return rightPinned - leftPinned;
  });
  return withPinnedFirst;
}

async function ensureProductFeatureTables(prisma: PrismaClient) {
  await prisma.$executeRawUnsafe(`
    CREATE TABLE IF NOT EXISTS "UserFeatureRecord" (
      "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      "userId" INTEGER NOT NULL,
      "kind" TEXT NOT NULL,
      "title" TEXT NOT NULL,
      "payloadJson" TEXT NOT NULL,
      "archived" BOOLEAN NOT NULL DEFAULT false,
      "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updatedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  `);
  await prisma.$executeRawUnsafe('CREATE INDEX IF NOT EXISTS "UserFeatureRecord_userId_kind_updatedAt_idx" ON "UserFeatureRecord"("userId", "kind", "updatedAt")');
  await prisma.$executeRawUnsafe('CREATE INDEX IF NOT EXISTS "UserFeatureRecord_kind_updatedAt_idx" ON "UserFeatureRecord"("kind", "updatedAt")');
  await prisma.$executeRawUnsafe(`
    CREATE TABLE IF NOT EXISTS "DeliveryHistoryRecord" (
      "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      "userId" INTEGER,
      "feedUrl" TEXT,
      "itemId" TEXT,
      "title" TEXT,
      "source" TEXT,
      "stage" TEXT NOT NULL,
      "status" TEXT NOT NULL,
      "reason" TEXT,
      "detailsJson" TEXT,
      "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  `);
  await prisma.$executeRawUnsafe('CREATE INDEX IF NOT EXISTS "DeliveryHistoryRecord_userId_createdAt_idx" ON "DeliveryHistoryRecord"("userId", "createdAt")');
  await prisma.$executeRawUnsafe('CREATE INDEX IF NOT EXISTS "DeliveryHistoryRecord_feedUrl_createdAt_idx" ON "DeliveryHistoryRecord"("feedUrl", "createdAt")');
  await prisma.$executeRawUnsafe('CREATE INDEX IF NOT EXISTS "DeliveryHistoryRecord_stage_status_createdAt_idx" ON "DeliveryHistoryRecord"("stage", "status", "createdAt")');
  await prisma.$executeRawUnsafe(`
    CREATE TABLE IF NOT EXISTS "ShareLink" (
      "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      "token" TEXT NOT NULL,
      "userId" INTEGER NOT NULL,
      "kind" TEXT NOT NULL,
      "title" TEXT NOT NULL,
      "payloadJson" TEXT NOT NULL,
      "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "expiresAt" DATETIME
    )
  `);
  await prisma.$executeRawUnsafe('CREATE UNIQUE INDEX IF NOT EXISTS "ShareLink_token_key" ON "ShareLink"("token")');
  await prisma.$executeRawUnsafe('CREATE INDEX IF NOT EXISTS "ShareLink_userId_createdAt_idx" ON "ShareLink"("userId", "createdAt")');
  await prisma.$executeRawUnsafe('CREATE INDEX IF NOT EXISTS "ShareLink_kind_createdAt_idx" ON "ShareLink"("kind", "createdAt")');
}

function normalizeFeaturePayload(kind: FeatureKind, rawPayload: unknown) {
  const source = parseJsonObject(rawPayload);
  if (kind === 'saved_story') {
    const payload = savedStoryPayloadSchema.parse(source);
    return { title: safeTitle(payload.title, 'Saved story'), payload };
  }
  if (kind === 'alert_rule') {
    const payload = alertRulePayloadSchema.parse(source);
    return { title: safeTitle(payload.name, 'Alert rule'), payload };
  }
  if (kind === 'schedule') {
    const payload = schedulePayloadSchema.parse(source);
    if (!payload.nextRunAtMs) payload.nextRunAtMs = computeNextRunAtMs(payload.cadence);
    return { title: safeTitle(payload.name, 'Scheduled briefing'), payload };
  }
  if (kind === 'digest') {
    const payload = digestPayloadSchema.parse(source);
    return { title: safeTitle((source.title as string | undefined) || 'Digest', 'Digest'), payload };
  }
  const payload = collectionPayloadSchema.parse(source);
  return { title: safeTitle(payload.name, 'Collection'), payload };
}

async function listFeatureRows(prisma: PrismaClient, userId: number, kind: FeatureKind, limit: number, includeArchived = false) {
  const archivedClause = includeArchived ? '' : 'AND "archived" = false';
  return prisma.$queryRawUnsafe<FeatureRow[]>(
    `SELECT * FROM "UserFeatureRecord" WHERE "userId" = ? AND "kind" = ? ${archivedClause} ORDER BY "updatedAt" DESC LIMIT ?`,
    userId,
    kind,
    limit
  );
}

async function findFeatureRow(prisma: PrismaClient, userId: number, id: number) {
  const rows = await prisma.$queryRawUnsafe<FeatureRow[]>(
    'SELECT * FROM "UserFeatureRecord" WHERE "userId" = ? AND "id" = ? LIMIT 1',
    userId,
    id
  );
  return rows[0] || null;
}

async function createFeatureRecord(prisma: PrismaClient, userId: number, kind: FeatureKind, title: string, payload: Record<string, unknown>) {
  await prisma.$executeRawUnsafe(
    'INSERT INTO "UserFeatureRecord" ("userId", "kind", "title", "payloadJson", "archived", "createdAt", "updatedAt") VALUES (?, ?, ?, ?, false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)',
    userId,
    kind,
    title,
    JSON.stringify(payload)
  );
  const ids = await prisma.$queryRawUnsafe<Array<{ id: number }>>('SELECT last_insert_rowid() as id');
  return findFeatureRow(prisma, userId, Number(ids[0]?.id || 0));
}

async function updateFeatureRecord(prisma: PrismaClient, userId: number, id: number, title: string, payload: Record<string, unknown>, archived = false) {
  await prisma.$executeRawUnsafe(
    'UPDATE "UserFeatureRecord" SET "title" = ?, "payloadJson" = ?, "archived" = ?, "updatedAt" = CURRENT_TIMESTAMP WHERE "userId" = ? AND "id" = ?',
    title,
    JSON.stringify(payload),
    archived ? 1 : 0,
    userId,
    id
  );
  return findFeatureRow(prisma, userId, id);
}

async function recordHistoryRaw(prisma: PrismaClient, entry: ProductHistoryEntry) {
  await ensureProductFeatureTables(prisma);
  await prisma.$executeRawUnsafe(
    'INSERT INTO "DeliveryHistoryRecord" ("userId", "feedUrl", "itemId", "title", "source", "stage", "status", "reason", "detailsJson", "createdAt") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)',
    entry.userId ?? null,
    entry.feedUrl || null,
    entry.itemId || null,
    entry.title || null,
    entry.source || null,
    String(entry.stage || 'event').slice(0, 80),
    String(entry.status || 'ok').slice(0, 80),
    entry.reason || null,
    entry.details ? JSON.stringify(entry.details) : null
  );
}

function buildUsageExport(usage: AiUsagePayload) {
  const byKind = usage.aiUsageByKind || {};
  return {
    generatedAt: new Date().toISOString(),
    inputTokens: usage.aiUsageInputTokens,
    outputTokens: usage.aiUsageOutputTokens,
    totalTokens: usage.aiUsageTotalTokens,
    runtimeStartedAt: usage.aiUsageRuntimeStartedAt,
    byKind,
    recent: usage.aiUsageRecent || []
  };
}

function usageExportToCsv(usage: ReturnType<typeof buildUsageExport>) {
  const lines = ['kind,model,label,inputTokens,outputTokens,totalTokens,createdAt'];
  for (const entry of usage.recent) {
    const values = [
      entry.kind,
      entry.model,
      entry.label,
      entry.inputTokens,
      entry.outputTokens,
      entry.totalTokens,
      entry.createdAt
    ].map(value => `"${String(value ?? '').replace(/"/g, '""')}"`);
    lines.push(values.join(','));
  }
  return `${lines.join('\n')}\n`;
}

export function parseOpmlFeeds(opmlRaw: string) {
  const opml = String(opmlRaw || '');
  const feeds: Array<z.infer<typeof opmlFeedSchema>> = [];
  const seen = new Set<string>();
  const outlineRe = /<outline\b[^>]*>/gi;
  const attrRe = /(\w+)=(?:"([^"]*)"|'([^']*)')/g;
  for (const outline of opml.match(outlineRe) || []) {
    const attrs: Record<string, string> = {};
    let attr: RegExpExecArray | null;
    while ((attr = attrRe.exec(outline))) {
      attrs[attr[1]] = decodeXmlEntities(attr[2] || attr[3] || '');
    }
    const xmlUrl = attrs.xmlUrl || attrs.xmlurl || attrs.url || '';
    if (!xmlUrl || seen.has(xmlUrl)) continue;
    const parsed = opmlFeedSchema.safeParse({
      title: attrs.title || attrs.text || new URL(xmlUrl).hostname,
      xmlUrl,
      htmlUrl: attrs.htmlUrl || attrs.htmlurl || undefined
    });
    if (!parsed.success) continue;
    seen.add(xmlUrl);
    feeds.push(parsed.data);
  }
  return feeds;
}

export function buildOpml(feeds: ProductFeed[]) {
  const outlines = feeds
    .filter(feed => feed.url && feed.url !== '__filtered__')
    .map(feed => `    <outline text="${escapeXml(feed.label || feed.url)}" title="${escapeXml(feed.label || feed.url)}" type="rss" xmlUrl="${escapeXml(feed.url)}" />`)
    .join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>\n<opml version="2.0">\n  <head><title>AI News feeds</title></head>\n  <body>\n${outlines}\n  </body>\n</opml>\n`;
}

function escapeXml(value: string) {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function decodeXmlEntities(value: string) {
  return String(value || '')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');
}

function computeNextRunAtMs(cadence: string, fromMs = Date.now()) {
  const hour = cadence === 'hourly' ? 60 * 60 * 1000 : cadence === 'weekly' ? 7 * 24 * 60 * 60 * 1000 : 24 * 60 * 60 * 1000;
  return fromMs + hour;
}

function newsMatchesRule(item: ProductNews, payload: z.infer<typeof alertRulePayloadSchema>) {
  const haystack = `${item.title || ''} ${item.summary || ''} ${item.research || ''}`.toLowerCase();
  const keywordOk = !payload.keywords.length || payload.keywords.some((keyword: string) => haystack.includes(keyword.toLowerCase()));
  const sourceOk = !payload.sources.length || payload.sources.some((source: string) => String(item.source || '').toLowerCase().includes(source.toLowerCase()));
  const moodOk = !payload.moods.length || payload.moods.includes(String(item.mood || ''));
  const typeOk = !payload.newsTypes.length || payload.newsTypes.includes(String(item.newsType || ''));
  return keywordOk && sourceOk && moodOk && typeOk;
}

async function postDiscordMessage(webhookUrl: string, title: string, body: string) {
  const url = String(webhookUrl || '').trim();
  if (!url || !/^https:\/\/(?:[^/]+\.)?(?:discord|discordapp)\.com\/api\/webhooks\//i.test(url)) return false;
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'AI News',
        embeds: [{
          title: title.slice(0, 240),
          description: body.slice(0, 3900),
          color: 0x3b82f6,
          timestamp: new Date().toISOString()
        }],
        allowed_mentions: { parse: [] }
      })
    });
    return res.ok;
  } catch {
    return false;
  }
}

async function runSchedule(prisma: PrismaClient, row: FeatureRow, getRecentNews: () => ProductNews[]) {
  const payload = schedulePayloadSchema.parse(parseJsonObject(row.payloadJson));
  const selected = payload.feedUrls.length ? new Set(payload.feedUrls) : null;
  const items = getRecentNews()
    .filter(item => !selected || selected.has(item.feedUrl))
    .sort((a, b) => Number(b.publishedMs || 0) - Number(a.publishedMs || 0))
    .slice(0, 12);
  const lines = items.map((item, index) => `${index + 1}. ${item.title}${item.source ? ` (${item.source})` : ''}`).join('\n');
  const body = lines || 'No recent stories matched this schedule yet.';
  const digestPayload = digestPayloadSchema.parse({
    storyIds: items.map(item => item.id),
    feedUrls: payload.feedUrls,
    body,
    format: payload.format,
    discordWebhookUrl: payload.discordWebhookUrl
  });
  await createFeatureRecord(prisma, row.userId, 'digest', `${payload.name} · ${new Date().toLocaleDateString()}`, digestPayload);
  let discordStatus = 'skipped';
  if (payload.discordWebhookUrl) {
    discordStatus = await postDiscordMessage(payload.discordWebhookUrl, payload.name, body) ? 'sent' : 'failed';
  }
  await recordHistoryRaw(prisma, {
    userId: row.userId,
    stage: 'scheduled_briefing',
    status: discordStatus === 'failed' ? 'failed' : 'generated',
    reason: discordStatus === 'skipped' ? 'No Discord webhook configured.' : undefined,
    details: { scheduleId: row.id, itemCount: items.length, discordStatus }
  });
  payload.lastRunAtMs = Date.now();
  payload.nextRunAtMs = computeNextRunAtMs(payload.cadence);
  await updateFeatureRecord(prisma, row.userId, row.id, row.title, payload);
}

async function runAlertRule(prisma: PrismaClient, row: FeatureRow, getRecentNews: () => ProductNews[]) {
  const payload = alertRulePayloadSchema.parse(parseJsonObject(row.payloadJson));
  if (!payload.enabled) return;
  const since = Number(payload.lastCheckedAtMs || 0);
  const matches = getRecentNews()
    .filter(item => Number(item.publishedMs || 0) > since)
    .filter(item => newsMatchesRule(item, payload))
    .slice(0, 20);
  for (const item of matches) {
    const body = `${item.title}\n${item.link || ''}`.trim();
    let discordStatus = 'skipped';
    if (payload.discordWebhookUrl) {
      discordStatus = await postDiscordMessage(payload.discordWebhookUrl, payload.name, body) ? 'sent' : 'failed';
    }
    await recordHistoryRaw(prisma, {
      userId: row.userId,
      feedUrl: item.feedUrl,
      itemId: item.id,
      title: item.title,
      source: item.source,
      stage: 'alert_rule',
      status: discordStatus === 'failed' ? 'failed' : 'matched',
      reason: discordStatus === 'skipped' ? 'No Discord webhook configured.' : undefined,
      details: { ruleId: row.id, discordStatus }
    });
  }
  payload.lastCheckedAtMs = Date.now();
  await updateFeatureRecord(prisma, row.userId, row.id, row.title, payload);
}

async function runDueAutomation(prisma: PrismaClient, getRecentNews: () => ProductNews[]) {
  await ensureProductFeatureTables(prisma);
  const now = Date.now();
  const schedules = await prisma.$queryRawUnsafe<FeatureRow[]>(
    'SELECT * FROM "UserFeatureRecord" WHERE "kind" = ? AND "archived" = false ORDER BY "updatedAt" DESC LIMIT 200',
    'schedule'
  );
  for (const row of schedules) {
    const payload = schedulePayloadSchema.safeParse(parseJsonObject(row.payloadJson));
    if (!payload.success || !payload.data.enabled) continue;
    if (!payload.data.nextRunAtMs || payload.data.nextRunAtMs <= now) {
      await runSchedule(prisma, row, getRecentNews).catch(() => {});
    }
  }
  const rules = await prisma.$queryRawUnsafe<FeatureRow[]>(
    'SELECT * FROM "UserFeatureRecord" WHERE "kind" = ? AND "archived" = false ORDER BY "updatedAt" DESC LIMIT 200',
    'alert_rule'
  );
  for (const row of rules) {
    await runAlertRule(prisma, row, getRecentNews).catch(() => {});
  }
}

export function registerProductFeatureApi({
  app,
  prisma,
  requireAuthUser,
  getFeeds,
  getRecentNews,
  getAiUsage,
  resetAiUsage,
  importFeeds,
  requestStoryAction,
  refreshFeed
}: RegisterProductFeatureApiArgs): ProductFeatureRuntime {
  void ensureProductFeatureTables(prisma).catch(err => {
    console.warn('[product-features] failed to ensure tables:', (err as Error).message);
  });

  const registerCrud = (basePath: string, kind: FeatureKind) => {
    app.get(basePath, async (req, res) => {
      const user = await requireAuthUser(req, res);
      if (!user) return;
      await ensureProductFeatureTables(prisma);
      const rows = await listFeatureRows(prisma, user.id, kind, normalizeLimit(req.query.limit), String(req.query.archived || '') === 'true');
      res.json({ ok: true, items: rows.map(rowToFeature) });
    });

    app.post(basePath, async (req, res) => {
      const user = await requireAuthUser(req, res);
      if (!user) return;
      await ensureProductFeatureTables(prisma);
      const { title, payload } = normalizeFeaturePayload(kind, (req.body as { payload?: unknown } | undefined)?.payload || req.body);
      const row = await createFeatureRecord(prisma, user.id, kind, title, payload);
      res.status(201).json({ ok: true, item: row ? rowToFeature(row) : null });
    });

    app.put(`${basePath}/:id`, async (req, res) => {
      const user = await requireAuthUser(req, res);
      if (!user) return;
      await ensureProductFeatureTables(prisma);
      const id = Number(req.params.id);
      const existing = Number.isFinite(id) ? await findFeatureRow(prisma, user.id, id) : null;
      if (!existing || existing.kind !== kind) {
        res.status(404).json({ error: 'Item not found.' });
        return;
      }
      const mergedPayload = {
        ...parseJsonObject(existing.payloadJson),
        ...parseJsonObject((req.body as { payload?: unknown } | undefined)?.payload || req.body)
      };
      const { title, payload } = normalizeFeaturePayload(kind, mergedPayload);
      const row = await updateFeatureRecord(prisma, user.id, id, title, payload, !!(req.body as { archived?: boolean } | undefined)?.archived);
      res.json({ ok: true, item: row ? rowToFeature(row) : null });
    });

    app.delete(`${basePath}/:id`, async (req, res) => {
      const user = await requireAuthUser(req, res);
      if (!user) return;
      await ensureProductFeatureTables(prisma);
      const id = Number(req.params.id);
      if (!Number.isFinite(id)) {
        res.status(400).json({ error: 'Invalid item id.' });
        return;
      }
      await prisma.$executeRawUnsafe(
        'UPDATE "UserFeatureRecord" SET "archived" = true, "updatedAt" = CURRENT_TIMESTAMP WHERE "userId" = ? AND "id" = ?',
        user.id,
        id
      );
      res.json({ ok: true });
    });
  };

  registerCrud('/api/library', 'saved_story');
  registerCrud('/api/collections', 'collection');
  registerCrud('/api/rules', 'alert_rule');
  registerCrud('/api/schedules', 'schedule');
  registerCrud('/api/digests', 'digest');

  app.post('/api/schedules/:id/run', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const row = await findFeatureRow(prisma, user.id, Number(req.params.id));
    if (!row || row.kind !== 'schedule') {
      res.status(404).json({ error: 'Schedule not found.' });
      return;
    }
    await runSchedule(prisma, row, getRecentNews);
    res.json({ ok: true });
  });

  app.post('/api/rules/:id/run', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const row = await findFeatureRow(prisma, user.id, Number(req.params.id));
    if (!row || row.kind !== 'alert_rule') {
      res.status(404).json({ error: 'Rule not found.' });
      return;
    }
    await runAlertRule(prisma, row, getRecentNews);
    res.json({ ok: true });
  });

  app.get('/api/history', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    await ensureProductFeatureTables(prisma);
    const limit = normalizeLimit(req.query.limit, 120, 500);
    const feedUrl = String(req.query.feedUrl || '').trim();
    const rows = await prisma.$queryRawUnsafe<Array<Record<string, unknown>>>(
      feedUrl
        ? 'SELECT * FROM "DeliveryHistoryRecord" WHERE ("userId" = ? OR "userId" IS NULL) AND "feedUrl" = ? ORDER BY "createdAt" DESC LIMIT ?'
        : 'SELECT * FROM "DeliveryHistoryRecord" WHERE "userId" = ? OR "userId" IS NULL ORDER BY "createdAt" DESC LIMIT ?',
      ...(feedUrl ? [user.id, feedUrl, limit] : [user.id, limit])
    );
    const newsRows = await prisma.$queryRawUnsafe<Array<Record<string, unknown>>>(
      feedUrl
        ? 'SELECT "feedUrl", "itemId", "title", "source", "publishedMs", "createdAt" FROM "NewsItemRecord" WHERE "feedUrl" = ? ORDER BY "publishedMs" DESC LIMIT ?'
        : 'SELECT "feedUrl", "itemId", "title", "source", "publishedMs", "createdAt" FROM "NewsItemRecord" ORDER BY "publishedMs" DESC LIMIT ?',
      ...(feedUrl ? [feedUrl, Math.min(limit, 120)] : [Math.min(limit, 120)])
    ).catch(() => []);
    // Raw SQL returns integer columns as BigInt, which JSON.stringify cannot
    // serialize — that previously threw and crashed the whole process. Coerce them.
    const toSerializable = (row: Record<string, unknown>) =>
      Object.fromEntries(Object.entries(row).map(([k, v]) => [k, typeof v === 'bigint' ? Number(v) : v]));
    res.json({
      ok: true,
      items: rows.map(row => ({ ...toSerializable(row), details: parseJsonObject(row.detailsJson) })),
      fetched: newsRows.map(row => ({ ...toSerializable(row), stage: 'feed_fetch', status: 'fetched' }))
    });
  });

  app.get('/api/sources', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const feeds = getFeeds();
    const news = getRecentNews();
    const items = feeds.map(feed => {
      const feedNews = news.filter(item => item.feedUrl === feed.url);
      const moods = new Map<string, number>();
      const types = new Map<string, number>();
      for (const item of feedNews) {
        if (item.mood) moods.set(item.mood, (moods.get(item.mood) || 0) + 1);
        if (item.newsType) types.set(item.newsType, (types.get(item.newsType) || 0) + 1);
      }
      return {
        ...feed,
        recentCount: feedNews.length,
        latest: feedNews[0] ? toWidgetStory(feedNews[0]) : null,
        moods: Object.fromEntries(moods),
        newsTypes: Object.fromEntries(types),
        discordEnabled: !!feed.discordWebhookUrl
      };
    });
    res.json({ ok: true, items });
  });

  app.get('/api/widget/bootstrap', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    await ensureProductFeatureTables(prisma);
    await ensureDefaultCollectionsForUser(prisma, user.id, getFeeds());
    const rows = await listFeatureRows(prisma, user.id, 'collection', 200, true);
    const categories = rows
      .map(mapCollectionRow)
      .sort((left, right) => left.sortOrder - right.sortOrder || left.id - right.id);
    const usage = buildUsageExport(getAiUsage());
    res.json({
      ok: true,
      user,
      categories,
      usage,
      widget: {
        imagesEnabled: false,
        defaultCount: 5,
        expandedCount: 10
      }
    });
  });

  app.get('/api/widget/categories', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    await ensureProductFeatureTables(prisma);
    await ensureDefaultCollectionsForUser(prisma, user.id, getFeeds());
    const rows = await listFeatureRows(prisma, user.id, 'collection', 200, true);
    const categories = rows
      .map(mapCollectionRow)
      .sort((left, right) => left.sortOrder - right.sortOrder || left.id - right.id);
    res.json({ ok: true, items: categories });
  });

  // Stories matching the user's keywords (the "Filtered" column from the web app).
  app.get('/api/widget/keyword-matches', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const limitRaw = Number(req.query.limit);
    const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(200, Math.floor(limitRaw))) : 30;
    const news = await widgetNewsOrFallback(prisma, getRecentNews(), { limit: limit + 1, filteredOnly: true });
    const page = news
      .filter(item => item.isMatch === true && item.filteredOk !== false)
      .sort((a, b) => Number(b.publishedMs || 0) - Number(a.publishedMs || 0))
      .slice(0, limit + 1);
    const stories = page
      .slice(0, limit)
      .map(toWidgetStory);
    res.json({ ok: true, stories, count: stories.length, limit, hasMore: page.length > limit });
  });

  app.get('/api/widget/master', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    await ensureProductFeatureTables(prisma);
    await ensureDefaultCollectionsForUser(prisma, user.id, getFeeds());
    const rows = await listFeatureRows(prisma, user.id, 'collection', 200, true);
    const news = await widgetNewsOrFallback(prisma, getRecentNews(), { limit: 1000 });
    const categories = rows
      .map(mapCollectionRow)
      .sort((left, right) => left.sortOrder - right.sortOrder || left.id - right.id)
      .map(category => ({
        ...category,
        stories: selectCategoryStories(category, news)
          .slice(0, Math.max(1, category.activeCount))
          .map(toWidgetStory)
      }));
    res.json({
      ok: true,
      categories,
      visibleCategories: categories.filter(category => !category.hidden).length,
      lastRefreshMs: Date.now(),
      imagesEnabled: false
    });
  });

  app.get('/api/widget/categories/:id/stories', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    await ensureProductFeatureTables(prisma);
    const id = Number(req.params.id);
    const row = Number.isFinite(id) ? await findFeatureRow(prisma, user.id, id) : null;
    if (!row || row.kind !== 'collection') {
      res.status(404).json({ error: 'Category not found.' });
      return;
    }
    const category = mapCollectionRow(row);
    const limit = normalizeLimit(req.query.limit, category.activeCount, 200);
    const news = await widgetNewsOrFallback(prisma, getRecentNews(), {
      limit: Math.max((limit + 1) * Math.max(category.feedUrls.length, 1), 100),
      feedUrls: category.feedUrls
    });
    const page = selectCategoryStories(category, news).slice(0, limit + 1);
    const stories = page.slice(0, limit).map(toWidgetStory);
    res.json({
      ok: true,
      category,
      stories,
      count: stories.length,
      limit,
      hasMore: page.length > limit,
      pinnedStoryKey: category.pinnedStoryId ? buildStoryLookupKey(category.pinnedStoryId, category.pinnedFeedUrl) : null,
      imagesEnabled: false
    });
  });

  app.post('/api/widget/categories/:id/visibility', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    await ensureProductFeatureTables(prisma);
    const id = Number(req.params.id);
    const existing = Number.isFinite(id) ? await findFeatureRow(prisma, user.id, id) : null;
    if (!existing || existing.kind !== 'collection') {
      res.status(404).json({ error: 'Category not found.' });
      return;
    }
    const payload = normalizeCollectionPayload(existing.payloadJson);
    payload.hidden = !!(req.body as { hidden?: unknown } | undefined)?.hidden;
    const row = await updateFeatureRecord(prisma, user.id, id, safeTitle(payload.name, existing.title), payload, !!existing.archived);
    res.json({ ok: true, item: row ? mapCollectionRow(row) : null });
  });

  app.post('/api/widget/categories/:id/expand', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    await ensureProductFeatureTables(prisma);
    const id = Number(req.params.id);
    const existing = Number.isFinite(id) ? await findFeatureRow(prisma, user.id, id) : null;
    if (!existing || existing.kind !== 'collection') {
      res.status(404).json({ error: 'Category not found.' });
      return;
    }
    const payload = normalizeCollectionPayload(existing.payloadJson);
    payload.activeCount = payload.expandedCount;
    const row = await updateFeatureRecord(prisma, user.id, id, safeTitle(payload.name, existing.title), payload, !!existing.archived);
    res.json({ ok: true, item: row ? mapCollectionRow(row) : null });
  });

  app.post('/api/widget/categories/:id/reset', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    await ensureProductFeatureTables(prisma);
    const id = Number(req.params.id);
    const existing = Number.isFinite(id) ? await findFeatureRow(prisma, user.id, id) : null;
    if (!existing || existing.kind !== 'collection') {
      res.status(404).json({ error: 'Category not found.' });
      return;
    }
    const payload = normalizeCollectionPayload(existing.payloadJson);
    payload.activeCount = payload.preferredCount;
    const row = await updateFeatureRecord(prisma, user.id, id, safeTitle(payload.name, existing.title), payload, !!existing.archived);
    res.json({ ok: true, item: row ? mapCollectionRow(row) : null });
  });

  app.post('/api/widget/categories/:id/pin', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    await ensureProductFeatureTables(prisma);
    const id = Number(req.params.id);
    const existing = Number.isFinite(id) ? await findFeatureRow(prisma, user.id, id) : null;
    if (!existing || existing.kind !== 'collection') {
      res.status(404).json({ error: 'Category not found.' });
      return;
    }
    const body = (req.body as { itemId?: unknown; feedUrl?: unknown; pinned?: unknown } | undefined) || {};
    const payload = normalizeCollectionPayload(existing.payloadJson);
    const pinned = body.pinned !== false;
    payload.pinnedStoryId = pinned ? String(body.itemId || '').trim() : '';
    payload.pinnedFeedUrl = pinned ? String(body.feedUrl || '').trim() : '';
    const row = await updateFeatureRecord(prisma, user.id, id, safeTitle(payload.name, existing.title), payload, !!existing.archived);
    res.json({ ok: true, item: row ? mapCollectionRow(row) : null });
  });

  app.post('/api/widget/stories/action', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const body = ((req.body as Record<string, unknown> | undefined) || {});
    const action = String(body.action || '').trim() as WidgetStoryActionKind;
    const itemId = String(body.itemId || '').trim();
    const feedUrl = String(body.feedUrl || '').trim();
    if (!itemId || !feedUrl || !['summary', 'research', 'translation', 'neutral_title', 'refresh'].includes(action)) {
      res.status(400).json({ error: 'Invalid story action payload.' });
      return;
    }
    if (action === 'refresh') {
      if (!refreshFeed) {
        res.status(501).json({ error: 'Feed refresh is not available.' });
        return;
      }
      const refreshed = await refreshFeed(feedUrl);
      res.json({ ok: !!refreshed, action, feedUrl });
      return;
    }
    if (!requestStoryAction) {
      res.status(501).json({ error: 'Story actions are not available.' });
      return;
    }
    const accepted = await requestStoryAction(action, itemId, feedUrl);
    await recordHistoryRaw(prisma, {
      userId: user.id,
      feedUrl,
      itemId,
      stage: 'widget_story_action',
      status: accepted ? 'queued' : 'skipped',
      reason: accepted ? undefined : 'Story action could not be queued.',
      details: { action }
    });
    res.json({ ok: !!accepted, action, itemId, feedUrl });
  });

  app.get('/api/ai-usage/export', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const usage = buildUsageExport(getAiUsage());
    if (String(req.query.format || '').toLowerCase() === 'csv') {
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader('Content-Disposition', 'attachment; filename="ai-usage.csv"');
      res.send(usageExportToCsv(usage));
      return;
    }
    res.json({ ok: true, usage });
  });

  app.post('/api/ai-usage/reset', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const usage = resetAiUsage();
    await recordHistoryRaw(prisma, {
      userId: user.id,
      stage: 'ai_usage',
      status: 'reset',
      reason: 'Usage counters reset by user.'
    });
    res.json({ ok: true, usage: buildUsageExport(usage) });
  });

  app.post('/api/opml/import-preview', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const feeds = parseOpmlFeeds(String((req.body as { opml?: unknown } | undefined)?.opml || ''));
    res.json({ ok: true, feeds });
  });

  app.post('/api/opml/import', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const feeds = parseOpmlFeeds(String((req.body as { opml?: unknown } | undefined)?.opml || ''));
    const added = importFeeds ? importFeeds(feeds) : 0;
    await recordHistoryRaw(prisma, {
      userId: user.id,
      stage: 'opml_import',
      status: added > 0 ? 'imported' : 'skipped',
      reason: added > 0 ? undefined : 'No new feeds to add.',
      details: { added, parsed: feeds.length }
    });
    res.json({ ok: true, feeds, added });
  });

  app.get('/api/opml/export', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const opml = buildOpml(getFeeds());
    res.setHeader('Content-Type', 'text/xml; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename="ai-news-feeds.opml"');
    res.send(opml);
  });

  app.post('/api/share', async (req, res) => {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    await ensureProductFeatureTables(prisma);
    const parsed = shareBodySchema.safeParse(req.body || {});
    if (!parsed.success) {
      res.status(400).json({ error: 'Invalid share payload.' });
      return;
    }
    const token = crypto.randomBytes(18).toString('base64url');
    await prisma.$executeRawUnsafe(
      'INSERT INTO "ShareLink" ("token", "userId", "kind", "title", "payloadJson", "createdAt") VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)',
      token,
      user.id,
      parsed.data.kind,
      parsed.data.title,
      JSON.stringify(parsed.data.payload)
    );
    res.status(201).json({ ok: true, token, url: `/share/${token}` });
  });

  app.get('/api/share/:token', async (req, res) => {
    await ensureProductFeatureTables(prisma);
    const token = String(req.params.token || '').trim();
    const rows = await prisma.$queryRawUnsafe<Array<Record<string, unknown>>>(
      'SELECT "token", "kind", "title", "payloadJson", "createdAt", "expiresAt" FROM "ShareLink" WHERE "token" = ? LIMIT 1',
      token
    );
    const row = rows[0];
    if (!row) {
      res.status(404).json({ error: 'Share link not found.' });
      return;
    }
    res.json({
      ok: true,
      item: {
        token: row.token,
        kind: row.kind,
        title: row.title,
        payload: parseJsonObject(row.payloadJson),
        createdAt: row.createdAt,
        expiresAt: row.expiresAt || null
      }
    });
  });

  const timer = setInterval(() => {
    void runDueAutomation(prisma, getRecentNews).catch(() => {});
  }, 60_000);

  return {
    recordHistory: entry => recordHistoryRaw(prisma, entry).catch(() => {}),
    stop: () => clearInterval(timer)
  };
}
