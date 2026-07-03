import express from 'express';
import type { Server as HttpServer } from 'http';
import Parser from 'rss-parser';
import { WebSocketServer, WebSocket } from 'ws';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import dotenv from 'dotenv';
import OpenAI from 'openai';
import { PrismaClient, type Prisma } from '@prisma/client';
import { aiFeatureSettingsSchema, aiProviderSchema, clientMsgSchema, type ClientMsg } from '@ai-news/shared';
import { z } from 'zod';
import { registerProductFeatureApi, type ProductFeatureRuntime } from './productFeatures';

function bootstrapEnv() {
  const envCandidates = [
    path.resolve(process.cwd(), '.env'),
    path.resolve(process.cwd(), '..', '.env'),
    path.resolve(process.cwd(), '..', '..', '.env'),
    path.resolve(__dirname, '..', '.env'),
    path.resolve(__dirname, '..', '..', '.env'),
    path.resolve(__dirname, '..', '..', '..', '.env')
  ];
  for (const envPath of envCandidates) {
    if (fs.existsSync(envPath)) {
      dotenv.config({ path: envPath, override: false });
    }
  }

  const prismaDirCandidates = [
    path.resolve(process.cwd(), 'prisma'),
    path.resolve(process.cwd(), 'apps', 'api', 'prisma'),
    path.resolve(__dirname, '..', 'prisma'),
    path.resolve(__dirname, '..', '..', 'apps', 'api', 'prisma')
  ];
  const prismaDir = prismaDirCandidates.find(dir => fs.existsSync(path.join(dir, 'schema.prisma')))
    || prismaDirCandidates[0];
  try {
    fs.mkdirSync(prismaDir, { recursive: true });
  } catch {}

  const normalizeSqliteDevDbUrl = (url?: string | null) => {
    const raw = String(url || '').trim();
    if (!raw) return `file:${path.join(prismaDir, 'dev.db')}`;
    if (/^file:(?:\.\/)?dev\.db$/i.test(raw)) return `file:${path.join(prismaDir, 'dev.db')}`;
    return raw;
  };

  process.env.DATABASE_URL = normalizeSqliteDevDbUrl(process.env.DATABASE_URL);
}

bootstrapEnv();

const app = express();
const PORT = Number(process.env.PORT || 4000);
const PORT_SEARCH_LIMIT = Math.max(1, Number.parseInt(process.env.PORT_SEARCH_LIMIT || '20', 10) || 20);
const RUNTIME_INFO_PATH = process.env.AI_NEWS_MAC_WIDGET_RUNTIME_FILE
  ? path.resolve(process.env.AI_NEWS_MAC_WIDGET_RUNTIME_FILE)
  : '/tmp/ai-news-mac-widget-runtime.json';
const prisma = new PrismaClient({
  datasources: {
    db: {
      url: process.env.DATABASE_URL
    }
  }
});
let productFeatures: ProductFeatureRuntime | null = null;

type SummaryLang = 'bg' | 'en' | 'bilingual';
type ResearchLang = 'bg' | 'en';
type TitleDisplayLanguage = 'original' | 'bg' | 'en';
type AIProvider = z.infer<typeof aiProviderSchema>;

enum MoodValue {
  Pesimistic = 'pesimistic',
  Optimistic = 'optimistic',
  Realistic = 'realistic',
  Melancholy = 'melancholy',
  Happiness = 'happiness',
  Sadness = 'sadness',
  Rage = 'rage',
  Uncertainty = 'uncertainty',
  Neutral = 'neutral',
  Curios = 'curios'
}

enum NewsTypeValue {
  Science = 'science',
  Movies = 'movies',
  Politics = 'politics',
  Business = 'business',
  Technology = 'technology',
  Sports = 'sports',
  Health = 'health',
  World = 'world',
  Culture = 'culture',
  Environment = 'environment',
  Crime = 'crime',
  Education = 'education',
  Other = 'other'
}

type Mood = `${MoodValue}`;
type NewsType = `${NewsTypeValue}`;

type FeedKind = 'rss' | 'reddit' | 'youtube';

type BudgetMode = 'low' | 'standard' | 'high';
type InsightConfidence = 'low' | 'medium' | 'high';
type InsightSeverity = 'low' | 'medium' | 'high';
type ImpactLevel = 'low' | 'medium' | 'high';
type BriefingDelivery = 'site' | 'email';
type BriefingFormat = 'executive' | 'bullets' | 'narrative';
type InsightStatus = 'pending' | 'ready' | 'empty';

type AiInsightFeatureSettings = {
  biasDetection: boolean;
  sensationalismDetection: boolean;
  factHighlights: boolean;
  storyImpact: boolean;
  dailyBriefing: boolean;
  topicTracking: boolean;
  perspectiveSimulator: boolean;
  emergingStoryDetector: boolean;
  historicalComparison: boolean;
  futureScenarioGenerator: boolean;
  localImpactDetector: boolean;
};

type BiasInsight = {
  detected: boolean;
  leaning: string;
  emotionalTone: string;
  framing: string;
  confidence: InsightConfidence;
  severity: InsightSeverity;
  summary: string;
};

type SensationalismInsight = {
  detected: boolean;
  level: InsightSeverity;
  reasons: string[];
  alternativeHeadline?: string;
  summary: string;
};

type FactHighlightsInsight = {
  people: string[];
  locations: string[];
  dates: string[];
  numbers: string[];
  quotes: string[];
};

type StoryImpactInsight = {
  score: ImpactLevel;
  economic: string;
  political: string;
  tech: string;
  industries: string[];
  summary: string;
};

type PerspectiveInsight = {
  id: string;
  label: string;
  text: string;
};

type HistoricalComparisonInsight = {
  comparisons: string[];
  explanation: string;
};

type FutureScenarioInsight = {
  disclaimer: string;
  scenarios: string[];
  outlook: string;
};

type LocalImpactInsight = {
  region: string;
  summary: string;
};

type EmergingStorySignal = {
  clusterSize: number;
  sources: string[];
  velocity: 'watch' | 'rising' | 'viral';
  reason: string;
};

type NewsInsights = {
  bias?: BiasInsight;
  sensationalism?: SensationalismInsight;
  facts?: FactHighlightsInsight;
  impact?: StoryImpactInsight;
  perspectives?: PerspectiveInsight[];
  historical?: HistoricalComparisonInsight;
  future?: FutureScenarioInsight;
  localImpact?: LocalImpactInsight;
};

type DailyBriefingResult = {
  type: 'daily_briefing';
  title: string;
  body: string;
  audioScript: string;
  generatedAtMs: number;
  itemCount: number;
  delivery: BriefingDelivery;
  email?: string;
  format: BriefingFormat;
  feedUrls: string[];
};

type SortMode = 'newest' | 'oldest' | 'matched';

type ColumnFilters = {
  onlyMatches: boolean;
  onlyResearched: boolean;
  onlySummaries: boolean;
};

type FeedInfo = {
  url: string;
  label: string;
  kind: FeedKind;
  intervalSec: number;
};

type FeedRuntime = {
  etag?: string;
  lastModified?: string;

  failCount: number;
  disabledUntilMs: number; // circuit breaker
  nextPollAtMs: number;

  lastFetchMs: number;
};

type FeedSettings = {
  summaryEnabled: boolean;
  translationEnabled: boolean;
  researchEnabled: boolean;
  discordWebhookUrl?: string;

  // auto-research guardrails
  budget: BudgetMode;

  // UI controls (persisted)
  sortMode: SortMode;
  filters: ColumnFilters;

  // polling
  intervalSec: number; // persisted override
  kind: FeedKind;
  label?: string;
};

type News = {
  type: 'news';
  id: string;
  title: string;
  titleBg?: string;
  titleEn?: string;
  coverUrl?: string;
  link: string;
  source: string;
  published?: string;
  publishedMs: number;
  feedUrl: string;

  isMatch: boolean;
  matchScore: number;
  filteredOk: boolean;

  summary?: string;
  summaryEligible?: boolean;
  summaryPending?: boolean;
  research?: string;
  researchPending?: boolean;
  titleTranslatePending?: boolean;
  insightStatus?: InsightStatus;
  insights?: NewsInsights;
  topicHits?: string[];
  emergingSignal?: EmergingStorySignal;
  mood?: Mood;
  newsType?: NewsType;
};

type NewsInternal = News & {
  __ctx?: string;
  __linkText?: string; // extracted article text
};

type AiModelKind = 'summary' | 'research' | 'ask';
type AiModelSelection = Record<AiModelKind, string>;
type ProviderModelOptions = Record<AiModelKind, string[]>;
type ModelOptionsByProvider = Record<AIProvider, ProviderModelOptions>;
type AiUsageKindStats = {
  requests: number;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
};
type AiUsageRecentEntry = {
  id: string;
  kind: AiModelKind;
  model: string;
  label: string;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  createdAt: number;
};

type Config = {
  type: 'config';
  keywords: string[];
  newsAccessLocked: boolean;

  aiProvider: AIProvider;
  aiAvailable: boolean;
  aiEnabled: boolean;

  summaryLang: SummaryLang;
  researchLang: ResearchLang;
  titleDisplayLanguage: TitleDisplayLanguage;
  summaryModel: string;
  researchModel: string;
  askModel: string;
  availableModels: ModelOptionsByProvider;
  aiFeatures: AiInsightFeatureSettings;
  localRegion: string;
  localLlmBaseUrl: string;
  trackedTopics: string[];

  matchThreshold: number;
  dedupeThreshold: number;

  filteredAiDedupe: boolean;
  filteredDedupeThreshold: number;

  feeds: FeedInfo[];
  feedSettings: Record<string, FeedSettings>; // by feedUrl
  hiddenIds: string[];
  aiUsageInputTokens: number;
  aiUsageOutputTokens: number;
  aiUsageTotalTokens: number;
  aiUsageRuntimeStartedAt: number;
  aiUsageByKind: Record<AiModelKind, AiUsageKindStats>;
  aiUsageRecent: AiUsageRecentEntry[];
};

type AskAgentReply = {
  type: 'ask_agent_reply';
  id: string;
  feedUrl: string;
  question?: string;
  answer?: string;
  error?: string;
  used: number;
  remaining: number;
};

type FeedPageCursor = {
  beforePublishedMs: number;
  beforeId: string;
};

type FeedPagePayload = {
  type: 'feed_page';
  feedUrl: string;
  items: News[];
  hasMore: boolean;
  nextCursor?: FeedPageCursor;
  replace?: boolean;
};

const parser: Parser = new Parser({
  timeout: 10_000,
  customFields: {
    item: [
      ['media:thumbnail', 'mediaThumbnail', { keepArray: true }],
      ['media:content', 'mediaContent', { keepArray: true }],
      ['media:group', 'mediaGroup'],
      ['itunes:image', 'itunesImage', { keepArray: true }],
      ['yt:videoId', 'ytVideoId']
    ]
  }
});

app.use(express.json({ limit: '512kb' }));
app.use((req, res, next) => {
  const allowOrigin = String(process.env.WEB_ORIGIN || '*').trim() || '*';
  res.setHeader('Access-Control-Allow-Origin', allowOrigin);
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
  next();
});

const AUTH_TOKEN_SECRET = String(process.env.AUTH_TOKEN_SECRET || '').trim();
const KEY_ENCRYPTION_SECRET = String(process.env.KEY_ENCRYPTION_SECRET || '').trim();
const AUTH_TOKEN_TTL_MS = 1000 * 60 * 60 * 24 * 30; // 30 days
const REQUIRE_LOGIN_AND_KEY_FOR_NEWS = String(process.env.REQUIRE_LOGIN_AND_KEY_FOR_NEWS || 'true').trim() !== 'false';
let newsAccessUnlocked = !REQUIRE_LOGIN_AND_KEY_FOR_NEWS;

type AuthTokenPayload = {
  uid: number;
  un: string;
  iat: number;
  exp: number;
};

const authCredentialsSchema = z.object({
  username: z.string().trim().min(3).max(64).regex(/^[a-zA-Z0-9._@+-]+$/),
  password: z.string().min(6).max(256)
});

const providerKeyBodySchema = z.object({
  provider: aiProviderSchema,
  apiKey: z.string().trim().min(10).max(5000)
});

const accountSettingsSchema = z.object({
  persistedAtMs: z.number().finite().nonnegative().optional(),
  language: z.union([z.literal('en'), z.literal('bg')]).optional(),
  colorMode: z.union([z.literal('system'), z.literal('dark'), z.literal('light')]).optional(),
  menuCollapsed: z.boolean().optional(),
  controlsCollapsed: z.boolean().optional(),
  searchVisible: z.boolean().optional(),
  addStreamVisible: z.boolean().optional(),
  allColumnControlsHidden: z.boolean().optional(),
  showFilteredColumn: z.boolean().optional(),
  showEmergingColumn: z.boolean().optional(),
  hideAllResearch: z.boolean().optional(),
  hideAllSummaries: z.boolean().optional(),
  vibe: z.string().trim().min(1).max(64).optional(),
  summaryLang: z.union([z.literal('bg'), z.literal('en'), z.literal('bilingual')]).optional(),
  researchLang: z.union([z.literal('bg'), z.literal('en')]).optional(),
  titleDisplayLanguage: z.union([z.literal('original'), z.literal('bg'), z.literal('en')]).optional(),
  insightFeatures: aiFeatureSettingsSchema.optional(),
  localImpactRegion: z.string().trim().max(120).optional(),
  localLlmBaseUrl: z.string().trim().max(500).optional(),
  trackedTopics: z.array(z.string().trim().min(1).max(120)).max(80).optional(),
  font: z.string().trim().min(1).max(32).optional(),
  fontSize: z.string().trim().min(1).max(32).optional(),
  scheme: z.string().trim().min(1).max(32).optional(),
  timezone: z.string().trim().min(1).max(80).optional(),
  dateFormat: z.string().trim().min(1).max(32).optional(),
  showNewsCovers: z.boolean().optional(),
  performanceMode: z.boolean().optional(),
  buttonMode: z.union([z.literal('icons'), z.literal('text')]).optional(),
  menuHintMode: z.union([z.literal('text'), z.literal('buttons')]).optional(),
  effectIntensity: z.union([z.literal('low'), z.literal('medium'), z.literal('high')]).optional(),
  soundEnabled: z.boolean().optional(),
  soundTheme: z.string().trim().min(1).max(32).optional(),
  notifyEnabled: z.boolean().optional(),
  notifyMode: z.string().trim().min(1).max(32).optional(),
  moodFilter: z.string().trim().min(1).max(32).optional(),
  typeFilter: z.string().trim().min(1).max(32).optional(),
  allBudget: z.union([z.literal('mixed'), z.literal('low'), z.literal('standard'), z.literal('high')]).optional(),
  aiProvider: aiProviderSchema.optional(),
  summaryModel: z.string().trim().min(1).max(120).optional(),
  researchModel: z.string().trim().min(1).max(120).optional(),
  askModel: z.string().trim().min(1).max(120).optional(),
  keywords: z.array(z.string().trim().min(1).max(80)).max(120).optional(),
  dailyBriefingDelivery: z.union([z.literal('site'), z.literal('email')]).optional(),
  dailyBriefingEmail: z.string().trim().max(200).optional(),
  dailyBriefingFormat: z.union([z.literal('executive'), z.literal('bullets'), z.literal('narrative')]).optional(),
  dailyBriefingAudio: z.boolean().optional(),
  dailyBriefingFeedUrls: z.array(z.string().trim().min(1).max(400)).max(80).optional()
}).strict();

function hmacSha256(payload: string, secret: string): string {
  return crypto.createHmac('sha256', secret).update(payload).digest('base64url');
}

function issueAuthToken(payload: AuthTokenPayload): string {
  if (!AUTH_TOKEN_SECRET) {
    throw new Error('AUTH_TOKEN_SECRET is not configured.');
  }
  const body = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
  const sig = hmacSha256(body, AUTH_TOKEN_SECRET);
  return `${body}.${sig}`;
}

function verifyAuthToken(tokenRaw: string): AuthTokenPayload | null {
  const token = String(tokenRaw || '').trim();
  if (!token || !AUTH_TOKEN_SECRET) return null;
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  const [body, signature] = parts;
  const expected = hmacSha256(body, AUTH_TOKEN_SECRET);
  const expectedBuf = Buffer.from(expected);
  const signatureBuf = Buffer.from(signature);
  if (expectedBuf.length !== signatureBuf.length) return null;
  if (!crypto.timingSafeEqual(expectedBuf, signatureBuf)) return null;
  try {
    const decoded = JSON.parse(Buffer.from(body, 'base64url').toString('utf8')) as AuthTokenPayload;
    if (!decoded || typeof decoded.uid !== 'number' || typeof decoded.un !== 'string') return null;
    if (!Number.isFinite(decoded.exp) || decoded.exp <= Date.now()) return null;
    return decoded;
  } catch {
    return null;
  }
}

function hashPassword(passwordRaw: string): string {
  const password = String(passwordRaw || '');
  const salt = crypto.randomBytes(16);
  const derived = crypto.scryptSync(password, salt, 64) as Buffer;
  return `s1:${salt.toString('hex')}:${derived.toString('hex')}`;
}

function verifyPassword(passwordRaw: string, storedHashRaw: string): boolean {
  const password = String(passwordRaw || '');
  const storedHash = String(storedHashRaw || '');
  const parts = storedHash.split(':');
  if (parts.length !== 3 || parts[0] !== 's1') return false;
  try {
    const salt = Buffer.from(parts[1], 'hex');
    const expected = Buffer.from(parts[2], 'hex');
    const derived = crypto.scryptSync(password, salt, expected.length) as Buffer;
    if (derived.length !== expected.length) return false;
    return crypto.timingSafeEqual(derived, expected);
  } catch {
    return false;
  }
}

function getEncryptionKey(): Buffer {
  const secret = KEY_ENCRYPTION_SECRET || AUTH_TOKEN_SECRET;
  if (!secret) throw new Error('KEY_ENCRYPTION_SECRET is not configured.');
  return crypto.createHash('sha256').update(`ai-news-key:${secret}`).digest();
}

function encryptSecret(raw: string): string {
  const plain = String(raw || '').trim();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', getEncryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return `v1:${iv.toString('base64url')}:${tag.toString('base64url')}:${encrypted.toString('base64url')}`;
}

function decryptSecret(raw: string): string {
  const value = String(raw || '').trim();
  const parts = value.split(':');
  if (parts.length !== 4 || parts[0] !== 'v1') {
    throw new Error('Invalid encrypted secret payload.');
  }
  const iv = Buffer.from(parts[1], 'base64url');
  const tag = Buffer.from(parts[2], 'base64url');
  const encrypted = Buffer.from(parts[3], 'base64url');
  const decipher = crypto.createDecipheriv('aes-256-gcm', getEncryptionKey(), iv);
  decipher.setAuthTag(tag);
  const plain = Buffer.concat([decipher.update(encrypted), decipher.final()]);
  return plain.toString('utf8').trim();
}

function readBearerToken(req: express.Request): string {
  const header = String(req.headers.authorization || '').trim();
  const prefix = 'bearer ';
  if (!header.toLowerCase().startsWith(prefix)) return '';
  return header.slice(prefix.length).trim();
}

async function requireAuthUser(req: express.Request, res: express.Response): Promise<{ id: number; username: string } | null> {
  const token = readBearerToken(req);
  const payload = verifyAuthToken(token);
  if (!payload) {
    res.status(401).json({ error: 'Unauthorized' });
    return null;
  }
  const user = await prisma.user.findUnique({
    where: { id: payload.uid },
    select: { id: true, username: true }
  });
  if (!user) {
    res.status(401).json({ error: 'Unauthorized' });
    return null;
  }
  return user;
}

function normalizeAccountSettings(raw: unknown): Record<string, unknown> {
  const parsed = accountSettingsSchema.safeParse(raw);
  if (!parsed.success) return {};
  return parsed.data as Record<string, unknown>;
}

function isNewsAccessLocked(): boolean {
  return REQUIRE_LOGIN_AND_KEY_FOR_NEWS && !newsAccessUnlocked;
}

function isMissingUserSettingsTableError(error: unknown): boolean {
  const code = String((error as { code?: unknown } | null)?.code || '').trim();
  const message = String((error as { message?: unknown } | null)?.message || '');
  if (code === 'P2021') return true;
  if (/UserSettings/i.test(message) && /does not exist|no such table/i.test(message)) return true;
  return false;
}

async function ensureUserSettingsTable(): Promise<void> {
  await prisma.$executeRawUnsafe(`
    CREATE TABLE IF NOT EXISTS "UserSettings" (
      "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      "userId" INTEGER NOT NULL,
      "settingsJson" TEXT NOT NULL,
      "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      "updatedAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      CONSTRAINT "UserSettings_userId_fkey"
        FOREIGN KEY ("userId") REFERENCES "User" ("id")
        ON DELETE CASCADE ON UPDATE CASCADE
    )
  `);
  await prisma.$executeRawUnsafe(
    'CREATE UNIQUE INDEX IF NOT EXISTS "UserSettings_userId_key" ON "UserSettings"("userId")'
  );
}

async function withUserSettingsTableRetry<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (error) {
    if (!isMissingUserSettingsTableError(error)) throw error;
    await ensureUserSettingsTable();
    return fn();
  }
}

app.post('/api/auth/register', async (req, res) => {
  const parsed = authCredentialsSchema.safeParse(req.body || {});
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid username or password.' });
    return;
  }
  const username = parsed.data.username.trim().toLowerCase();
  const password = parsed.data.password;
  try {
    const exists = await prisma.user.findUnique({ where: { username } });
    if (exists) {
      res.status(409).json({ error: 'Username already exists.' });
      return;
    }
    const created = await prisma.user.create({
      data: {
        username,
        passwordHash: hashPassword(password)
      },
      select: { id: true, username: true }
    });
    const token = issueAuthToken({
      uid: created.id,
      un: created.username,
      iat: Date.now(),
      exp: Date.now() + AUTH_TOKEN_TTL_MS
    });
    res.json({ token, user: created });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message || 'Failed to register user.' });
  }
});

app.post('/api/auth/login', async (req, res) => {
  const parsed = authCredentialsSchema.safeParse(req.body || {});
  if (!parsed.success) {
    res.status(400).json({ error: 'Invalid username or password.' });
    return;
  }
  const username = parsed.data.username.trim().toLowerCase();
  const password = parsed.data.password;
  try {
    const user = await prisma.user.findUnique({
      where: { username },
      select: { id: true, username: true, passwordHash: true }
    });
    if (!user || !verifyPassword(password, user.passwordHash)) {
      res.status(401).json({ error: 'Invalid username or password.' });
      return;
    }
    const token = issueAuthToken({
      uid: user.id,
      un: user.username,
      iat: Date.now(),
      exp: Date.now() + AUTH_TOKEN_TTL_MS
    });
    res.json({ token, user: { id: user.id, username: user.username } });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message || 'Failed to sign in.' });
  }
});

app.get('/api/auth/me', async (req, res) => {
  try {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    res.json({ user });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message || 'Failed to load user.' });
  }
});

app.post('/api/auth/provider-key', async (req, res) => {
  try {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const parsed = providerKeyBodySchema.safeParse(req.body || {});
    if (!parsed.success) {
      res.status(400).json({ error: 'Invalid provider or API key.' });
      return;
    }
    const { provider, apiKey } = parsed.data;
    const encryptedKey = encryptSecret(apiKey);
    await prisma.userProviderKey.upsert({
      where: {
        userId_provider: {
          userId: user.id,
          provider
        }
      },
      create: {
        userId: user.id,
        provider,
        encryptedKey
      },
      update: {
        encryptedKey
      }
    });
    res.json({ saved: true });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message || 'Failed to save provider key.' });
  }
});

app.get('/api/auth/provider-key/:provider', async (req, res) => {
  try {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const providerParsed = aiProviderSchema.safeParse(String(req.params.provider || '').trim());
    if (!providerParsed.success) {
      res.status(400).json({ error: 'Invalid provider.' });
      return;
    }
    const row = await prisma.userProviderKey.findUnique({
      where: {
        userId_provider: {
          userId: user.id,
          provider: providerParsed.data
        }
      },
      select: { id: true }
    });
    res.json({ hasKey: !!row });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message || 'Failed to load provider key status.' });
  }
});

app.get('/api/account/settings', async (req, res) => {
  try {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const row = await withUserSettingsTableRetry(() => prisma.userSettings.findUnique({
      where: { userId: user.id },
      select: { settingsJson: true }
    }));
    if (!row || !row.settingsJson) {
      res.json({ settings: {} });
      return;
    }
    let parsed: unknown = {};
    try {
      parsed = JSON.parse(row.settingsJson);
    } catch {
      parsed = {};
    }
    res.json({ settings: normalizeAccountSettings(parsed) });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message || 'Failed to load account settings.' });
  }
});

app.put('/api/account/settings', async (req, res) => {
  try {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const normalized = normalizeAccountSettings((req.body as { settings?: unknown } | undefined)?.settings || {});
    await withUserSettingsTableRetry(() => prisma.userSettings.upsert({
      where: { userId: user.id },
      create: {
        userId: user.id,
        settingsJson: JSON.stringify(normalized)
      },
      update: {
        settingsJson: JSON.stringify(normalized)
      }
    }));
    res.json({ saved: true, settings: normalized });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message || 'Failed to save account settings.' });
  }
});

app.get('/api/runtime/config', async (req, res) => {
  try {
    const user = await requireAuthUser(req, res);
    if (!user) return;
    const activeSelection = currentModelSelection(aiProvider);
    res.json({
      ok: true,
      aiProvider,
      aiAvailable,
      aiEnabled,
      summaryModel: activeSelection.summary,
      researchModel: activeSelection.research,
      askModel: activeSelection.ask,
      summaryLang,
      researchLang,
      titleDisplayLanguage,
      feeds: currentFeeds().map(feed => ({
        ...feed,
        settings: feedSettings.get(feed.url) || defaultSettingsForFeed(feed)
      }))
    });
  } catch (error) {
    res.status(500).json({ error: (error as Error).message || 'Failed to load runtime config.' });
  }
});

app.get('/api/health', (_req, res) => {
  res.json({
    ok: true,
    service: 'ai-news-mac-widget-backend',
    port: Number(process.env.PORT || PORT),
    pid: process.pid,
    now: new Date().toISOString()
  });
});

productFeatures = registerProductFeatureApi({
  app,
  prisma,
  requireAuthUser,
  getFeeds: () => currentFeeds().map(feed => ({
    ...feed,
    discordWebhookUrl: feedSettings.get(feed.url)?.discordWebhookUrl || ''
  })),
  getRecentNews: () => recent.map(item => ({
    id: item.id,
    feedUrl: item.feedUrl,
    title: item.title,
    titleBg: item.titleBg,
    titleEn: item.titleEn,
    link: item.link,
    source: item.source,
    publishedMs: item.publishedMs,
    summary: item.summary,
    research: item.research,
    mood: item.mood,
    newsType: item.newsType,
    isMatch: item.isMatch,
    filteredOk: item.filteredOk,
    summaryPending: !!item.summaryPending,
    researchPending: !!item.researchPending,
    titleTranslatePending: !!item.titleTranslatePending
  })),
  getAiUsage: buildAiUsagePayload,
  resetAiUsage: resetAiUsageCounters,
  importFeeds: feeds => {
    let added = 0;
    for (const feed of feeds) {
      const url = String(feed.xmlUrl || '').trim();
      if (!url || feedsList.some(existing => existing.url === url)) continue;
      const fi: FeedInfo = {
        url,
        label: String(feed.title || url).trim() || url,
        kind: 'rss',
        intervalSec: 120
      };
      feedsList.push(fi);
      ensureFeedSettings(fi);
      ensureFeedRuntime(fi.url);
      added += 1;
    }
    if (added > 0) {
      markDirty();
      broadcastConfig();
    }
    return added;
  },
  requestStoryAction: async (action, itemId, feedUrl) => {
    const item = recent.find(entry => entry.id === itemId && entry.feedUrl === feedUrl);
    if (!item) return false;
    if (action === 'summary') {
      enqueueJob({ kind: 'summary', id: item.id, feedUrl: item.feedUrl, manual: true });
      return true;
    }
    if (action === 'research') {
      enqueueJob({ kind: 'research', id: item.id, feedUrl: item.feedUrl, manual: true });
      return true;
    }
    if (action === 'translation') {
      enqueueJob({ kind: 'title_translate', id: item.id, feedUrl: item.feedUrl, manual: true });
      return true;
    }
    return false;
  },
  refreshFeed: async feedUrl => {
    const feed = currentFeeds().find(entry => entry.url === feedUrl);
    if (!feed) return false;
    await processFeed(feed);
    return true;
  }
});

app.post('/api/maintenance/regenerate', async (req, res) => {
  const user = await requireAuthUser(req, res);
  if (!user) return;
  if (!aiEnabled || !aiAvailable) {
    res.status(409).json({ error: 'AI is disabled or unavailable.' });
    return;
  }

  const body = (req.body || {}) as Record<string, unknown>;
  const kindRaw = String(body.kind || 'all').trim();
  const kind = ['summary', 'translation', 'research', 'all'].includes(kindRaw) ? kindRaw as 'summary' | 'translation' | 'research' | 'all' : 'all';
  const feedUrl = String(body.feedUrl || '').trim();
  const limitRaw = Number(body.limit);
  const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(500, Math.floor(limitRaw))) : 80;
  const missingOnly = body.missingOnly === true;
  const jobs = new Set<AiJobKind>();
  if (kind === 'summary' || kind === 'all') jobs.add('summary');
  if (kind === 'translation' || kind === 'all') jobs.add('title_translate');
  if (kind === 'research' || kind === 'all') jobs.add('research');

  const selected = recent
    .slice()
    .sort((a, b) => b.publishedMs - a.publishedMs)
    .filter(item => {
      if (hiddenIds.has(item.id)) return false;
      if (!feedUrl) return true;
      if (feedUrl === FILTERED_FEED_URL) return item.isMatch && item.filteredOk !== false;
      return item.feedUrl === feedUrl;
    })
    .slice(0, limit);

  const queued = { summary: 0, translation: 0, research: 0 };
  const skipped = { summary: 0, translation: 0, research: 0 };
  const writes: Array<Promise<unknown>> = [];

  for (const item of selected) {
    let changed = false;
    if (jobs.has('summary')) {
      if (activeModel('summary') === 'none' || !shouldHaveSummary(item) || hasSummaryJobQueuedOrRunning(item.id, item.feedUrl) || (missingOnly && !!String(item.summary || '').trim())) {
        skipped.summary += 1;
      } else {
        if (!missingOnly) item.summary = '';
        summaryRetryCooldownUntilMs.delete(summaryItemKey(item.id, item.feedUrl));
        enqueueJob({ kind: 'summary', id: item.id, feedUrl: item.feedUrl, manual: true });
        if (hasSummaryJobQueuedOrRunning(item.id, item.feedUrl)) queued.summary += 1;
        changed = true;
      }
    }

    if (jobs.has('title_translate')) {
      const hasTranslation = hasValidOppositeLanguageTitle(item.title, item.titleBg, item.titleEn);
      if (activeModel('summary') === 'none' || !isTranslationEnabledForFeed(item.feedUrl) || hasTitleTranslateJobQueuedOrRunning(item.id, item.feedUrl) || (missingOnly && hasTranslation)) {
        skipped.translation += 1;
      } else {
        if (!missingOnly) {
          item.titleBg = undefined;
          item.titleEn = undefined;
        }
        enqueueJob({ kind: 'title_translate', id: item.id, feedUrl: item.feedUrl, manual: true });
        if (hasTitleTranslateJobQueuedOrRunning(item.id, item.feedUrl)) queued.translation += 1;
        changed = true;
      }
    }

    if (jobs.has('research')) {
      if (activeModel('research') === 'none' || !shouldHaveResearch(item) || hasResearchJobQueuedOrRunning(item.id, item.feedUrl) || (missingOnly && !!String(item.research || '').trim())) {
        skipped.research += 1;
      } else {
        if (!missingOnly) item.research = '';
        enqueueJob({ kind: 'research', id: item.id, feedUrl: item.feedUrl, manual: true });
        if (hasResearchJobQueuedOrRunning(item.id, item.feedUrl)) queued.research += 1;
        changed = true;
      }
    }

    if (changed) {
      refreshDerivedDataForItem(item);
      writes.push(upsertPersistedNewsItem(item).catch(() => undefined));
      broadcastNewsUpdate(item);
    }
  }

  await Promise.all(writes);
  if (writes.length) {
    markDirty();
    broadcastConfig();
  }
  void productFeatures?.recordHistory({
    userId: user.id,
    stage: 'maintenance_regenerate',
    status: 'queued',
    reason: missingOnly ? 'Fill missing AI outputs.' : 'Regenerate selected AI outputs.',
    details: { kind, feedUrl: feedUrl || null, limit, selected: selected.length, queued, skipped }
  });
  res.json({ ok: true, kind, feedUrl: feedUrl || null, limit, selected: selected.length, queued, skipped, missingOnly });
});

app.get('/', (_req, res) => {
  res.json({
    ok: true,
    service: 'ai-news-api',
    message: 'API server is running.',
    links: {
      web: 'http://localhost:3000',
      health: '/health',
      websocket: `ws://localhost:${PORT}`
    }
  });
});

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'ai-news-api' });
});

app.get('/api/ops/ai-jobs', (req, res) => {
  const kindRaw = String(req.query.kind || '').trim();
  const stageRaw = String(req.query.stage || '').trim();
  const limitRaw = Number(req.query.limit);
  const deadLimitRaw = Number(req.query.deadLimit);
  const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(1000, Math.floor(limitRaw))) : 120;
  const deadLimit = Number.isFinite(deadLimitRaw) ? Math.max(1, Math.min(400, Math.floor(deadLimitRaw))) : 40;

  const kinds: AiJobKind[] = ['summary', 'title_translate', 'research', 'mood', 'news_type'];
  const stages: AiJobLogStage[] = ['enqueue', 'start', 'success', 'skip', 'drop', 'error'];
  const kindFilter = kinds.includes(kindRaw as AiJobKind) ? (kindRaw as AiJobKind) : '';
  const stageFilter = stages.includes(stageRaw as AiJobLogStage) ? (stageRaw as AiJobLogStage) : '';

  const events = aiJobLogEvents
    .filter(e => (!kindFilter || e.kind === kindFilter) && (!stageFilter || e.stage === stageFilter))
    .slice(-limit)
    .reverse();

  const deadLetters = aiDeadLetters
    .slice(-deadLimit)
    .reverse();

  const queuePreview = aiQueue
    .slice(-Math.min(limit, 200))
    .map(job => ({
      kind: job.kind,
      id: job.id,
      feedUrl: job.feedUrl,
      manual: !!job.manual,
      enqueuedAtMs: job.enqueuedAtMs,
      ageMs: Math.max(0, Date.now() - job.enqueuedAtMs)
    }))
    .reverse();

  const inFlightKeys = Array.from(aiInFlight).slice(-Math.min(limit, 200));

  res.json({
    ok: true,
    now: new Date().toISOString(),
    newsAccessLocked: isNewsAccessLocked(),
    storage: {
      persistEnabled: AI_JOB_LOG_PERSIST,
      logDir: AI_JOB_LOG_DIR,
      logFile: AI_JOB_LOG_FILE_PATH,
      bufferedEvents: aiJobLogFileBuffer.length,
      rotateBytes: AI_JOB_LOG_ROTATE_BYTES,
      rotateFiles: AI_JOB_LOG_ROTATE_FILES
    },
    queue: {
      size: aiQueue.length,
      countsByKind: aiQueueCounts(),
      inFlight: aiInFlight.size,
      deadLetters: aiDeadLetters.length,
      queuedJobs: queuePreview,
      inFlightKeys
    },
    events,
    deadLetters
  });
});

app.get('/api/ops/ai-summary-debug', (req, res) => {
  const itemId = String(req.query.itemId || '').trim();
  const feedUrl = String(req.query.feedUrl || '').trim();
  const statusRaw = String(req.query.status || '').trim();
  const limitRaw = Number(req.query.limit);
  const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(500, Math.floor(limitRaw))) : 80;
  const statuses: SummaryDebugEvent['status'][] = ['start', 'success', 'empty', 'error'];
  const status = statuses.includes(statusRaw as SummaryDebugEvent['status'])
    ? (statusRaw as SummaryDebugEvent['status'])
    : '';

  const events = summaryDebugEvents
    .filter(event => (!itemId || event.itemId === itemId) && (!feedUrl || event.feedUrl === feedUrl) && (!status || event.status === status))
    .slice(-limit)
    .reverse();

  res.json({
    ok: true,
    now: new Date().toISOString(),
    provider: aiProvider,
    model: activeModel('summary'),
    aiAvailable,
    aiEnabled,
    events
  });
});

let server: HttpServer;
let wss: WebSocketServer;

function listenOnPort(port: number) {
  return new Promise<HttpServer>((resolve, reject) => {
    const nextServer = app.listen(port, () => resolve(nextServer));
    nextServer.once('error', reject);
  });
}

async function bindServer(startPort: number) {
  let attemptPort = startPort;
  for (let attempt = 0; attempt < PORT_SEARCH_LIMIT; attempt += 1) {
    try {
      const boundServer = await listenOnPort(attemptPort);
      process.env.PORT = String(attemptPort);
      if (attemptPort !== startPort) {
        console.warn(`[startup] Port ${startPort} was busy, switched to ${attemptPort}.`);
      }
      return { boundServer, port: attemptPort };
    } catch (error) {
      const code = String((error as NodeJS.ErrnoException | undefined)?.code || '');
      if (code !== 'EADDRINUSE') throw error;
      attemptPort += 1;
    }
  }
  throw new Error(`Could not find a free port in range ${startPort}-${startPort + PORT_SEARCH_LIMIT - 1}.`);
}

