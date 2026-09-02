import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn, type ChildProcess } from 'node:child_process';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import WebSocket from 'ws';

type WireConfig = {
  type: 'config';
  keywords?: string[];
};

type WireNews = {
  type: 'news';
  id?: string;
  isMatch?: boolean;
};

const START_TIMEOUT_MS = 25_000;
const WAIT_STEP_MS = 150;

const apiPort = 4900 + Math.floor(Math.random() * 1000);
const wsUrl = `ws://127.0.0.1:${apiPort}`;
const healthUrl = `http://127.0.0.1:${apiPort}/health`;

const distDir = path.resolve(__dirname, '../dist');
const serverEntry = path.join(distDir, 'server.js');
const dataDir = path.join(distDir, '.data');
const statePath = path.join(dataDir, 'state.json');

let apiProc: ChildProcess | null = null;
let previousState: string | null = null;
let hadPreviousState = false;
let dbPath = '';
let startupError: string | null = null;

function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function waitFor(check: () => boolean, timeoutMs: number, label: string) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (check()) return;
    await sleep(WAIT_STEP_MS);
  }
  throw new Error(`Timed out waiting for ${label}`);
}

async function waitForHealth() {
  const start = Date.now();
  while (Date.now() - start < START_TIMEOUT_MS) {
    try {
      const res = await fetch(healthUrl);
      if (res.ok) return;
    } catch {}
    await sleep(WAIT_STEP_MS);
  }
  throw new Error(`API health did not become ready on ${healthUrl}`);
}

function seedStateFile() {
  const seededState = {
    version: 1,
    keywords: [],
    feeds: [
      { url: 'http://127.0.0.1:9/rss', label: 'Seed Feed', kind: 'rss', intervalSec: 300 }
    ],
    feedSettings: {
      'http://127.0.0.1:9/rss': {
        summaryEnabled: false,
        researchEnabled: false,
        budget: 'standard',
        sortMode: 'newest',
        filters: { onlyMatches: false, onlyResearched: false, onlySummaries: false },
        intervalSec: 300,
        kind: 'rss',
        label: 'Seed Feed'
      },
      '__filtered__': {
        summaryEnabled: false,
        researchEnabled: false,
        budget: 'standard',
        sortMode: 'newest',
        filters: { onlyMatches: true, onlyResearched: false, onlySummaries: false },
        intervalSec: 0,
        kind: 'rss',
        label: 'Filtered'
      }
    },
    hiddenIds: [],
    feedRuntime: {},
    recent: [
      {
        type: 'news',
        id: 'seed-news-1',
        title: 'Energy crisis update in Europe',
        link: 'https://example.com/news/1',
        source: 'Seed Feed',
        published: '2026-03-07T00:00:00.000Z',
        publishedMs: 1772841600000,
        feedUrl: 'http://127.0.0.1:9/rss',
        isMatch: false,
        matchScore: 0,
        filteredOk: false
      }
    ]
  };

  fs.mkdirSync(dataDir, { recursive: true });
  hadPreviousState = fs.existsSync(statePath);
  previousState = hadPreviousState ? fs.readFileSync(statePath, 'utf8') : null;
  fs.writeFileSync(statePath, JSON.stringify(seededState, null, 2), 'utf8');
}

function restoreStateFile() {
  try {
    if (hadPreviousState && previousState !== null) {
      fs.writeFileSync(statePath, previousState, 'utf8');
      return;
    }
    if (fs.existsSync(statePath)) {
      fs.unlinkSync(statePath);
    }
  } catch {}
}

async function startApi() {
  if (!fs.existsSync(serverEntry)) {
    throw new Error('apps/api/dist/server.js not found. Run `npm run build -w @ai-news/api` first.');
  }

  dbPath = path.join(os.tmpdir(), `ai-news-api-int-${Date.now()}-${Math.random().toString(16).slice(2)}.db`);
  const env = {
    ...process.env,
    PORT: String(apiPort),
    AI_ENABLED: 'false',
    KEYWORDS: '',
    DATABASE_URL: `file:${dbPath}`
  };

  apiProc = spawn(process.execPath, [serverEntry], {
    cwd: path.resolve(__dirname, '..'),
    env,
    stdio: ['ignore', 'pipe', 'pipe']
  });
  const proc = apiProc;
  if (!proc) throw new Error('Failed to start API process');

  let bootError = '';
  proc.stderr?.on('data', chunk => {
    bootError += String(chunk || '');
  });

  await Promise.race([
    waitForHealth(),
    new Promise((_, reject) => {
      proc.once('exit', code => reject(new Error(`API exited early (${code}): ${bootError}`)));
    })
  ]);
}