// -------------------- Runtime timer (exit after X hours) --------------------
const RUNTIME_HOURS = parseFloat(process.env.RUNTIME_HOURS || '0');
const RUNTIME_MS =
  Number.isFinite(RUNTIME_HOURS) && RUNTIME_HOURS > 0
    ? RUNTIME_HOURS * 60 * 60 * 1000
    : 0;

function shutdown(reason: string) {
  console.log(`Shutting down: ${reason}`);
  try {
    const currentRuntimeInfo = fs.existsSync(RUNTIME_INFO_PATH)
      ? JSON.parse(fs.readFileSync(RUNTIME_INFO_PATH, 'utf8')) as { pid?: unknown }
      : null;
    if (!currentRuntimeInfo || Number(currentRuntimeInfo.pid || 0) === process.pid) {
      fs.rmSync(RUNTIME_INFO_PATH, { force: true });
    }
  } catch {}
  try {
    stopAiJobLogFlushTimer();
    flushAiJobLogBufferNow();
    productFeatures?.stop();
  } catch {}
  try {
    wss?.clients.forEach((c: WebSocket) => {
      try { c.close(); } catch {}
    });
  } catch {}
  try { wss?.close(); } catch {}
  try { server?.close(() => process.exit(0)); } catch { process.exit(0); }
  void prisma.$disconnect().catch(() => {});
  setTimeout(() => process.exit(0), 1500);
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
void bindServer(PORT)
  .then(({ boundServer, port }) => {
    server = boundServer;
    wss = new WebSocketServer({ server });
    registerWebSocketHandlers(wss);
    try {
      fs.writeFileSync(RUNTIME_INFO_PATH, JSON.stringify({
        url: `http://127.0.0.1:${port}`,
        port,
        pid: process.pid,
        startedAt: new Date().toISOString()
      }, null, 2));
    } catch (error) {
      console.warn(`[startup] Failed to write runtime info: ${String((error as Error).message || error)}`);
    }
    console.log(`Live RSS running at http://localhost:${port}`);
  })
  .catch(error => {
    console.error('Failed to start server:', (error as Error).message || error);
    process.exit(1);
  });
// ---------------------------------------------------------------------------

const FILTERED_FEED_URL = '__filtered__';
const CURRENT_STATE_VERSION = 4;
const IGN_FEED_URL = 'https://www.ign.com/rss/v2/articles/feed?categories=news';
const LEGACY_CAPITAL_FEED_URL = 'https://capital.bg/rss';
const CAPITAL_FEED_URL = 'https://www.capital.bg/rss/';
const LEGACY_SVOBODNA_EVROPA_FEED_URL = 'https://www.svobodnaevropa.bg/api/epiqq';
const SVOBODNA_TOCHKA_FEED_URL = 'https://svobodnatochka.bg/feed/';
const SVOBODNA_TOCHKA_DEFAULT_FEED: FeedInfo = {
  url: SVOBODNA_TOCHKA_FEED_URL,
  label: 'Svobodna Tochka',
  kind: 'rss',
  intervalSec: 180
};
const DEFAULT_FEED_MIGRATIONS: Record<number, string[]> = {
  2: [IGN_FEED_URL],
  3: [SVOBODNA_TOCHKA_FEED_URL],
  4: [CAPITAL_FEED_URL]
};

// ✅ Default feeds — ORDER MATTERS
const defaultFeeds: FeedInfo[] = [
  { url: 'https://www.dnevnik.bg/rss/', label: 'dnevnik.bg', kind: 'rss', intervalSec: 75 },
  { url: 'https://standartnews.com/rss?p=1', label: 'standartnews.com', kind: 'rss', intervalSec: 90 },
  { url: 'https://www.bta.bg/en/rss/free', label: 'BTA', kind: 'rss', intervalSec: 120 },
  { url: CAPITAL_FEED_URL, label: 'capital.bg', kind: 'rss', intervalSec: 90 },
  { url: 'https://actualno.com/rss', label: 'actualno.com', kind: 'rss', intervalSec: 90 },
  { url: 'http://feeds.bbci.co.uk/news/world/rss.xml', label: 'BBC World', kind: 'rss', intervalSec: 120 },
  { url: 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml', label: 'NYT World', kind: 'rss', intervalSec: 150 },
  { url: 'https://www.aljazeera.com/xml/rss/all.xml', label: 'Al Jazeera', kind: 'rss', intervalSec: 120 },
  { url: 'https://hollywoodreporter.com/feed', label: 'Hollywood Reporter', kind: 'rss', intervalSec: 180 },
  { url: 'https://hollywoodreporter.com/c/movies/feed', label: 'THR Movies', kind: 'rss', intervalSec: 240 },
  { url: 'https://hollywoodreporter.com/c/tv/feed', label: 'THR TV', kind: 'rss', intervalSec: 240 },
  { url: 'https://hollywoodreporter.com/c/music/feed', label: 'THR Music', kind: 'rss', intervalSec: 240 },
  { url: 'https://www.npr.org/rss/rss.php?id=1008', label: 'NPR Music', kind: 'rss', intervalSec: 180 },
  { url: 'https://www.npr.org/rss/rss.php?id=1045', label: 'NPR Movies', kind: 'rss', intervalSec: 180 },
  { url: IGN_FEED_URL, label: 'IGN', kind: 'rss', intervalSec: 180 },
  { url: 'https://feeds.feedburner.com/variety/headlines', label: 'Variety', kind: 'rss', intervalSec: 180 },
  { url: 'https://www.rollingstone.com/music/music-news/feed/', label: 'Rolling Stone', kind: 'rss', intervalSec: 180 },
  { url: 'https://rss.nytimes.com/services/xml/rss/nyt/Movies.xml', label: 'NYT Movies', kind: 'rss', intervalSec: 180 },
  SVOBODNA_TOCHKA_DEFAULT_FEED
];

function normalizeKeywordList(input: string[]): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const raw of input) {
    const value = String(raw || '').trim();
    if (!value) continue;
    const key = normalizeText(value);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    out.push(value);
  }
  return out;
}

function parseKeywordsCsv(raw: string): string[] {
  return normalizeKeywordList(
    String(raw || '')
      .split(/[,\n]+/g)
      .map(s => s.trim())
      .filter(Boolean)
  );
}

function parseKeywordsPayload(payload: unknown): string[] {
  if (typeof payload === 'string') {
    return parseKeywordsCsv(payload);
  }
  if (Array.isArray(payload)) {
    return normalizeKeywordList(payload.map(v => (typeof v === 'string' ? v : '')));
  }
  return [];
}

function parseKeywords(): string[] {
  const fromArg = process.argv.find(a => a.startsWith('--keywords='));
  const raw =
    (fromArg ? fromArg.slice('--keywords='.length) : '') ||
    process.env.KEYWORDS ||
    '';
  return parseKeywordsCsv(raw);
}
let keywords = parseKeywords();

const DEFAULT_AI_INSIGHT_FEATURES: AiInsightFeatureSettings = {
  biasDetection: false,
  sensationalismDetection: false,
  factHighlights: false,
  storyImpact: false,
  dailyBriefing: false,
  topicTracking: false,
  perspectiveSimulator: false,
  emergingStoryDetector: false,
  historicalComparison: false,
  futureScenarioGenerator: false,
  localImpactDetector: false
};

function isLegacyAutoEnabledInsightFeatures(input: unknown): boolean {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return false;
  const features = input as Record<string, unknown>;
  return features.biasDetection === true
    && features.sensationalismDetection === true
    && features.factHighlights === true
    && features.storyImpact === true
    && features.dailyBriefing === true
    && features.topicTracking === true
    && features.perspectiveSimulator === true
    && features.emergingStoryDetector === true
    && features.historicalComparison === false
    && features.futureScenarioGenerator === false
    && features.localImpactDetector === false;
}

function normalizeTrimmedList(input: unknown, max = 80): string[] {
  if (!Array.isArray(input)) return [];
  const out: string[] = [];
  const seen = new Set<string>();
  for (const raw of input) {
    const value = String(raw || '').trim();
    if (!value) continue;
    const key = value.toLocaleLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(value.slice(0, 120));
    if (out.length >= max) break;
  }
  return out;
}

function normalizeAiFeatureSettings(
  input: unknown,
  fallback: AiInsightFeatureSettings = DEFAULT_AI_INSIGHT_FEATURES
): AiInsightFeatureSettings {
  const src = (input && typeof input === 'object') ? input as Record<string, unknown> : {};
  return {
    biasDetection: typeof src.biasDetection === 'boolean' ? src.biasDetection : fallback.biasDetection,
    sensationalismDetection: typeof src.sensationalismDetection === 'boolean' ? src.sensationalismDetection : fallback.sensationalismDetection,
    factHighlights: typeof src.factHighlights === 'boolean' ? src.factHighlights : fallback.factHighlights,
    storyImpact: false,
    dailyBriefing: typeof src.dailyBriefing === 'boolean' ? src.dailyBriefing : fallback.dailyBriefing,
    topicTracking: typeof src.topicTracking === 'boolean' ? src.topicTracking : fallback.topicTracking,
    perspectiveSimulator: false,
    emergingStoryDetector: typeof src.emergingStoryDetector === 'boolean' ? src.emergingStoryDetector : fallback.emergingStoryDetector,
    historicalComparison: false,
    futureScenarioGenerator: false,
    localImpactDetector: false
  };
}

let aiFeatures: AiInsightFeatureSettings = { ...DEFAULT_AI_INSIGHT_FEATURES };
let localRegion = 'United States';
let trackedTopics: string[] = [];

// ---- AI configuration (.env) ----
const aiProviderParsed = aiProviderSchema.safeParse(process.env.AI_PROVIDER || 'openai');
let aiProvider: AIProvider = aiProviderParsed.success ? aiProviderParsed.data : 'openai';

const providerApiKeys: Record<AIProvider, string> = {
  openai: String(process.env.OPENAI_API_KEY || '').trim(),
  claude: String(process.env.ANTHROPIC_API_KEY || process.env.CLAUDE_API_KEY || '').trim(),
  openrouter: String(process.env.OPENROUTER_API_KEY || '').trim(),
  local: ''
};
const DEFAULT_LOCAL_LLM_BASE_URL = String(process.env.LOCAL_LLM_BASE_URL || process.env.OPENAI_BASE_URL || 'http://localhost:11434/v1').trim();

const EMBED_MODEL =
  process.env.OPENAI_EMBED_MODEL ||
  process.env.EMBED_MODEL ||
  'text-embedding-3-small';

const OPENAI_SUMMARY_MODEL =
  process.env.OPENAI_SUMMARY_MODEL ||
  process.env.SUMMARY_MODEL ||
  'gpt-4.1-nano';

const OPENAI_RESEARCH_MODEL =
  process.env.OPENAI_RESEARCH_MODEL ||
  process.env.RESEARCH_MODEL ||
  'gpt-4.1-mini';

const OPENAI_ASK_MODEL =
  process.env.OPENAI_ASK_MODEL ||
  process.env.ASK_MODEL ||
  'gpt-4.1-nano';

const CLAUDE_SUMMARY_MODEL =
  process.env.CLAUDE_SUMMARY_MODEL ||
  process.env.SUMMARY_MODEL ||
  'claude-3-5-haiku-latest';

const CLAUDE_RESEARCH_MODEL =
  process.env.CLAUDE_RESEARCH_MODEL ||
  process.env.RESEARCH_MODEL ||
  'claude-3-7-sonnet-latest';

const CLAUDE_ASK_MODEL =
  process.env.CLAUDE_ASK_MODEL ||
  process.env.ASK_MODEL ||
  'claude-3-5-haiku-latest';

const OPENROUTER_SUMMARY_MODEL =
  process.env.OPENROUTER_SUMMARY_MODEL ||
  process.env.SUMMARY_MODEL ||
  'openai/gpt-4.1-mini';

const OPENROUTER_RESEARCH_MODEL =
  process.env.OPENROUTER_RESEARCH_MODEL ||
  process.env.RESEARCH_MODEL ||
  'openai/gpt-4.1';

const OPENROUTER_ASK_MODEL =
  process.env.OPENROUTER_ASK_MODEL ||
  process.env.ASK_MODEL ||
  'openai/gpt-4.1-mini';

const LOCAL_SUMMARY_MODEL =
  process.env.LOCAL_SUMMARY_MODEL ||
  process.env.SUMMARY_MODEL ||
  'llama3.1';

const LOCAL_RESEARCH_MODEL =
  process.env.LOCAL_RESEARCH_MODEL ||
  process.env.RESEARCH_MODEL ||
  LOCAL_SUMMARY_MODEL;

const LOCAL_ASK_MODEL =
  process.env.LOCAL_ASK_MODEL ||
  process.env.ASK_MODEL ||
  LOCAL_SUMMARY_MODEL;

const LOCAL_EMBED_MODEL =
  process.env.LOCAL_EMBED_MODEL ||
  process.env.EMBED_MODEL ||
  'nomic-embed-text';

function parseModelCsv(raw: string | undefined): string[] {
  if (!raw) return [];
  return raw
    .split(',')
    .map(x => x.trim())
    .filter(Boolean);
}

function uniqueModels(models: string[]): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const model of models) {
    const id = String(model || '').trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push(id);
  }
  return out;
}

function buildModelOptions(primary: string, fallback: string[]): string[] {
  return uniqueModels([primary, ...fallback]);
}

const modelOptionsByProvider: ModelOptionsByProvider = {
  openai: {
    summary: buildModelOptions(
      OPENAI_SUMMARY_MODEL,
      parseModelCsv(process.env.OPENAI_SUMMARY_MODEL_OPTIONS)
        .concat(['gpt-4.1-nano', 'gpt-4.1-mini', 'gpt-4o-mini', 'gpt-4.1'])
    ),
    research: buildModelOptions(
      OPENAI_RESEARCH_MODEL,
      parseModelCsv(process.env.OPENAI_RESEARCH_MODEL_OPTIONS)
        .concat(['gpt-4.1-mini', 'gpt-4.1', 'gpt-4o-mini'])
    ),
    ask: buildModelOptions(
      OPENAI_ASK_MODEL,
      parseModelCsv(process.env.OPENAI_ASK_MODEL_OPTIONS)
        .concat(['gpt-4.1-nano', 'gpt-4.1-mini', 'gpt-4o-mini'])
    )
  },
  claude: {
    summary: buildModelOptions(
      CLAUDE_SUMMARY_MODEL,
      parseModelCsv(process.env.CLAUDE_SUMMARY_MODEL_OPTIONS)
        .concat(['claude-3-5-haiku-latest', 'claude-3-7-sonnet-latest'])
    ),
    research: buildModelOptions(
      CLAUDE_RESEARCH_MODEL,
      parseModelCsv(process.env.CLAUDE_RESEARCH_MODEL_OPTIONS)
        .concat(['claude-3-7-sonnet-latest', 'claude-3-5-haiku-latest'])
    ),
    ask: buildModelOptions(
      CLAUDE_ASK_MODEL,
      parseModelCsv(process.env.CLAUDE_ASK_MODEL_OPTIONS)
        .concat(['claude-3-5-haiku-latest', 'claude-3-7-sonnet-latest'])
    )
  },
  openrouter: {
    summary: buildModelOptions(
      OPENROUTER_SUMMARY_MODEL,
      parseModelCsv(process.env.OPENROUTER_SUMMARY_MODEL_OPTIONS)
        .concat(['openai/gpt-4.1-mini', 'openai/gpt-4.1', 'anthropic/claude-3.5-haiku'])
    ),
    research: buildModelOptions(
      OPENROUTER_RESEARCH_MODEL,
      parseModelCsv(process.env.OPENROUTER_RESEARCH_MODEL_OPTIONS)
        .concat(['openai/gpt-4.1', 'openai/gpt-4.1-mini', 'anthropic/claude-3.7-sonnet'])
    ),
    ask: buildModelOptions(
      OPENROUTER_ASK_MODEL,
      parseModelCsv(process.env.OPENROUTER_ASK_MODEL_OPTIONS)
        .concat(['openai/gpt-4.1-mini', 'openai/gpt-4.1-nano', 'anthropic/claude-3.5-haiku'])
    )
  },
  local: {
    summary: buildModelOptions(
      LOCAL_SUMMARY_MODEL,
      parseModelCsv(process.env.LOCAL_SUMMARY_MODEL_OPTIONS).concat([LOCAL_SUMMARY_MODEL])
    ),
    research: buildModelOptions(
      LOCAL_RESEARCH_MODEL,
      parseModelCsv(process.env.LOCAL_RESEARCH_MODEL_OPTIONS).concat([LOCAL_RESEARCH_MODEL])
    ),
    ask: buildModelOptions(
      LOCAL_ASK_MODEL,
      parseModelCsv(process.env.LOCAL_ASK_MODEL_OPTIONS).concat([LOCAL_ASK_MODEL])
    )
  }
};

const selectedModelsByProvider: Record<AIProvider, AiModelSelection> = {
  openai: {
    summary: modelOptionsByProvider.openai.summary[0] || OPENAI_SUMMARY_MODEL,
    research: modelOptionsByProvider.openai.research[0] || OPENAI_RESEARCH_MODEL,
    ask: modelOptionsByProvider.openai.ask[0] || OPENAI_ASK_MODEL
  },
  claude: {
    summary: modelOptionsByProvider.claude.summary[0] || CLAUDE_SUMMARY_MODEL,
    research: modelOptionsByProvider.claude.research[0] || CLAUDE_RESEARCH_MODEL,
    ask: modelOptionsByProvider.claude.ask[0] || CLAUDE_ASK_MODEL
  },
  openrouter: {
    summary: modelOptionsByProvider.openrouter.summary[0] || OPENROUTER_SUMMARY_MODEL,
    research: modelOptionsByProvider.openrouter.research[0] || OPENROUTER_RESEARCH_MODEL,
    ask: modelOptionsByProvider.openrouter.ask[0] || OPENROUTER_ASK_MODEL
  },
  local: {
    summary: modelOptionsByProvider.local.summary[0] || LOCAL_SUMMARY_MODEL,
    research: modelOptionsByProvider.local.research[0] || LOCAL_RESEARCH_MODEL,
    ask: modelOptionsByProvider.local.ask[0] || LOCAL_ASK_MODEL
  }
};

const ASK_AGENT_MAX_QUESTIONS = 5;
const ASK_AGENT_MAX_CHARS = 400;
const ASK_AGENT_RESEARCH_TIMEOUT_MS = 8_000;
const ASK_AGENT_ANSWER_TIMEOUT_MS = 22_000;

const MATCH_THRESHOLD = parseFloat(process.env.MATCH_THRESHOLD || '0.72');
const DEDUPE_THRESHOLD = parseFloat(process.env.DEDUPE_THRESHOLD || '0.92');

const FILTERED_AI_DEDUPE =
  (process.env.FILTERED_AI_DEDUPE || 'true') !== 'false';

const FILTERED_DEDUPE_THRESHOLD = parseFloat(
  process.env.FILTERED_DEDUPE_THRESHOLD || '0.90'
);

// Summary defaults
const SUMMARY_DEFAULT_FILTERED =
  (process.env.SUMMARY_DEFAULT_FILTERED || 'true') !== 'false';
const SUMMARY_DEFAULT_ALL =
  (process.env.SUMMARY_DEFAULT_ALL || 'false') === 'true';

// Research defaults
const RESEARCH_DEFAULT_FILTERED =
  (process.env.RESEARCH_DEFAULT_FILTERED || 'false') === 'true';
const RESEARCH_DEFAULT_ALL =
  (process.env.RESEARCH_DEFAULT_ALL || 'false') === 'true';

let openaiEmbeddingClient: OpenAI | null = null;
let openaiGenerationClient: OpenAI | null = null;
let openrouterGenerationClient: OpenAI | null = null;
let localEmbeddingClient: OpenAI | null = null;
let localGenerationClient: OpenAI | null = null;
let localLlmBaseUrl = DEFAULT_LOCAL_LLM_BASE_URL;
let aiAvailable: boolean = false;

function activeModel(kind: AiModelKind): string {
  return selectedModelsByProvider[aiProvider][kind] || 'none';
}

function providerSupportsModel(provider: AIProvider, kind: AiModelKind, model: string): boolean {
  if (provider === 'local') return !!String(model || '').trim();
  return modelOptionsByProvider[provider][kind].includes(model);
}

function currentModelSelection(provider: AIProvider): AiModelSelection {
  return { ...selectedModelsByProvider[provider] };
}

function activeOpenAiLikeClient(): OpenAI | null {
  if (aiProvider === 'local') return localGenerationClient;
  if (aiProvider === 'openrouter') return openrouterGenerationClient;
  if (aiProvider === 'openai') return openaiGenerationClient;
  return null;
}

function activeEmbeddingClient(): OpenAI | null {
  if (aiProvider === 'local') return localEmbeddingClient;
  return openaiEmbeddingClient;
}

function activeProviderHasKey(provider: AIProvider): boolean {
  if (provider === 'local') return !!String(localLlmBaseUrl || '').trim();
  return provider === 'claude'
    ? !!providerApiKeys.claude
    : provider === 'openrouter'
      ? !!openrouterGenerationClient
      : !!openaiGenerationClient;
}

function refreshAiClients() {
  const localBaseUrl = String(localLlmBaseUrl || '').trim();
  openaiEmbeddingClient = providerApiKeys.openai
    ? new OpenAI({ apiKey: providerApiKeys.openai })
    : null;
  openaiGenerationClient = providerApiKeys.openai
    ? new OpenAI({ apiKey: providerApiKeys.openai })
    : null;
  openrouterGenerationClient = providerApiKeys.openrouter
    ? new OpenAI({
      apiKey: providerApiKeys.openrouter,
      baseURL: process.env.OPENROUTER_BASE_URL || 'https://openrouter.ai/api/v1'
    })
    : null;
  localEmbeddingClient = localBaseUrl
    ? new OpenAI({
      apiKey: process.env.LOCAL_LLM_API_KEY || 'local',
      baseURL: localBaseUrl
    })
    : null;
  localGenerationClient = localBaseUrl
    ? new OpenAI({
      apiKey: process.env.LOCAL_LLM_API_KEY || 'local',
      baseURL: localBaseUrl
    })
    : null;
  aiAvailable = activeProviderHasKey(aiProvider);
}

function setAiProviderKey(provider: AIProvider, apiKey?: string) {
  const next = String(apiKey || '').trim();
  if (next) providerApiKeys[provider] = next;
  refreshAiClients();
}

async function resolveSavedProviderKey(authTokenRaw: string, provider: AIProvider): Promise<string | null> {
  const payload = verifyAuthToken(authTokenRaw);
  if (!payload) return null;
  const row = await prisma.userProviderKey.findUnique({
    where: {
      userId_provider: {
        userId: payload.uid,
        provider
      }
    },
    select: { encryptedKey: true }
  });
  if (!row?.encryptedKey) return null;
  try {
    return decryptSecret(row.encryptedKey);
  } catch {
    return null;
  }
}

refreshAiClients();

let aiEnabled: boolean =
  (process.env.AI_ENABLED ? process.env.AI_ENABLED !== 'false' : true) &&
  aiAvailable;

let summaryLang: SummaryLang = (process.env.SUMMARY_LANG as SummaryLang) || 'bilingual';
if (!['bg', 'en', 'bilingual'].includes(summaryLang)) summaryLang = 'bilingual';

let researchLang: ResearchLang = (process.env.RESEARCH_LANG as ResearchLang) || 'bg';
if (!['bg', 'en'].includes(researchLang)) researchLang = 'bg';

let titleDisplayLanguage: TitleDisplayLanguage = 'original';

const AI_USAGE_LOG_LIMIT = 80;
const aiUsageRuntimeStartedAt = Date.now();
let aiUsageInputTokens = 0;
let aiUsageOutputTokens = 0;
let aiUsageTotalTokens = 0;
let aiUsageSequence = 0;
const aiUsageByKind: Record<AiModelKind, AiUsageKindStats> = {
  summary: { requests: 0, inputTokens: 0, outputTokens: 0, totalTokens: 0 },
  research: { requests: 0, inputTokens: 0, outputTokens: 0, totalTokens: 0 },
  ask: { requests: 0, inputTokens: 0, outputTokens: 0, totalTokens: 0 }
};
const aiUsageRecent: AiUsageRecentEntry[] = [];

function normalizeAiUsageLabel(labelRaw: unknown) {
  const label = String(labelRaw || '').replace(/\s+/g, ' ').trim();
  if (!label) return '';
  if (label.length <= 120) return label;
  const cut = label.slice(0, 120);
  const lastSpace = cut.lastIndexOf(' ');
  return `${(lastSpace > 48 ? cut.slice(0, lastSpace) : cut).trim()}...`;
}

function buildAiUsagePayload() {
  return {
    aiUsageInputTokens,
    aiUsageOutputTokens,
    aiUsageTotalTokens,
    aiUsageRuntimeStartedAt,
    aiUsageByKind: {
      summary: { ...aiUsageByKind.summary },
      research: { ...aiUsageByKind.research },
      ask: { ...aiUsageByKind.ask }
    },
    aiUsageRecent: aiUsageRecent.map(entry => ({ ...entry }))
  };
}

function broadcastAiUsageSnapshot() {
  const payload = JSON.stringify({
    type: 'ai_usage',
    inputTokens: aiUsageInputTokens,
    outputTokens: aiUsageOutputTokens,
    totalTokens: aiUsageTotalTokens,
    runtimeStartedAt: aiUsageRuntimeStartedAt,
    byKind: {
      summary: { ...aiUsageByKind.summary },
      research: { ...aiUsageByKind.research },
      ask: { ...aiUsageByKind.ask }
    },
    recent: aiUsageRecent.map(entry => ({ ...entry }))
  });
  wss.clients.forEach((c: WebSocket) => {
    if (c.readyState === WebSocket.OPEN) c.send(payload);
  });
}

function resetAiUsageCounters() {
  aiUsageInputTokens = 0;
  aiUsageOutputTokens = 0;
  aiUsageTotalTokens = 0;
  aiUsageSequence = 0;
  for (const kind of Object.keys(aiUsageByKind) as AiModelKind[]) {
    aiUsageByKind[kind] = { requests: 0, inputTokens: 0, outputTokens: 0, totalTokens: 0 };
  }
  aiUsageRecent.length = 0;
  broadcastAiUsageSnapshot();
  return buildAiUsagePayload();
}

function trackUsage(
  kind: AiModelKind,
  model: string,
  inputRaw: unknown,
  outputRaw: unknown,
  totalRaw: unknown,
  labelRaw?: unknown
) {
  const input = Number(inputRaw || 0);
  const output = Number(outputRaw || 0);
  const total = Number(totalRaw || (input + output) || 0);
  if (!Number.isFinite(input) && !Number.isFinite(output) && !Number.isFinite(total)) return;

  const safeInput = Number.isFinite(input) ? Math.max(0, Math.floor(input)) : 0;
  const safeOutput = Number.isFinite(output) ? Math.max(0, Math.floor(output)) : 0;
  const safeTotal = Number.isFinite(total)
    ? Math.max(0, Math.floor(total))
    : Math.max(0, Math.floor(input + output));
  aiUsageInputTokens += safeInput;
  aiUsageOutputTokens += safeOutput;
  aiUsageTotalTokens += safeTotal;

  aiUsageByKind[kind].requests += 1;
  aiUsageByKind[kind].inputTokens += safeInput;
  aiUsageByKind[kind].outputTokens += safeOutput;
  aiUsageByKind[kind].totalTokens += safeTotal;

  aiUsageRecent.unshift({
    id: `usage-${++aiUsageSequence}`,
    kind,
    model: String(model || '').trim() || 'unknown',
    label: normalizeAiUsageLabel(labelRaw) || `${kind} request`,
    inputTokens: safeInput,
    outputTokens: safeOutput,
    totalTokens: safeTotal,
    createdAt: Date.now()
  });
  if (aiUsageRecent.length > AI_USAGE_LOG_LIMIT) aiUsageRecent.length = AI_USAGE_LOG_LIMIT;

  broadcastAiUsageSnapshot();
}

function trackUsageFromResponse(kind: AiModelKind, model: string, resp: any, labelRaw?: unknown) {
  const usage = (resp && typeof resp === 'object') ? (resp as any).usage : null;
  if (!usage || typeof usage !== 'object') return;

  trackUsage(
    kind,
    model,
    usage.input_tokens || usage.prompt_tokens || 0,
    usage.output_tokens || usage.completion_tokens || 0,
    usage.total_tokens || 0,
    labelRaw
  );
}

function previewText(raw: unknown, limit = 360): string {
  const text = String(raw || '').replace(/\s+/g, ' ').trim();
  if (!text) return '';
  if (text.length <= limit) return text;
  return `${text.slice(0, Math.max(0, limit - 3)).trim()}...`;
}

function previewJson(raw: unknown, limit = 900): string {
  try {
    return previewText(JSON.stringify(raw), limit);
  } catch {
    return previewText(raw, limit);
  }
}

function recordSummaryDebugEvent(event: SummaryDebugEvent) {
  summaryDebugEvents.push(event);
  if (summaryDebugEvents.length > AI_SUMMARY_DEBUG_MAX) {
    summaryDebugEvents.splice(0, summaryDebugEvents.length - AI_SUMMARY_DEBUG_MAX);
  }
}

function extractOpenAiLikeText(resp: any): { text: string; extractionSource: string } {
  const direct = String(resp?.output_text || '').trim();
  if (direct) {
    return { text: direct, extractionSource: 'output_text' };
  }

  const output = Array.isArray(resp?.output) ? resp.output : [];
  const parts: string[] = [];
  for (const item of output) {
    const content = Array.isArray(item?.content) ? item.content : [];
    for (const block of content) {
      if (!block || typeof block !== 'object') continue;
      const text = typeof block.text === 'string'
        ? block.text
        : typeof block.value === 'string'
          ? block.value
          : '';
      if (!text) continue;
      const type = String(block.type || '').trim();
      if (type === 'output_text' || type === 'text' || !type) {
        parts.push(text);
      }
    }
  }

  return {
    text: parts.join('\n').trim(),
    extractionSource: parts.length ? 'output.content' : 'none'
  };
}

// ---------------- Persistence (JSON) ----------------
const DATA_DIR = path.join(__dirname, '.data');
const STATE_PATH = path.join(DATA_DIR, 'state.json');
const APP_STATE_ROW_ID = 1;

type PersistedState = {
  version: number;
  keywords?: string[];
  aiFeatures?: AiInsightFeatureSettings;
  localRegion?: string;
  localLlmBaseUrl?: string;
  trackedTopics?: string[];
  titleDisplayLanguage?: TitleDisplayLanguage;
  feeds: FeedInfo[];
  feedSettings: Record<string, FeedSettings>;
  hiddenIds: string[];
  feedRuntime: Record<string, FeedRuntime>;
  recent?: NewsInternal[];
};

type PersistedNewsRow = Prisma.NewsItemRecordGetPayload<Record<string, never>>;

const NEWS_PAGE_LIMIT_DEFAULT = 10;
const NEWS_PAGE_LIMIT_MAX = 200;
const NEWS_ARCHIVE_RETENTION_DAYS = Math.max(1, Math.floor(Number(process.env.NEWS_ARCHIVE_RETENTION_DAYS || 90)));
const NEWS_ARCHIVE_MAX_ITEMS_PER_FEED = Math.max(200, Math.floor(Number(process.env.NEWS_ARCHIVE_MAX_ITEMS_PER_FEED || 5000)));
const NEWS_ARCHIVE_PRUNE_INTERVAL_MS = 6 * 60 * 60 * 1000;

function newsRecordKey(feedUrl: string, itemId: string): string {
  return `${String(feedUrl || '').trim()}::${String(itemId || '').trim()}`;
}

function safeJsonStringify(value: unknown): string | undefined {
  if (typeof value === 'undefined') return undefined;
  try {
    return JSON.stringify(value);
  } catch {
    return undefined;
  }
}

function safeJsonParseString<T>(value: string | null | undefined): T | undefined {
  if (!value) return undefined;
  try {
    return JSON.parse(value) as T;
  } catch {
    return undefined;
  }
}

function normalizePersistedMs(value: number): bigint {
  const parsed = Math.floor(Number(value));
  const safeValue = Number.isFinite(parsed) && parsed > 0 ? parsed : Date.now();
  return BigInt(safeValue);
}

function newsFromPersistedRow(row: PersistedNewsRow): NewsInternal {
  return {
    type: 'news',
    id: row.itemId,
    title: row.title,
    titleBg: row.titleBg || undefined,
    titleEn: row.titleEn || undefined,
    coverUrl: row.coverUrl || undefined,
    link: row.link,
    source: row.source,
    published: row.published || undefined,
    publishedMs: Number(row.publishedMs),
    feedUrl: row.feedUrl,
    isMatch: row.isMatch,
    matchScore: Number(row.matchScore || 0),
    filteredOk: row.filteredOk,
    summary: row.summary || undefined,
    research: row.research || undefined,
    insightStatus: (row.insightStatus as InsightStatus | null) || undefined,
    insights: safeJsonParseString<NewsInsights>(row.insightsJson),
    topicHits: safeJsonParseString<string[]>(row.topicHitsJson),
    emergingSignal: safeJsonParseString<EmergingStorySignal>(row.emergingSignalJson),
    mood: (row.mood as Mood | null) || undefined,
    newsType: (row.newsType as NewsType | null) || undefined,
    __ctx: row.contextText || undefined,
    __linkText: row.linkText || undefined
  };
}

function buildPersistedNewsUpdate(it: NewsInternal): Prisma.NewsItemRecordUncheckedCreateInput {
  return {
    key: newsRecordKey(it.feedUrl, it.id),
    feedUrl: it.feedUrl,
    itemId: it.id,
    title: it.title,
    titleBg: it.titleBg || undefined,
    titleEn: it.titleEn || undefined,
    coverUrl: it.coverUrl || undefined,
    link: it.link,
    source: it.source,
    published: it.published || undefined,
    publishedMs: normalizePersistedMs(it.publishedMs),
    isMatch: !!it.isMatch,
    matchScore: Number.isFinite(it.matchScore) ? it.matchScore : 0,
    filteredOk: it.filteredOk !== false,
    summary: it.summary || undefined,
    research: it.research || undefined,
    insightStatus: it.insightStatus || undefined,
    insightsJson: safeJsonStringify(it.insights),
    topicHitsJson: safeJsonStringify(it.topicHits),
    emergingSignalJson: safeJsonStringify(it.emergingSignal),
    mood: it.mood || undefined,
    newsType: it.newsType || undefined,
    contextText: it.__ctx || undefined,
    linkText: it.__linkText || undefined
  };
}

function migratedDefaultFeedUrlsForVersion(version: number): Set<string> {
  const urls = new Set<string>();
  for (let nextVersion = version + 1; nextVersion <= CURRENT_STATE_VERSION; nextVersion += 1) {
    const additions = DEFAULT_FEED_MIGRATIONS[nextVersion];
    if (!Array.isArray(additions)) continue;
    additions.forEach(url => urls.add(url));
  }
  return urls;
}

function normalizeLegacyFeedUrl(url: string) {
  if (url === LEGACY_SVOBODNA_EVROPA_FEED_URL) return SVOBODNA_TOCHKA_FEED_URL;
  if (url === LEGACY_CAPITAL_FEED_URL) return CAPITAL_FEED_URL;
  return url;
}

function rewriteLegacyFeed(feed: FeedInfo): FeedInfo {
  if (feed.url === LEGACY_CAPITAL_FEED_URL) {
    return {
      ...feed,
      url: CAPITAL_FEED_URL,
      label: feed.label || 'capital.bg',
      kind: 'rss'
    };
  }
  if (feed.url !== LEGACY_SVOBODNA_EVROPA_FEED_URL) return feed;
  return {
    ...feed,
    url: SVOBODNA_TOCHKA_FEED_URL,
    label: SVOBODNA_TOCHKA_DEFAULT_FEED.label,
    kind: 'rss'
  };
}

function mergeLoadedFeedsWithDefaultMigrations(version: number, loadedFeeds: FeedInfo[]): FeedInfo[] {
  const migratedUrls = migratedDefaultFeedUrlsForVersion(version);
  if (!migratedUrls.size) {
    const result: FeedInfo[] = [];
    const seen = new Set<string>();
    for (const feed of loadedFeeds.map(rewriteLegacyFeed)) {
      if (seen.has(feed.url)) continue;
      seen.add(feed.url);
      result.push(feed);
    }
    return result;
  }

  const loadedByUrl = new Map(loadedFeeds.map(feed => {
    const normalized = rewriteLegacyFeed(feed);
    return [normalized.url, normalized] as const;
  }));
  const result: FeedInfo[] = [];
  const seen = new Set<string>();

  for (const defaultFeed of defaultFeeds) {
    const loaded = loadedByUrl.get(defaultFeed.url);
    if (!loaded && !migratedUrls.has(defaultFeed.url)) continue;
    result.push(loaded || defaultFeed);
    seen.add(defaultFeed.url);
  }

  for (const feed of loadedFeeds.map(rewriteLegacyFeed)) {
    if (seen.has(feed.url)) continue;
    result.push(feed);
    seen.add(feed.url);
  }

  return result;
}

function ensureDataDir() {
  try { fs.mkdirSync(DATA_DIR, { recursive: true }); } catch {}
}

function safeReadJson<T>(filePath: string): T | null {
  try {
    if (!fs.existsSync(filePath)) return null;
    const raw = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

let persistDirty = false;
function markDirty() { persistDirty = true; }

async function saveStateToDb(st: PersistedState) {
  try {
    await prisma.appState.upsert({
      where: { id: APP_STATE_ROW_ID },
      create: { id: APP_STATE_ROW_ID, payload: JSON.stringify(st) },
      update: { payload: JSON.stringify(st) }
    });
  } catch (e) {
    console.error('Failed to save Prisma state:', (e as Error).message);
  }
}

async function readStateFromDb(): Promise<PersistedState | null> {
  try {
    const row = await prisma.appState.findUnique({ where: { id: APP_STATE_ROW_ID } });
    if (!row?.payload) return null;
    const parsed = JSON.parse(row.payload) as PersistedState;
    if (!parsed || typeof parsed !== 'object') return null;
    return parsed;
  } catch {
    return null;
  }
}

async function upsertPersistedNewsItem(it: NewsInternal) {
  try {
    const data = buildPersistedNewsUpdate(it);
    await prisma.newsItemRecord.upsert({
      where: { key: data.key },
      create: data,
      update: data
    });
  } catch (e) {
    console.error('Failed to persist news item:', (e as Error).message);
  }
}

async function appendErrorLog(entry: {
  category: string;
  message: string;
  feedUrl?: string;
  feedLabel?: string;
  attempt?: number;
  maxAttempts?: number;
  failCount?: number;
  disabledUntilMs?: number;
  details?: Record<string, unknown>;
}) {
  try {
    await prisma.errorLogRecord.create({
      data: {
        category: entry.category,
        feedUrl: entry.feedUrl?.trim() || null,
        feedLabel: entry.feedLabel?.trim() || null,
        attempt: Number.isFinite(entry.attempt) ? Math.floor(Number(entry.attempt)) : null,
        maxAttempts: Number.isFinite(entry.maxAttempts) ? Math.floor(Number(entry.maxAttempts)) : null,
        failCount: Number.isFinite(entry.failCount) ? Math.floor(Number(entry.failCount)) : null,
        disabledUntilMs: Number.isFinite(entry.disabledUntilMs) ? BigInt(Math.floor(Number(entry.disabledUntilMs))) : null,
        message: String(entry.message || '').trim().slice(0, 2000),
        detailsJson: entry.details ? JSON.stringify(entry.details) : null
      }
    });
  } catch (e) {
    console.error('Failed to persist error log:', (e as Error).message);
  }
}

async function hasPersistedNewsArchive(): Promise<boolean> {
  try {
    const first = await prisma.newsItemRecord.findFirst({ select: { key: true } });
    return !!first?.key;
  } catch {
    return false;
  }
}

async function loadRecentFromDb(limit = MAX_RECENT_ITEMS) {
  try {
    const rows = await prisma.newsItemRecord.findMany({
      orderBy: [
        { publishedMs: 'desc' },
        { itemId: 'desc' }
      ],
      take: Math.max(1, Math.min(MAX_RECENT_ITEMS, Math.floor(limit || MAX_RECENT_ITEMS)))
    });

    recent.length = 0;
    seen = new Set<string>();

    rows.reverse().forEach(row => {
      const item = newsFromPersistedRow(row);
      recent.push(item);
      seen.add(newsRecordKey(item.feedUrl, item.id));
      refreshDerivedDataForItem(item);
    });
  } catch (e) {
    console.error('Failed to load persisted news archive:', (e as Error).message);
  }
}

async function migrateLegacyRecentToDb(items: NewsInternal[]) {
  for (const item of items) {
    if (!item?.id || !item.feedUrl) continue;
    await upsertPersistedNewsItem(item);
  }
}

async function readFeedPageFromDb(
  feedUrl: string,
  limitRaw: number,
  cursor?: FeedPageCursor
): Promise<{ items: NewsInternal[]; hasMore: boolean; nextCursor?: FeedPageCursor }> {
  const feedUrlTrimmed = String(feedUrl || '').trim();
  if (!feedUrlTrimmed) return { items: [], hasMore: false };

  const limit = Math.max(1, Math.min(NEWS_PAGE_LIMIT_MAX, Math.floor(limitRaw || NEWS_PAGE_LIMIT_DEFAULT)));
  const visibleRows: PersistedNewsRow[] = [];
  const seenKeys = new Set<string>();
  let currentCursor = cursor;
  let exhausted = false;

  while (visibleRows.length < limit + 1 && !exhausted) {
    const where: Prisma.NewsItemRecordWhereInput = { feedUrl: feedUrlTrimmed };
    if (currentCursor?.beforeId && Number.isFinite(currentCursor.beforePublishedMs)) {
      where.OR = [
        { publishedMs: { lt: BigInt(Math.floor(currentCursor.beforePublishedMs)) } },
        {
          publishedMs: BigInt(Math.floor(currentCursor.beforePublishedMs)),
          itemId: { lt: currentCursor.beforeId }
        }
      ];
    }

    const batch = await prisma.newsItemRecord.findMany({
      where,
      orderBy: [
        { publishedMs: 'desc' },
        { itemId: 'desc' }
      ],
      take: limit + 1
    });

    if (!batch.length) {
      exhausted = true;
      break;
    }

    const lastBatchRow = batch[batch.length - 1];
    currentCursor = {
      beforePublishedMs: Number(lastBatchRow.publishedMs),
      beforeId: lastBatchRow.itemId
    };

    batch.forEach(row => {
      if (hiddenIds.has(row.itemId)) return;
      if (seenKeys.has(row.key)) return;
      seenKeys.add(row.key);
      visibleRows.push(row);
    });

    exhausted = batch.length < limit + 1;
  }

  const pageRows = visibleRows.slice(0, limit);
  const items = pageRows.map(newsFromPersistedRow);
  const hasMore = visibleRows.length > limit || !exhausted;
  const lastVisibleRow = pageRows[pageRows.length - 1];

  return {
    items,
    hasMore,
    nextCursor: hasMore && lastVisibleRow
      ? {
          beforePublishedMs: Number(lastVisibleRow.publishedMs),
          beforeId: lastVisibleRow.itemId
        }
      : undefined
  };
}

let lastNewsArchivePruneAtMs = 0;

async function prunePersistedNewsArchive(nowMs = Date.now()) {
  if (nowMs - lastNewsArchivePruneAtMs < NEWS_ARCHIVE_PRUNE_INTERVAL_MS) return;
  lastNewsArchivePruneAtMs = nowMs;

  const retentionCutoffMs = nowMs - (NEWS_ARCHIVE_RETENTION_DAYS * 24 * 60 * 60 * 1000);

  try {
    await prisma.newsItemRecord.deleteMany({
      where: {
        publishedMs: { lt: BigInt(retentionCutoffMs) }
      }
    });

    const feedUrls = await prisma.newsItemRecord.findMany({
      distinct: ['feedUrl'],
      select: { feedUrl: true }
    });

    for (const entry of feedUrls) {
      while (true) {
        const overflowRows = await prisma.newsItemRecord.findMany({
          where: { feedUrl: entry.feedUrl },
          orderBy: [
            { publishedMs: 'desc' },
            { itemId: 'desc' }
          ],
          skip: NEWS_ARCHIVE_MAX_ITEMS_PER_FEED,
          take: 250,
          select: { key: true }
        });

        if (!overflowRows.length) break;

        await prisma.newsItemRecord.deleteMany({
          where: {
            key: { in: overflowRows.map(row => row.key) }
          }
        });

        if (overflowRows.length < 250) break;
      }
    }
  } catch (e) {
    console.error('Failed to prune persisted news archive:', (e as Error).message);
  }
}

function saveStateNow() {
  if (!persistDirty) return;
  persistDirty = false;

  ensureDataDir();
  const st: PersistedState = {
    version: CURRENT_STATE_VERSION,
    keywords,
    aiFeatures,
    localRegion,
    localLlmBaseUrl,
    trackedTopics,
    titleDisplayLanguage,
    feeds: feedsList,
    feedSettings: feedSettingsObj(),
    hiddenIds: Array.from(hiddenIds),
    feedRuntime: feedRuntimeObj()
  };

  try {
    fs.writeFileSync(STATE_PATH, JSON.stringify(st, null, 2), 'utf8');
  } catch (e) {
    console.error('Failed to save state:', (e as Error).message);
  }

  void saveStateToDb(st);
}

// Save periodically + on exit
setInterval(saveStateNow, 2500);
process.on('exit', () => {
  try { saveStateNow(); } catch {}
  try {
    stopAiJobLogFlushTimer();
    flushAiJobLogBufferNow();
  } catch {}
});
process.on('uncaughtException', (err) => {
  console.error('uncaughtException:', err);
  try { saveStateNow(); } catch {}
  try {
    stopAiJobLogFlushTimer();
    flushAiJobLogBufferNow();
  } catch {}
  process.exit(1);
});
// ----------------------------------------------------

// -------- feeds (ordered list) + settings ----------
let feedsList: FeedInfo[] = [...defaultFeeds];

// per-feed settings store (persisted)
const feedSettings = new Map<string, FeedSettings>();

// runtime-only fetch cache + breaker
const feedRuntime = new Map<string, FeedRuntime>();
const lastFeedErrorBroadcastMs = new Map<string, number>();

// hidden items (persisted)
const hiddenIds = new Set<string>();

// labels override
function labelForFeed(info: FeedInfo): string {
  return info.label || info.url;
}

function normalizeDiscordWebhookUrl(raw: unknown): string | undefined {
  const value = String(raw || '').trim();
  if (!value) return undefined;
  try {
    const parsed = new URL(value);
    const host = parsed.hostname.replace(/^www\./i, '').toLowerCase();
    const allowedHost =
      host === 'discord.com'
      || host.endsWith('.discord.com')
      || host === 'discordapp.com'
      || host.endsWith('.discordapp.com');
    if (!allowedHost) return undefined;
    if (!parsed.pathname.includes('/api/webhooks/')) return undefined;
    return value.slice(0, 500);
  } catch {
    return undefined;
  }
}

function compactDiscordText(value: string, max = 700): string {
  return compactSentence(String(value || '').replace(/\s+/g, ' ').trim(), max);
}

function collectDiscordAiNotes(item: NewsInternal): string[] {
  const notes: string[] = [];
  const push = (label: string, value: string | undefined, max = 180) => {
    const text = compactDiscordText(value || '', max);
    if (text) notes.push(`${label}: ${text}`);
  };

  push('Mood', item.mood);
  push('Type', item.newsType);
  push('Impact', item.insights?.impact?.summary, 180);
  push('Bias', item.insights?.bias?.summary, 180);
  push('Sensationalism', item.insights?.sensationalism?.summary, 180);
  push('Historical', item.insights?.historical?.explanation, 180);
  push('Future', item.insights?.future?.outlook, 180);
  push('Local impact', item.insights?.localImpact?.summary, 180);
  push('Emerging signal', item.emergingSignal?.reason, 180);

  return notes.slice(0, 6);
}

function normalizeDiscordTitleLanguage(value: unknown): TitleDisplayLanguage {
  return value === 'bg' || value === 'en' || value === 'original' ? value : 'original';
}

function chooseDiscordTitle(item: NewsInternal, preferred: TitleDisplayLanguage, translationEnabled: boolean): string {
  const original = compactDiscordText(item.title || '', 260) || '(untitled)';
  const bg = compactDiscordText(item.titleBg || '', 260);
  const en = compactDiscordText(item.titleEn || '', 260);

  if (!translationEnabled) return original;
  if (preferred === 'bg') return bg || en || original;
  if (preferred === 'en') return en || bg || original;
  return original;
}

function buildDiscordEmbed(item: NewsInternal, feed: FeedInfo, feedConfig: FeedSettings) {
  const source = String(item.source || feed.label || feed.url).trim() || 'Unknown source';
  const translationEnabled = feedConfig.translationEnabled !== false;
  const preferredTitle = chooseDiscordTitle(item, normalizeDiscordTitleLanguage(titleDisplayLanguage), translationEnabled);
  const summaryEnabled = feedConfig.summaryEnabled !== false;
  const researchEnabled = feedConfig.researchEnabled !== false;
  const fields: Array<{ name: string; value: string; inline?: boolean }> = [];

  const summaryText = compactDiscordText(item.summary || '', 1800);
  const researchText = compactDiscordText(item.research || '', 1800);
  if (researchEnabled && researchText) {
    fields.push({ name: 'Research', value: researchText });
  }

  const aiNotes = collectDiscordAiNotes(item);
  if (aiNotes.length) {
    fields.push({ name: 'AI notes', value: aiNotes.join('\n').slice(0, 1024) });
  }

  const descriptionSource = summaryEnabled && summaryText
    ? summaryText
    : (researchEnabled && researchText ? researchText : compactDiscordText(item.title || '', 900));

  const description = [
    descriptionSource,
  ].filter(Boolean).join('\n\n').slice(0, 4000);

  const embed: Record<string, unknown> = {
    title: preferredTitle,
    url: item.link || undefined,
    description: description || undefined,
    color: 0x4f6fff,
    author: { name: source },
    footer: {
      text: feed.label || source
    },
    timestamp: Number.isFinite(item.publishedMs) ? new Date(item.publishedMs).toISOString() : undefined,
    fields
  };

  if (item.coverUrl) {
    embed.image = { url: item.coverUrl };
  }

  return embed;
}

function feedSettingsObj(): Record<string, FeedSettings> {
  const obj: Record<string, FeedSettings> = {};
  for (const [k, v] of feedSettings.entries()) obj[k] = v;
  return obj;
}

type DiscordPostResult = {
  ok: boolean;
  retry: boolean;
};

const discordWebhookCooldownUntilMs = new Map<string, number>();
const discordWebhookFailCount = new Map<string, number>();

function discordWebhookCooldownMs(webhookUrl: string) {
  const until = discordWebhookCooldownUntilMs.get(webhookUrl) || 0;
  return Math.max(0, until - Date.now());
}

async function postNewsToDiscord(item: NewsInternal, feed: FeedInfo): Promise<DiscordPostResult> {
  const feedConfig = feedSettings.get(feed.url);
  const webhookUrl = normalizeDiscordWebhookUrl(feedConfig?.discordWebhookUrl);
  if (!webhookUrl) {
    void productFeatures?.recordHistory({
      feedUrl: feed.url,
      itemId: item.id,
      title: item.title,
      source: item.source || feed.label,
      stage: 'discord_delivery',
      status: 'skipped',
      reason: 'No Discord webhook configured.'
    });
    return { ok: false, retry: false };
  }

  const cooldownMs = discordWebhookCooldownMs(webhookUrl);
  if (cooldownMs > 0) {
    void productFeatures?.recordHistory({
      feedUrl: feed.url,
      itemId: item.id,
      title: item.title,
      source: item.source || feed.label,
      stage: 'discord_delivery',
      status: 'skipped',
      reason: `Discord webhook is cooling down for ${Math.ceil(cooldownMs / 1000)}s after rate limiting.`
    });
    return { ok: false, retry: false };
  }

  const source = String(item.source || feed.label || feed.url).trim();
  const embed = buildDiscordEmbed(item, feed, feedConfig || defaultSettingsForFeed(feed));

  try {
    const res = await fetchWithTimeout(webhookUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: feed.label || source,
        content: '',
        embeds: [embed],
        allowed_mentions: { parse: [] }
      })
    }, 7000);
    if (!res.ok) {
      console.warn(`[discord] webhook failed for ${feed.url}: HTTP ${res.status}`);
      const retryAfterMs = parseRetryAfterMs(res.headers.get('retry-after'));
      if (res.status === 429) {
        const failCount = (discordWebhookFailCount.get(webhookUrl) || 0) + 1;
        discordWebhookFailCount.set(webhookUrl, failCount);
        const fallbackMs = Math.min(15 * 60 * 1000, Math.max(30_000, failCount * 60_000));
        const nextCooldownMs = retryAfterMs || fallbackMs;
        discordWebhookCooldownUntilMs.set(webhookUrl, Date.now() + nextCooldownMs);
        console.warn(`[discord] cooling down webhook for ${feed.url}: ${Math.round(nextCooldownMs / 1000)}s`);
      }
      void productFeatures?.recordHistory({
        feedUrl: feed.url,
        itemId: item.id,
        title: item.title,
        source,
        stage: 'discord_delivery',
        status: 'failed',
        reason: `Discord returned HTTP ${res.status}`
      });
      return { ok: false, retry: res.status >= 500 };
    }
  } catch (err) {
    console.warn(`[discord] webhook failed for ${feed.url}: ${(err as Error).message}`);
    void productFeatures?.recordHistory({
      feedUrl: feed.url,
      itemId: item.id,
      title: item.title,
      source,
      stage: 'discord_delivery',
      status: 'failed',
      reason: (err as Error).message
    });
    return { ok: false, retry: true };
  }

  discordWebhookCooldownUntilMs.delete(webhookUrl);
  discordWebhookFailCount.delete(webhookUrl);
  void productFeatures?.recordHistory({
    feedUrl: feed.url,
    itemId: item.id,
    title: item.title,
    source,
    stage: 'discord_delivery',
    status: 'sent'
  });
  return { ok: true, retry: false };
}

function discordPostKey(item: NewsInternal, targetFeedUrl: string): string {
  return `${targetFeedUrl}::${item.feedUrl}::${item.id}`;
}

function clearDiscordPostTimer(key: string) {
  const timer = discordPostTimerByKey.get(key);
  if (timer) clearTimeout(timer);
  discordPostTimerByKey.delete(key);
  discordPostAttemptStartedAtMs.delete(key);
}

function isDiscordPostReady(item: NewsInternal, feedConfig: FeedSettings): boolean {
  const summaryEnabled = feedConfig.summaryEnabled !== false;
  const researchEnabled = feedConfig.researchEnabled !== false;
  const translationEnabled = feedConfig.translationEnabled !== false;
  const summaryReady = !summaryEnabled
    || !!String(item.summary || '').trim()
    || activeModel('summary') === 'none';
  const researchReady = !researchEnabled
    || !!String(item.research || '').trim()
    || activeModel('research') === 'none';
  const translationReady = !translationEnabled
    || !needsTitleTranslation(item.title, item.titleBg, item.titleEn)
    || !!String(item.titleBg || '').trim()
    || !!String(item.titleEn || '').trim()
    || activeModel('summary') === 'none';

  return summaryReady && researchReady && translationReady;
}

function discordFeedTargetForItem(item: NewsInternal, targetFeedUrl: string): FeedInfo {
  if (targetFeedUrl === FILTERED_FEED_URL) {
    const filteredSettings = feedSettings.get(FILTERED_FEED_URL);
    return {
      url: FILTERED_FEED_URL,
      label: filteredSettings?.label || 'Filtered',
      kind: filteredSettings?.kind || 'rss',
      intervalSec: filteredSettings?.intervalSec || 0
    };
  }

  return feedsList.find(f => f.url === targetFeedUrl) || {
    url: targetFeedUrl,
    label: item.source || targetFeedUrl,
    kind: 'rss',
    intervalSec: 0
  };
}

function scheduleDiscordPostForTarget(item: NewsInternal, targetFeedUrl: string) {
  const feed = discordFeedTargetForItem(item, targetFeedUrl);
  const feedConfig = feedSettings.get(feed.url);
  const webhookUrl = normalizeDiscordWebhookUrl(feedConfig?.discordWebhookUrl);
  if (!webhookUrl) return;
  const effectiveFeedConfig = feedConfig || defaultSettingsForFeed(feed);

  if (effectiveFeedConfig.summaryEnabled !== false && !String(item.summary || '').trim() && activeModel('summary') !== 'none' && !hasSummaryJobQueuedOrRunning(item.id, item.feedUrl)) {
    enqueueJob({ kind: 'summary', id: item.id, feedUrl: item.feedUrl, manual: true });
  }
  if (effectiveFeedConfig.researchEnabled !== false && !String(item.research || '').trim() && activeModel('research') !== 'none' && !hasResearchJobQueuedOrRunning(item.id, item.feedUrl)) {
    enqueueJob({ kind: 'research', id: item.id, feedUrl: item.feedUrl, manual: true });
  }
  if (effectiveFeedConfig.translationEnabled !== false && needsTitleTranslation(item.title, item.titleBg, item.titleEn) && activeModel('summary') !== 'none' && !hasTitleTranslateJobQueuedOrRunning(item.id, item.feedUrl)) {
    enqueueJob({ kind: 'title_translate', id: item.id, feedUrl: item.feedUrl, manual: true });
  }

  const key = discordPostKey(item, feed.url);
  if (!discordPostAttemptStartedAtMs.has(key)) {
    discordPostAttemptStartedAtMs.set(key, Date.now());
  }
  if (discordPostTimerByKey.has(key)) return;

  const run = async () => {
    discordPostTimerByKey.delete(key);
    const current = recent.find(x => x.id === item.id && x.feedUrl === item.feedUrl) || item;
    const currentFeedConfig = feedSettings.get(feed.url) || defaultSettingsForFeed(feed);
    const startedAt = discordPostAttemptStartedAtMs.get(key) || Date.now();
    const elapsed = Date.now() - startedAt;
    const ready = isDiscordPostReady(current, currentFeedConfig);

    if (!ready && elapsed < DISCORD_POST_MAX_WAIT_MS) {
      const timer = setTimeout(run, DISCORD_POST_RETRY_DELAY_MS);
      discordPostTimerByKey.set(key, timer);
      return;
    }

    const result = await postNewsToDiscord(current, feed);
    clearDiscordPostTimer(key);

    if (!result.ok && result.retry && elapsed < DISCORD_POST_MAX_WAIT_MS) {
      discordPostAttemptStartedAtMs.set(key, Date.now() - elapsed);
      const timer = setTimeout(run, DISCORD_POST_RETRY_DELAY_MS);
      discordPostTimerByKey.set(key, timer);
    }
  };

  const timer = setTimeout(run, 1000);
  discordPostTimerByKey.set(key, timer);
}

function scheduleDiscordPost(item: NewsInternal) {
  if (item.isMatch && item.filteredOk !== false) {
    const filteredWebhookUrl = normalizeDiscordWebhookUrl(feedSettings.get(FILTERED_FEED_URL)?.discordWebhookUrl);
    if (filteredWebhookUrl) {
      scheduleDiscordPostForTarget(item, FILTERED_FEED_URL);
      return;
    }
  }
  scheduleDiscordPostForTarget(item, item.feedUrl);
}

function feedRuntimeObj(): Record<string, FeedRuntime> {
  const obj: Record<string, FeedRuntime> = {};
  for (const [k, v] of feedRuntime.entries()) obj[k] = v;
  return obj;
}

function defaultSettingsForFeed(fi: FeedInfo): FeedSettings {
  const summaryEnabled =
    fi.url === FILTERED_FEED_URL ? SUMMARY_DEFAULT_FILTERED : SUMMARY_DEFAULT_ALL;
  const researchEnabled =
    fi.url === FILTERED_FEED_URL ? RESEARCH_DEFAULT_FILTERED : RESEARCH_DEFAULT_ALL;

  return {
    summaryEnabled,
    translationEnabled: true,
    researchEnabled,
    discordWebhookUrl: undefined,
    budget: 'standard',
    sortMode: 'newest',
    filters: { onlyMatches: false, onlyResearched: false, onlySummaries: false },
    intervalSec: fi.intervalSec,
    kind: fi.kind,
    label: fi.label
  };
}

function normalizeFeedSettings(raw: Partial<FeedSettings> | undefined, fi: FeedInfo): FeedSettings {
  const base = defaultSettingsForFeed(fi);
  const filters = raw?.filters;
  return {
    summaryEnabled: typeof raw?.summaryEnabled === 'boolean' ? raw.summaryEnabled : base.summaryEnabled,
    translationEnabled: raw?.translationEnabled !== false,
    researchEnabled: typeof raw?.researchEnabled === 'boolean' ? raw.researchEnabled : base.researchEnabled,
    discordWebhookUrl: normalizeDiscordWebhookUrl(raw?.discordWebhookUrl),
    budget: raw?.budget === 'low' || raw?.budget === 'standard' || raw?.budget === 'high'
      ? raw.budget
      : base.budget,
    sortMode: raw?.sortMode === 'newest' || raw?.sortMode === 'oldest' || raw?.sortMode === 'matched'
      ? raw.sortMode
      : base.sortMode,
    filters: {
      onlyMatches: !!filters?.onlyMatches,
      onlyResearched: !!filters?.onlyResearched,
      onlySummaries: !!filters?.onlySummaries
    },
    intervalSec: Math.max(0, Math.min(3600, Math.floor(Number(raw?.intervalSec ?? base.intervalSec) || base.intervalSec))),
    kind: raw?.kind === 'reddit' || raw?.kind === 'youtube' || raw?.kind === 'rss'
      ? raw.kind
      : fi.kind,
    label: typeof raw?.label === 'string' && raw.label.trim() ? raw.label.trim() : fi.label
  };
}

function ensureFeedRuntime(url: string) {
  if (!feedRuntime.has(url)) {
    feedRuntime.set(url, {
      failCount: 0,
      disabledUntilMs: 0,
      nextPollAtMs: 0,
      lastFetchMs: 0
    });
  }
}

function ensureFeedSettings(fi: FeedInfo) {
  if (!feedSettings.has(fi.url)) {
    feedSettings.set(fi.url, defaultSettingsForFeed(fi));
  } else {
    feedSettings.set(fi.url, normalizeFeedSettings(feedSettings.get(fi.url), fi));
  }
}

function currentFeeds(): FeedInfo[] {
  return feedsList.map(f => ({
    url: f.url,
    label: labelForFeed(f),
    kind: f.kind,
    intervalSec: feedSettings.get(f.url)?.intervalSec ?? f.intervalSec
  }));
}
// ---------------------------------------------------

// ---- memory for seen/recent ----
let seen = new Set<string>();
const recent: NewsInternal[] = [];

// ---- embeddings caches ----
let keywordVecs: { keyword: string; vec: number[] }[] = [];
let keywordEmbeddingsInitRunId = 0;
const titleVecCache = new Map<string, number[]>();
const TITLE_VEC_CACHE_MAX = 3000;

// global AI dedupe window (across feeds)
type DedupeItem = { vec: number[]; publishedMs: number };
let dedupeWindow: DedupeItem[] = [];
const DEDUPE_WINDOW_MAX = 1400;
const DEDUPE_COMPARE_LAST_N = 400;
const MAX_RECENT_ITEMS = 5000;
const PERSISTED_RECENT_ITEMS = 5000;
const MAX_SEEN_IDS = 30000;
const SEEN_TRIM_TO = 18000;

// Filtered-only semantic dedupe window
let filteredDedupeWindow: number[][] = [];
const FILTERED_DEDUPE_MAX = 700;
const FILTERED_DEDUPE_COMPARE_LAST_N = 250;

function normalizeText(s: string): string {
  return String(s || '').normalize('NFKC').toLocaleLowerCase('bg').trim();
}

const STORY_LINK_DROP_QUERY_PARAMS = new Set([
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_term',
  'utm_content',
  'utm_id',
  'fbclid',
  'gclid',
  'mc_cid',
  'mc_eid',
  'ref',
  'source',
  't'
]);

function normalizeStoryLink(raw: string): string {
  const input = String(raw || '').trim();
  if (!input) return '';
  try {
    const url = new URL(input);
    url.hash = '';
    Array.from(url.searchParams.keys()).forEach(key => {
      const normalizedKey = key.toLocaleLowerCase();
      if (STORY_LINK_DROP_QUERY_PARAMS.has(normalizedKey) || normalizedKey.startsWith('utm_')) {
        url.searchParams.delete(key);
      }
    });
    url.searchParams.sort();
    url.protocol = url.protocol.toLocaleLowerCase();
    url.hostname = url.hostname.toLocaleLowerCase();
    url.pathname = url.pathname.replace(/\/+$/, '') || '/';
    return url.toString();
  } catch {
    return input.replace(/#.*$/, '');
  }
}

function storyLinkKey(raw: string): string {
  return normalizeText(normalizeStoryLink(raw));
}

function storyTitleKey(raw: string): string {
  return normalizeText(String(raw || '').replace(/\s+/g, ' ')).slice(0, 240);
}

function findReusableNewsItem(
  feedUrl: string,
  source: string,
  title: string,
  link: string,
  publishedMs: number
): NewsInternal | undefined {
  const normalizedSource = normalizeText(source);
  const normalizedTitle = storyTitleKey(title);
  const normalizedLink = storyLinkKey(link);
  const publishedDay = Number.isFinite(publishedMs) ? Math.floor(publishedMs / 86_400_000) : 0;

  for (let i = recent.length - 1; i >= 0; i -= 1) {
    const item = recent[i];
    if (!item || item.type !== 'news') continue;
    if (item.feedUrl !== feedUrl) continue;

    if (normalizedLink && storyLinkKey(item.link) === normalizedLink) {
      return item;
    }

    if (normalizeText(item.source) !== normalizedSource) continue;
    if (storyTitleKey(item.title) !== normalizedTitle) continue;

    const itemDay = Number.isFinite(item.publishedMs) ? Math.floor(item.publishedMs / 86_400_000) : 0;
    if (!publishedDay || !itemDay || Math.abs(itemDay - publishedDay) <= 2) {
      return item;
    }
  }

  return undefined;
}

function mergeReusableNewsItem(
  target: NewsInternal,
  patch: Pick<NewsInternal, 'title' | 'link' | 'published' | 'publishedMs' | 'source' | '__ctx' | 'coverUrl'>
): boolean {
  let changed = false;
  if (patch.title && patch.title !== target.title) {
    target.title = patch.title;
    changed = true;
  }
  if (patch.link && patch.link !== target.link) {
    target.link = patch.link;
    changed = true;
  }
  if (patch.published && patch.published !== target.published) {
    target.published = patch.published;
    changed = true;
  }
  if (Number.isFinite(patch.publishedMs) && patch.publishedMs !== target.publishedMs) {
    target.publishedMs = patch.publishedMs;
    changed = true;
  }
  if (patch.source && patch.source !== target.source) {
    target.source = patch.source;
    changed = true;
  }
  if (patch.__ctx && patch.__ctx.length > String(target.__ctx || '').length) {
    target.__ctx = patch.__ctx;
    changed = true;
  }
  if (patch.coverUrl && patch.coverUrl !== target.coverUrl) {
    target.coverUrl = patch.coverUrl;
    changed = true;
  }
  return changed;
}

function toPublishedMs(item: any): { published?: string; publishedMs: number } {
  const published =
    (typeof item.isoDate === 'string' && item.isoDate) ||
    (typeof item.pubDate === 'string' && item.pubDate) ||
    undefined;
  const ms = published ? Date.parse(published) : NaN;
  return { published, publishedMs: Number.isFinite(ms) ? ms : Date.now() };
}

function dot(a: number[], b: number[]) {
  let s = 0;
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) s += a[i] * b[i];
  return s;
}
function norm(a: number[]) { return Math.sqrt(dot(a, a)); }
function cosine(a: number[], b: number[]) {
  const na = norm(a);
  const nb = norm(b);
  if (!na || !nb) return 0;
  return dot(a, b) / (na * nb);
}

async function embed(text: string): Promise<number[] | null> {
  const client = activeEmbeddingClient();
  if (!client) return null;

  const key = normalizeText(text);
  if (!key) return null;

  const cached = titleVecCache.get(key);
  if (cached) return cached;

  const res = await client.embeddings.create({
    model: aiProvider === 'local' ? LOCAL_EMBED_MODEL : EMBED_MODEL,
    input: text,
    encoding_format: 'float'
  });

  const vec = res.data[0]?.embedding as unknown as number[] | undefined;
  if (!vec) return null;

  titleVecCache.set(key, vec);
  if (titleVecCache.size > TITLE_VEC_CACHE_MAX) {
    const firstKey = titleVecCache.keys().next().value;
    if (firstKey) titleVecCache.delete(firstKey);
  }

  return vec;
}

async function initKeywordEmbeddings() {
  const runId = ++keywordEmbeddingsInitRunId;
  const keywordSnapshot = Array.isArray(keywords) ? [...keywords] : [];

  if (!activeEmbeddingClient() || !aiEnabled || keywordSnapshot.length === 0) {
    if (runId === keywordEmbeddingsInitRunId) {
      keywordVecs = [];
      console.log(`AI enabled: ${aiEnabled}. Keyword embeddings loaded: 0/${keywordSnapshot.length}`);
    }
    return;
  }

  const nextKeywordVecs: { keyword: string; vec: number[] }[] = [];
  for (const kw of keywordSnapshot) {
    const v = await embed(kw);
    if (v) nextKeywordVecs.push({ keyword: kw, vec: v });
  }

  // Drop stale runs if a newer init started while this one was in-flight.
  if (runId !== keywordEmbeddingsInitRunId) return;

  keywordVecs = nextKeywordVecs;
  console.log(
    `AI enabled: ${aiEnabled}. Keyword embeddings loaded: ${keywordVecs.length}/${keywordSnapshot.length}`
  );
}

async function safeInitKeywordEmbeddings(ws?: WebSocket, context = 'AI keyword matching') {
  try {
    await initKeywordEmbeddings();
    return true;
  } catch (error) {
    const message = (error as Error)?.message || 'Unknown embedding error.';
    keywordVecs = [];
    console.warn(`[ai] ${context} unavailable: ${message}`);
    ws?.send(JSON.stringify({
      type: 'error',
      message: `${context} is unavailable right now. The server is still running; check provider connectivity or API key.`
    }));
    return false;
  }
}

function substringHit(title: string): boolean {
  if (!keywords.length) return false;
  const t = normalizeText(title);
  if (!t) return false;
  return keywords.some(k => t.includes(normalizeText(k)));
}

async function hybridMatch(
  title: string
): Promise<{ isMatch: boolean; score: number; vec: number[] | null }> {
  const hit = substringHit(title);

  if (!activeEmbeddingClient() || !aiEnabled || keywordVecs.length === 0) {
    return { isMatch: hit, score: hit ? 1 : 0, vec: null };
  }

  const vec = await embed(title);
  if (!vec) return { isMatch: hit, score: hit ? 1 : 0, vec: null };

  let best = -1;
  for (const k of keywordVecs) {
    const s = cosine(vec, k.vec);
    if (s > best) best = s;
  }

  const semScore = Number.isFinite(best) ? best : 0;
  const semMatch = semScore >= MATCH_THRESHOLD;

  if (hit) return { isMatch: true, score: Math.max(1, semScore), vec };
  return { isMatch: semMatch, score: semScore, vec };
}

async function refreshMatchStateForRecent() {
  filteredDedupeWindow = [];
  const sorted = recent.slice().sort((a, b) => b.publishedMs - a.publishedMs);
  for (const it of sorted) {
    let isMatch = false;
    let matchScore = 0;
    let titleVec: number[] | null = null;

    try {
      const m = await hybridMatch(it.title);
      isMatch = m.isMatch;
      matchScore = m.score;
      titleVec = m.vec;
    } catch {
      const hit = substringHit(it.title);
      isMatch = hit;
      matchScore = hit ? 1 : 0;
      titleVec = null;
    }

    let filteredOk = isMatch;
    if (filteredOk && aiEnabled && FILTERED_AI_DEDUPE && titleVec) {
      if (isFilteredDuplicate(titleVec)) filteredOk = false;
      else addToFilteredDedupe(titleVec);
    }

    it.isMatch = isMatch;
    it.matchScore = matchScore;
    it.filteredOk = filteredOk;
    refreshDerivedDataForItem(it);
    await upsertPersistedNewsItem(it);
  }

  for (const it of sorted) {
    broadcastNewsUpdate(it);
  }
}

function isDuplicate(vec: number[] | null): boolean {
  if (!vec || !aiEnabled) return false;
  const start = Math.max(0, dedupeWindow.length - DEDUPE_COMPARE_LAST_N);
  for (let i = start; i < dedupeWindow.length; i++) {
    const s = cosine(vec, dedupeWindow[i].vec);
    if (s >= DEDUPE_THRESHOLD) return true;
  }
  return false;
}
function addToDedupeWindow(vec: number[] | null, publishedMs: number) {
  if (!vec || !aiEnabled) return;
  dedupeWindow.push({ vec, publishedMs });
  if (dedupeWindow.length > DEDUPE_WINDOW_MAX) {
    dedupeWindow = dedupeWindow.slice(dedupeWindow.length - DEDUPE_WINDOW_MAX);
  }
}

function isFilteredDuplicate(vec: number[]): boolean {
  const start = Math.max(0, filteredDedupeWindow.length - FILTERED_DEDUPE_COMPARE_LAST_N);
  for (let i = start; i < filteredDedupeWindow.length; i++) {
    const s = cosine(vec, filteredDedupeWindow[i]);
    if (s >= FILTERED_DEDUPE_THRESHOLD) return true;
  }
  return false;
}
function addToFilteredDedupe(vec: number[]) {
  filteredDedupeWindow.push(vec);
  if (filteredDedupeWindow.length > FILTERED_DEDUPE_MAX) {
    filteredDedupeWindow = filteredDedupeWindow.slice(
      filteredDedupeWindow.length - FILTERED_DEDUPE_MAX
    );
  }
}