async function stopApi() {
  if (!apiProc) return;
  const proc = apiProc;
  apiProc = null;
  proc.kill('SIGTERM');
  await Promise.race([
    new Promise(resolve => proc.once('exit', resolve)),
    sleep(2_000).then(() => {
      try { proc.kill('SIGKILL'); } catch {}
    })
  ]);
}

function collectWsMessages(url: string) {
  const messages: Array<Record<string, unknown>> = [];
  const ws = new WebSocket(url);
  return new Promise<{ ws: WebSocket; messages: Array<Record<string, unknown>> }>((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('WebSocket connect timeout')), 8_000);
    ws.on('open', () => {
      clearTimeout(timeout);
      resolve({ ws, messages });
    });
    ws.on('message', data => {
      try {
        const parsed = JSON.parse(String(data || '')) as Record<string, unknown>;
        messages.push(parsed);
      } catch {}
    });
    ws.on('error', err => {
      clearTimeout(timeout);
      reject(err);
    });
  });
}

describe('api integration: keyword rematch', () => {
  beforeAll(async () => {
    seedStateFile();
    try {
      await startApi();
      startupError = null;
    } catch (err) {
      startupError = String((err as Error)?.message || err || 'Unknown startup error');
    }
  });

  afterAll(async () => {
    await stopApi();
    restoreStateFile();
    try { if (dbPath) fs.unlinkSync(dbPath); } catch {}
    try { if (dbPath) fs.unlinkSync(`${dbPath}-wal`); } catch {}
    try { if (dbPath) fs.unlinkSync(`${dbPath}-shm`); } catch {}
  });

  it('serves health', async (ctx) => {
    if (startupError) {
      if (startupError.includes('EPERM')) {
        ctx.skip();
        return;
      }
      throw new Error(startupError);
    }
    const res = await fetch(healthUrl);
    expect(res.ok).toBe(true);
    const body = await res.json() as { ok?: boolean; service?: string };
    expect(body.ok).toBe(true);
    expect(body.service).toBe('ai-news-api');
  });

  it('resets a local account password through the auth API', async (ctx) => {
    if (startupError) {
      if (startupError.includes('EPERM')) {
        ctx.skip();
        return;
      }
      throw new Error(startupError);
    }
    const username = `reset-${apiPort}@example.com`;
    const firstPassword = 'first-password';
    const secondPassword = 'second-password';
    const baseUrl = `http://127.0.0.1:${apiPort}`;

    const registerRes = await fetch(`${baseUrl}/api/auth/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password: firstPassword })
    });
    expect(registerRes.ok).toBe(true);

    const resetRes = await fetch(`${baseUrl}/api/auth/reset-password`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password: secondPassword })
    });
    expect(resetRes.ok).toBe(true);
    const resetBody = await resetRes.json() as { token?: string; user?: { username?: string } };
    expect(resetBody.token).toBeTruthy();
    expect(resetBody.user?.username).toBe(username);

    const oldLoginRes = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password: firstPassword })
    });
    expect(oldLoginRes.status).toBe(401);

    const newLoginRes = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password: secondPassword })
    });
    expect(newLoginRes.ok).toBe(true);
  });

  it('reprocesses retained news when keywords are updated', async (ctx) => {
    if (startupError) {
      if (startupError.includes('EPERM')) {
        ctx.skip();
        return;
      }
      throw new Error(startupError);
    }
    const { ws, messages } = await collectWsMessages(wsUrl);
    try {
      await waitFor(
        () => messages.some(m => m.type === 'config') && messages.some(m => m.type === 'news' && m.id === 'seed-news-1'),
        8_000,
        'initial config and seeded news snapshot'
      );

      const initialNews = messages.find((m): m is WireNews => m.type === 'news' && m.id === 'seed-news-1');
      expect(initialNews?.isMatch).toBe(false);

      ws.send(JSON.stringify({ type: 'set_keywords', keywords: 'energy, crisis' }));

      await waitFor(
        () => messages.some((m): m is WireConfig => m.type === 'config' && Array.isArray(m.keywords) && m.keywords.length === 2),
        10_000,
        'keyword config broadcast'
      );
      await waitFor(
        () => messages.some((m): m is WireNews => m.type === 'news' && m.id === 'seed-news-1' && m.isMatch === true),
        10_000,
        'reprocessed seeded news as match'
      );

      const cfg = messages
        .filter((m): m is WireConfig => m.type === 'config' && Array.isArray(m.keywords))
        .at(-1);
      const lower = (cfg?.keywords || []).map(v => String(v).toLocaleLowerCase());
      expect(lower).toContain('energy');
      expect(lower).toContain('crisis');
    } finally {
      ws.close();
    }
  });
});