function stripHtml(input: string): string {
  return String(input || '')
    .replace(/<script[\s\S]*?>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<\/?[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

function decodeHtmlEntities(input: string): string {
  return String(input || '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .trim();
}

function toAbsoluteHttpUrl(raw: string, base?: string): string | undefined {
  const input = decodeHtmlEntities(raw);
  if (!input) return undefined;
  const normalized = input.startsWith('//') ? `https:${input}` : input;
  try {
    const parsed = base ? new URL(normalized, base) : new URL(normalized);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return undefined;
    return parsed.toString();
  } catch {
    return undefined;
  }
}

function isLikelyImageUrl(raw: string): boolean {
  const value = String(raw || '').toLowerCase();
  return /\.(avif|gif|jpe?g|png|svg|webp)(?:[?#].*)?$/.test(value)
    || value.includes('ytimg.com/')
    || value.includes('img.youtube.com/')
    || value.includes('preview.redd.it/')
    || value.includes('i.redd.it/');
}

function extractMediaUrl(node: unknown, base?: string): string | undefined {
  if (!node) return undefined;
  if (Array.isArray(node)) {
    for (const entry of node) {
      const url = extractMediaUrl(entry, base);
      if (url) return url;
    }
    return undefined;
  }
  if (typeof node === 'string') {
    return toAbsoluteHttpUrl(node, base);
  }
  if (typeof node !== 'object') return undefined;

  const record = node as Record<string, unknown>;
  const attrs = (record.$ && typeof record.$ === 'object') ? (record.$ as Record<string, unknown>) : null;
  const rawUrl = typeof attrs?.url === 'string'
    ? attrs.url
    : typeof attrs?.href === 'string'
      ? attrs.href
      : typeof record.url === 'string'
        ? record.url
        : typeof record.href === 'string'
          ? record.href
          : '';
  const directUrl = toAbsoluteHttpUrl(rawUrl, base);
  const medium = typeof attrs?.medium === 'string' ? attrs.medium.toLowerCase() : '';
  const type = typeof attrs?.type === 'string' ? attrs.type.toLowerCase() : '';
  if (directUrl && (medium === 'image' || type.startsWith('image/') || isLikelyImageUrl(directUrl))) {
    return directUrl;
  }

  for (const nestedKey of ['media:thumbnail', 'media:content', 'url']) {
    if (!(nestedKey in record)) continue;
    const url = extractMediaUrl(record[nestedKey], base);
    if (url) return url;
  }

  return undefined;
}

function extractEnclosureImageUrl(node: unknown, base?: string): string | undefined {
  if (!node || typeof node !== 'object') return undefined;
  const record = node as Record<string, unknown>;
  const url = toAbsoluteHttpUrl(typeof record.url === 'string' ? record.url : '', base);
  if (!url) return undefined;
  const type = typeof record.type === 'string' ? record.type.toLowerCase() : '';
  if (type.startsWith('image/') || isLikelyImageUrl(url)) return url;
  return undefined;
}

function extractImageUrlFromHtml(raw: unknown, base?: string): string | undefined {
  if (typeof raw !== 'string' || !raw.trim()) return undefined;
  const match = raw.match(/<img[^>]+src=["']([^"']+)["']/i);
  if (!match) return undefined;
  return toAbsoluteHttpUrl(match[1], base);
}

function extractExternalLinkFromHtml(raw: unknown, base?: string): string | undefined {
  if (typeof raw !== 'string' || !raw.trim()) return undefined;
  const hrefRe = /<a[^>]+href=["']([^"']+)["']/ig;
  let match: RegExpExecArray | null = null;
  while ((match = hrefRe.exec(raw))) {
    const url = toAbsoluteHttpUrl(match[1], base);
    if (!url) continue;
    try {
      const parsed = new URL(url);
      const host = parsed.hostname.replace(/^www\./i, '').toLowerCase();
      if (host === 'reddit.com' || host.endsWith('.reddit.com') || host === 'redd.it') continue;
    } catch {}
    return url;
  }
  return undefined;
}

function extractYouTubeVideoId(raw: unknown): string | undefined {
  const input = String(raw || '').trim();
  if (!input) return undefined;
  try {
    const parsed = new URL(input);
    const host = parsed.hostname.replace(/^www\./i, '').toLowerCase();
    if (host === 'youtu.be') {
      const id = parsed.pathname.replace(/^\/+/, '').split('/')[0];
      return id || undefined;
    }
    if (!host.endsWith('youtube.com')) return undefined;
    const watchId = parsed.searchParams.get('v');
    if (watchId) return watchId;
    const parts = parsed.pathname.split('/').filter(Boolean);
    if (parts[0] === 'shorts' || parts[0] === 'embed' || parts[0] === 'v') {
      return parts[1] || undefined;
    }
    return undefined;
  } catch {
    return undefined;
  }
}

function buildYouTubeThumbnailUrl(videoId: string): string | undefined {
  const clean = String(videoId || '').trim();
  if (!/^[A-Za-z0-9_-]{6,}$/.test(clean)) return undefined;
  return `https://i3.ytimg.com/vi/${clean}/hqdefault.jpg`;
}

function extractCoverUrlFromItem(item: any, fi: FeedInfo, link: string): string | undefined {
  const base = toAbsoluteHttpUrl(link) || toAbsoluteHttpUrl(fi.url) || fi.url;
  const externalLink = extractExternalLinkFromHtml(item.description, base)
    || extractExternalLinkFromHtml(item.content, base)
    || extractExternalLinkFromHtml(item.summary, base);
  const youtubeId = typeof item.ytVideoId === 'string' && item.ytVideoId.trim()
    ? item.ytVideoId.trim()
    : extractYouTubeVideoId(link)
      || extractYouTubeVideoId(externalLink)
      || '';

  return extractEnclosureImageUrl(item.enclosure, base)
    || extractMediaUrl(item.mediaThumbnail, base)
    || extractMediaUrl(item.mediaContent, base)
    || extractMediaUrl(item.mediaGroup, base)
    || extractMediaUrl(item.itunesImage, base)
    || extractImageUrlFromHtml(item.description, base)
    || extractImageUrlFromHtml(item.content, base)
    || extractImageUrlFromHtml(item.summary, base)
    || buildYouTubeThumbnailUrl(youtubeId);
}

function pickRssContextCombined(item: any, limitChars: number): string {
  const partsRaw: string[] = [];
  const pushIf = (v: any) => { if (typeof v === 'string' && v.trim()) partsRaw.push(v); };

  pushIf(item.contentSnippet);
  pushIf(item.summary);
  pushIf(item.description);
  pushIf(item.content);

  if (!partsRaw.length) return '';

  const cleanedParts: string[] = [];
  const seenKeys = new Set<string>();

  for (const p of partsRaw) {
    const cleaned = stripHtml(p);
    if (!cleaned) continue;

    const key = normalizeText(cleaned).slice(0, 220);
    if (!key) continue;
    if (seenKeys.has(key)) continue;

    seenKeys.add(key);
    cleanedParts.push(cleaned);
  }

  if (!cleanedParts.length) return '';
  return cleanedParts.join(' -- ').slice(0, Math.max(0, limitChars));
}

function insightFeatureAllowed(feature: keyof AiInsightFeatureSettings, budget: BudgetMode): boolean {
  if (feature === 'biasDetection' || feature === 'sensationalismDetection' || feature === 'factHighlights') {
    return budget === 'standard' || budget === 'high';
  }
  return budget === 'high';
}

function joinInsightTextParts(values: Array<string | undefined>): string {
  return values
    .filter((value): value is string => typeof value === 'string' && value.trim().length > 0)
    .join('\n');
}

function rawInsightContextText(item: NewsInternal): string {
  return joinInsightTextParts([
    item.__ctx,
    item.__linkText
  ]);
}

function combinedInsightText(item: NewsInternal): string {
  const rawContext = rawInsightContextText(item);
  return joinInsightTextParts([
    item.title,
    item.titleBg,
    item.titleEn,
    rawContext,
    rawContext ? undefined : item.summary
  ]);
}

function compactSentence(value: string, max = 220): string {
  const normalized = String(value || '').replace(/\s+/g, ' ').trim();
  if (normalized.length <= max) return normalized;
  const candidate = normalized.slice(0, max + 1);
  const lastSpace = candidate.lastIndexOf(' ');
  if (lastSpace >= Math.max(24, Math.floor(max * 0.6))) {
    return candidate.slice(0, lastSpace).trim();
  }
  return normalized.slice(0, max).trim();
}

function capitalizeWords(values: string[], max = 6): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const raw of values) {
    const value = compactSentence(raw, 90);
    if (!value) continue;
    const key = value.toLocaleLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(value);
    if (out.length >= max) break;
  }
  return out;
}

function sentenceQuoteHighlights(values: string[], max = 2): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  for (const raw of values) {
    const normalized = String(raw || '').replace(/\s+/g, ' ').trim();
    if (!normalized) continue;
    const sentenceMatch = normalized.match(/^(.+?[.!?…])(?:\s|$)/u);
    const value = compactSentence(sentenceMatch ? sentenceMatch[1] : '', 220);
    if (!value) continue;
    const key = value.toLocaleLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(value);
    if (out.length >= max) break;
  }
  return out;
}

const FACT_HIGHLIGHT_ENTITY_STOPWORDS = new Set([
  'agency',
  'bank',
  'board',
  'capital',
  'city',
  'cloud',
  'commission',
  'committee',
  'company',
  'computer',
  'conference',
  'council',
  'court',
  'defense',
  'department',
  'directorate',
  'eu',
  'european',
  'federal',
  'foundation',
  'fund',
  'government',
  'group',
  'hospital',
  'industry',
  'institute',
  'international',
  'ministry',
  'nato',
  'nuclear',
  'office',
  'organization',
  'parliament',
  'party',
  'plant',
  'police',
  'power',
  'president',
  'reactor',
  'republic',
  'school',
  'service',
  'state',
  'system',
  'technology',
  'the',
  'tribunal',
  'union',
  'university',
  'war'
]);

const FACT_HIGHLIGHT_HEADLINE_STOPWORDS = new Set([
  'after',
  'against',
  'amid',
  'best',
  'before',
  'can',
  'during',
  'for',
  'from',
  'how',
  'inside',
  'keep',
  'live',
  'near',
  'new',
  'online',
  'only',
  'over',
  'pays',
  'should',
  'speak',
  'silent',
  'top',
  'tribute',
  'under',
  'watch',
  'what',
  'when',
  'with',
  'who',
  'why',
  'will',
  'worst',
  'you'
]);

function factHighlightSourceText(item: NewsInternal): string {
  return joinInsightTextParts([
    rawInsightContextText(item),
    item.summary,
    item.title
  ]);
}

function collectRegexMatches(text: string, regex: RegExp): string[] {
  return Array.from(text.matchAll(regex), match => String(match[1] || match[0] || ''));
}

function factCandidateTokens(value: string): string[] {
  return compactSentence(value, 120)
    .replace(/["“”„'`.,:;!?()[\]{}]/g, ' ')
    .split(/\s+/)
    .filter(Boolean);
}

function hasFactStopword(tokens: string[], stopwords: Set<string>): boolean {
  return tokens.some(token => stopwords.has(token.toLocaleLowerCase()));
}

function isLikelyPersonFact(value: string): boolean {
  const tokens = factCandidateTokens(value);
  if (tokens.length < 2 || tokens.length > 3) return false;
  if (tokens.filter(token => token.length >= 3).length < 2) return false;
  if (hasFactStopword(tokens, FACT_HIGHLIGHT_ENTITY_STOPWORDS)) return false;
  if (hasFactStopword(tokens, FACT_HIGHLIGHT_HEADLINE_STOPWORDS)) return false;
  return true;
}

function isLikelyLocationFact(value: string): boolean {
  const tokens = factCandidateTokens(value);
  if (!tokens.length || tokens.length > 4) return false;
  if (hasFactStopword(tokens, FACT_HIGHLIGHT_HEADLINE_STOPWORDS)) return false;
  if (tokens.length > 1 && hasFactStopword(tokens, FACT_HIGHLIGHT_ENTITY_STOPWORDS)) return false;
  return true;
}

function isLikelyDateFact(value: string): boolean {
  const candidate = compactSentence(value, 40);
  if (/^\d{4}$/.test(candidate)) {
    const year = Number(candidate);
    return year >= 1900 && year <= 2100;
  }
  return candidate.length >= 4;
}

function isLikelyNumberFact(value: string): boolean {
  const candidate = compactSentence(value, 40);
  if (!candidate) return false;
  if (/[€$£¥%]/.test(candidate)) return true;
  if (/\b(?:million|billion|trillion|thousand|percent|usd|eur|gbp|bgn|leva|dollars|euros|pounds)\b/i.test(candidate)) return true;
  if (/\d{3,}/.test(candidate)) return true;
  if (/\d+[.,]\d+\s*(?:million|billion|trillion|thousand|percent|usd|eur|gbp|bgn|leva|dollars|euros|pounds)\b/i.test(candidate)) return true;
  return false;
}

function isLikelyQuoteFact(value: string): boolean {
  const candidate = compactSentence(value, 180);
  if (candidate.length < 18) return false;
  const words = candidate.split(/\s+/).filter(Boolean);
  if (words.length < 4) return false;
  if (/^[\p{L}\s-]+$/u.test(candidate) && words.every(word => /^[\p{Lu}]/u.test(word))) return false;
  return true;
}

function extractFactHighlights(item: NewsInternal): FactHighlightsInsight | undefined {
  const text = factHighlightSourceText(item);
  if (!text) return undefined;
  const peopleMatches = collectRegexMatches(text, /([\p{Lu}][\p{Ll}]+(?:[-\s]+[\p{Lu}][\p{Ll}]+){1,2})/gu);
  const locationMatches = collectRegexMatches(text, /(?:\b(?:in|from|at|near|across|inside|outside|around|within)\s+)([\p{Lu}][\p{Ll}]+(?:[-\s]+[\p{Lu}][\p{Ll}]+){0,2})/gu);
  const dateMatches = collectRegexMatches(text, /(\b(?:\d{1,2}[\/.-]\d{1,2}(?:[\/.-]\d{2,4})?|\d{4}|\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2}(?:,\s*\d{4})?)\b)/gi);
  const numberMatches = collectRegexMatches(text, /(\b\d[\d,.%$]*(?:\s?(?:million|billion|trillion|thousand|k|m|bn|usd|eur|gbp|bgn))?\b)/gi);
  const quoteMatches = collectRegexMatches(text, /["“„]([^"”]{12,220})["”]/g);
  const facts: FactHighlightsInsight = {
    people: capitalizeWords(peopleMatches.filter(isLikelyPersonFact), 4),
    locations: capitalizeWords(locationMatches.filter(isLikelyLocationFact), 4),
    dates: capitalizeWords(dateMatches.filter(isLikelyDateFact), 4),
    numbers: capitalizeWords(numberMatches.filter(isLikelyNumberFact), 4),
    quotes: sentenceQuoteHighlights(quoteMatches.filter(isLikelyQuoteFact), 2)
  };

  const normalizedDates = new Set(facts.dates.map(value => normalizeText(value)));
  facts.numbers = facts.numbers.filter(value => {
    const normalized = normalizeText(value);
    if (/^\d{4}$/.test(normalized) && normalizedDates.has(normalized)) return false;
    return true;
  });

  if (!facts.people.length && !facts.locations.length && !facts.quotes.length) {
    return undefined;
  }

  const signalScore =
    (facts.people.length ? 2 : 0) +
    (facts.locations.length ? 1 : 0) +
    (facts.dates.length ? 1 : 0) +
    (facts.numbers.length ? 1 : 0) +
    (facts.quotes.length ? 2 : 0);
  return signalScore >= 2
    ? facts
    : undefined;
}

type InsightLocale = 'bg' | 'en';
type IndustryKey = 'semiconductors' | 'cloud' | 'defense' | 'finance' | 'policy' | 'crypto' | 'energy' | 'technology';

function insightLocale(item?: NewsInternal): InsightLocale {
  if (researchLang === 'bg') return 'bg';
  const sample = item
    ? [item.title, item.summary, item.research, item.__ctx, item.__linkText]
        .filter((value): value is string => typeof value === 'string' && value.trim().length > 0)
        .join(' ')
    : '';
  return /[\u0400-\u04FF]/.test(sample) ? 'bg' : 'en';
}

function insightText(locale: InsightLocale, en: string, bg: string): string {
  return locale === 'bg' ? bg : en;
}

function capitalizeInsight(text: string): string {
  return text ? `${text.slice(0, 1).toLocaleUpperCase()}${text.slice(1)}` : text;
}

function joinInsightList(locale: InsightLocale, values: string[]): string {
  if (!values.length) return locale === 'bg' ? 'засегнатите сектори' : 'the affected sectors';
  if (values.length === 1) return values[0];
  if (values.length === 2) {
    return locale === 'bg'
      ? `${values[0]} и ${values[1]}`
      : `${values[0]} and ${values[1]}`;
  }
  const last = values[values.length - 1];
  const rest = values.slice(0, -1).join(', ');
  return locale === 'bg'
    ? `${rest} и ${last}`
    : `${rest}, and ${last}`;
}

function localizedIndustryLabel(key: IndustryKey, locale: InsightLocale): string {
  const labels: Record<IndustryKey, { en: string; bg: string }> = {
    semiconductors: { en: 'Semiconductors', bg: 'Полупроводници' },
    cloud: { en: 'Cloud computing', bg: 'Облачни услуги' },
    defense: { en: 'Defense', bg: 'Отбрана' },
    finance: { en: 'Finance', bg: 'Финанси' },
    policy: { en: 'Public policy', bg: 'Публични политики' },
    crypto: { en: 'Cryptocurrency', bg: 'Криптовалути' },
    energy: { en: 'Energy', bg: 'Енергетика' },
    technology: { en: 'Technology', bg: 'Технологии' }
  };
  return locale === 'bg' ? labels[key].bg : labels[key].en;
}

const CONTEXTUAL_INSIGHT_NEWS_TYPES = new Set<NewsType>([
  NewsTypeValue.Politics,
  NewsTypeValue.Business,
  NewsTypeValue.Technology,
  NewsTypeValue.World,
  NewsTypeValue.Health,
  NewsTypeValue.Environment,
  NewsTypeValue.Crime
]);

const CLOUD_SIGNAL_RE = /\b(?:cloud|data center|data centres?|server|servers|hosting)\b|облач|сървър/iu;
const POLICY_SIGNAL_RE = /\b(?:regulator|regulators|law|laws|policy|policies|vote|election|government|parliament|sanction|sanctions|commission|authority|cabinet|ministry)\b|регулац|политик|правителств|парламент|санкц|комисия|министерств/iu;
const MARKET_SIGNAL_RE = /\b(?:market|markets|stocks?|earnings|prices?|investor|investors|trade|tariff|tariffs|bank|banks|economy|economic|deal|deals|inflation|currency|currencies|business|businesses|company|companies)\b|пазар|акци|инвест|банка|банки|иконом|сделк|цена|инфлац|валут|бизнес|компан/iu;
const WAR_SIGNAL_RE = /\b(?:war|military|missile|drone|strike|strikes|defense|defence|iran|israel|ukraine|russia|nato|attack|attacks|security|airspace|shipping|oil)\b|войн|удар|атака|дрон|ракет|отбран|сигурност|доставк|петрол/iu;
const HEALTH_SIGNAL_RE = /\b(?:hospital|doctor|medical|health|patient|patients|clinic|clinics)\b|лекар|болниц|медицин|пациент|здрав/iu;
const CLIMATE_SIGNAL_RE = /\b(?:climate|weather|storm|flood|drought|fire|energy|pollution)\b|еколог|климат|буря|навод|суша|пожар|енерг|замърся/iu;
const LEGAL_SIGNAL_RE = /\b(?:prosecutor|court|courts|police|investigation|investigations|lawsuit|lawsuits|trial|charge|charges|arrest|arrests|complaint|complaints|probe|probes)\b|прокурат|съд|полици|разслед|дело|жалб|арест|обвин/iu;
const TOURISM_SIGNAL_RE = /\b(?:travel|tourism|airport|airports|flight|flights|airline|airlines|hotel|hotels|visitor|visitors|tourist|tourists)\b|пътуван|туриз|летищ|полет|авиокомпан|хотел|посетител|турист/iu;
const TECHNOLOGY_STRONG_SIGNAL_RE = /\b(?:artificial intelligence|machine learning|semiconductor|semiconductors|chip|chips|software|cyber|cybersecurity|platform|platforms|cloud|cloud computing|privacy|app|apps|startup|startups|data breach|data center|data centres?)\b|изкуствен интелект|полупровод|софтуер|кибер|платформ|технолог|приложени/iu;
const TECHNOLOGY_SUPPORT_SIGNAL_RE = /\b(?:ai|algorithm|algorithms|model|models|data|digital|internet|online)\b|алгорит|модел|данни|дигитал|интернет|онлайн/iu;

function hasTechnologySignal(text: string): boolean {
  if (!text) return false;
  if (TECHNOLOGY_STRONG_SIGNAL_RE.test(text)) return true;
  let supportSignals = 0;
  if (/\bai\b/iu.test(text) || /\bизкуствен интелект\b/iu.test(text)) supportSignals += 1;
  if (/\b(?:data|digital|internet|online)\b/iu.test(text) || /данни|дигитал|интернет|онлайн/iu.test(text)) supportSignals += 1;
  if (/\b(?:algorithm|algorithms|model|models)\b/iu.test(text) || /алгорит|модел/iu.test(text)) supportSignals += 1;
  return supportSignals >= 2;
}

function contextualInsightSignalCount(item: NewsInternal): number {
  const text = combinedInsightText(item);
  if (!text) return 0;
  return [
    POLICY_SIGNAL_RE.test(text),
    MARKET_SIGNAL_RE.test(text),
    hasTechnologySignal(text),
    WAR_SIGNAL_RE.test(text),
    HEALTH_SIGNAL_RE.test(text),
    CLIMATE_SIGNAL_RE.test(text),
    LEGAL_SIGNAL_RE.test(text),
    TOURISM_SIGNAL_RE.test(text)
  ].filter(Boolean).length;
}

function hasContextualInsightText(item: NewsInternal): boolean {
  const rawContext = rawInsightContextText(item);
  if (rawContext.length >= 220) return true;
  return joinInsightTextParts([item.title, item.summary, rawContext]).length >= 180;
}

function shouldGenerateContextualInsights(item: NewsInternal): boolean {
  if (!hasContextualInsightText(item)) return false;
  const signalCount = contextualInsightSignalCount(item);
  if (signalCount >= 2) return true;
  const matched = item.isMatch && item.filteredOk !== false;
  const eligibleType = !!item.newsType && CONTEXTUAL_INSIGHT_NEWS_TYPES.has(item.newsType);
  return signalCount >= 1 && (matched || eligibleType);
}

function hasContextualInsightFeatureForBudget(budget: BudgetMode): boolean {
  void budget;
  return false;
}

function industryKeysForItem(item: NewsInternal): IndustryKey[] {
  const text = combinedInsightText(item);
  const industries: IndustryKey[] = [];
  const add = (key: IndustryKey) => {
    if (!industries.includes(key)) industries.push(key);
  };
  if (/\b(?:chip|chips|semiconductor|semiconductors|nvidia|tsmc|intel)\b|полупровод|чип/iu.test(text)) add('semiconductors');
  if (CLOUD_SIGNAL_RE.test(text)) add('cloud');
  if (/\b(?:army|defense|defence|missile|military|security)\b|армия|отбран|ракет|сигурност/iu.test(text)) add('defense');
  if (/\b(?:bank|banks|finance|financial|market|markets|stocks?|investor|investors)\b|банка|банки|финанс|пазар|инвест/iu.test(text)) add('finance');
  if (/\b(?:regulator|regulators|law|policy|parliament|senate|european union|eu)\b|регулац|правителств|парламент|европейски съюз/iu.test(text)) add('policy');
  if (/\b(?:crypto|bitcoin|blockchain)\b|крипто|биткойн|блокчейн/iu.test(text)) add('crypto');
  if (/\b(?:climate|energy|oil|gas|solar|wind)\b|климат|енерг|петрол|газ|солар|вятър/iu.test(text)) add('energy');
  if (hasTechnologySignal(text)) add('technology');
  return industries.slice(0, 6);
}

function detectSensationalism(item: NewsInternal): SensationalismInsight | undefined {
  const locale = insightLocale(item);
  const title = compactSentence(item.title, 220);
  if (!title) return undefined;
  const lower = title.toLocaleLowerCase();
  const reasons: string[] = [];
  if (/[!?]{2,}/.test(title)) reasons.push(insightText(locale, 'Repeated exclamation or question punctuation', 'Повтаряща се удивителна или въпросителна пунктуация'));
  if (/[A-Z]{4,}/.test(title)) reasons.push(insightText(locale, 'Excessive all-caps wording', 'Прекалено много думи с главни букви'));
  if (/(shocking|outrage|rage|furious|slams|destroys|explodes|massive|must see|you won.?t believe|panic)/i.test(lower)) reasons.push(insightText(locale, 'Emotionally charged wording', 'Емоционално натоварен език'));
  if (/(secret|exposed|what happened next|watch now|gone wrong)/i.test(lower)) reasons.push(insightText(locale, 'Clickbait phrasing', 'Кликбейт формулировка'));
  if (!reasons.length) return undefined;
  const level: InsightSeverity = reasons.length >= 3 ? 'high' : reasons.length === 2 ? 'medium' : 'low';
  return {
    detected: true,
    level,
    reasons,
    alternativeHeadline: title.replace(/[!?]+/g, '').replace(/\b(shocking|outrageous|massive|furious)\b/gi, '').replace(/\s+/g, ' ').trim() || title,
    summary: level === 'high'
      ? insightText(locale, 'Headline looks highly sensational and likely optimized for clicks.', 'Заглавието изглежда силно сензационно и вероятно е оптимизирано за кликове.')
      : insightText(locale, 'Headline shows signs of clickbait framing.', 'Заглавието показва признаци на кликбейт рамкиране.')
  };
}

function detectBias(item: NewsInternal): BiasInsight | undefined {
  const locale = insightLocale(item);
  const text = combinedInsightText(item);
  if (!text) return undefined;
  const lower = text.toLocaleLowerCase();
  let leaning = insightText(locale, 'no clear leaning', 'няма ясен уклон');
  if (/(government|regulator|state media|officials say|national security)/i.test(lower)) leaning = insightText(locale, 'closer to the government viewpoint', 'по-близо до правителствената гледна точка');
  else if (/(activists|rights groups|grassroots|workers|protesters)/i.test(lower)) leaning = insightText(locale, 'closer to a civil-society viewpoint', 'по-близо до гражданска гледна точка');
  else if (/(investors|markets|earnings|shareholders|business leaders)/i.test(lower)) leaning = insightText(locale, 'closer to an investor viewpoint', 'по-близо до инвеститорска гледна точка');

  let emotionalTone = insightText(locale, 'measured', 'сдържан');
  if (/(fear|anger|outrage|panic|crisis|chaos|furious)/i.test(lower)) emotionalTone = insightText(locale, 'emotionally charged', 'емоционален');
  else if (/(hope|optimism|breakthrough|relief)/i.test(lower)) emotionalTone = insightText(locale, 'reassuring', 'успокояващ');

  let framing = '';
  if (/(critics say|supporters say|officials say|according to)/i.test(lower)) framing = insightText(locale, 'Story relies on selective attribution and highlights one side more strongly.', 'Материалът разчита на селективно приписване и подчертава едната страна по-силно.');
  else if (/(investigation|alleged|claims|accused)/i.test(lower)) framing = insightText(locale, 'Story frames the topic through conflict or accusation language.', 'Материалът рамкира темата чрез език на конфликт или обвинение.');

  const severity: InsightSeverity = emotionalTone === insightText(locale, 'emotionally charged', 'емоционален') || framing ? 'medium' : 'low';
  if (leaning === insightText(locale, 'no clear leaning', 'няма ясен уклон') && emotionalTone === insightText(locale, 'measured', 'сдържан') && !framing) return undefined;
  return {
    detected: true,
    leaning,
    emotionalTone,
    framing: framing || insightText(locale, 'No strong framing distortion stands out.', 'Не се вижда силно изкривяване в подбора на факти.'),
    confidence: severity === 'medium' ? 'medium' : 'low',
    severity,
    summary: locale === 'bg'
      ? (
          leaning === insightText(locale, 'no clear leaning', 'няма ясен уклон')
            ? (
                emotionalTone === insightText(locale, 'emotionally charged', 'емоционален')
                  ? 'Не се вижда ясен политически уклон, но езикът е емоционален.'
                  : 'Не се вижда ясен политически уклон.'
              )
            : `${capitalizeInsight(leaning)}.`
        )
      : (
          leaning === insightText(locale, 'no clear leaning', 'няма ясен уклон')
            ? (
                emotionalTone === insightText(locale, 'emotionally charged', 'емоционален')
                  ? 'No clear political leaning stands out, but the language is emotionally charged.'
                  : 'No clear political leaning stands out.'
              )
            : `${capitalizeInsight(leaning)}.`
        )
  };
}

function industriesForItem(item: NewsInternal): string[] {
  const locale = insightLocale(item);
  return industryKeysForItem(item).map(key => localizedIndustryLabel(key, locale));
}

function buildStoryImpact(item: NewsInternal): StoryImpactInsight | undefined {
  const locale = insightLocale(item);
  const text = combinedInsightText(item);
  if (!text) return undefined;
  const industryKeys = industryKeysForItem(item);
  const industries = industryKeys.map(key => localizedIndustryLabel(key, locale));
  const policy = POLICY_SIGNAL_RE.test(text);
  const markets = MARKET_SIGNAL_RE.test(text);
  const tech = hasTechnologySignal(text);
  const score: ImpactLevel = (policy && markets) || (markets && tech) || industryKeys.length >= 3 ? 'high' : (policy || markets || tech) ? 'medium' : 'low';
  if (score === 'low') return undefined;
  const targetSectors = joinInsightList(locale, industries.slice(0, 3));
  return {
    score,
    economic: markets ? insightText(locale, 'Watch for moves in prices, costs, or investor expectations.', 'Следете за ефект върху цени, разходи или очаквания на инвеститорите.') : insightText(locale, 'No broad economic effect stands out yet.', 'Засега не се вижда широк икономически ефект.'),
    political: policy ? insightText(locale, 'A regulatory or political response is plausible.', 'Възможна е регулаторна или политическа реакция.') : insightText(locale, 'A political effect looks limited for now.', 'Политическият ефект засега изглежда ограничен.'),
    tech: tech ? insightText(locale, 'Technology companies may need to adjust products, infrastructure, or compliance.', 'Технологичните компании може да коригират продукти, инфраструктура или съответствие.') : insightText(locale, 'No direct technology effect stands out yet.', 'Засега не се вижда пряк ефект върху технологичния сектор.'),
    industries,
    summary: score === 'high'
      ? insightText(locale, `The clearest risk is for ${targetSectors}, with spillover into broader markets or policy if the story grows.`, `Най-ясният риск е за ${targetSectors}, а при развитие на темата може да има по-широк пазарен или регулаторен ефект.`)
      : insightText(locale, `The most likely effect is on ${targetSectors}, not on the whole economy.`, `Най-вероятният ефект е върху ${targetSectors}, а не върху цялата икономика.`)
  };
}

function buildPerspectives(item: NewsInternal): PerspectiveInsight[] | undefined {
  const locale = insightLocale(item);
  const text = combinedInsightText(item);
  const impact = buildStoryImpact(item);
  const industries = impact?.industries.length ? impact.industries.join(', ') : insightText(locale, 'affected sectors', 'засегнатите сектори');
  const out: PerspectiveInsight[] = [];
  const seen = new Set<string>();
  const add = (id: string, enLabel: string, bgLabel: string, enText: string, bgText: string) => {
    if (seen.has(id)) return;
    seen.add(id);
    out.push({
      id,
      label: locale === 'bg' ? bgLabel : enLabel,
      text: locale === 'bg' ? bgText : enText
    });
  };

  const health = HEALTH_SIGNAL_RE.test(text);
  const legal = LEGAL_SIGNAL_RE.test(text);
  const war = WAR_SIGNAL_RE.test(text);
  const politics = /\b(?:election|parliament|government|minister|party|vote|cabinet|policy|campaign|coalition)\b|избор|парламент|правителств|министр|партия|вот|политическ|политик/iu.test(text);
  const markets = MARKET_SIGNAL_RE.test(text);
  const tech = hasTechnologySignal(text);
  const environment = CLIMATE_SIGNAL_RE.test(text);
  const sports = /\b(?:match|football|soccer|uefa|fifa|basketball|tennis|coach)\b|спорт|мач|футбол|треньор|отбор|тенис|баскет/iu.test(text);
  const entertainment = /\b(?:film|movie|music|festival|celebrity|oscar|tv|concert)\b|кино|филм|музик|фестивал|оскар|концерт|телевиз/iu.test(text);
  const culture = /\b(?:zoo|gallery|museum|theatre|theater|concert|exhibition|festival|event|creative|art|artist|workshop|cultural|community|local event)\b|зоопарк|галери|музей|теат|концерт|изложб|фестивал|събитие|творческ|култур|артист|работилниц/iu.test(text);
  const localCommunity = /\b(?:municipality|mayor|city hall|community|local|citizens|residents|town|city)\b|общин|кмет|местн|жител|граждан/iu.test(text);

  if (health) {
    add('patient-safety', 'Patient safety', 'Безопасност на пациентите',
      'The practical question is whether the case points to a broader patient-safety failure, delayed care, or weak hospital controls.',
      'Практичният въпрос е дали случаят показва по-широк проблем с безопасността на пациентите, забавена грижа или слаби болнични контроли.');
    add('hospital-management', 'Hospital management', 'Болнично управление',
      'Hospital managers will look at staffing, procedures, documentation, and whether internal controls were followed.',
      'Болничното ръководство ще гледа към персонала, процедурите, документацията и дали вътрешните правила са били спазени.');
    add('investigators', 'Investigators', 'Разследващи органи',
      'Investigators will focus on evidence, timelines, and whether the incident reflects negligence or a systemic failure.',
      'Разследващите ще се фокусират върху доказателствата, хронологията и това дали има небрежност или системен проблем.');
    add('families', 'Families and the public', 'Близки и общество',
      'Families and the public care about accountability, transparency, and whether similar cases can be prevented.',
      'Близките и обществото се интересуват от отговорност, прозрачност и дали подобни случаи могат да бъдат предотвратени.');
  } else if (legal) {
    add('investigators', 'Investigators', 'Разследващи органи',
      'Investigators will care about evidence quality, witness credibility, and whether the timeline supports the claims.',
      'Разследващите органи ще гледат качеството на доказателствата, надеждността на свидетелите и дали хронологията подкрепя твърденията.');
    add('institutions', 'Institutions under scrutiny', 'Проверявани институции',
      'The institution under scrutiny will focus on legal exposure, procedure, and reputational damage.',
      'Проверяваната институция ще се фокусира върху правния риск, процедурите и репутационните щети.');
    add('public-trust', 'Public trust', 'Обществено доверие',
      'The wider public will judge whether the process looks fair, transparent, and credible.',
      'По-широката публика ще прецени дали процесът изглежда справедлив, прозрачен и достоверен.');
  } else if (war) {
    add('governments', 'Governments and diplomats', 'Правителства и дипломати',
      'Governments will watch for escalation risk, alliance pressure, and whether a diplomatic response becomes necessary.',
      'Правителствата ще следят риска от ескалация, натиска между съюзници и дали ще се наложи дипломатическа реакция.');
    add('security', 'Security services', 'Служби за сигурност',
      'Security teams care about deterrence, supply resilience, and whether the event changes threat assumptions.',
      'Службите за сигурност се интересуват от възпирането, устойчивостта на доставките и дали събитието променя оценката на риска.');
    add('civilians', 'Civilians and essential services', 'Граждани и жизнени услуги',
      'Civilians care about direct safety, transport disruption, energy costs, and access to essential services.',
      'Гражданите се интересуват от пряката безопасност, смущенията в транспорта, цените на енергията и достъпа до важни услуги.');
    if (markets || impact?.industries.length) {
      add('markets', 'Markets and operators', 'Пазари и оператори',
        `Markets will focus on price shocks, supply disruption, and operating risk across ${industries}.`,
        `Пазарите ще следят ценови шокове, смущения в доставките и оперативен риск за ${industries}.`);
    }
  } else if (culture) {
    add('audience', 'Visitors and audience', 'Посетители и публика',
      'The main question for visitors is whether the event feels accessible, worthwhile, and relevant to families or the local audience.',
      'Основният въпрос за посетителите е дали събитието е достъпно, стойностно и подходящо за семейства или местната публика.');
    add('organizers', 'Organizers', 'Организатори',
      'Organizers will care about turnout, logistics, public interest, and whether the program reaches the intended audience.',
      'Организаторите ще гледат посещаемостта, логистиката, обществения интерес и дали програмата достига до търсената публика.');
    add('institutions', 'Cultural institutions', 'Културни институции',
      'The institutions involved will care whether the event strengthens local visibility, partnerships, and public engagement.',
      'Замесените институции ще се интересуват дали събитието засилва местната видимост, партньорствата и ангажираността на публиката.');
    if (localCommunity) {
      add('community', 'Local community', 'Местна общност',
        'For the local community, the value is whether the event adds something useful, attractive, or educational to city life.',
        'За местната общност е важно дали събитието носи нещо полезно, привлекателно или образователно за живота в града.');
    }
  } else if (politics) {
    add('voters', 'Voters', 'Избиратели',
      'Voters will mainly care whether this changes trust, turnout, or the perceived competence of the main actors.',
      'Избирателите ще гледат най-вече дали това променя доверието, активността и възприятието за компетентност на основните участници.');
    add('institutions', 'Institutions', 'Институции',
      'Institutions will focus on legality, process stability, and whether rules need to be clarified or enforced.',
      'Институциите ще се фокусират върху законността, стабилността на процеса и дали правилата трябва да бъдат изяснени или приложени.');
    add('parties', 'Political actors', 'Политически играчи',
      'Political actors will look at narrative advantage, coalition pressure, and the risk of backlash.',
      'Политическите играчи ще мислят за предимството в наратива, коалиционния натиск и риска от обратна реакция.');
  } else if (markets) {
    add('companies', 'Companies', 'Компании',
      `Companies will care whether the story changes costs, demand, or operating conditions across ${industries}.`,
      `Компаниите ще гледат дали новината променя разходите, търсенето или условията за работа в ${industries}.`);
    add('investors', 'Investors', 'Инвеститори',
      `Investors will focus on revenue risk, margins, and whether regulation or sentiment shifts for ${industries}.`,
      `Инвеститорите ще се фокусират върху риска за приходите, маржовете и това дали регулацията или пазарните нагласи се променят за ${industries}.`);
    add('customers', 'Customers', 'Клиенти',
      'Customers will mainly notice the story if it affects price, availability, quality, or trust.',
      'Клиентите ще усетят темата най-вече ако тя влияе на цената, наличността, качеството или доверието.');
    add('regulators', 'Regulators', 'Регулатори',
      'Regulators will ask whether oversight, disclosure, or compliance enforcement needs to change.',
      'Регулаторите ще питат дали надзорът, разкриването на информация или прилагането на правилата трябва да се променят.');
  } else if (tech) {
    add('product-teams', 'Product teams', 'Продуктови екипи',
      'Product teams will care whether they need to change features, infrastructure, moderation, or compliance.',
      'Продуктовите екипи ще гледат дали трябва да променят функции, инфраструктура, модерация или съответствие.');
    add('users', 'Users', 'Потребители',
      'Users care whether the story changes reliability, privacy, safety, or cost.',
      'Потребителите се интересуват дали темата променя надеждността, поверителността, безопасността или цената.');
    add('regulators', 'Regulators', 'Регулатори',
      'Regulators will focus on data handling, platform power, security, or market conduct.',
      'Регулаторите ще следят управлението на данни, силата на платформите, сигурността или пазарното поведение.');
    add('security', 'Security teams', 'Екипи по сигурността',
      'Security teams will care whether the story changes threat models, patch urgency, or operational exposure.',
      'Екипите по сигурността ще гледат дали темата променя заплахите, спешността на корекциите или оперативния риск.');
  } else if (environment) {
    add('households', 'Households', 'Домакинства',
      'Households care whether the event changes safety, bills, transport, or day-to-day disruption.',
      'Домакинствата се интересуват дали събитието влияе на безопасността, сметките, транспорта или ежедневието.');
    add('local-authorities', 'Local authorities', 'Местни власти',
      'Local authorities will focus on response capacity, public communication, and mitigation steps.',
      'Местните власти ще се фокусират върху капацитета за реакция, публичната комуникация и мерките за ограничаване.');
    add('businesses', 'Businesses', 'Бизнес',
      'Businesses will watch for supply disruption, higher operating costs, or damage to infrastructure.',
      'Бизнесът ще следи за смущения в доставките, по-високи разходи или щети по инфраструктурата.');
  } else if (sports) {
    add('fans', 'Fans', 'Фенове',
      'Fans mainly care how the development changes competition, trust, and the experience around the sport.',
      'Феновете се интересуват основно как развитието променя състезанието, доверието и усещането около спорта.');
    add('clubs', 'Clubs and organizers', 'Клубове и организатори',
      'Clubs and organizers will focus on rules, scheduling, reputation, and commercial fallout.',
      'Клубовете и организаторите ще гледат правилата, графика, репутацията и търговските последици.');
    add('sponsors', 'Sponsors and broadcasters', 'Спонсори и медии',
      'Sponsors and broadcasters will care if the story affects audience interest, rights value, or brand safety.',
      'Спонсорите и медиите ще следят дали темата влияе на интереса на аудиторията, стойността на правата или безопасността за марките.');
  } else if (entertainment) {
    add('audience', 'Audience', 'Публика',
      'The audience cares whether the story changes trust, attention, or willingness to support the people involved.',
      'Публиката се интересува дали темата променя доверието, вниманието или желанието да подкрепя замесените хора.');
    add('studios', 'Studios and organizers', 'Студиа и организатори',
      'Studios and organizers will focus on reputation, contracts, scheduling, and commercial fallout.',
      'Студията и организаторите ще гледат репутацията, договорите, графика и търговските последици.');
    add('platforms', 'Platforms and advertisers', 'Платформи и рекламодатели',
      'Platforms and advertisers care whether the story changes audience demand, moderation pressure, or brand risk.',
      'Платформите и рекламодателите ще следят дали темата променя търсенето, натиска за модерация или риска за марките.');
  }

  return out.length ? out.slice(0, 4) : undefined;
}

function buildHistoricalComparison(item: NewsInternal): HistoricalComparisonInsight | undefined {
  const locale = insightLocale(item);
  const text = combinedInsightText(item).toLocaleLowerCase();
  type ComparisonCandidate = { label: string; explanation: string; score: number };
  const candidates: ComparisonCandidate[] = [];
  const addCandidate = (score: number, enLabel: string, bgLabel: string, enExplanation: string, bgExplanation: string) => {
    if (score < 2) return;
    candidates.push({
      score,
      label: locale === 'bg' ? bgLabel : enLabel,
      explanation: locale === 'bg' ? bgExplanation : enExplanation
    });
  };

  const privacySignals = [
    /\bprivacy\b/i.test(text),
    /\bdata\b/i.test(text),
    /\bplatform\b/i.test(text),
    /\bconsent\b/i.test(text),
    /\bgdpr\b/i.test(text),
    /\bрегулац/i.test(text),
    /\bданн/i.test(text),
    /\bплатформ/i.test(text)
  ].filter(Boolean).length;
  addCandidate(
    privacySignals,
    'EU GDPR rollout',
    'въвеждането на GDPR в ЕС',
    'The overlap is in data rules, platform obligations, and compliance pressure rather than in the exact event itself.',
    'Сходството е в правилата за данни, задълженията на платформите и натиска за съответствие, а не в самото събитие.'
  );

  const financeSignals = [
    /\bbank|banks|credit|liquidity|financial|bond|fund|market stress|bailout/i.test(text),
    /\bregulation|oversight|capital requirements|supervision/i.test(text),
    /\bбанка|банки|кредит|ликвид|финанс|облигац|фонд/i.test(text),
    /\bрегулац|надзор|капиталов/i.test(text)
  ].filter(Boolean).length;
  addCandidate(
    financeSignals,
    '2008 financial crisis regulations',
    'регулациите след финансовата криза от 2008 г.',
    'The overlap is in financial risk, market stress, and the likelihood of tighter oversight.',
    'Сходството е във финансовия риск, напрежението на пазарите и вероятността от по-строг надзор.'
  );

  const semiconductorSignals = [
    /\bchip|chips|semiconductor|semiconductors|foundry|nvidia|export controls?|supply chain/i.test(text),
    /\bchina|taiwan|factory|manufactur/i.test(text),
    /\bчип|чипове|полупровод|доставк|износ|контрол на износа/i.test(text)
  ].filter(Boolean).length;
  addCandidate(
    semiconductorSignals,
    '2020-2021 semiconductor shortages',
    'недостига на полупроводници през 2020-2021 г.',
    'The overlap is in chip supply constraints, export pressure, and exposure across hardware and downstream products.',
    'Сходството е в ограниченията по веригата за чипове, натиска върху износа и отражението върху хардуера и крайните продукти.'
  );

  const energySignals = [
    /\benergy|gas|oil|pipeline|shipping|strait|electricity|fuel/i.test(text),
    /\bwar|sanction|ukraine|russia|iran|israel|conflict|attack/i.test(text),
    /\bенерг|газ|петрол|горив|доставк|проток|кораб/i.test(text),
    /\bвойн|санкц|украйн|руси|иран|израел|конфликт|атака/i.test(text)
  ].filter(Boolean).length;
  addCandidate(
    energySignals,
    '2022 European energy shock',
    'европейския енергиен шок през 2022 г.',
    'The overlap is in conflict-driven energy risk, supply disruption, and spillover into prices and logistics.',
    'Сходството е в риска за енергията, породен от конфликт, прекъсванията на доставките и отражението върху цените и логистиката.'
  );

  candidates.sort((a, b) => b.score - a.score);
  if (!candidates.length) return undefined;
  const primary = candidates[0];
  return {
    comparisons: candidates.slice(0, 3).map(candidate => candidate.label),
    explanation: primary.explanation
  };
}

function buildFutureScenarios(item: NewsInternal): FutureScenarioInsight | undefined {
  const locale = insightLocale(item);
  const impact = buildStoryImpact(item);
  const text = combinedInsightText(item);
  const scenarios: string[] = [];
  const hasRegulatoryActor = /\b(regulator|regulators|government|parliament|lawmakers?|ministry|commission|authority|cabinet|policy|regulation|regulations|закон|закона|закони|правителств|парламент|министерств|комисия|регулатор)\b/i.test(text);
  const hasBusinessActor = /\b(company|companies|firm|firms|startup|startups|manufacturer|manufacturers|producer|producers|operator|operators|platform|platforms|bank|banks|business|businesses|corporate|corporation|meta|google|apple|amazon|microsoft|tesla|компания|компании|фирма|фирми|производител|производители|оператор|оператори|банка|банки|бизнес)\b/i.test(text);
  const hasLegalActor = /\b(lawsuit|lawsuits|investigation|investigations|complaint|complaints|probe|probes|alleged|court|courts|prosecutor|prosecutors|regulator|authority|дело|дела|разследване|разследвания|жалба|жалби|съд|съда|прокуратур)\b/i.test(text);
  const hasMarketActor = /\b(market|markets|investor|investors|share|shares|stock|stocks|bond|bonds|bank|banks|fund|funds|fx|валут|пазар|пазара|пазари|инвеститор|инвеститори|акци|облигаци|банка|банки|фонд|фондове)\b/i.test(text);

  if (hasRegulatoryActor) scenarios.push(insightText(locale, 'Regulators or lawmakers may intervene next', 'Възможна е следваща намеса на регулатори или законодатели'));
  if (hasBusinessActor) scenarios.push(insightText(locale, 'Companies involved may adjust products, hiring, or investment plans', 'Замесените компании може да коригират продукти, наемане или инвестиционни планове'));
  if (hasLegalActor) scenarios.push(insightText(locale, 'Legal or enforcement action may widen', 'Възможно е разширяване на правни или контролни действия'));
  if (hasMarketActor) scenarios.push(insightText(locale, 'Markets may reprice risk for the exposed names', 'Пазарите може да преоценят риска за засегнатите компании или активи'));
  if (!scenarios.length) return undefined;
  return {
    disclaimer: insightText(locale, 'Speculative', 'Спекулативно'),
    scenarios: scenarios.slice(0, 4),
    outlook: impact?.score === 'high'
      ? insightText(locale, 'Near-term follow-up is likely and could broaden the effect of the story.', 'Вероятно е скоро развитие, което може да разшири ефекта на темата.')
      : insightText(locale, 'Further movement is plausible, but it depends on confirmation and reaction from markets or institutions.', 'Възможно е развитие, но то зависи от потвърждение и реакция на пазара или институциите.')
  };
}

function buildLocalImpact(item: NewsInternal, region: string): LocalImpactInsight | undefined {
  const locale = insightLocale(item);
  const text = combinedInsightText(item);
  const impact = buildStoryImpact(item);
  if (!impact) return undefined;
  const safeRegion = compactSentence(region || insightText(locale, 'United States', 'България'), 120) || insightText(locale, 'United States', 'България');
  const war = WAR_SIGNAL_RE.test(text);
  const finance = MARKET_SIGNAL_RE.test(text);
  const tech = hasTechnologySignal(text);
  const health = HEALTH_SIGNAL_RE.test(text);
  const climate = CLIMATE_SIGNAL_RE.test(text);
  const tourism = TOURISM_SIGNAL_RE.test(text);

  let summary: string;
  if (war) {
    summary = locale === 'bg'
      ? `За ${safeRegion} по-вероятният ефект е през пътуванията, сигурността, горивата и цените на енергията, ако напрежението се разшири.`
      : `For ${safeRegion}, the more plausible effect is through travel, security, fuel costs, and energy prices if the tension spreads.`;
  } else if (finance) {
    summary = locale === 'bg'
      ? `За ${safeRegion} следете дали темата ще повлияе на пазарните нагласи, цената на кредитирането, валутите или бизнес доверието.`
      : `For ${safeRegion}, watch whether the story affects market sentiment, borrowing costs, currencies, or business confidence.`;
  } else if (tech) {
    summary = locale === 'bg'
      ? `За ${safeRegion} темата има значение най-вече ако доведе до нови правила, разходи за съответствие или промени в цифровите услуги.`
      : `For ${safeRegion}, the story matters mainly if it leads to new rules, compliance costs, or changes in digital services.`;
  } else if (health) {
    summary = locale === 'bg'
      ? `За ${safeRegion} темата е важна, ако предизвика проверки, промени в болничните стандарти или нов обществен натиск за по-добър контрол.`
      : `For ${safeRegion}, the story matters if it triggers inspections, changes in hospital standards, or stronger public pressure for oversight.`;
  } else if (climate) {
    summary = locale === 'bg'
      ? `За ${safeRegion} следете дали ще има ефект върху енергийните разходи, транспорта, инфраструктурата или местните мерки за реакция.`
      : `For ${safeRegion}, watch for effects on energy costs, transport, infrastructure, or local response measures.`;
  } else if (tourism) {
    summary = locale === 'bg'
      ? `За ${safeRegion} темата има значение най-вече ако промени туристическия поток, полетите, сигурността на събитията или местния интерес към пътувания и посещения.`
      : `For ${safeRegion}, the story matters mainly if it changes tourist flows, flights, event security, or local demand for travel and visits.`;
  } else {
    summary = locale === 'bg'
      ? `За ${safeRegion} темата е най-важна за ${impact.industries.length ? joinInsightList(locale, impact.industries.slice(0, 3)) : 'местния бизнес и публичните политики'}. Следете дали ще има регулации, ценови промени или ефект върху доставки и услуги.`
      : `For ${safeRegion}, the story matters most for ${impact.industries.length ? joinInsightList(locale, impact.industries.slice(0, 3)) : 'local business and public policy'}. Watch for regulation, price changes, or effects on supply and services.`;
  }
  return {
    region: safeRegion,
    summary
  };
}

function reviewGeneratedInsights(item: NewsInternal, insights: NewsInsights): NewsInsights | undefined {
  const reviewed: NewsInsights = { ...insights };
  const locale = insightLocale(item);

  if (reviewed.bias) {
    const mixed = reviewed.bias.leaning === insightText(locale, 'no clear leaning', 'няма ясен уклон');
    const neutralFraming = reviewed.bias.framing === insightText(locale, 'No strong framing distortion stands out.', 'Не се вижда силно изкривяване в подбора на факти.');
    if (mixed && reviewed.bias.severity === 'low' && neutralFraming) {
      delete reviewed.bias;
    }
  }

  if (reviewed.facts) {
    const hasStrongKeywords = reviewed.facts.people.length > 0 || reviewed.facts.locations.length > 0 || reviewed.facts.quotes.length > 0;
    if (!hasStrongKeywords) delete reviewed.facts;
  }

  return Object.keys(reviewed).length ? reviewed : undefined;
}

function hasEligibleInsightFeatureForBudget(budget: BudgetMode): boolean {
  return (
    (aiFeatures.biasDetection && insightFeatureAllowed('biasDetection', budget)) ||
    (aiFeatures.sensationalismDetection && insightFeatureAllowed('sensationalismDetection', budget)) ||
    (aiFeatures.factHighlights && insightFeatureAllowed('factHighlights', budget)) ||
    (aiFeatures.topicTracking && insightFeatureAllowed('topicTracking', budget)) ||
    (aiFeatures.emergingStoryDetector && insightFeatureAllowed('emergingStoryDetector', budget))
  );
}

function computeInsightStatus(item: NewsInternal, budget: BudgetMode, insights: NewsInsights | undefined): InsightStatus | undefined {
  if (!aiEnabled || !aiAvailable) return undefined;
  if (!hasEligibleInsightFeatureForBudget(budget)) return undefined;
  if (insights && Object.keys(insights).length) return 'ready';
  const contextualCandidate = hasContextualInsightFeatureForBudget(budget) && shouldGenerateContextualInsights(item);
  if (!contextualCandidate) return undefined;
  const waitingForSummary = shouldHaveSummary(item) && (!item.summary || !item.summary.trim() || hasSummaryJobQueuedOrRunning(item.id, item.feedUrl));
  const waitingForResearch = shouldHaveResearch(item) && (!item.research || !item.research.trim() || hasResearchJobQueuedOrRunning(item.id, item.feedUrl));
  return waitingForSummary || waitingForResearch ? 'pending' : 'empty';
}

function topicHitsForItem(item: NewsInternal): string[] {
  if (!aiFeatures.topicTracking || !trackedTopics.length) return [];
  const text = combinedInsightText(item).toLocaleLowerCase();
  return trackedTopics.filter(topic => text.includes(topic.toLocaleLowerCase())).slice(0, 8);
}

function emergingSignalForItem(item: NewsInternal): EmergingStorySignal | undefined {
  const locale = insightLocale(item);
  if (!aiFeatures.emergingStoryDetector || !item.isMatch || item.filteredOk === false) return undefined;
  const base = normalizeText(item.title).slice(0, 160);
  if (!base) return undefined;
  const tokens = new Set(base.split(/\s+/g).filter(token => token.length > 3));
  if (!tokens.size) return undefined;
  const related = recent.filter(candidate => {
    if (candidate.id === item.id) return false;
    if (!candidate.isMatch || candidate.filteredOk === false) return false;
    if (Math.abs(candidate.publishedMs - item.publishedMs) > 18 * 60 * 60 * 1000) return false;
    const candidateTokens = new Set(normalizeText(candidate.title).split(/\s+/g).filter(token => token.length > 3));
    let overlap = 0;
    tokens.forEach(token => {
      if (candidateTokens.has(token)) overlap += 1;
    });
    return overlap >= Math.max(2, Math.floor(tokens.size * 0.4));
  });
  const clusterSize = related.length + 1;
  if (clusterSize < 2) return undefined;
  const sources = Array.from(new Set([item.source, ...related.map(candidate => candidate.source)])).filter(Boolean).slice(0, 6);
  const velocity: EmergingStorySignal['velocity'] = clusterSize >= 5 ? 'viral' : clusterSize >= 3 ? 'rising' : 'watch';
  return {
    clusterSize,
    sources,
    velocity,
    reason: clusterSize >= 5
      ? insightText(locale, 'This topic is repeating across multiple sources quickly.', 'Темата се повтаря бързо в множество източници.')
      : insightText(locale, 'Similar matched stories are appearing across more than one source.', 'Подобни истории се появяват в повече от един източник.')
  };
}

function generateInsightsForItem(item: NewsInternal, budget: BudgetMode): NewsInsights | undefined {
  const insights: NewsInsights = {};
  if (aiFeatures.biasDetection && insightFeatureAllowed('biasDetection', budget)) {
    const bias = detectBias(item);
    if (bias) insights.bias = bias;
  }
  if (aiFeatures.sensationalismDetection && insightFeatureAllowed('sensationalismDetection', budget)) {
    const sensationalism = detectSensationalism(item);
    if (sensationalism) insights.sensationalism = sensationalism;
  }
  if (aiFeatures.factHighlights && insightFeatureAllowed('factHighlights', budget)) {
    const facts = extractFactHighlights(item);
    if (facts) insights.facts = facts;
  }
  return reviewGeneratedInsights(item, insights);
}

function refreshDerivedDataForItem(item: NewsInternal) {
  const budget = feedSettings.get(item.feedUrl)?.budget || 'standard';
  const insights = generateInsightsForItem(item, budget);
  item.insights = insights;
  item.insightStatus = computeInsightStatus(item, budget, insights);
  item.topicHits = topicHitsForItem(item);
  item.emergingSignal = emergingSignalForItem(item);
}

function reprocessCachedItems(broadcast = false, persist = true) {
  recent.forEach(item => {
    refreshDerivedDataForItem(item);
    if (persist) void upsertPersistedNewsItem(item);
    if (broadcast) broadcastNewsUpdate(item);
  });
}

function canGenerateDailyBriefing(feedUrls: string[]): { ok: true; items: NewsInternal[] } | { ok: false; reason: string } {
  if (!aiEnabled || !aiAvailable) return { ok: false, reason: 'AI must be enabled and configured before a briefing can be created.' };
  if (!aiFeatures.dailyBriefing) return { ok: false, reason: 'Daily briefing is turned off in AI features.' };
  const selected = feedUrls.length ? feedUrls : currentFeeds().map(feed => feed.url);
  const uniqueSelected = Array.from(new Set(selected));
  const selectedHighBudget = uniqueSelected.some(feedUrl => (feedSettings.get(feedUrl)?.budget || 'standard') === 'high');
  if (!selectedHighBudget) return { ok: false, reason: 'Daily briefing requires at least one selected high-budget column.' };
  const items = recent.filter(item => uniqueSelected.includes(item.feedUrl)).sort((a, b) => b.publishedMs - a.publishedMs).slice(0, 16);
  if (!items.length) return { ok: false, reason: 'No recent stories are available for the selected columns.' };
  return { ok: true, items };
}

function isValidEmailAddress(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function generateDailyBriefingPayload(
  items: NewsInternal[],
  delivery: BriefingDelivery,
  email: string | undefined,
  format: BriefingFormat,
  includeAudio: boolean,
  feedUrls: string[]
): DailyBriefingResult {
  const topItems = items.slice(0, 8);
  const lines = topItems.map(item => {
    const lead = compactSentence(item.summary || item.research || item.title, 180) || item.title;
    const impact = item.insights?.impact?.summary || '';
    return { item, lead, impact };
  });
  let body = '';
  if (format === 'bullets') {
    body = lines.map(({ item, lead, impact }) => `• ${item.title}\n${lead}${impact ? `\nImpact: ${impact}` : ''}`).join('\n\n');
  } else if (format === 'narrative') {
    body = lines.map(({ item, lead, impact }) => `${item.source}: ${lead}${impact ? ` ${impact}` : ''}`).join('\n\n');
  } else {
    body = ['Executive briefing', '', ...lines.map(({ item, lead, impact }) => `${item.title}\n${lead}${impact ? `\nWhy it matters: ${impact}` : ''}`)].join('\n\n');
  }
  return {
    type: 'daily_briefing',
    title: `Daily briefing · ${new Date().toLocaleDateString()}`,
    body,
    audioScript: includeAudio ? body.replace(/•/g, 'Story:') : '',
    generatedAtMs: Date.now(),
    itemCount: items.length,
    delivery,
    email: email || undefined,
    format,
    feedUrls
  };
}

function summaryInstruction(lang: SummaryLang): string {
  const quality = 'Use the context/article text, not the headline alone. Add one concrete detail that is NOT already in the headline. If no extra factual detail is available, return exactly NO_SUMMARY.';
  if (lang === 'bg') return `${quality} Write ONE short sentence in Bulgarian (max 22 words). Do NOT include English text. Do NOT use "/" separators.`;
  if (lang === 'en') return `${quality} Write ONE short sentence in English (max 22 words). Do NOT include Bulgarian text. Do NOT use "/" separators.`;
  return `${quality} Write TWO short sentences: first Bulgarian (max 18 words), then English (max 18 words). Separate with " / ".`;
}

function enforceSummaryLanguage(summaryRaw: string, lang: SummaryLang): string {
  const summary = String(summaryRaw || '').trim();
  if (!summary) return '';
  const parts = summary.split(/\s\/\s/).map(v => v.trim()).filter(Boolean);
  if (parts.length <= 1) return summary;
  if (lang === 'bg') return parts[0] || summary;
  if (lang === 'en') return parts[parts.length - 1] || summary;
  if (parts.length >= 2) return `${parts[0]} / ${parts[parts.length - 1]}`;
  return summary;
}

function summaryInstructionWithoutTranslation(title: string): string {
  const quality = 'Use the context/article text, not the headline alone. Add one concrete detail that is NOT already in the headline. If no extra factual detail is available, return exactly NO_SUMMARY.';
  if (looksBulgarianTitle(title)) {
    return `${quality} Write ONE short sentence in Bulgarian (max 22 words). Do not translate.`;
  }
  if (looksEnglishTitle(title)) {
    return `${quality} Write ONE short sentence in English (max 22 words). Do not translate.`;
  }
  return `${quality} Write ONE short sentence in the same language as the original headline/context (max 22 words). Do not translate.`;
}

function isTranslationEnabledForFeed(feedUrl: string): boolean {
  return feedSettings.get(feedUrl)?.translationEnabled !== false;
}

function summaryInstructionForFeed(feedUrl: string, title: string): string {
  return isTranslationEnabledForFeed(feedUrl)
    ? summaryInstruction(summaryLang)
    : summaryInstructionWithoutTranslation(title);
}

const SUMMARY_STOPWORDS = new Set([
  'the', 'and', 'for', 'from', 'with', 'that', 'this', 'into', 'over', 'after', 'before',
  'about', 'will', 'would', 'could', 'should', 'only', 'news', 'said', 'says',
  'както', 'като', 'след', 'преди', 'това', 'този', 'тази', 'тези', 'които', 'който',
  'която', 'към', 'във', 'със', 'без', 'при', 'или', 'ако', 'има', 'няма', 'ще',
  'беше', 'са', 'се', 'си', 'на', 'за', 'от', 'до', 'по', 'че', 'и', 'в', 'с', 'а', 'е'
]);

function summaryTokens(raw: string): string[] {
  return String(raw || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .split(/\s+/g)
    .map(token => token.trim())
    .filter(token => token.length >= 3 && !SUMMARY_STOPWORDS.has(token));
}

function usefulContextTokenCount(title: string, context: string): number {
  const titleTokens = new Set(summaryTokens(title));
  return Array.from(new Set(summaryTokens(context))).filter(token => !titleTokens.has(token)).length;
}

function hasUsefulSummaryContext(title: string, context: string): boolean {
  const cleaned = String(context || '').replace(/\s+/g, ' ').trim();
  if (!cleaned) return false;
  if (cleaned.length >= 140) return true;
  return usefulContextTokenCount(title, cleaned) >= 5;
}

function summaryRepeatsHeadline(title: string, summary: string): boolean {
  const titleTokens = new Set(summaryTokens(title));
  const summaryUnique = Array.from(new Set(summaryTokens(summary)));
  if (summaryUnique.length < 4) return true;
  const overlap = summaryUnique.filter(token => titleTokens.has(token)).length;
  const novel = summaryUnique.length - overlap;
  const coverage = overlap / summaryUnique.length;
  const titleKey = normalizedTitleKey(title);
  const summaryKey = normalizedTitleKey(summary);
  if (!summaryKey) return true;
  if (titleKey && (titleKey.includes(summaryKey) || summaryKey.includes(titleKey))) return true;
  return coverage >= 0.68 && novel < 3;
}

// ---------------- Better Research Prompt ----------------
function researchInstruction(lang: ResearchLang): string {
  const common = [
    'Write a concise but detailed research note (1–2 paragraphs).',
    'Cover: what happened, who is involved, why it matters, what to watch next.',
    'Be explicit when context is insufficient.',
    'End all paragraphs with complete sentences. Do not cut off mid-sentence.',
    'End with: "Confidence: Low/Medium/High".',
    'If Confidence is Low, add one more sentence starting with "What to verify:" describing what sources/details are missing.',
    'Neutral tone. No quotes. No bullet points.'
  ].join(' ');

  if (lang === 'bg') return common + ' Write in Bulgarian.';
  return common + ' Write in English.';
}

function titleTranslateInstruction(): string {
  return [
    'Translate the headline to Bulgarian and English.',
    'Return strict JSON only with exactly two keys: "bg" and "en".',
    'Do not add markdown, code fences, or extra keys.',
    'Keep meaning and names intact.',
    'Keep each headline concise and natural.'
  ].join(' ');
}

function titleTranslateSingleInstruction(lang: 'bg' | 'en'): string {
  if (lang === 'bg') {
    return [
      'Translate this headline to Bulgarian.',
      'Return plain text only.',
      'No quotes, no markdown, no extra commentary.'
    ].join(' ');
  }
  return [
    'Translate this headline to English.',
    'Return plain text only.',
    'No quotes, no markdown, no extra commentary.'
  ].join(' ');
}

function normalizeTitleValue(raw: unknown): string {
  return String(raw || '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 320);
}

function normalizedTitleKey(raw: string): string {
  return String(raw || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function letterScriptRatios(raw: string): { cyr: number; lat: number } {
  const text = String(raw || '');
  const cyr = (text.match(/[А-Яа-яЁёЍѝ]/g) || []).length;
  const lat = (text.match(/[A-Za-z]/g) || []).length;
  const total = cyr + lat;
  if (!total) return { cyr: 0, lat: 0 };
  return { cyr: cyr / total, lat: lat / total };
}

function looksBulgarianTitle(raw: string): boolean {
  const { cyr } = letterScriptRatios(raw);
  return cyr >= 0.45;
}

function looksEnglishTitle(raw: string): boolean {
  const { lat } = letterScriptRatios(raw);
  return lat >= 0.55;
}

function parseTitleTranslation(raw: string): { bg: string; en: string } | undefined {
  const text = String(raw || '').trim();
  if (!text) return undefined;

  const normalized = text
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/\s*```$/i, '')
    .trim();

  const tryParse = (candidate: string): { bg: string; en: string } | undefined => {
    try {
      const parsed = JSON.parse(candidate) as Record<string, unknown>;
      const bg = normalizeTitleValue(parsed.bg);
      const en = normalizeTitleValue(parsed.en);
      if (!bg || !en) return undefined;
      return { bg, en };
    } catch {
      return undefined;
    }
  };

  const direct = tryParse(normalized);
  if (direct) return direct;

  const m = normalized.match(/\{[\s\S]*\}/);
  if (!m) return undefined;
  return tryParse(m[0]);
}

function hasValidOppositeLanguageTitle(
  originalTitle: string,
  titleBgRaw: string | undefined,
  titleEnRaw: string | undefined
): boolean {
  const original = normalizeTitleValue(originalTitle);
  if (!original) return false;
  const sourceKey = normalizedTitleKey(original);

  const bg = normalizeTitleValue(titleBgRaw || '');
  const en = normalizeTitleValue(titleEnRaw || '');
  const bgKey = normalizedTitleKey(bg);
  const enKey = normalizedTitleKey(en);

  const sourceLooksBg = looksBulgarianTitle(original);
  const sourceLooksEn = looksEnglishTitle(original);

  if (sourceLooksBg && !sourceLooksEn) {
    return !!en && !!enKey && enKey !== sourceKey && looksEnglishTitle(en);
  }

  if (sourceLooksEn && !sourceLooksBg) {
    return !!bg && !!bgKey && bgKey !== sourceKey && looksBulgarianTitle(bg);
  }

  // Fallback for mixed/unknown script sources.
  return !!bg && !!en && !!bgKey && !!enKey && bgKey !== enKey;
}

function needsTitleTranslation(
  originalTitle: string,
  titleBgRaw: string | undefined,
  titleEnRaw: string | undefined
): boolean {
  return !hasValidOppositeLanguageTitle(originalTitle, titleBgRaw, titleEnRaw);
}

function normalizeMood(raw: string): Mood | undefined {
  const s = String(raw || '')
    .trim()
    .toLowerCase()
    .replace(/["'`]/g, '')
    .replace(/[^\p{L}\p{N}\s_-]+/gu, ' ')
    .replace(/\s+/g, ' ');
  const direct = s.replace(/[\s_-]/g, '');

  if (direct === 'pesimistic' || direct === 'pessimistic') return MoodValue.Pesimistic;
  if (direct === 'optimistic') return MoodValue.Optimistic;
  if (direct === 'realistic') return MoodValue.Realistic;
  if (direct === 'melancholy' || direct === 'melancholic') return MoodValue.Melancholy;
  if (direct === 'happiness' || direct === 'happy' || direct === 'joy' || direct === 'joyful') return MoodValue.Happiness;
  if (direct === 'sadness' || direct === 'sad') return MoodValue.Sadness;
  if (direct === 'rage' || direct === 'angry' || direct === 'anger' || direct === 'furious') return MoodValue.Rage;
  if (direct === 'uncertainty' || direct === 'uncertain' || direct === 'anxiety' || direct === 'anxious') return MoodValue.Uncertainty;
  if (direct === 'neutral') return MoodValue.Neutral;
  if (direct === 'curios' || direct === 'curious' || direct === 'curiosity') return MoodValue.Curios;

  if (s.includes('pesimistic') || s.includes('pessimistic')) return MoodValue.Pesimistic;
  if (s.includes('optimistic')) return MoodValue.Optimistic;
  if (s.includes('realistic')) return MoodValue.Realistic;
  if (s.includes('melancholy') || s.includes('melancholic')) return MoodValue.Melancholy;
  if (s.includes('happiness') || s.includes('joy')) return MoodValue.Happiness;
  if (s.includes('sadness') || s.includes(' sad')) return MoodValue.Sadness;
  if (s.includes('rage') || s.includes('anger') || s.includes('angry')) return MoodValue.Rage;
  if (s.includes('uncertainty') || s.includes('uncertain') || s.includes('anxiety')) return MoodValue.Uncertainty;
  if (s.includes('neutral')) return MoodValue.Neutral;
  if (s.includes('curios') || s.includes('curious') || s.includes('curiosity')) return MoodValue.Curios;
  return undefined;
}

function moodInstruction(): string {
  return [
    'Classify the overall mood of this news into exactly one label.',
    'Allowed labels only:',
    `${Object.values(MoodValue).join(', ')}.`,
    'Return exactly one label with no extra words or punctuation.'
  ].join(' ');
}

function normalizeNewsType(raw: string): NewsType | undefined {
  const s = String(raw || '')
    .trim()
    .toLowerCase()
    .replace(/["'`]/g, '')
    .replace(/[^\p{L}\p{N}\s_-]+/gu, ' ')
    .replace(/\s+/g, ' ');
  const direct = s.replace(/[\s_-]/g, '');

  if (direct === 'science' || direct === 'scientific') return NewsTypeValue.Science;
  if (direct === 'movies' || direct === 'movie' || direct === 'film' || direct === 'cinema') return NewsTypeValue.Movies;
  if (direct === 'politics' || direct === 'political') return NewsTypeValue.Politics;
  if (direct === 'business' || direct === 'finance' || direct === 'economy' || direct === 'economic') return NewsTypeValue.Business;
  if (direct === 'technology' || direct === 'tech') return NewsTypeValue.Technology;
  if (direct === 'sports' || direct === 'sport') return NewsTypeValue.Sports;
  if (direct === 'health' || direct === 'medical' || direct === 'medicine') return NewsTypeValue.Health;
  if (direct === 'world' || direct === 'international') return NewsTypeValue.World;
  if (direct === 'culture' || direct === 'arts' || direct === 'art') return NewsTypeValue.Culture;
  if (direct === 'environment' || direct === 'climate') return NewsTypeValue.Environment;
  if (direct === 'crime' || direct === 'criminal' || direct === 'law') return NewsTypeValue.Crime;
  if (direct === 'education' || direct === 'school' || direct === 'academic') return NewsTypeValue.Education;
  if (direct === 'other') return NewsTypeValue.Other;

  if (s.includes('science')) return NewsTypeValue.Science;
  if (s.includes('movie') || s.includes('film') || s.includes('cinema')) return NewsTypeValue.Movies;
  if (s.includes('politic')) return NewsTypeValue.Politics;
  if (s.includes('business') || s.includes('finance') || s.includes('econom')) return NewsTypeValue.Business;
  if (s.includes('technology') || s.includes('tech')) return NewsTypeValue.Technology;
  if (s.includes('sport')) return NewsTypeValue.Sports;
  if (s.includes('health') || s.includes('medical') || s.includes('medicine')) return NewsTypeValue.Health;
  if (s.includes('world') || s.includes('international')) return NewsTypeValue.World;
  if (s.includes('culture') || s.includes('art')) return NewsTypeValue.Culture;
  if (s.includes('environment') || s.includes('climate')) return NewsTypeValue.Environment;
  if (s.includes('crime') || s.includes('criminal') || s.includes('law')) return NewsTypeValue.Crime;
  if (s.includes('education') || s.includes('school') || s.includes('academic')) return NewsTypeValue.Education;
  return undefined;
}

function newsTypeInstruction(): string {
  return [
    'Classify the news topic into exactly one label.',
    'Allowed labels only:',
    `${Object.values(NewsTypeValue).join(', ')}.`,
    'Return exactly one label with no extra words or punctuation.'
  ].join(' ');
}

function budgetToTokensSummary(b: BudgetMode) {
  if (b === 'low') return 55;
  if (b === 'high') return 95;
  return 70;
}

function budgetToTokensResearch(b: BudgetMode) {
  if (b === 'low') return 320;
  if (b === 'high') return 760;
  return 540;
}

function budgetToTokensAsk(b: BudgetMode) {
  if (b === 'low') return 130;
  if (b === 'high') return 260;
  return 190;
}

function budgetAllowsAutoResearch(b: BudgetMode) {
  // Low mode: research only on manual click
  return b !== 'low';
}

// --------------- Optional article fetch + extraction ---------------
async function fetchWithTimeout(url: string, options: RequestInit, timeoutMs: number) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { ...options, signal: ctrl.signal });
    return res;
  } finally {
    clearTimeout(t);
  }
}

function extractMainTextFromHtml(html: string): string {
  const cleaned = String(html || '')
    .replace(/<script[\s\S]*?>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?>[\s\S]*?<\/style>/gi, ' ');

  // Prefer <article> if present
  const articleMatch = cleaned.match(/<article[\s\S]*?<\/article>/i);
  const chunk = articleMatch ? articleMatch[0] : cleaned;

  // Strip tags -> text
  const text = stripHtml(chunk);

  // Light de-noise: remove too many repeats / huge whitespace already handled
  return text;
}

async function fetchArticleText(link: string, maxChars: number): Promise<string> {
  if (!link || !/^https?:\/\//i.test(link)) return '';
  try {
    const res = await fetchWithTimeout(
      link,
      {
        headers: {
          'User-Agent': 'live-news-ai/1.0 (+rss-research)',
          'Accept': 'text/html,application/xhtml+xml'
        }
      },
      9000
    );
    if (!res.ok) return '';
    const ctype = res.headers.get('content-type') || '';
    if (!ctype.includes('text/html')) return '';
    const html = await res.text();
    const text = extractMainTextFromHtml(html);
    return text.slice(0, Math.max(0, maxChars));
  } catch {
    return '';
  }
}
// ------------------------------------------------------------------

// ---------------- AI calls ----------------
async function generateWithOpenAiLike(
  kind: AiModelKind,
  model: string,
  input: string,
  maxOutputTokens: number,
  temperature: number,
  labelRaw?: unknown,
  debugMeta?: SummaryDebugMeta
): Promise<string | undefined> {
  const client = activeOpenAiLikeClient();
  if (!client) return undefined;
  const startedAt = Date.now();
  try {
    const resp = await client.responses.create({
      model,
      input,
      max_output_tokens: maxOutputTokens,
      temperature
    });
    trackUsageFromResponse(kind, model, resp, labelRaw);
    const extracted = extractOpenAiLikeText(resp);
    if (kind === 'summary' && debugMeta) {
      recordSummaryDebugEvent({
        atMs: Date.now(),
        isoTime: new Date().toISOString(),
        itemId: debugMeta.itemId,
        feedUrl: debugMeta.feedUrl,
        source: debugMeta.source,
        title: debugMeta.title,
        provider: aiProvider,
        model,
        status: extracted.text ? 'success' : 'empty',
        durationMs: Date.now() - startedAt,
        extractionSource: extracted.extractionSource,
        promptPreview: previewText(input),
        responsePreview: previewJson({
          output_text: resp?.output_text,
          output: resp?.output,
          usage: resp?.usage
        }),
        summaryPreview: previewText(extracted.text)
      });
    }
    return extracted.text || undefined;
  } catch (error) {
    if (kind === 'summary' && debugMeta) {
      recordSummaryDebugEvent({
        atMs: Date.now(),
        isoTime: new Date().toISOString(),
        itemId: debugMeta.itemId,
        feedUrl: debugMeta.feedUrl,
        source: debugMeta.source,
        title: debugMeta.title,
        provider: aiProvider,
        model,
        status: 'error',
        durationMs: Date.now() - startedAt,
        promptPreview: previewText(input),
        error: previewText((error as Error)?.message || error, 500)
      });
    }
    throw error;
  }
}

async function generateWithClaude(
  kind: AiModelKind,
  model: string,
  input: string,
  maxOutputTokens: number,
  temperature: number,
  labelRaw?: unknown,
  debugMeta?: SummaryDebugMeta
): Promise<string | undefined> {
  if (!providerApiKeys.claude) return undefined;
  const startedAt = Date.now();

  try {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': providerApiKeys.claude,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model,
        max_tokens: maxOutputTokens,
        temperature,
        messages: [{ role: 'user', content: input }]
      })
    });

    if (!res.ok) {
      throw new Error(`Claude HTTP ${res.status}`);
    }

    const json = await res.json() as any;
    const usage = json?.usage || {};
    trackUsage(kind, model, usage.input_tokens || 0, usage.output_tokens || 0, 0, labelRaw);

    const text = Array.isArray(json?.content)
      ? json.content
        .filter((x: any) => x && x.type === 'text' && typeof x.text === 'string')
        .map((x: any) => String(x.text))
        .join('\n')
        .trim()
      : '';

    if (kind === 'summary' && debugMeta) {
      recordSummaryDebugEvent({
        atMs: Date.now(),
        isoTime: new Date().toISOString(),
        itemId: debugMeta.itemId,
        feedUrl: debugMeta.feedUrl,
        source: debugMeta.source,
        title: debugMeta.title,
        provider: aiProvider,
        model,
        status: text ? 'success' : 'empty',
        durationMs: Date.now() - startedAt,
        extractionSource: text ? 'content.text' : 'none',
        promptPreview: previewText(input),
        responsePreview: previewJson({
          content: json?.content,
          usage: json?.usage
        }),
        summaryPreview: previewText(text)
      });
    }
    return text || undefined;
  } catch (error) {
    if (kind === 'summary' && debugMeta) {
      recordSummaryDebugEvent({
        atMs: Date.now(),
        isoTime: new Date().toISOString(),
        itemId: debugMeta.itemId,
        feedUrl: debugMeta.feedUrl,
        source: debugMeta.source,
        title: debugMeta.title,
        provider: aiProvider,
        model,
        status: 'error',
        durationMs: Date.now() - startedAt,
        promptPreview: previewText(input),
        error: previewText((error as Error)?.message || error, 500)
      });
    }
    throw error;
  }
}

async function generateAiText(
  kind: 'summary' | 'research' | 'ask',
  input: string,
  maxOutputTokens: number,
  temperature: number,
  labelRaw?: unknown,
  debugMeta?: SummaryDebugMeta
): Promise<string | undefined> {
  if (!aiEnabled || !aiAvailable) return undefined;
  const model = activeModel(kind);
  if (!model || model === 'none') return undefined;

  if (aiProvider === 'claude') {
    return generateWithClaude(kind, model, input, maxOutputTokens, temperature, labelRaw, debugMeta);
  }
  return generateWithOpenAiLike(kind, model, input, maxOutputTokens, temperature, labelRaw, debugMeta);
}

async function withTimeout<T>(promise: Promise<T>, timeoutMs: number, label: string): Promise<T> {
  let timeoutId: ReturnType<typeof setTimeout> | null = null;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timeoutId = setTimeout(() => reject(new Error(`${label} timeout`)), timeoutMs);
      })
    ]);
  } finally {
    if (timeoutId) clearTimeout(timeoutId);
  }
}

async function oneLineSummary(
  itemId: string,
  feedUrl: string,
  title: string,
  source: string,
  context: string,
  articleText: string,
  budget: BudgetMode
): Promise<string | undefined> {
  const usefulContext = hasUsefulSummaryContext(title, context) ? context : '';
  const usefulArticle = hasUsefulSummaryContext(title, articleText) ? articleText : '';
  if (!usefulContext && !usefulArticle) return undefined;

  const input =
    `${summaryInstructionForFeed(feedUrl, title)} No quotes.\n` +
    `Source: ${source}\n` +
    `Headline: ${title}\n` +
    (usefulContext ? `RSS context: ${usefulContext}\n` : '') +
    (usefulArticle ? `Article text: ${usefulArticle}\n` : '');

  const generated = await generateAiText(
    'summary',
    input,
    budgetToTokensSummary(budget),
    0.2,
    `Summary: ${source} - ${title}`,
    { itemId, feedUrl, source, title }
  );
  if (!generated) return generated;
  const summary = enforceSummaryLanguage(generated, summaryLang);
  if (!summary || /^NO_SUMMARY\.?$/i.test(summary.trim())) return undefined;
  if (summaryRepeatsHeadline(title, summary)) return undefined;
  return summary;
}

async function translateTitleBilingual(
  title: string,
  source: string,
  budget: BudgetMode
): Promise<{ bg: string; en: string } | undefined> {
  const originalTitle = normalizeTitleValue(title);
  if (!originalTitle) return undefined;
  const srcKey = normalizedTitleKey(originalTitle);
  const sourceLooksBg = looksBulgarianTitle(originalTitle);
  const sourceLooksEn = looksEnglishTitle(originalTitle);
  const maxTokens = Math.max(90, Math.min(220, budgetToTokensSummary(budget) + 70));

  const translateSingle = async (lang: 'bg' | 'en'): Promise<string> => {
    const retryText = await generateAiText(
      'summary',
      `${titleTranslateSingleInstruction(lang)}\nSource: ${source}\nHeadline: ${originalTitle}\n`,
      maxTokens,
      0,
      `Title translation (${lang}): ${source} - ${originalTitle}`
    );
    return normalizeTitleValue(retryText || '');
  };

  const input =
    `${titleTranslateInstruction()}\n` +
    `Source: ${source}\n` +
    `Headline: ${originalTitle}\n`;

  const text = await generateAiText('summary', input, maxTokens, 0, `Title translation: ${source} - ${originalTitle}`);
  const parsed = text ? parseTitleTranslation(text) : undefined;

  let bg = normalizeTitleValue(parsed?.bg || '');
  let en = normalizeTitleValue(parsed?.en || '');

  // If the source is clearly one language, keep that side exactly as the original title
  // and only translate the opposite side.
  if (sourceLooksBg && !sourceLooksEn) {
    bg = originalTitle;
    let enKey = normalizedTitleKey(en);
    if (!en || enKey === srcKey || !looksEnglishTitle(en)) {
      en = await translateSingle('en');
      enKey = normalizedTitleKey(en);
    }
    if (!en || enKey === srcKey) return undefined;
    return { bg, en };
  }

  if (sourceLooksEn && !sourceLooksBg) {
    en = originalTitle;
    let bgKey = normalizedTitleKey(bg);
    if (!bg || bgKey === srcKey || !looksBulgarianTitle(bg)) {
      bg = await translateSingle('bg');
      bgKey = normalizedTitleKey(bg);
    }
    if (!bg || bgKey === srcKey) return undefined;
    return { bg, en };
  }

  const bgNeedsRetry = !bg || !looksBulgarianTitle(bg);
  const enNeedsRetry = !en || !looksEnglishTitle(en);

  if (bgNeedsRetry) {
    const retryBg = await translateSingle('bg');
    if (retryBg && looksBulgarianTitle(retryBg)) bg = retryBg;
  }

  if (enNeedsRetry) {
    const retryEn = await translateSingle('en');
    if (retryEn && looksEnglishTitle(retryEn)) en = retryEn;
  }

  if (!bg || !en) return undefined;

  const bgKey = normalizedTitleKey(bg);
  const enKey = normalizedTitleKey(en);

  if (bgKey && enKey && bgKey === enKey) {
    if (looksBulgarianTitle(title)) {
      // Source is likely BG; keep BG and keep EN only if it differs.
      if (enKey === srcKey) return undefined;
    } else if (looksEnglishTitle(title)) {
      // Source is likely EN; keep EN and keep BG only if it differs.
      if (bgKey === srcKey) return undefined;
    } else {
      return undefined;
    }
  }

  return { bg, en };
}

async function oneItemResearch(
  title: string,
  source: string,
  link: string,
  context: string,
  linkText: string,
  budget: BudgetMode
): Promise<string | undefined> {
  const input =
    `${researchInstruction(researchLang)}\n` +
    `Source: ${source}\n` +
    `Headline: ${title}\n` +
    `Link: ${link}\n` +
    (context ? `RSS context: ${context}\n` : '') +
    (linkText ? `Article text (may be partial): ${linkText}\n` : '');

  return generateAiText('research', input, budgetToTokensResearch(budget), 0.25, `Research: ${source} - ${title}`);
}

async function oneItemResearchFallback(
  title: string,
  source: string,
  link: string,
  context: string,
  budget: BudgetMode
): Promise<string | undefined> {
  const input =
    `${researchInstruction(researchLang)}\n` +
    `Source: ${source}\n` +
    `Headline: ${title}\n` +
    `Link: ${link}\n` +
    (context ? `RSS context: ${context}\n` : '') +
    'Note: article body fetch was slow/unavailable. Use available context only.';

  const maxTokens = Math.max(220, Math.floor(budgetToTokensResearch(budget) * 0.62));
  return generateAiText('research', input, maxTokens, 0.2, `Research fallback: ${source} - ${title}`);
}

async function classifyMoodForItem(
  title: string,
  source: string,
  context: string,
  summary: string,
  research: string,
  budget: BudgetMode
): Promise<Mood | undefined> {
  const input =
    `${moodInstruction()}\n` +
    `Source: ${source}\n` +
    `Headline: ${title}\n` +
    (context ? `Context: ${context}\n` : '') +
    (summary ? `Summary: ${summary}\n` : '') +
    (research ? `Research: ${research}\n` : '');
  const text = await generateAiText('research', input, Math.max(12, Math.min(28, budgetToTokensSummary(budget))), 0, `Mood classification: ${source} - ${title}`);
  if (!text) return undefined;
  return normalizeMood(text);
}

async function classifyNewsTypeForItem(
  title: string,
  source: string,
  context: string,
  summary: string,
  research: string,
  budget: BudgetMode
): Promise<NewsType | undefined> {
  const input =
    `${newsTypeInstruction()}\n` +
    `Source: ${source}\n` +
    `Headline: ${title}\n` +
    (context ? `Context: ${context}\n` : '') +
    (summary ? `Summary: ${summary}\n` : '') +
    (research ? `Research: ${research}\n` : '');
  const text = await generateAiText('research', input, Math.max(16, Math.min(34, budgetToTokensSummary(budget))), 0, `Type classification: ${source} - ${title}`);
  if (!text) return undefined;
  return normalizeNewsType(text) || 'other';
}

function askAgentInstruction(lang: ResearchLang): string {
  const langText = lang === 'bg' ? 'Reply in Bulgarian.' : 'Reply in English.';
  return [
    'You are an assistant for exactly one news item.',
    'Answer only questions that are about this exact item and only with the supplied item context.',
    'If the question is off-topic for this item, reply exactly: "I can only answer questions about this specific news item."',
    'If context is missing, say it briefly and stay grounded in the provided text.',
    'Keep the answer concise (max 4 sentences).',
    langText
  ].join(' ');
}

async function askAgentAboutItem(
  question: string,
  item: NewsInternal,
  budget: BudgetMode,
  chatResearch?: string
): Promise<string | undefined> {
  const safeQuestion = String(question || '').slice(0, ASK_AGENT_MAX_CHARS);
  const input =
    `${askAgentInstruction(researchLang)}\n` +
    `Question: ${safeQuestion}\n` +
    `Source: ${item.source}\n` +
    `Headline: ${item.title}\n` +
    `Link: ${item.link}\n` +
    (item.summary ? `Summary: ${item.summary}\n` : '') +
    ((chatResearch && chatResearch.trim()) || (item.research && item.research.trim())
      ? `Research: ${(chatResearch && chatResearch.trim()) ? chatResearch : item.research}\n`
      : '') +
    (item.__ctx ? `RSS context: ${item.__ctx}\n` : '') +
    (item.__linkText ? `Article text (may be partial): ${item.__linkText}\n` : '');

  return generateAiText('ask', input, budgetToTokensAsk(budget), 0.2, `Ask agent: ${item.source} - ${item.title}`);
}
// -----------------------------------------

function broadcastConfig() {
  const activeSelection = currentModelSelection(aiProvider);
  const cfg: Config = {
    type: 'config',
    keywords,
    newsAccessLocked: isNewsAccessLocked(),

    aiProvider,
    aiAvailable,
    aiEnabled,

    summaryLang,
    researchLang,
    titleDisplayLanguage,
    summaryModel: activeSelection.summary,
    researchModel: activeSelection.research,
    askModel: activeSelection.ask,
    availableModels: modelOptionsByProvider,
    aiFeatures,
    localRegion,
    localLlmBaseUrl,
    trackedTopics,

    matchThreshold: MATCH_THRESHOLD,
    dedupeThreshold: DEDUPE_THRESHOLD,

    filteredAiDedupe: FILTERED_AI_DEDUPE,
    filteredDedupeThreshold: FILTERED_DEDUPE_THRESHOLD,

    feeds: currentFeeds(),
    feedSettings: feedSettingsObj(),
    hiddenIds: Array.from(hiddenIds),
    ...buildAiUsagePayload()
  };

  const payload = JSON.stringify(cfg);
  wss.clients.forEach((c: WebSocket) => {
    if (c.readyState === WebSocket.OPEN) c.send(payload);
  });
}

function toNewsWire(it: NewsInternal): News {
  return {
    type: 'news',
    id: it.id,
    title: it.title,
    titleBg: it.titleBg,
    titleEn: it.titleEn,
    coverUrl: it.coverUrl,
    link: it.link,
    source: it.source,
    published: it.published,
    publishedMs: it.publishedMs,
    feedUrl: it.feedUrl,
    isMatch: it.isMatch,
    matchScore: it.matchScore,
    filteredOk: it.filteredOk,
    summary: it.summary,
    summaryEligible: isPublishedInRecentSummaryWindow(it.publishedMs),
    summaryPending: hasSummaryJobQueuedOrRunning(it.id, it.feedUrl),
    research: it.research,
    researchPending: hasResearchJobQueuedOrRunning(it.id, it.feedUrl),
    titleTranslatePending: hasTitleTranslateJobQueuedOrRunning(it.id, it.feedUrl),
    insightStatus: it.insightStatus,
    insights: it.insights,
    topicHits: it.topicHits,
    emergingSignal: it.emergingSignal,
    mood: it.mood,
    newsType: it.newsType
  };
}

function broadcastNewsUpdate(it: NewsInternal) {
  if (hiddenIds.has(it.id)) return;

  const payload = JSON.stringify(toNewsWire(it));

  wss.clients.forEach((c: WebSocket) => {
    if (c.readyState === WebSocket.OPEN) c.send(payload);
  });
}

function sendFeedPage(ws: WebSocket, feedUrl: string, items: NewsInternal[], hasMore: boolean, nextCursor?: FeedPageCursor, replace = false) {
  const payload: FeedPagePayload = {
    type: 'feed_page',
    feedUrl,
    items: items.map(toNewsWire),
    hasMore,
    replace,
    ...(nextCursor ? { nextCursor } : {})
  };
  ws.send(JSON.stringify(payload));
}

function broadcastFeedError(fi: FeedInfo, error: string) {
  const now = Date.now();
  const last = lastFeedErrorBroadcastMs.get(fi.url) || 0;
  if (now - last < 15_000) return;
  lastFeedErrorBroadcastMs.set(fi.url, now);

  const rt = feedRuntime.get(fi.url);
  const payload = JSON.stringify({
    type: 'feed_error',
    feedUrl: fi.url,
    feedLabel: labelForFeed(fi),
    error,
    failCount: rt?.failCount ?? 0,
    disabledUntilMs: rt?.disabledUntilMs ?? 0
  });

  wss.clients.forEach((c: WebSocket) => {
    if (c.readyState === WebSocket.OPEN) c.send(payload);
  });
}

function eligibleForFeed(it: NewsInternal, feedUrl: string): boolean {
  if (feedUrl === FILTERED_FEED_URL) return it.isMatch && it.filteredOk !== false;
  return it.feedUrl === feedUrl;
}

function shouldHaveSummary(it: NewsInternal): boolean {
  const ownFeedSummary = !!feedSettings.get(it.feedUrl)?.summaryEnabled;
  const filteredSummary =
    !!feedSettings.get(FILTERED_FEED_URL)?.summaryEnabled &&
    !!it.isMatch &&
    it.filteredOk !== false;
  return ownFeedSummary || filteredSummary;
}

function recentSummaryWindowStartLocal(nowMs = Date.now()): number {
  const todayStart = new Date(nowMs);
  todayStart.setHours(0, 0, 0, 0);
  return todayStart.getTime() - 24 * 60 * 60 * 1000;
}

function isPublishedInRecentSummaryWindow(publishedMs: number, nowMs = Date.now()): boolean {
  if (!Number.isFinite(publishedMs) || publishedMs <= 0) return false;
  return publishedMs >= recentSummaryWindowStartLocal(nowMs);
}

function isAutoSummaryEligible(it: NewsInternal, nowMs = Date.now()): boolean {
  return shouldHaveSummary(it) && isPublishedInRecentSummaryWindow(it.publishedMs, nowMs);
}

function shouldHaveResearch(it: NewsInternal): boolean {
  const ownFeedResearch = !!feedSettings.get(it.feedUrl)?.researchEnabled;
  const filteredResearch =
    !!feedSettings.get(FILTERED_FEED_URL)?.researchEnabled &&
    !!it.isMatch &&
    it.filteredOk !== false;
  return ownFeedResearch || filteredResearch;
}

// ---------------- AI JOB QUEUE (non-blocking) ----------------
type AiJobKind = 'summary' | 'title_translate' | 'research' | 'mood' | 'news_type';
type AiJobInput = { kind: AiJobKind; id: string; feedUrl: string; manual?: boolean; viewport?: boolean };
type AiJob = AiJobInput & { enqueuedAtMs: number };
type DeadLetterAiJob = {
  kind: AiJobKind;
  id: string;
  feedUrl: string;
  manual?: boolean;
  viewport?: boolean;
  enqueuedAtMs: number;
  droppedAtMs: number;
  reason: string;
};

type AiJobLogStage = 'enqueue' | 'start' | 'success' | 'skip' | 'drop' | 'error';
type AiJobLogEvent = {
  atMs: number;
  isoTime: string;
  stage: AiJobLogStage;
  kind: AiJobKind;
  id: string;
  feedUrl: string;
  manual: boolean;
  reason?: string;
  durationMs?: number;
  queueLength: number;
  inFlight: number;
};
type SummaryDebugMeta = {
  itemId: string;
  feedUrl: string;
  source: string;
  title: string;
};
type SummaryDebugEvent = {
  atMs: number;
  isoTime: string;
  itemId: string;
  feedUrl: string;
  source: string;
  title: string;
  provider: AIProvider;
  model: string;
  status: 'start' | 'success' | 'empty' | 'error';
  durationMs?: number;
  extractionSource?: string;
  promptPreview?: string;
  responsePreview?: string;
  summaryPreview?: string;
  error?: string;
};

const aiQueue: AiJob[] = [];
const aiInFlight = new Set<string>();
const aiDeadLetters: DeadLetterAiJob[] = [];
const aiJobLogEvents: AiJobLogEvent[] = [];
const summaryDebugEvents: SummaryDebugEvent[] = [];
const lastAiJobErrorAtMs = new Map<string, number>();
const aiTimeoutCounts = new Map<string, number>();

const AI_MAX_CONCURRENCY = Math.max(1, parseInt(process.env.AI_MAX_CONCURRENCY || '1', 10));
const AI_QUEUE_MAX = Math.max(200, parseInt(process.env.AI_QUEUE_MAX || '600', 10));
const AI_JOB_TTL_MS = Math.max(15_000, Number.parseInt(process.env.AI_JOB_TTL_MS ?? '180_000', 10) || 180_000);
const AI_DEAD_LETTER_MAX = Math.max(50, Number.parseInt(process.env.AI_DEAD_LETTER_MAX ?? '400', 10) || 400);
const AI_JOB_LOG_MAX = Math.max(100, Number.parseInt(process.env.AI_JOB_LOG_MAX ?? '1200', 10) || 1200);
const AI_JOB_LOG_VERBOSE = String(process.env.AI_JOB_LOG_VERBOSE || '').trim().toLowerCase() === 'true';
const AI_JOB_LOG_PERSIST = String(process.env.AI_JOB_LOG_PERSIST || 'true').trim().toLowerCase() !== 'false';
const API_ROOT_DIR = (() => {
  const candidate = path.resolve(__dirname, '..');
  if (fs.existsSync(path.join(candidate, 'package.json'))) return candidate;
  return process.cwd();
})();
const AI_JOB_LOG_DIR = (() => {
  const fromEnv = String(process.env.AI_JOB_LOG_DIR || '').trim();
  if (fromEnv) return path.resolve(fromEnv);
  return path.join(API_ROOT_DIR, '.data', 'logs');
})();
const AI_JOB_LOG_FILE_PATH = path.join(AI_JOB_LOG_DIR, 'ai-jobs.jsonl');
const AI_JOB_LOG_ROTATE_BYTES = Math.max(
  128 * 1024,
  Number.parseInt(process.env.AI_JOB_LOG_ROTATE_BYTES ?? '5242880', 10) || 5 * 1024 * 1024
);
const AI_JOB_LOG_ROTATE_FILES = Math.max(
  1,
  Number.parseInt(process.env.AI_JOB_LOG_ROTATE_FILES ?? '10', 10) || 10
);
const AI_JOB_LOG_FLUSH_INTERVAL_MS = Math.max(
  250,
  Number.parseInt(process.env.AI_JOB_LOG_FLUSH_INTERVAL_MS ?? '1500', 10) || 1500
);
const AI_SUMMARY_DEBUG_MAX = Math.max(
  50,
  Number.parseInt(process.env.AI_SUMMARY_DEBUG_MAX ?? '240', 10) || 240
);
const AI_TIMEOUT_RETRY_LIMIT = Math.max(
  1,
  Number.parseInt(process.env.AI_TIMEOUT_RETRY_LIMIT ?? '4', 10) || 4
);
const aiJobLogFileBuffer: string[] = [];
let aiJobLogFlushTimer: NodeJS.Timeout | null = null;
let aiJobLogFlushInProgress = false;
const AI_SUMMARY_TIMEOUT_MS = Math.max(4_000, Number.parseInt(process.env.AI_SUMMARY_TIMEOUT_MS ?? '22_000', 10) || 22_000);
const AI_SUMMARY_RETRY_COOLDOWN_MS = Math.max(5_000, Number.parseInt(process.env.AI_SUMMARY_RETRY_COOLDOWN_MS ?? '20_000', 10) || 20_000);
const AI_SUMMARY_RECOVERY_INTERVAL_MS = Math.max(2_000, Number.parseInt(process.env.AI_SUMMARY_RECOVERY_INTERVAL_MS ?? '8_000', 10) || 8_000);
const AI_SUMMARY_RECOVERY_BATCH = Math.max(1, Math.min(100, Number.parseInt(process.env.AI_SUMMARY_RECOVERY_BATCH ?? '24', 10) || 24));
const AI_SUMMARY_BACKLOG_PAUSE_TITLE_TRANSLATE = Math.max(
  1,
  Number.parseInt(process.env.AI_SUMMARY_BACKLOG_PAUSE_TITLE_TRANSLATE ?? '8', 10) || 8
);
const AI_TITLE_RECOVERY_INTERVAL_MS = Math.max(3_000, Number.parseInt(process.env.AI_TITLE_RECOVERY_INTERVAL_MS ?? '9_000', 10) || 9_000);
const AI_TITLE_RECOVERY_BATCH = Math.max(1, Math.min(120, Number.parseInt(process.env.AI_TITLE_RECOVERY_BATCH ?? '32', 10) || 32));
const AI_RESEARCH_RECOVERY_INTERVAL_MS = Math.max(4_000, Number.parseInt(process.env.AI_RESEARCH_RECOVERY_INTERVAL_MS ?? '12_000', 10) || 12_000);
const AI_RESEARCH_RECOVERY_BATCH = Math.max(1, Math.min(80, Number.parseInt(process.env.AI_RESEARCH_RECOVERY_BATCH ?? '18', 10) || 18));
const AI_TITLE_TRANSLATE_TIMEOUT_MS = Math.max(6_000, Number.parseInt(process.env.AI_TITLE_TRANSLATE_TIMEOUT_MS ?? '24_000', 10) || 24_000);
const AI_RESEARCH_TIMEOUT_MS = Math.max(8_000, Number.parseInt(process.env.AI_RESEARCH_TIMEOUT_MS ?? '45_000', 10) || 45_000);
const AI_RESEARCH_TIMEOUT_MANUAL_MS = Math.max(
  AI_RESEARCH_TIMEOUT_MS,
  Number.parseInt(process.env.AI_RESEARCH_TIMEOUT_MANUAL_MS ?? '60_000', 10) || 60_000
);
const AI_RESEARCH_ARTICLE_MAX_CHARS = Math.max(
  800,
  Number.parseInt(process.env.AI_RESEARCH_ARTICLE_MAX_CHARS ?? '1600', 10) || 1600
);
const AI_SUMMARY_ARTICLE_MAX_CHARS = Math.max(
  600,
  Number.parseInt(process.env.AI_SUMMARY_ARTICLE_MAX_CHARS ?? '2200', 10) || 2200
);
const AI_CLASSIFY_TIMEOUT_MS = Math.max(6_000, Number.parseInt(process.env.AI_CLASSIFY_TIMEOUT_MS ?? '22_000', 10) || 22_000);
const AI_ERROR_TOAST_COOLDOWN_MS = Math.max(5_000, Number.parseInt(process.env.AI_ERROR_TOAST_COOLDOWN_MS ?? '20_000', 10) || 20_000);
let lastSummaryRecoveryAtMs = 0;
let lastTitleRecoveryAtMs = 0;
let lastResearchRecoveryAtMs = 0;
const summaryRetryCooldownUntilMs = new Map<string, number>();
const discordPostAttemptStartedAtMs = new Map<string, number>();
const discordPostTimerByKey = new Map<string, ReturnType<typeof setTimeout>>();
const DISCORD_POST_RETRY_DELAY_MS = 7_500;
const DISCORD_POST_MAX_WAIT_MS = 2 * 60_000;

function ensureAiJobLogDir() {
  if (!AI_JOB_LOG_PERSIST) return;
  try {
    fs.mkdirSync(AI_JOB_LOG_DIR, { recursive: true });
  } catch {}
}

function rotateSuffix() {
  return new Date()
    .toISOString()
    .replace(/[-:]/g, '')
    .replace(/\..+$/, '')
    .replace('T', '_');
}

function rotateAiJobLogFileIfNeeded(nextBytes: number) {
  if (!AI_JOB_LOG_PERSIST) return;
  try {
    if (!fs.existsSync(AI_JOB_LOG_FILE_PATH)) return;
    const stat = fs.statSync(AI_JOB_LOG_FILE_PATH);
    if ((stat.size + nextBytes) < AI_JOB_LOG_ROTATE_BYTES) return;
    const rotatedPath = path.join(AI_JOB_LOG_DIR, `ai-jobs-${rotateSuffix()}.jsonl`);
    fs.renameSync(AI_JOB_LOG_FILE_PATH, rotatedPath);
  } catch (error) {
    console.error('AI job log rotate failed:', (error as Error).message);
  }
}

function pruneAiJobLogFiles() {
  if (!AI_JOB_LOG_PERSIST) return;
  try {
    const entries = fs.readdirSync(AI_JOB_LOG_DIR, { withFileTypes: true });
    const rotated = entries
      .filter(entry => entry.isFile() && /^ai-jobs-\d{8}_\d{6}\.jsonl$/i.test(entry.name))
      .map(entry => {
        const fullPath = path.join(AI_JOB_LOG_DIR, entry.name);
        const stat = fs.statSync(fullPath);
        return { fullPath, mtimeMs: stat.mtimeMs };
      })
      .sort((a, b) => b.mtimeMs - a.mtimeMs);

    const toDelete = rotated.slice(AI_JOB_LOG_ROTATE_FILES);
    toDelete.forEach(file => {
      try {
        fs.unlinkSync(file.fullPath);
      } catch {}
    });
  } catch {}
}

function flushAiJobLogBufferNow() {
  if (!AI_JOB_LOG_PERSIST) return;
  if (aiJobLogFlushInProgress) return;
  if (!aiJobLogFileBuffer.length) return;
  aiJobLogFlushInProgress = true;
  try {
    ensureAiJobLogDir();
    const lines = aiJobLogFileBuffer.splice(0, aiJobLogFileBuffer.length);
    const payload = `${lines.join('\n')}\n`;
    rotateAiJobLogFileIfNeeded(Buffer.byteLength(payload, 'utf8'));
    fs.appendFileSync(AI_JOB_LOG_FILE_PATH, payload, 'utf8');
    pruneAiJobLogFiles();
  } catch (error) {
    console.error('AI job log flush failed:', (error as Error).message);
  } finally {
    aiJobLogFlushInProgress = false;
  }
}

function ensureAiJobLogFlushTimer() {
  if (!AI_JOB_LOG_PERSIST) return;
  if (aiJobLogFlushTimer) return;
  aiJobLogFlushTimer = setInterval(() => {
    flushAiJobLogBufferNow();
  }, AI_JOB_LOG_FLUSH_INTERVAL_MS);
  aiJobLogFlushTimer.unref?.();
}

function stopAiJobLogFlushTimer() {
  if (!aiJobLogFlushTimer) return;
  clearInterval(aiJobLogFlushTimer);
  aiJobLogFlushTimer = null;
}

function persistAiJobEvent(event: AiJobLogEvent) {
  if (!AI_JOB_LOG_PERSIST) return;
  ensureAiJobLogFlushTimer();
  aiJobLogFileBuffer.push(JSON.stringify(event));
  if (aiJobLogFileBuffer.length >= 100) {
    flushAiJobLogBufferNow();
  }
}

function jobKey(j: AiJob) {
  return `${j.kind}:${j.feedUrl || ''}::${j.id}`;
}

function hasSummaryJobQueuedOrRunning(id: string, feedUrl: string): boolean {
  const k = `summary:${feedUrl || ''}::${id}`;
  if (aiInFlight.has(k)) return true;
  return aiQueue.some(job => job.kind === 'summary' && job.id === id && job.feedUrl === feedUrl);
}

function hasResearchJobQueuedOrRunning(id: string, feedUrl: string): boolean {
  const k = `research:${feedUrl || ''}::${id}`;
  if (aiInFlight.has(k)) return true;
  return aiQueue.some(job => job.kind === 'research' && job.id === id && job.feedUrl === feedUrl);
}

function hasTitleTranslateJobQueuedOrRunning(id: string, feedUrl: string): boolean {
  const k = `title_translate:${feedUrl || ''}::${id}`;
  if (aiInFlight.has(k)) return true;
  return aiQueue.some(job => job.kind === 'title_translate' && job.id === id && job.feedUrl === feedUrl);
}

function summaryItemKey(id: string, feedUrl: string): string {
  return `${feedUrl || ''}::${id}`;
}

function isJobExpired(job: AiJob, nowMs = Date.now()): boolean {
  return nowMs - job.enqueuedAtMs > AI_JOB_TTL_MS;
}

function pushDeadLetter(job: AiJob, reason: string) {
  aiDeadLetters.push({
    kind: job.kind,
    id: job.id,
    feedUrl: job.feedUrl,
    manual: job.manual,
    viewport: job.viewport,
    enqueuedAtMs: job.enqueuedAtMs,
    droppedAtMs: Date.now(),
    reason
  });
  if (aiDeadLetters.length > AI_DEAD_LETTER_MAX) {
    aiDeadLetters.splice(0, aiDeadLetters.length - AI_DEAD_LETTER_MAX);
  }
}

function aiQueueCounts() {
  const counts: Record<AiJobKind, number> = {
    summary: 0,
    title_translate: 0,
    research: 0,
    mood: 0,
    news_type: 0
  };
  aiQueue.forEach(job => {
    counts[job.kind] += 1;
  });
  return counts;
}

function hasSummaryBacklog(): boolean {
  const counts = aiQueueCounts();
  if (counts.summary >= AI_SUMMARY_BACKLOG_PAUSE_TITLE_TRANSLATE) return true;
  for (const key of aiInFlight) {
    if (key.startsWith('summary:')) return true;
  }
  return false;
}

function timeoutAttemptKey(job: Pick<AiJob, 'kind' | 'id' | 'feedUrl'>): string {
  return `${job.kind}:${job.feedUrl || ''}::${job.id}`;
}

function timeoutAttemptsFor(job: Pick<AiJob, 'kind' | 'id' | 'feedUrl'>): number {
  return aiTimeoutCounts.get(timeoutAttemptKey(job)) || 0;
}

function hasExceededTimeoutRetryLimit(job: Pick<AiJob, 'kind' | 'id' | 'feedUrl'>): boolean {
  return timeoutAttemptsFor(job) >= AI_TIMEOUT_RETRY_LIMIT;
}

function recordTimeoutAttempt(job: Pick<AiJob, 'kind' | 'id' | 'feedUrl'>): number {
  const key = timeoutAttemptKey(job);
  const next = timeoutAttemptsFor(job) + 1;
  aiTimeoutCounts.set(key, next);
  if (aiTimeoutCounts.size > 20_000) {
    const entries = Array.from(aiTimeoutCounts.entries());
    for (let i = 0; i < entries.length - 10_000; i += 1) {
      aiTimeoutCounts.delete(entries[i][0]);
    }
  }
  return next;
}

function clearTimeoutAttempts(job: Pick<AiJob, 'kind' | 'id' | 'feedUrl'>) {
  aiTimeoutCounts.delete(timeoutAttemptKey(job));
}

function recordAiJobEvent(job: Pick<AiJob, 'kind' | 'id' | 'feedUrl' | 'manual'>, stage: AiJobLogStage, opts?: {
  reason?: string;
  durationMs?: number;
}) {
  const event: AiJobLogEvent = {
    atMs: Date.now(),
    isoTime: new Date().toISOString(),
    stage,
    kind: job.kind,
    id: job.id,
    feedUrl: job.feedUrl,
    manual: !!job.manual,
    reason: opts?.reason,
    durationMs: opts?.durationMs,
    queueLength: aiQueue.length,
    inFlight: aiInFlight.size
  };
  aiJobLogEvents.push(event);
  if (aiJobLogEvents.length > AI_JOB_LOG_MAX) {
    aiJobLogEvents.splice(0, aiJobLogEvents.length - AI_JOB_LOG_MAX);
  }
  persistAiJobEvent(event);
  if (AI_JOB_LOG_VERBOSE) {
    console.log('[ai-job]', JSON.stringify(event));
  }
}

function resolveJobItem(job: AiJob): NewsInternal | undefined {
  return recent.find(x => x.id === job.id && x.feedUrl === job.feedUrl)
    || recent.find(x => x.id === job.id);
}

function dropJob(job: AiJob, reason: string) {
  pushDeadLetter(job, reason);
  recordAiJobEvent(job, 'drop', { reason });
  const it = resolveJobItem(job);
  if (it) {
    broadcastNewsUpdate(it);
  }
}

function purgeExpiredQueuedJobs() {
  if (!aiQueue.length) return;
  const nowMs = Date.now();
  for (let i = aiQueue.length - 1; i >= 0; i -= 1) {
    const job = aiQueue[i];
    if (!isJobExpired(job, nowMs)) continue;
    aiQueue.splice(i, 1);
    dropJob(job, 'ttl_expired_queue');
  }
}

function jobPriority(j: AiJob): number {
  if (j.manual) {
    if (j.kind === 'summary') return 0;
    if (j.kind === 'title_translate') return 1;
    if (j.kind === 'research') return 2;
    if (j.kind === 'mood') return 6;
    return 7; // news_type
  }
  if (j.kind === 'summary') return 3;
  if (j.kind === 'title_translate') return 4;
  if (j.kind === 'research') return 5;
  if (j.kind === 'mood') return 6;
  return 7; // news_type
}

function dequeueNextJob(): AiJob | undefined {
  while (aiQueue.length) {
    let bestIndex = 0;
    let bestPriority = jobPriority(aiQueue[0]);
    for (let i = 1; i < aiQueue.length; i += 1) {
      const priority = jobPriority(aiQueue[i]);
      if (priority < bestPriority) {
        bestPriority = priority;
        bestIndex = i;
        if (bestPriority === 0) break;
      }
    }
    const next = aiQueue.splice(bestIndex, 1)[0];
    if (!next) return undefined;
    if (isJobExpired(next)) {
      dropJob(next, 'ttl_expired_dequeue');
      continue;
    }
    return next;
  }
  return undefined;
}

function broadcastAiJobError(job: AiJob, item: NewsInternal | undefined, error: unknown) {
  const message = (error as Error)?.message || String(error || 'unknown error');
  const dedupeKey = `${job.kind}:${job.feedUrl}:${job.id}:${message}`;
  const now = Date.now();
  const last = lastAiJobErrorAtMs.get(dedupeKey) || 0;
  if (now - last < AI_ERROR_TOAST_COOLDOWN_MS) return;
  lastAiJobErrorAtMs.set(dedupeKey, now);

  const label = item?.source || item?.feedUrl || job.feedUrl || 'feed';
  const payload = JSON.stringify({
    type: 'error',
    message: `AI ${job.kind} failed for ${label}: ${message}`
  });
  wss.clients.forEach((c: WebSocket) => {
    if (c.readyState === WebSocket.OPEN) c.send(payload);
  });
}

function isTimeoutError(error: unknown): boolean {
  const message = (error as Error)?.message || String(error || '');
  return message.toLowerCase().includes('timeout');
}

function enqueueJob(job: AiJobInput) {
  if (!aiEnabled || !aiAvailable) return;
  const nextJob: AiJob = { ...job, enqueuedAtMs: Date.now() };
  if (hasExceededTimeoutRetryLimit(nextJob)) {
    recordAiJobEvent(nextJob, 'skip', {
      reason: `timeout_retry_limit_reached:${timeoutAttemptsFor(nextJob)}`
    });
    return;
  }
  const k = jobKey(nextJob);
  if (aiInFlight.has(k)) {
    recordAiJobEvent(nextJob, 'skip', { reason: 'duplicate_inflight' });
    return;
  }
  if (aiQueue.some(x => jobKey(x) === k)) {
    recordAiJobEvent(nextJob, 'skip', { reason: 'duplicate_queue' });
    return;
  }

  if (aiQueue.length >= AI_QUEUE_MAX) {
    // Protect higher-priority work by dropping lowest-priority queued work first.
    const pickDropIndex = (manualFlag: boolean): number => {
      let dropIdx = -1;
      for (let i = 0; i < aiQueue.length; i += 1) {
        const candidate = aiQueue[i];
        if (!!candidate.manual !== manualFlag) continue;
        if (dropIdx < 0) {
          dropIdx = i;
          continue;
        }
        const current = aiQueue[dropIdx];
        const candidatePriority = jobPriority(candidate);
        const currentPriority = jobPriority(current);
        if (candidatePriority > currentPriority) {
          dropIdx = i;
          continue;
        }
        if (candidatePriority === currentPriority && candidate.enqueuedAtMs < current.enqueuedAtMs) {
          dropIdx = i;
        }
      }
      return dropIdx;
    };

    const nonManualIdx = pickDropIndex(false);
    const manualIdx = pickDropIndex(true);
    const idx = nonManualIdx >= 0 ? nonManualIdx : manualIdx;
    const dropped = idx >= 0 ? aiQueue.splice(idx, 1)[0] : aiQueue.shift();
    if (dropped) dropJob(dropped, 'queue_overflow');
  }

  aiQueue.push(nextJob);
  recordAiJobEvent(nextJob, 'enqueue');
}

function enqueueTitleTranslateBackfill(options?: {
  feedUrl?: string;
  max?: number;
  manual?: boolean;
}): number {
  if (!aiEnabled || !aiAvailable) return 0;
  if (activeModel('summary') === 'none') return 0;

  const targetFeedUrl = String(options?.feedUrl || '').trim();
  const max = Math.max(1, Math.min(2_000, Math.floor(options?.max ?? 320)));
  const manual = !!options?.manual;
  if (!manual && hasSummaryBacklog()) return 0;
  const list = recent.slice().sort((a, b) => b.publishedMs - a.publishedMs);
  let done = 0;

  for (const it of list) {
    if (done >= max) break;
    if (targetFeedUrl && !eligibleForFeed(it, targetFeedUrl)) continue;
    if (hiddenIds.has(it.id)) continue;
    if (!isTranslationEnabledForFeed(it.feedUrl)) continue;
    if (!needsTitleTranslation(it.title, it.titleBg, it.titleEn)) continue;

    const itemBudget = feedSettings.get(it.feedUrl)?.budget || 'standard';
    if (!manual && itemBudget !== 'high') continue;
    if (hasTitleTranslateJobQueuedOrRunning(it.id, it.feedUrl)) continue;

    enqueueJob({ kind: 'title_translate', id: it.id, feedUrl: it.feedUrl, manual });
    done++;
  }

  return done;
}

function enqueueSummaryRecoveryPass(nowMs = Date.now()): number {
  if (!aiEnabled || !aiAvailable) return 0;
  if (activeModel('summary') === 'none') return 0;
  if (nowMs - lastSummaryRecoveryAtMs < AI_SUMMARY_RECOVERY_INTERVAL_MS) return 0;
  lastSummaryRecoveryAtMs = nowMs;

  // Keep map bounded over long runtimes.
  if (summaryRetryCooldownUntilMs.size > 10_000) {
    const keys = Array.from(summaryRetryCooldownUntilMs.keys());
    for (const key of keys) {
      const until = summaryRetryCooldownUntilMs.get(key) || 0;
      if (until <= nowMs) summaryRetryCooldownUntilMs.delete(key);
    }
  }

  let queued = 0;
  const list = recent.slice().sort((a, b) => b.publishedMs - a.publishedMs);
  for (const it of list) {
    if (queued >= AI_SUMMARY_RECOVERY_BATCH) break;
    if (!it?.id || !it.feedUrl) continue;
    if (hiddenIds.has(it.id)) continue;
    if (!isAutoSummaryEligible(it, nowMs)) continue;
    if (it.summary && it.summary.trim()) {
      summaryRetryCooldownUntilMs.delete(summaryItemKey(it.id, it.feedUrl));
      continue;
    }

    const key = summaryItemKey(it.id, it.feedUrl);
    const cooldownUntil = summaryRetryCooldownUntilMs.get(key) || 0;
    if (cooldownUntil > nowMs) continue;
    if (hasSummaryJobQueuedOrRunning(it.id, it.feedUrl)) continue;

    enqueueJob({ kind: 'summary', id: it.id, feedUrl: it.feedUrl });
    if (hasSummaryJobQueuedOrRunning(it.id, it.feedUrl)) {
      queued += 1;
      broadcastNewsUpdate(it);
    }
  }
  return queued;
}

function enqueueTitleTranslateRecoveryPass(nowMs = Date.now()): number {
  if (!aiEnabled || !aiAvailable) return 0;
  if (activeModel('summary') === 'none') return 0;
  if (nowMs - lastTitleRecoveryAtMs < AI_TITLE_RECOVERY_INTERVAL_MS) return 0;
  lastTitleRecoveryAtMs = nowMs;
  if (hasSummaryBacklog()) return 0;

  let queued = 0;
  const list = recent.slice().sort((a, b) => b.publishedMs - a.publishedMs);
  for (const it of list) {
    if (queued >= AI_TITLE_RECOVERY_BATCH) break;
    if (!it?.id || !it.feedUrl) continue;
    if (hiddenIds.has(it.id)) continue;
    if (!needsTitleTranslation(it.title, it.titleBg, it.titleEn)) continue;
    const budget = feedSettings.get(it.feedUrl)?.budget || 'standard';
    if (budget !== 'high') continue;
    if (hasTitleTranslateJobQueuedOrRunning(it.id, it.feedUrl)) continue;

    enqueueJob({ kind: 'title_translate', id: it.id, feedUrl: it.feedUrl });
    if (hasTitleTranslateJobQueuedOrRunning(it.id, it.feedUrl)) {
      queued += 1;
      broadcastNewsUpdate(it);
    }
  }
  return queued;
}

function enqueueResearchRecoveryPass(nowMs = Date.now()): number {
  if (!aiEnabled || !aiAvailable) return 0;
  if (activeModel('research') === 'none') return 0;
  if (nowMs - lastResearchRecoveryAtMs < AI_RESEARCH_RECOVERY_INTERVAL_MS) return 0;
  lastResearchRecoveryAtMs = nowMs;

  let queued = 0;
  const list = recent.slice().sort((a, b) => b.publishedMs - a.publishedMs);
  for (const it of list) {
    if (queued >= AI_RESEARCH_RECOVERY_BATCH) break;
    if (!it?.id || !it.feedUrl) continue;
    if (hiddenIds.has(it.id)) continue;
    if (!shouldHaveResearch(it)) continue;
    if (it.research && it.research.trim()) continue;
    const budget = feedSettings.get(it.feedUrl)?.budget || 'standard';
    if (!budgetAllowsAutoResearch(budget)) continue;
    if (hasResearchJobQueuedOrRunning(it.id, it.feedUrl)) continue;

    enqueueJob({ kind: 'research', id: it.id, feedUrl: it.feedUrl });
    if (hasResearchJobQueuedOrRunning(it.id, it.feedUrl)) {
      queued += 1;
      broadcastNewsUpdate(it);
    }
  }
  return queued;
}

async function runOneJob(job: AiJob) {
  const startedAtMs = Date.now();
  const duration = () => Math.max(0, Date.now() - startedAtMs);
  const k = jobKey(job);
  aiInFlight.add(k);
  recordAiJobEvent(job, 'start');
  let itemForError: NewsInternal | undefined;
  let didBroadcastUpdate = false;
  let outcomeRecorded = false;
  const markSkip = (reason: string) => {
    outcomeRecorded = true;
    recordAiJobEvent(job, 'skip', { reason, durationMs: duration() });
  };
  const markSuccess = (reason: string) => {
    outcomeRecorded = true;
    recordAiJobEvent(job, 'success', { reason, durationMs: duration() });
  };

  try {
    if (isJobExpired(job)) {
      dropJob(job, 'ttl_expired_before_run');
      outcomeRecorded = true;
      return;
    }
    if (hasExceededTimeoutRetryLimit(job)) {
      markSkip(`timeout_retry_limit_reached:${timeoutAttemptsFor(job)}`);
      return;
    }

    const it = resolveJobItem(job);
    if (!it) {
      markSkip('item_not_found');
      return;
    }
    itemForError = it;
    if (hiddenIds.has(it.id)) {
      markSkip('hidden_item');
      return;
    }

    const s = feedSettings.get(it.feedUrl) || defaultSettingsForFeed({ url: it.feedUrl, label: it.source, kind: 'rss', intervalSec: 120 });
    const budget = s.budget || 'standard';

    if (job.kind === 'summary') {
      if (it.summary && it.summary.trim()) {
        markSkip('summary_exists');
        return;
      }
      if (activeModel('summary') === 'none') {
        markSkip('summary_model_disabled');
        return;
      }

      const ctx = it.__ctx || '';
      let linkText = it.__linkText || '';
      if (!hasUsefulSummaryContext(it.title, ctx) && !hasUsefulSummaryContext(it.title, linkText) && it.link) {
        linkText = await fetchArticleText(it.link, AI_SUMMARY_ARTICLE_MAX_CHARS);
        if (linkText) it.__linkText = linkText;
      }
      recordSummaryDebugEvent({
        atMs: Date.now(),
        isoTime: new Date().toISOString(),
        itemId: it.id,
        feedUrl: it.feedUrl,
        source: it.source,
        title: it.title,
        provider: aiProvider,
        model: activeModel('summary'),
        status: 'start',
        promptPreview: previewText(`${it.source} | ${it.title}`)
      });
      const text = await withTimeout(
        oneLineSummary(it.id, it.feedUrl, it.title, it.source, ctx, linkText, budget),
        AI_SUMMARY_TIMEOUT_MS,
        `summary:${it.id}`
      );
      if (text) {
        it.summary = text;
        clearTimeoutAttempts(job);
        refreshDerivedDataForItem(it);
        await upsertPersistedNewsItem(it);
        broadcastNewsUpdate(it);
        scheduleDiscordPost(it);
        didBroadcastUpdate = true;
        summaryRetryCooldownUntilMs.delete(summaryItemKey(it.id, it.feedUrl));
        markDirty();
        markSuccess('summary_generated');
      } else {
        summaryRetryCooldownUntilMs.set(
          summaryItemKey(it.id, it.feedUrl),
          Date.now() + AI_SUMMARY_RETRY_COOLDOWN_MS
        );
        markSkip('summary_empty');
      }
      return;
    }

    if (job.kind === 'title_translate') {
      if (!job.manual && !job.viewport && budget !== 'high') {
        markSkip('budget_not_high');
        return;
      }
      if (activeModel('summary') === 'none') {
        markSkip('summary_model_disabled');
        return;
      }
      if (!isTranslationEnabledForFeed(it.feedUrl)) {
        markSkip('translation_disabled_for_feed');
        return;
      }
      if (!needsTitleTranslation(it.title, it.titleBg, it.titleEn)) {
        markSkip('already_translated_or_not_needed');
        return;
      }

      const translated = await withTimeout(
        translateTitleBilingual(it.title, it.source, budget),
        AI_TITLE_TRANSLATE_TIMEOUT_MS,
        `title_translate:${it.id}`
      );
      if (translated) {
        it.titleBg = translated.bg;
        it.titleEn = translated.en;
        clearTimeoutAttempts(job);
        refreshDerivedDataForItem(it);
        await upsertPersistedNewsItem(it);
        broadcastNewsUpdate(it);
        scheduleDiscordPost(it);
        didBroadcastUpdate = true;
        markDirty();
        markSuccess('title_translated');
      } else {
        markSkip('title_translate_empty_or_invalid');
      }
      return;
    }

    if (job.kind === 'mood') {
      if (it.mood) {
        markSkip('mood_exists');
        return;
      }
      if (activeModel('research') === 'none') {
        markSkip('research_model_disabled');
        return;
      }
      const mood = await withTimeout(
        classifyMoodForItem(
          it.title,
          it.source,
          it.__ctx || '',
          it.summary || '',
          it.research || '',
          budget
        ),
        AI_CLASSIFY_TIMEOUT_MS,
        `mood:${it.id}`
      );
      if (mood) {
        it.mood = mood;
        clearTimeoutAttempts(job);
        refreshDerivedDataForItem(it);
        await upsertPersistedNewsItem(it);
        broadcastNewsUpdate(it);
        scheduleDiscordPost(it);
        didBroadcastUpdate = true;
        markDirty();
        markSuccess('mood_classified');
      } else {
        markSkip('mood_empty');
      }
      return;
    }

    if (job.kind === 'news_type') {
      if (it.newsType) {
        markSkip('news_type_exists');
        return;
      }
      if (activeModel('research') === 'none') {
        markSkip('research_model_disabled');
        return;
      }
      const newsType = await withTimeout(
        classifyNewsTypeForItem(
          it.title,
          it.source,
          it.__ctx || '',
          it.summary || '',
          it.research || '',
          budget
        ),
        AI_CLASSIFY_TIMEOUT_MS,
        `news_type:${it.id}`
      );
      if (newsType) {
        it.newsType = newsType;
        clearTimeoutAttempts(job);
        refreshDerivedDataForItem(it);
        await upsertPersistedNewsItem(it);
        broadcastNewsUpdate(it);
        scheduleDiscordPost(it);
        didBroadcastUpdate = true;
        markDirty();
        markSuccess('news_type_classified');
      } else {
        markSkip('news_type_empty');
      }
      return;
    }

    if (job.kind === 'research') {
      if (it.research && it.research.trim() && !job.manual) {
        markSkip('research_exists');
        return;
      }
      if (activeModel('research') === 'none') {
        markSkip('research_model_disabled');
        return;
      }

      // If budget is low and not manual -> skip auto research
      if (!job.manual && !budgetAllowsAutoResearch(budget)) {
        markSkip('budget_low_auto_research_blocked');
        return;
      }

      const ctx = it.__ctx || '';

      // Optional article fetch for real research (bounded)
      let linkText = it.__linkText || '';
      if (!linkText) {
        try {
          linkText = await fetchArticleText(it.link, AI_RESEARCH_ARTICLE_MAX_CHARS);
        } catch {
          linkText = '';
        }
        it.__linkText = linkText;
      }

      const timeoutMs = job.manual ? AI_RESEARCH_TIMEOUT_MANUAL_MS : AI_RESEARCH_TIMEOUT_MS;
      let text: string | undefined;
      try {
        text = await withTimeout(
          oneItemResearch(it.title, it.source, it.link, ctx, linkText, budget),
          timeoutMs,
          `research:${it.id}`
        );
      } catch (err) {
        if (!isTimeoutError(err)) throw err;
        text = await withTimeout(
          oneItemResearchFallback(it.title, it.source, it.link, ctx, budget),
          timeoutMs,
          `research_fallback:${it.id}`
        );
      }
      if (text) {
        it.research = text;
        clearTimeoutAttempts(job);
        refreshDerivedDataForItem(it);
        await upsertPersistedNewsItem(it);
        broadcastNewsUpdate(it);
        scheduleDiscordPost(it);
        didBroadcastUpdate = true;
        markDirty();
        markSuccess('research_generated');
      } else {
        markSkip('research_empty');
      }
      return;
    }
  } catch (err) {
    const message = (err as Error)?.message || String(err);
    const classifyJob = job.kind === 'mood' || job.kind === 'news_type';
    const timedOut = isTimeoutError(err);
    if (timedOut) {
      const attempts = recordTimeoutAttempt(job);
      if (job.kind === 'summary') {
        summaryRetryCooldownUntilMs.set(summaryItemKey(job.id, job.feedUrl), Date.now() + AI_SUMMARY_RETRY_COOLDOWN_MS);
      }
      if (!outcomeRecorded) {
        recordAiJobEvent(job, 'skip', {
          reason: attempts >= AI_TIMEOUT_RETRY_LIMIT
            ? `timeout_retry_limit_reached:${attempts}`
            : `timeout_retry:${attempts}`,
          durationMs: duration()
        });
        outcomeRecorded = true;
      }
      if (!classifyJob) {
        console.warn(`AI job timed out (${job.kind}:${job.id}) attempt ${attempts}/${AI_TIMEOUT_RETRY_LIMIT}`);
      }
      return;
    }

    if (classifyJob) {
      console.warn(`AI classify job skipped (${job.kind}:${job.id})`, message);
      if (!outcomeRecorded) {
        recordAiJobEvent(job, 'skip', { reason: `classify_error:${message}`, durationMs: duration() });
        outcomeRecorded = true;
      }
      return;
    }

    console.error(`AI job failed (${job.kind}:${job.id})`, message);
    if (!outcomeRecorded) {
      recordAiJobEvent(job, 'error', { reason: message, durationMs: duration() });
      outcomeRecorded = true;
    }
    broadcastAiJobError(job, itemForError, err);
  } finally {
    aiInFlight.delete(k);
    if (!didBroadcastUpdate && itemForError && !hiddenIds.has(itemForError.id)) {
      // Push final pending=false state when jobs finish without producing output.
      if (job.kind === 'summary' || job.kind === 'research' || job.kind === 'title_translate') {
        broadcastNewsUpdate(itemForError);
      }
    }
  }
}

async function tickAiQueue() {
  if (!aiEnabled || !aiAvailable) return;
  purgeExpiredQueuedJobs();
  if (!aiQueue.length) return;

  while (aiInFlight.size < AI_MAX_CONCURRENCY && aiQueue.length) {
    const job = dequeueNextJob();
    if (!job) break;
    const k = jobKey(job);
    if (aiInFlight.has(k)) continue;

    runOneJob(job).catch(() => {}).finally(() => {});
  }
}
// -------------------------------------------------------------

// ---------------- Robust feed fetch (ETag, LM, retry, breaker) ----------------
function sleep(ms: number) {
  return new Promise<void>(r => setTimeout(r, ms));
}

function jitter(ms: number) {
  const j = Math.floor(Math.random() * Math.min(450, Math.max(50, ms * 0.2)));
  return ms + j;
}

function isSocial(fi: FeedInfo) {
  return fi.kind === 'reddit' || fi.kind === 'youtube';
}

function defaultIntervalForKind(kind: FeedKind) {
  if (kind === 'reddit') return 45;
  if (kind === 'youtube') return 120;
  return 120;
}

function shouldUseRedditHeaders(kind: FeedKind) {
  return kind === 'reddit';
}

const REDDIT_MIN_INTERVAL_SEC = 180;
const RATE_LIMIT_BASE_COOLDOWN_MS = 15 * 60 * 1000;
const RATE_LIMIT_MAX_COOLDOWN_MS = 6 * 60 * 60 * 1000;
let redditFetchChain: Promise<void> = Promise.resolve();

function isRedditFeed(fi: FeedInfo): boolean {
  return shouldUseRedditHeaders(fi.kind);
}

function parseRetryAfterMs(raw: string | null): number | null {
  const value = String(raw || '').trim();
  if (!value) return null;
  const seconds = Number(value);
  if (Number.isFinite(seconds) && seconds >= 0) return Math.floor(seconds * 1000);
  const when = Date.parse(value);
  if (!Number.isFinite(when)) return null;
  return Math.max(0, when - Date.now());
}

function rateLimitCooldownMs(failCount: number, retryAfterMs?: number): number {
  const retryAfter = Number.isFinite(retryAfterMs as number) && (retryAfterMs as number) > 0
    ? (retryAfterMs as number)
    : 0;
  if (retryAfter > 0) {
    return Math.min(RATE_LIMIT_MAX_COOLDOWN_MS, Math.max(RATE_LIMIT_BASE_COOLDOWN_MS, retryAfter));
  }
  const scale = Math.min(6, Math.max(1, failCount));
  return Math.min(RATE_LIMIT_MAX_COOLDOWN_MS, RATE_LIMIT_BASE_COOLDOWN_MS * scale);
}

async function runRedditFetchExclusive<T>(task: () => Promise<T>): Promise<T> {
  const prev = redditFetchChain;
  let release!: () => void;
  redditFetchChain = new Promise<void>(resolve => {
    release = resolve;
  });
  await prev.catch(() => {});
  try {
    return await task();
  } finally {
    release();
  }
}

function shouldUseIgnHeaders(url: string) {
  try {
    const parsed = new URL(url);
    const host = parsed.hostname.replace(/^www\./i, '').toLowerCase();
    return host === 'ign.com' && parsed.pathname.includes('/rss/');
  } catch {
    return false;
  }
}

function shouldUseBrowserFeedHeaders(url: string) {
  try {
    const parsed = new URL(url);
    const host = parsed.hostname.replace(/^www\./i, '').toLowerCase();
    return host === 'ign.com' || host === 'capital.bg';
  } catch {
    return false;
  }
}

function sanitizeFeedXml(xml: string): string {
  return String(xml || '')
    .replace(/^\uFEFF/, '')
    .replace(/&(?!#\d+;|#x[a-fA-F0-9]+;|[a-zA-Z][a-zA-Z0-9]+;)/g, '&amp;');
}

async function fetchFeedXml(fi: FeedInfo): Promise<{ xml: string | null; notModified: boolean }> {
  ensureFeedRuntime(fi.url);
  const rt = feedRuntime.get(fi.url)!;

  const now = Date.now();
  if (rt.disabledUntilMs && now < rt.disabledUntilMs) {
    return { xml: null, notModified: true };
  }

  const headers: Record<string, string> = {
    'User-Agent': 'live-news-ai/1.0 (+rss)',
    'Accept': 'application/rss+xml, application/xml, text/xml, */*'
  };

  if (isRedditFeed(fi)) {
    headers['User-Agent'] = 'live-news-ai/1.0 (+https://github.com/donetian-petkov/ai_news; reddit rss)';
    headers['Accept'] = 'application/rss+xml, application/xml;q=0.9, text/xml;q=0.8, */*;q=0.1';
  }

  if (shouldUseBrowserFeedHeaders(fi.url)) {
    headers['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
    headers['Accept'] = 'application/rss+xml, application/xml;q=0.9, text/xml;q=0.8, text/html;q=0.7, */*;q=0.1';
    headers['Accept-Language'] = 'bg-BG,bg;q=0.9,en-US;q=0.8,en;q=0.7';
    headers['Referer'] = `https://${new URL(fi.url).hostname}/`;
  }

  if (rt.etag) headers['If-None-Match'] = rt.etag;
  if (rt.lastModified) headers['If-Modified-Since'] = rt.lastModified;

  const timeoutMs = 9000;

  const maxAttempts = isRedditFeed(fi) ? 2 : 3;
  let attempt = 0;
  let backoff = isRedditFeed(fi) ? 15_000 : 800;

  while (attempt < maxAttempts) {
    attempt++;
    try {
      const res = await fetchWithTimeout(fi.url, { headers }, timeoutMs);

      if (res.status === 304) {
        rt.failCount = 0;
        rt.lastFetchMs = now;
        return { xml: null, notModified: true };
      }

      if (res.status === 429) {
        rt.failCount += 1;
        const retryAfterMs = parseRetryAfterMs(res.headers.get('retry-after'));
        const cooldownMs = rateLimitCooldownMs(rt.failCount, retryAfterMs || undefined);
        rt.disabledUntilMs = now + cooldownMs;
        rt.lastFetchMs = now;
        const message = 'HTTP 429';
        console.warn(
          `[feed-fetch] rate limited for ${fi.url}: ${message} ` +
          `(failCount=${rt.failCount}, cooldown=${Math.round(cooldownMs / 1000)}s${retryAfterMs ? `, retryAfter=${Math.round(retryAfterMs / 1000)}s` : ''})`
        );
        void appendErrorLog({
          category: 'feed-fetch',
          feedUrl: fi.url,
          feedLabel: labelForFeed(fi),
          attempt,
          maxAttempts,
          failCount: rt.failCount,
          disabledUntilMs: rt.disabledUntilMs,
          message,
          details: {
            kind: fi.kind,
            retrying: false,
            userAgent: headers['User-Agent'],
            retryAfterMs,
            cooldownMs
          }
        });
        throw new Error(message);
      }

      if (res.status === 401 || res.status === 403) {
        rt.failCount += 1;
        const cooldownMs = 6 * 60 * 60 * 1000;
        rt.disabledUntilMs = now + cooldownMs;
        rt.lastFetchMs = now;
        const message = `HTTP ${res.status}`;
        console.warn(
          `[feed-fetch] access denied for ${fi.url}: ${message} ` +
          `(cooldown=${Math.round(cooldownMs / 1000)}s)`
        );
        void appendErrorLog({
          category: 'feed-fetch',
          feedUrl: fi.url,
          feedLabel: labelForFeed(fi),
          attempt,
          maxAttempts,
          failCount: rt.failCount,
          disabledUntilMs: rt.disabledUntilMs,
          message,
          details: {
            kind: fi.kind,
            retrying: false,
            userAgent: headers['User-Agent'],
            cooldownMs
          }
        });
        throw new Error(message);
      }

      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }

      const etag = res.headers.get('etag') || undefined;
      const lm = res.headers.get('last-modified') || undefined;
      if (etag) rt.etag = etag;
      if (lm) rt.lastModified = lm;

      const xml = await res.text();
      rt.failCount = 0;
      rt.lastFetchMs = now;

      return { xml, notModified: false };
    } catch (e) {
      if (e instanceof Error && (e.message === 'HTTP 429' || e.message === 'HTTP 401' || e.message === 'HTTP 403')) {
        break;
      }
      rt.failCount += 1;
      const message = e instanceof Error ? e.message : String(e);
      const waitMs = rt.failCount >= 6 ? 10 * 60 * 1000 : rt.failCount >= 3 ? 2 * 60 * 1000 : 0;
      console.warn(
        `[feed-fetch] attempt ${attempt}/${maxAttempts} failed for ${fi.url}: ${message} ` +
        `(failCount=${rt.failCount}${waitMs ? `, breaker=${Math.round(waitMs / 1000)}s` : ''})`
      );
      void appendErrorLog({
        category: 'feed-fetch',
        feedUrl: fi.url,
        feedLabel: labelForFeed(fi),
        attempt,
        maxAttempts,
        failCount: rt.failCount,
        disabledUntilMs: waitMs ? now + waitMs : undefined,
        message,
        details: {
          kind: fi.kind,
          retrying: attempt < maxAttempts,
          userAgent: headers['User-Agent']
        }
      });

      // circuit breaker: after 6 fails, pause longer
      if (rt.failCount >= 6) {
        rt.disabledUntilMs = now + 10 * 60 * 1000; // 10 min
      } else if (rt.failCount >= 3) {
        rt.disabledUntilMs = now + 2 * 60 * 1000; // 2 min
      }

      if (attempt >= maxAttempts) {
        console.error(
          `[feed-fetch] exhausted retries for ${fi.url}: ${message} ` +
          `(failCount=${rt.failCount}, disabledUntilMs=${rt.disabledUntilMs ?? 0})`
        );
        throw e;
      }

      if (isRedditFeed(fi)) {
        break;
      }

      await sleep(jitter(backoff));
      backoff = Math.min(6000, backoff * 2);
    }
  }

  return { xml: null, notModified: true };
}
// ---------------------------------------------------------------------------

async function processFeed(fi: FeedInfo) {
  ensureFeedSettings(fi);
  ensureFeedRuntime(fi.url);

  const s = feedSettings.get(fi.url)!;
  const rt = feedRuntime.get(fi.url)!;

  // compute interval (per-feed override)
  const baseIntervalSec = Math.max(20, Math.min(3600, Number(s.intervalSec || fi.intervalSec || defaultIntervalForKind(fi.kind))));
  const intervalSec = isRedditFeed(fi) ? Math.max(REDDIT_MIN_INTERVAL_SEC, baseIntervalSec) : baseIntervalSec;
  const now = Date.now();

  if (rt.nextPollAtMs && now < rt.nextPollAtMs) return;
  if (rt.disabledUntilMs && now < rt.disabledUntilMs) {
    rt.nextPollAtMs = now + intervalSec * 1000;
    return;
  }

  rt.nextPollAtMs = now + intervalSec * 1000;

  try {
    const { xml, notModified } = isRedditFeed(fi)
      ? await runRedditFetchExclusive(() => fetchFeedXml(fi))
      : await fetchFeedXml(fi);
    if (notModified || !xml) return;
    if (!xml.trim()) {
      console.warn(`[feed-fetch] empty body for ${fi.url}`);
      void appendErrorLog({
        category: 'feed-empty',
        feedUrl: fi.url,
        feedLabel: labelForFeed(fi),
        message: 'Feed returned an empty body',
        details: {
          kind: fi.kind,
          stage: 'processFeed'
        }
      });
      return;
    }

    let feed;
    try {
      feed = await parser.parseString(xml);
    } catch (parseError) {
      const repairedXml = sanitizeFeedXml(xml);
      if (repairedXml === xml) throw parseError;
      console.warn(`[feed-parse] repairing malformed xml for ${fi.url}: ${(parseError as Error).message}`);
      feed = await parser.parseString(repairedXml);
    }
    if (!feed.items.length) {
      console.warn(`[feed-fetch] zero items parsed for ${fi.url}`);
      void appendErrorLog({
        category: 'feed-empty',
        feedUrl: fi.url,
        feedLabel: labelForFeed(fi),
        message: 'Feed parsed successfully but contained no items',
        details: {
          kind: fi.kind,
          stage: 'processFeed',
          title: feed.title || undefined
        }
      });
      return;
    }

    // improve label from feed title if missing
    if (feed.title && (!fi.label || fi.label === fi.url)) {
      fi.label = feed.title;
      s.label = feed.title;
      markDirty();
    }

    for (const item of feed.items) {
      const id = String(item.guid ?? item.link ?? item.title ?? '');
      const link = String(item.link ?? item.guid ?? '#');
      const seenKey = newsRecordKey(fi.url, id);

      if (!id || seen.has(seenKey)) continue;
      seen.add(seenKey);

      if (seen.size > MAX_SEEN_IDS) {
        seen = new Set(Array.from(seen).slice(-SEEN_TRIM_TO));
      }

      const { published, publishedMs } = toPublishedMs(item);

      const title = item.title ?? '(no title)';
      const source = feed.title ?? labelForFeed(fi) ?? 'unknown';
      const coverUrl = extractCoverUrlFromItem(item, fi, link);
      const reusable = findReusableNewsItem(fi.url, source, title, link, publishedMs);
      if (reusable) {
        const changed = mergeReusableNewsItem(reusable, {
          title,
          link,
          published,
          publishedMs,
          source,
          __ctx: pickRssContextCombined(item, 1500),
          coverUrl
        });
        if (changed) {
          refreshDerivedDataForItem(reusable);
          await upsertPersistedNewsItem(reusable);
          broadcastNewsUpdate(reusable);
          markDirty();
        }
        continue;
      }

      // match (+ embedding if AI)
      let isMatch = false;
      let matchScore = 0;
      let titleVec: number[] | null = null;

      try {
        const m = await hybridMatch(title);
        isMatch = m.isMatch;
        matchScore = m.score;
        titleVec = m.vec;
      } catch {
        const hit = substringHit(title);
        isMatch = hit;
        matchScore = hit ? 1 : 0;
        titleVec = null;
      }

      // global AI dedupe (across feeds)
      if (aiEnabled && titleVec) {
        if (isDuplicate(titleVec)) continue;
        addToDedupeWindow(titleVec, publishedMs);
      }

      // Filtered-only AI dedupe
      let filteredOk = isMatch;
      if (filteredOk && aiEnabled && FILTERED_AI_DEDUPE && titleVec) {
        if (isFilteredDuplicate(titleVec)) filteredOk = false;
        else addToFilteredDedupe(titleVec);
      }
      const ctx = pickRssContextCombined(item, 1500);

      const pkt: NewsInternal = {
        type: 'news',
        id,
        title,
        titleBg: undefined,
        titleEn: undefined,
        coverUrl,
        link,
        source,
        published,
        publishedMs,
        feedUrl: fi.url,
        isMatch,
        matchScore,
        filteredOk,
        summary: undefined,
        research: undefined,
        mood: undefined,
        newsType: undefined,
        __ctx: ctx
      };

      recent.push(pkt);
      if (recent.length > MAX_RECENT_ITEMS) recent.shift();
      refreshDerivedDataForItem(pkt);
      await upsertPersistedNewsItem(pkt);

      broadcastNewsUpdate(pkt);
      scheduleDiscordPost(pkt);
    }

    markDirty();
  } catch (err) {
    if (err instanceof Error && err.message === 'HTTP 429') {
      return;
    }
    console.error(`✗ ${fi.url}`, (err as Error).message);
    void appendErrorLog({
      category: 'feed-process',
      feedUrl: fi.url,
      feedLabel: labelForFeed(fi),
      message: (err as Error).message,
      details: {
        kind: fi.kind,
        stage: 'processFeed'
      }
    });
    broadcastFeedError(fi, (err as Error).message);
    markDirty();
  }
}

// ---------------- Scheduler (per-feed interval) ----------------
let schedulerTimer: NodeJS.Timeout | null = null;

async function schedulerTick() {
  // run AI queue
  try { await tickAiQueue(); } catch {}

  const now = Date.now();
  await prunePersistedNewsArchive(now);
  if (isNewsAccessLocked()) return;
  for (const fi of feedsList) {
    // skip filtered pseudo-feed
    if (fi.url === FILTERED_FEED_URL) continue;

    ensureFeedSettings(fi);
    ensureFeedRuntime(fi.url);

    const rt = feedRuntime.get(fi.url)!;
    const s = feedSettings.get(fi.url)!;

    const intervalSec = Math.max(20, Math.min(3600, Number(s.intervalSec || fi.intervalSec)));
    if (!rt.nextPollAtMs) rt.nextPollAtMs = now + Math.floor(Math.random() * 6000);

    if (now >= rt.nextPollAtMs) {
      processFeed(fi).catch(() => {});
      // nextPollAtMs set inside processFeed()
    } else {
      // keep
    }
  }
}

function startScheduler() {
  if (schedulerTimer) clearInterval(schedulerTimer);
  schedulerTimer = setInterval(schedulerTick, 350);
}
// ---------------------------------------------------------------

// ---------------- Load persisted state ----------------
async function applyLoadedState(st: PersistedState | null) {
  if (!st || typeof st.version !== 'number' || st.version < 1 || st.version > CURRENT_STATE_VERSION) {
    await loadRecentFromDb();
    reprocessCachedItems(false, false);
    return;
  }

  if (Array.isArray(st.keywords)) {
    keywords = normalizeKeywordList(st.keywords);
  }
  if (st.aiFeatures) {
    aiFeatures = isLegacyAutoEnabledInsightFeatures(st.aiFeatures)
      ? { ...DEFAULT_AI_INSIGHT_FEATURES }
      : normalizeAiFeatureSettings(st.aiFeatures, aiFeatures);
  }
  if (typeof st.localRegion === 'string') {
    localRegion = st.localRegion.trim().slice(0, 120);
  }
  if (Array.isArray(st.trackedTopics)) {
    trackedTopics = normalizeTrimmedList(st.trackedTopics, 80);
  }
  if (typeof st.localLlmBaseUrl === 'string') {
    localLlmBaseUrl = st.localLlmBaseUrl.trim().slice(0, 500) || localLlmBaseUrl;
    refreshAiClients();
  }
  if (st.titleDisplayLanguage === 'original' || st.titleDisplayLanguage === 'bg' || st.titleDisplayLanguage === 'en') {
    titleDisplayLanguage = st.titleDisplayLanguage;
  }

  if (Array.isArray(st.feeds) && st.feeds.length) {
    feedsList = mergeLoadedFeedsWithDefaultMigrations(st.version, st.feeds);
  }

  if (st.feedSettings && typeof st.feedSettings === 'object') {
    for (const [url, s] of Object.entries(st.feedSettings)) {
      const normalizedUrl = normalizeLegacyFeedUrl(url);
      const normalizedLabel = url === LEGACY_SVOBODNA_EVROPA_FEED_URL
        ? SVOBODNA_TOCHKA_DEFAULT_FEED.label
        : (typeof s?.label === 'string' ? s.label : url);
      const feedInfo = feedsList.find(feed => feed.url === normalizedUrl) || {
        url: normalizedUrl,
        label: normalizedLabel,
        kind: s?.kind === 'reddit' || s?.kind === 'youtube' || s?.kind === 'rss' ? s.kind : 'rss',
        intervalSec: Math.max(0, Math.min(3600, Math.floor(Number(s?.intervalSec) || 120)))
      };
      const normalizedSettings = normalizeFeedSettings(s, feedInfo);
      if (url === LEGACY_SVOBODNA_EVROPA_FEED_URL) {
        normalizedSettings.label = SVOBODNA_TOCHKA_DEFAULT_FEED.label;
      }
      feedSettings.set(normalizedUrl, normalizedSettings);
    }
  }

  if (st.feedRuntime && typeof st.feedRuntime === 'object') {
    for (const [url, rt] of Object.entries(st.feedRuntime)) {
      const normalizedUrl = normalizeLegacyFeedUrl(url);
      if (url === LEGACY_CAPITAL_FEED_URL) {
        feedRuntime.set(normalizedUrl, {
          failCount: 0,
          disabledUntilMs: 0,
          nextPollAtMs: 0,
          lastFetchMs: 0
        });
        continue;
      }
      feedRuntime.set(normalizedUrl, rt);
    }
  }

  if (Array.isArray(st.hiddenIds)) {
    for (const id of st.hiddenIds) hiddenIds.add(id);
  }

  const legacyRecent = Array.isArray(st.recent)
    ? st.recent
      .filter((it): it is NewsInternal => !!it?.id && !!it?.feedUrl && !!it?.title)
      .map(it => {
        const normalizedFeedUrl = normalizeLegacyFeedUrl(it.feedUrl);
        return normalizedFeedUrl !== it.feedUrl
          ? { ...it, feedUrl: normalizedFeedUrl }
          : it;
      })
    : [];

  // ensure settings for all feeds
  for (const fi of feedsList) ensureFeedSettings(fi);

  // ensure filtered settings exist too
  if (!feedSettings.has(FILTERED_FEED_URL)) {
    feedSettings.set(FILTERED_FEED_URL, normalizeFeedSettings({
      summaryEnabled: SUMMARY_DEFAULT_FILTERED,
      researchEnabled: RESEARCH_DEFAULT_FILTERED,
      budget: 'standard',
      sortMode: 'newest',
      filters: { onlyMatches: true, onlyResearched: false, onlySummaries: false },
      intervalSec: 0,
      kind: 'rss',
      label: 'Filtered'
    }, {
      url: FILTERED_FEED_URL,
      label: 'Filtered',
      kind: 'rss',
      intervalSec: 0
    }));
  }

  if (!(await hasPersistedNewsArchive()) && legacyRecent.length) {
    legacyRecent.forEach(item => refreshDerivedDataForItem(item));
    await migrateLegacyRecentToDb(legacyRecent);
  }

  await loadRecentFromDb();
  reprocessCachedItems(false, false);
  markDirty();
}

async function loadState() {
  ensureDataDir();
  const dbState = await readStateFromDb();
  if (dbState) {
    await applyLoadedState(dbState);
    return;
  }
  const fileState = safeReadJson<PersistedState>(STATE_PATH);
  if (fileState) {
    await applyLoadedState(fileState);
    return;
  }
  await loadRecentFromDb();
  reprocessCachedItems(false, false);
}
// ------------------------------------------------------

// ensure filtered pseudo-feed exists in settings
if (!feedSettings.has(FILTERED_FEED_URL)) {
  feedSettings.set(FILTERED_FEED_URL, normalizeFeedSettings({
    summaryEnabled: SUMMARY_DEFAULT_FILTERED,
    researchEnabled: RESEARCH_DEFAULT_FILTERED,
    budget: 'standard',
    sortMode: 'newest',
    filters: { onlyMatches: true, onlyResearched: false, onlySummaries: false },
    intervalSec: 0,
    kind: 'rss',
    label: 'Filtered'
  }, {
    url: FILTERED_FEED_URL,
    label: 'Filtered',
    kind: 'rss',
    intervalSec: 0
  }));
}

// ---------------- WebSocket handling ----------------
function registerWebSocketHandlers(socketServer: WebSocketServer) {
socketServer.on('connection', (ws: WebSocket) => {
  const askAgentCountByItem = new Map<string, number>();
  const activeSelection = currentModelSelection(aiProvider);

  ws.send(JSON.stringify({
    type: 'config',
    keywords,
    newsAccessLocked: isNewsAccessLocked(),

    aiProvider,
    aiAvailable,
    aiEnabled,

    summaryLang,
    researchLang,
    titleDisplayLanguage,
    summaryModel: activeSelection.summary,
    researchModel: activeSelection.research,
    askModel: activeSelection.ask,
    availableModels: modelOptionsByProvider,
    aiFeatures,
    localRegion,
    localLlmBaseUrl,
    trackedTopics,

    matchThreshold: MATCH_THRESHOLD,
    dedupeThreshold: DEDUPE_THRESHOLD,

    filteredAiDedupe: FILTERED_AI_DEDUPE,
    filteredDedupeThreshold: FILTERED_DEDUPE_THRESHOLD,

    feeds: currentFeeds(),
    feedSettings: feedSettingsObj(),
    hiddenIds: Array.from(hiddenIds),
    ...buildAiUsagePayload()
  } satisfies Config));

  ws.on('message', async data => {
    let raw: unknown;
    try { raw = JSON.parse(String(data)); } catch { return; }

    // Handle keyword updates directly from raw payload too, so this works
    // even if a stale @ai-news/shared build is still in use at runtime.
    if (raw && typeof raw === 'object' && (raw as { type?: unknown }).type === 'set_keywords') {
      const beforeMatchCount = recent.reduce((acc, it) => acc + (it.isMatch ? 1 : 0), 0);
      keywords = parseKeywordsPayload((raw as { keywords?: unknown }).keywords);

      titleVecCache.clear();
      filteredDedupeWindow = [];
      keywordVecs = [];

      await safeInitKeywordEmbeddings(ws, 'Keyword matching');
      await refreshMatchStateForRecent();
      broadcastConfig();

      const afterMatchCount = recent.reduce((acc, it) => acc + (it.isMatch ? 1 : 0), 0);
      ws.send(JSON.stringify({
        type: 'ok',
        message: `Updated ${keywords.length} keywords. Reprocessed ${recent.length} stored news items (${beforeMatchCount} -> ${afterMatchCount} matches).`
      }));
      markDirty();
      return;
    }

    if (raw && typeof raw === 'object' && (raw as { type?: unknown }).type === 'run_title_translate_item') {
      const id = String((raw as { id?: unknown }).id || '').trim();
      const feedUrl = String((raw as { feedUrl?: unknown }).feedUrl || '').trim();
      if (!id || !feedUrl) return;
      if (!aiEnabled || !aiAvailable || activeModel('summary') === 'none') {
        ws.send(JSON.stringify({ type: 'error', message: 'Title translation is unavailable (AI disabled, key missing, or no summary model).' }));
        return;
      }

      const it = recent.find(x => x.id === id && x.feedUrl === feedUrl) || recent.find(x => x.id === id);
      if (!it) return;
      if (!isTranslationEnabledForFeed(it.feedUrl)) {
        ws.send(JSON.stringify({ type: 'error', message: 'Title translation is disabled for this column.' }));
        return;
      }
      if (!needsTitleTranslation(it.title, it.titleBg, it.titleEn)) {
        ws.send(JSON.stringify({ type: 'ok', message: 'Title translation already exists for this item.' }));
        return;
      }
      enqueueJob({ kind: 'title_translate', id: it.id, feedUrl: it.feedUrl, manual: true });
      const queued = hasTitleTranslateJobQueuedOrRunning(it.id, it.feedUrl);
      ws.send(JSON.stringify({ type: 'ok', message: queued ? 'Title translation queued.' : 'Title translation requested.' }));
      return;
    }

    if (raw && typeof raw === 'object' && (raw as { type?: unknown }).type === 'load_feed_page') {
      if (isNewsAccessLocked()) return;
      const feedUrl = String((raw as { feedUrl?: unknown }).feedUrl || '').trim();
      const limitRaw = Number((raw as { limit?: unknown }).limit);
      const limit = Number.isFinite(limitRaw) ? limitRaw : NEWS_PAGE_LIMIT_DEFAULT;
      const cursorRaw = (raw as { cursor?: unknown }).cursor;
      const cursor = cursorRaw && typeof cursorRaw === 'object'
        ? {
            beforePublishedMs: Number((cursorRaw as { beforePublishedMs?: unknown }).beforePublishedMs),
            beforeId: String((cursorRaw as { beforeId?: unknown }).beforeId || '').trim()
          }
        : undefined;
      const validCursor = cursor && Number.isFinite(cursor.beforePublishedMs) && cursor.beforeId
        ? cursor
        : undefined;
      const replace = !!(raw as { replace?: unknown }).replace;
      if (!feedUrl) return;
      try {
        const page = await readFeedPageFromDb(feedUrl, limit, validCursor);
        sendFeedPage(ws, feedUrl, page.items, page.hasMore, page.nextCursor, replace);
      } catch (error) {
        const message = (error as Error)?.message || 'Failed to load feed page.';
        console.warn(`[feed-page] failed for ${feedUrl}: ${message}`);
        ws.send(JSON.stringify({
          type: 'feed_error',
          feedUrl,
          feedLabel: feedSettings.get(feedUrl)?.label || feedUrl,
          error: message
        }));
      }
      return;
    }

    if (raw && typeof raw === 'object' && (raw as { type?: unknown }).type === 'run_title_translate_backfill') {
      if (!aiEnabled || !aiAvailable || activeModel('summary') === 'none') {
        ws.send(JSON.stringify({ type: 'error', message: 'Title translation backfill is unavailable (AI disabled, key missing, or no summary model).' }));
        return;
      }
      const feedUrl = String((raw as { feedUrl?: unknown }).feedUrl || '').trim();
      const maxRaw = Number((raw as { max?: unknown }).max);
      const max = Number.isFinite(maxRaw) ? Math.max(1, Math.min(2_000, Math.floor(maxRaw))) : 500;
      const done = enqueueTitleTranslateBackfill({
        feedUrl: feedUrl || undefined,
        max,
        manual: true
      });
      ws.send(JSON.stringify({ type: 'ok', message: `Queued ${done} title translations.` }));
      return;
    }

    const parsed = clientMsgSchema.safeParse(raw);
    if (!parsed.success) return;
    const msg: ClientMsg = parsed.data;

    if (msg.type === 'toggle_ai') {
      const desired = !!msg.enabled;
      aiEnabled = desired && aiAvailable;

      // reset AI-dependent caches/windows
      titleVecCache.clear();
      dedupeWindow = [];
      filteredDedupeWindow = [];

      aiQueue.length = 0;
      aiInFlight.clear();

      await safeInitKeywordEmbeddings(ws, 'AI keyword matching');
      broadcastConfig();
      markDirty();
      return;
    }

    if (msg.type === 'set_ai_provider') {
      const wasLocked = isNewsAccessLocked();
      const provider = msg.provider;
      const nextKey = typeof msg.apiKey === 'string' ? msg.apiKey.trim() : '';
      if (provider !== 'local' && typeof msg.apiKey === 'string' && !nextKey) {
        ws.send(JSON.stringify({ type: 'error', message: 'API key is required for provider switch.' }));
        return;
      }
      const authToken = typeof msg.authToken === 'string' ? msg.authToken.trim() : '';
      const authPayload = verifyAuthToken(authToken);
      if (REQUIRE_LOGIN_AND_KEY_FOR_NEWS && !authPayload) {
        ws.send(JSON.stringify({ type: 'error', message: 'Sign in is required before starting news fetching.' }));
        return;
      }

      let resolvedKey = nextKey;
      if (!resolvedKey && authToken) {
        resolvedKey = await resolveSavedProviderKey(authToken, provider) || '';
      }
      if (!resolvedKey && !REQUIRE_LOGIN_AND_KEY_FOR_NEWS) {
        resolvedKey = String(providerApiKeys[provider] || '').trim();
      }
      if (provider !== 'local' && !resolvedKey) {
        ws.send(JSON.stringify({
          type: 'error',
          message: REQUIRE_LOGIN_AND_KEY_FOR_NEWS
            ? 'Provider key is required. Save a key in your account first.'
            : 'No key available for provider switch. Sign in and save a provider key.'
        }));
        return;
      }

      aiProvider = provider;
      if (provider !== 'local') {
        setAiProviderKey(provider, resolvedKey);
      } else {
        refreshAiClients();
      }

      aiEnabled = aiEnabled && aiAvailable;

      titleVecCache.clear();
      dedupeWindow = [];
      filteredDedupeWindow = [];
      aiQueue.length = 0;
      aiInFlight.clear();

      await safeInitKeywordEmbeddings(ws, 'AI provider keyword matching');
      if (REQUIRE_LOGIN_AND_KEY_FOR_NEWS && !newsAccessUnlocked) {
        newsAccessUnlocked = true;
      }
      broadcastConfig();
      ws.send(JSON.stringify({
        type: 'ok',
        message: `AI provider switched to ${provider}`
      }));
      markDirty();
      return;
    }

    if (msg.type === 'set_ai_models') {
      const provider = aiProvider;
      const current = selectedModelsByProvider[provider];
      const updates: Partial<AiModelSelection> = {};
      const rejected: string[] = [];
      if (!msg.summaryModel && !msg.researchModel && !msg.askModel) {
        ws.send(JSON.stringify({
          type: 'error',
          message: 'At least one model must be provided.'
        }));
        return;
      }

      if (msg.summaryModel) {
        if (providerSupportsModel(provider, 'summary', msg.summaryModel)) {
          updates.summary = msg.summaryModel;
        } else {
          rejected.push(`summary=${msg.summaryModel}`);
        }
      }
      if (msg.researchModel) {
        if (providerSupportsModel(provider, 'research', msg.researchModel)) {
          updates.research = msg.researchModel;
        } else {
          rejected.push(`research=${msg.researchModel}`);
        }
      }
      if (msg.askModel) {
        if (providerSupportsModel(provider, 'ask', msg.askModel)) {
          updates.ask = msg.askModel;
        } else {
          rejected.push(`ask=${msg.askModel}`);
        }
      }

      if (rejected.length > 0) {
        ws.send(JSON.stringify({
          type: 'error',
          message: `Unsupported model for ${provider}: ${rejected.join(', ')}`
        }));
        return;
      }

      if (updates.summary) current.summary = updates.summary;
      if (updates.research) current.research = updates.research;
      if (updates.ask) current.ask = updates.ask;

      aiQueue.length = 0;
      aiInFlight.clear();

      broadcastConfig();
      markDirty();
      return;
    }

    if (msg.type === 'set_summary_lang') {
      const lang = msg.lang;
      if (lang === 'bg' || lang === 'en' || lang === 'bilingual') {
        const prev = summaryLang;
        summaryLang = lang;
        broadcastConfig();
        if (prev !== lang) {
          ws.send(JSON.stringify({
            type: 'ok',
            message: `Summary language set to ${lang.toUpperCase()}. Existing summaries are preserved; newly visible or manually refreshed items will use the new language.`
          }));
        }

        markDirty();
      }
      return;
    }

    if (msg.type === 'set_research_lang') {
      const lang = msg.lang;
      if (lang === 'bg' || lang === 'en') {
        researchLang = lang;
        reprocessCachedItems(true);
        broadcastConfig();
        markDirty();
      }
      return;
    }

    if (msg.type === 'set_title_display_language') {
      const next = msg.titleDisplayLanguage;
      if (next === 'original' || next === 'bg' || next === 'en') {
        titleDisplayLanguage = next;
        broadcastConfig();
        markDirty();
      }
      return;
    }

    if (msg.type === 'set_keywords') {
      const beforeMatchCount = recent.reduce((acc, it) => acc + (it.isMatch ? 1 : 0), 0);
      keywords = parseKeywordsPayload(msg.keywords);

      titleVecCache.clear();
      filteredDedupeWindow = [];
      keywordVecs = [];

      await safeInitKeywordEmbeddings(ws, 'Keyword matching');
      await refreshMatchStateForRecent();
      broadcastConfig();
      const afterMatchCount = recent.reduce((acc, it) => acc + (it.isMatch ? 1 : 0), 0);
      ws.send(JSON.stringify({
        type: 'ok',
        message: `Updated ${keywords.length} keywords. Reprocessed ${recent.length} stored news items (${beforeMatchCount} -> ${afterMatchCount} matches).`
      }));
      markDirty();
      return;
    }

    if (msg.type === 'set_ai_features') {
      let shouldRebuildEmbeddings = false;
      if (msg.features) {
        aiFeatures = normalizeAiFeatureSettings(msg.features, aiFeatures);
      }
      if (typeof msg.localRegion === 'string') {
        localRegion = msg.localRegion.trim().slice(0, 120);
      }
      if (typeof msg.localBaseUrl === 'string') {
        localLlmBaseUrl = msg.localBaseUrl.trim().slice(0, 500) || localLlmBaseUrl;
        refreshAiClients();
        shouldRebuildEmbeddings = true;
      }
      if (Array.isArray(msg.trackedTopics)) {
        trackedTopics = normalizeTrimmedList(msg.trackedTopics, 80);
      }
      if (shouldRebuildEmbeddings) {
        titleVecCache.clear();
        keywordVecs = [];
        await safeInitKeywordEmbeddings(ws, 'AI keyword matching');
      }
      reprocessCachedItems(true);
      broadcastConfig();
      markDirty();
      return;
    }

    if (msg.type === 'generate_daily_briefing') {
      const delivery: BriefingDelivery = msg.delivery === 'email' ? 'email' : 'site';
      const email = String(msg.email || '').trim();
      const format: BriefingFormat = msg.format === 'bullets' || msg.format === 'narrative' ? msg.format : 'executive';
      const feedUrls = normalizeTrimmedList(msg.feedUrls, 80);
      if (delivery === 'email' && (!email || !isValidEmailAddress(email))) {
        ws.send(JSON.stringify({ type: 'error', message: 'Daily briefing email address is invalid.' }));
        return;
      }
      const eligibility = canGenerateDailyBriefing(feedUrls);
      if (!eligibility.ok) {
        ws.send(JSON.stringify({ type: 'error', message: `Daily briefing unavailable: ${eligibility.reason}` }));
        return;
      }
      const briefing = generateDailyBriefingPayload(
        eligibility.items,
        delivery,
        email || undefined,
        format,
        !!msg.includeAudio,
        feedUrls.length ? feedUrls : currentFeeds().map(feed => feed.url)
      );
      ws.send(JSON.stringify(briefing));
      return;
    }

    if (msg.type === 'set_feed_summary') {
      const feedUrl = String(msg.feedUrl || '').trim();
      const enabled = !!msg.enabled;
      if (!feedUrl) return;

      if (!feedSettings.has(feedUrl)) {
        feedSettings.set(feedUrl, defaultSettingsForFeed({ url: feedUrl, label: feedUrl, kind: 'rss', intervalSec: 120 }));
      }

      feedSettings.get(feedUrl)!.summaryEnabled = enabled;
      broadcastConfig();

      if (!enabled) {
        // ensure summaryPending is cleared on UI for this feed when summary is turned off
        for (const it of recent) {
          if (!eligibleForFeed(it, feedUrl)) continue;
          broadcastNewsUpdate(it);
        }
      }

      markDirty();
      return;
    }

    if (msg.type === 'set_feed_translation') {
      const feedUrl = String(msg.feedUrl || '').trim();
      const enabled = !!msg.enabled;
      if (!feedUrl) return;

      if (!feedSettings.has(feedUrl)) {
        feedSettings.set(feedUrl, defaultSettingsForFeed({ url: feedUrl, label: feedUrl, kind: 'rss', intervalSec: 120 }));
      }

      feedSettings.get(feedUrl)!.translationEnabled = enabled;
      broadcastConfig();

      ws.send(JSON.stringify({
        type: 'ok',
        message: enabled
          ? 'Translations enabled. Existing text is preserved; newly visible or manually refreshed items will translate on demand.'
          : 'Translations disabled. Existing translated text is preserved, and future auto translation is paused for this column.'
      }));

      markDirty();
      return;
    }

    if (msg.type === 'set_feed_research') {
      const feedUrl = String(msg.feedUrl || '').trim();
      const enabled = !!msg.enabled;
      if (!feedUrl) return;

      if (!feedSettings.has(feedUrl)) {
        feedSettings.set(feedUrl, defaultSettingsForFeed({ url: feedUrl, label: feedUrl, kind: 'rss', intervalSec: 120 }));
      }

      feedSettings.get(feedUrl)!.researchEnabled = enabled;
      broadcastConfig();
      ws.send(JSON.stringify({
        type: 'ok',
        message: enabled
          ? 'Research enabled. Existing research is preserved; newly visible or manually requested items will analyze on demand.'
          : 'Research disabled for this column. Existing research is preserved.'
      }));

      markDirty();
      return;
    }

    if (msg.type === 'set_feed_discord_webhook') {
      const feedUrl = String(msg.feedUrl || '').trim();
      if (!feedUrl) return;

      if (!feedSettings.has(feedUrl)) {
        feedSettings.set(feedUrl, defaultSettingsForFeed({ url: feedUrl, label: feedUrl, kind: 'rss', intervalSec: 120 }));
      }

      const webhookUrl = normalizeDiscordWebhookUrl(msg.webhookUrl);
      if (String(msg.webhookUrl || '').trim() && !webhookUrl) {
        ws.send(JSON.stringify({
          type: 'error',
          message: 'Discord webhook URL must be a valid Discord webhook link.'
        }));
        return;
      }

      feedSettings.get(feedUrl)!.discordWebhookUrl = webhookUrl;
      broadcastConfig();
      markDirty();
      return;
    }

    if (msg.type === 'set_feed_budget') {
      const feedUrl = String(msg.feedUrl || '').trim();
      const budget = msg.budget;
      if (!feedUrl) return;
      if (budget !== 'low' && budget !== 'standard' && budget !== 'high') return;

      if (!feedSettings.has(feedUrl)) {
        feedSettings.set(feedUrl, defaultSettingsForFeed({ url: feedUrl, label: feedUrl, kind: 'rss', intervalSec: 120 }));
      }

      feedSettings.get(feedUrl)!.budget = budget;

      recent.forEach(it => {
        if (!eligibleForFeed(it, feedUrl)) return;
        refreshDerivedDataForItem(it);
        void upsertPersistedNewsItem(it);
        broadcastNewsUpdate(it);
      });

      broadcastConfig();
      markDirty();
      return;
    }

    if (msg.type === 'set_all_budget') {
      const budget = msg.budget;
      if (budget !== 'low' && budget !== 'standard' && budget !== 'high') return;

      for (const fi of currentFeeds()) {
        if (!feedSettings.has(fi.url)) {
          feedSettings.set(fi.url, defaultSettingsForFeed(fi));
        }
        feedSettings.get(fi.url)!.budget = budget;
      }

      if (feedSettings.has(FILTERED_FEED_URL)) {
        feedSettings.get(FILTERED_FEED_URL)!.budget = budget;
      }

      recent.forEach(it => {
        refreshDerivedDataForItem(it);
        void upsertPersistedNewsItem(it);
        broadcastNewsUpdate(it);
      });

      broadcastConfig();
      markDirty();
      return;
    }

    if (msg.type === 'set_feed_interval') {
      const feedUrl = String(msg.feedUrl || '').trim();
      const intervalSec = Number(msg.intervalSec);
      if (!feedUrl || !Number.isFinite(intervalSec)) return;

      const v = Math.max(20, Math.min(3600, Math.floor(intervalSec)));

      if (!feedSettings.has(feedUrl)) {
        feedSettings.set(feedUrl, defaultSettingsForFeed({ url: feedUrl, label: feedUrl, kind: 'rss', intervalSec: v }));
      }

      feedSettings.get(feedUrl)!.intervalSec = v;

      // update feedsList display interval too
      const fi = feedsList.find(x => x.url === feedUrl);
      if (fi) fi.intervalSec = v;

      broadcastConfig();
      markDirty();
      return;
    }

    if (msg.type === 'set_feed_column_settings') {
      const feedUrl = String(msg.feedUrl || '').trim();
      if (!feedUrl) return;

      const sortMode = msg.sortMode;
      const filters = msg.filters;

      if (!feedSettings.has(feedUrl)) {
        feedSettings.set(feedUrl, defaultSettingsForFeed({ url: feedUrl, label: feedUrl, kind: 'rss', intervalSec: 120 }));
      }

      const s = feedSettings.get(feedUrl)!;

      if (sortMode === 'newest' || sortMode === 'oldest' || sortMode === 'matched') {
        s.sortMode = sortMode;
      }

      if (filters && typeof filters === 'object') {
        s.filters = {
          onlyMatches: !!filters.onlyMatches,
          onlyResearched: !!filters.onlyResearched,
          onlySummaries: !!filters.onlySummaries
        };
      }

      broadcastConfig();
      markDirty();
      return;
    }

    if (msg.type === 'hide_item') {
      const id = String(msg.id || '').trim();
      if (!id) return;
      hiddenIds.add(id);
      broadcastConfig();
      markDirty();
      return;
    }

    if (msg.type === 'unhide_item') {
      const id = String(msg.id || '').trim();
      if (!id) return;
      hiddenIds.delete(id);
      broadcastConfig();
      markDirty();
      return;
    }

    if (msg.type === 'run_research_item') {
      if (!aiEnabled || !aiAvailable || activeModel('research') === 'none') return;
      const id = String(msg.id || '').trim();
      if (!id) return;

      const it = recent.find(x => x.id === id && x.feedUrl === String(msg.feedUrl || '').trim()) || recent.find(x => x.id === id);
      if (!it) return;
      it.research = '';
      void upsertPersistedNewsItem(it);
      broadcastNewsUpdate(it);
      markDirty();

      enqueueJob({ kind: 'research', id: it.id, feedUrl: it.feedUrl, manual: true });
      return;
    }

    if (msg.type === 'run_summary_item') {
      if (!aiEnabled || !aiAvailable || activeModel('summary') === 'none') return;
      const id = String(msg.id || '').trim();
      if (!id) return;

      const it = recent.find(x => x.id === id && x.feedUrl === String(msg.feedUrl || '').trim()) || recent.find(x => x.id === id);
      if (!it) return;
      it.summary = '';
      void upsertPersistedNewsItem(it);
      enqueueJob({ kind: 'summary', id: it.id, feedUrl: it.feedUrl, manual: true });
      broadcastNewsUpdate(it);
      markDirty();
      return;
    }

    if (msg.type === 'run_item_auto') {
      if (!aiEnabled || !aiAvailable) return;
      const id = String(msg.id || '').trim();
      const requestedFeedUrl = String(msg.feedUrl || '').trim();
      if (!id) return;

      const it = recent.find(x => x.id === id && x.feedUrl === requestedFeedUrl) || recent.find(x => x.id === id);
      if (!it || hiddenIds.has(it.id)) return;

      const summaryModelReady = activeModel('summary') !== 'none';
      const researchModelReady = activeModel('research') !== 'none';
      const budget = feedSettings.get(it.feedUrl)?.budget || 'standard';
      let queuedSomething = false;

      if (msg.summary && summaryModelReady && isAutoSummaryEligible(it) && !String(it.summary || '').trim() && !hasSummaryJobQueuedOrRunning(it.id, it.feedUrl)) {
        enqueueJob({ kind: 'summary', id: it.id, feedUrl: it.feedUrl });
        queuedSomething = hasSummaryJobQueuedOrRunning(it.id, it.feedUrl) || queuedSomething;
      }

      if (msg.research && researchModelReady) {
        const wantsFeedResearch = !!feedSettings.get(it.feedUrl)?.researchEnabled;
        const wantsFilteredResearch =
          !!feedSettings.get(FILTERED_FEED_URL)?.researchEnabled &&
          !!it.isMatch &&
          it.filteredOk !== false;
        if ((wantsFeedResearch || wantsFilteredResearch) && !String(it.research || '').trim() && !hasResearchJobQueuedOrRunning(it.id, it.feedUrl) && budgetAllowsAutoResearch(budget)) {
          enqueueJob({ kind: 'research', id: it.id, feedUrl: it.feedUrl });
          queuedSomething = hasResearchJobQueuedOrRunning(it.id, it.feedUrl) || queuedSomething;
        }
      }

      if (msg.titleTranslate && summaryModelReady && isTranslationEnabledForFeed(it.feedUrl) && needsTitleTranslation(it.title, it.titleBg, it.titleEn) && !hasTitleTranslateJobQueuedOrRunning(it.id, it.feedUrl)) {
        enqueueJob({ kind: 'title_translate', id: it.id, feedUrl: it.feedUrl, viewport: true });
        queuedSomething = hasTitleTranslateJobQueuedOrRunning(it.id, it.feedUrl) || queuedSomething;
      }

      if (msg.mood && researchModelReady && !it.mood) {
        enqueueJob({ kind: 'mood', id: it.id, feedUrl: it.feedUrl, viewport: true });
        queuedSomething = true;
      }

      if (msg.newsType && researchModelReady && !it.newsType) {
        enqueueJob({ kind: 'news_type', id: it.id, feedUrl: it.feedUrl, viewport: true });
        queuedSomething = true;
      }

      if (queuedSomething) {
        broadcastNewsUpdate(it);
      }
      return;
    }

    if (msg.type === 'ask_agent_item') {
      if (!aiEnabled || !aiAvailable || activeModel('ask') === 'none') {
        const unavailable: AskAgentReply = {
          type: 'ask_agent_reply',
          id: String(msg.id || ''),
          feedUrl: String(msg.feedUrl || ''),
          question: String(msg.question || ''),
          error: 'AI is unavailable right now.',
          used: 0,
          remaining: ASK_AGENT_MAX_QUESTIONS
        };
        ws.send(JSON.stringify(unavailable));
        return;
      }

      const id = String(msg.id || '').trim();
      const feedUrl = String(msg.feedUrl || '').trim();
      const question = String(msg.question || '').trim().slice(0, ASK_AGENT_MAX_CHARS);
      if (!id || !question) return;

      const it = recent.find(x => x.id === id && x.feedUrl === feedUrl) || recent.find(x => x.id === id);
      if (!it) {
        const notFound: AskAgentReply = {
          type: 'ask_agent_reply',
          id,
          feedUrl,
          question,
          error: 'News item not found. Try again from the latest card.',
          used: 0,
          remaining: ASK_AGENT_MAX_QUESTIONS
        };
        ws.send(JSON.stringify(notFound));
        return;
      }

      const key = `${it.feedUrl}::${it.id}`;
      const usedBefore = askAgentCountByItem.get(key) || 0;
      if (usedBefore >= ASK_AGENT_MAX_QUESTIONS) {
        const limit: AskAgentReply = {
          type: 'ask_agent_reply',
          id: it.id,
          feedUrl: feedUrl || it.feedUrl,
          question,
          error: `Question limit reached for this news (${ASK_AGENT_MAX_QUESTIONS}/${ASK_AGENT_MAX_QUESTIONS}).`,
          used: ASK_AGENT_MAX_QUESTIONS,
          remaining: 0
        };
        ws.send(JSON.stringify(limit));
        return;
      }

      const usedNow = usedBefore + 1;
      askAgentCountByItem.set(key, usedNow);

      const budget = feedSettings.get(it.feedUrl)?.budget || 'standard';
      const requestedResearchMode = msg.researchMode === 'force' || msg.researchMode === 'reuse'
        ? msg.researchMode
        : 'auto';
      try {
        // Ask latency policy:
        // - force: always refresh research first
        // - reuse: never refresh research first
        // - auto (default): refresh only for high budget OR when no research exists yet
        const hasExistingResearch = !!String(it.research || '').trim();
        const shouldRefreshResearch = requestedResearchMode === 'force'
          ? true
          : requestedResearchMode === 'reuse'
            ? false
            : (budget === 'high' || !hasExistingResearch);

        let chatResearch = '';
        if (shouldRefreshResearch) {
          const ctx = it.__ctx || '';
          const linkText = it.__linkText || '';
          try {
            const refreshedResearch = await withTimeout(
              oneItemResearch(it.title, it.source, it.link, ctx, linkText, budget),
              ASK_AGENT_RESEARCH_TIMEOUT_MS,
              'ask_agent_research'
            );
            if (refreshedResearch) {
              // Keep chat-triggered research private to Ask Agent panel.
              chatResearch = refreshedResearch;
            }
          } catch {
            // Do not fail Ask Agent when optional refresh-research is slow.
          }
        }

        const answer = await withTimeout(
          askAgentAboutItem(question, it, budget, chatResearch),
          ASK_AGENT_ANSWER_TIMEOUT_MS,
          'ask_agent_answer'
        );
        const ok: AskAgentReply = {
          type: 'ask_agent_reply',
          id: it.id,
          feedUrl: feedUrl || it.feedUrl,
          question,
          answer: answer || 'I can only answer questions about this specific news item.',
          used: usedNow,
          remaining: Math.max(0, ASK_AGENT_MAX_QUESTIONS - usedNow)
        };
        ws.send(JSON.stringify(ok));
      } catch {
        // Do not consume quota on transport/model failure.
        askAgentCountByItem.set(key, usedBefore);
        const fail: AskAgentReply = {
          type: 'ask_agent_reply',
          id: it.id,
          feedUrl: feedUrl || it.feedUrl,
          question,
          error: 'Ask Agent failed. Please try again.',
          used: usedBefore,
          remaining: Math.max(0, ASK_AGENT_MAX_QUESTIONS - usedBefore)
        };
        ws.send(JSON.stringify(fail));
      }
      return;
    }

    if (msg.type === 'add_feed') {
      const url = String(msg.url || '').trim();
      if (!url) return;

      let parsed: URL;
      try { parsed = new URL(url); } catch {
        ws.send(JSON.stringify({ type: 'error', message: 'Invalid URL' }));
        return;
      }
      if (!['http:', 'https:'].includes(parsed.protocol)) {
        ws.send(JSON.stringify({ type: 'error', message: 'URL must be http/https' }));
        return;
      }

      const kind: FeedKind = (msg.kind === 'reddit' || msg.kind === 'youtube') ? msg.kind : 'rss';

      const intervalSecRaw = Number(msg.intervalSec);
      const intervalSec = Number.isFinite(intervalSecRaw)
        ? Math.max(20, Math.min(3600, Math.floor(intervalSecRaw)))
        : defaultIntervalForKind(kind);

      const label = String(msg.label || '').trim() || parsed.hostname;

      if (!feedsList.some(f => f.url === url)) {
        const fi: FeedInfo = { url, label, kind, intervalSec };
        feedsList.unshift(fi);
        ensureFeedSettings(fi);
        feedSettings.get(url)!.intervalSec = intervalSec;
        feedSettings.get(url)!.kind = kind;
        feedSettings.get(url)!.label = label;
        ensureFeedRuntime(url);

        markDirty();
      }

      broadcastConfig();
      ws.send(JSON.stringify({ type: 'ok', message: `Added feed: ${label}` }));
      return;
    }

    if (msg.type === 'remove_feed') {
      const feedUrl = String(msg.feedUrl || '').trim();
      if (!feedUrl || feedUrl === FILTERED_FEED_URL) return;

      const before = feedsList.length;
      feedsList = feedsList.filter(f => f.url !== feedUrl);
      if (feedsList.length === before) {
        ws.send(JSON.stringify({ type: 'error', message: 'Feed not found' }));
        return;
      }

      feedSettings.delete(feedUrl);
      feedRuntime.delete(feedUrl);

      // Drop queued AI work for removed feed.
      for (let i = aiQueue.length - 1; i >= 0; i--) {
        if (aiQueue[i].feedUrl === feedUrl) aiQueue.splice(i, 1);
      }

      // Remove recent items for removed feed so it fully disappears from client snapshots.
      for (let i = recent.length - 1; i >= 0; i--) {
        if (recent[i].feedUrl === feedUrl) recent.splice(i, 1);
      }
      void prisma.newsItemRecord.deleteMany({ where: { feedUrl } }).catch(err => {
        console.error(`Failed to delete archived news for removed feed ${feedUrl}:`, (err as Error).message);
      });

      broadcastConfig();
      ws.send(JSON.stringify({ type: 'ok', message: `Removed feed` }));
      markDirty();
      return;
    }
  });
});
}

// ---------------- Startup ----------------
(async () => {
  await loadState();

  // ensure settings for each feed
  for (const fi of feedsList) ensureFeedSettings(fi);

  // load embeddings once
  if (aiEnabled) await safeInitKeywordEmbeddings(undefined, 'Startup keyword matching');

  // Push the hydrated state to already-connected clients so they do not wait
  // for the browser replay to restore keywords and filtered-column state.
  broadcastConfig();

  // start scheduler
  startScheduler();

  if (RUNTIME_MS > 0) {
    console.log(`Runtime limit set to ${RUNTIME_HOURS} hours`);
    setTimeout(() => shutdown(`runtime limit reached (${RUNTIME_HOURS} hours)`), RUNTIME_MS);
  }
})();
