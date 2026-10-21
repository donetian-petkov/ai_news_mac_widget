// Times research "clicks" the way the widget sends them, while the app may be busy with background work:
// sends run_research_item for N stories that have no research yet and reports how long each result took
// to come back over the socket. Usage: node click-time.mjs <port> <db> [N] [gapSeconds]
import { execFileSync } from 'child_process';
import { createRequire } from 'module';
const require = createRequire(new URL('../../backend/apps/api/package.json', import.meta.url));
const WebSocket = require('ws');

const [,, port, db, nRaw, gapRaw] = process.argv;
const n = Number(nRaw || 3), gap = Number(gapRaw || 20) * 1000;
const items = JSON.parse(execFileSync('sqlite3', ['-readonly', '-json', db,
  `SELECT itemId AS id, feedUrl, title FROM NewsItemRecord WHERE (research IS NULL OR research = '') ORDER BY publishedMs DESC LIMIT ${n}`]).toString() || '[]');
const sent = {}, took = {};
// Finds any object for the item with research text, anywhere in a message.
const findResearch = (v, id) => {
  if (!v || typeof v !== 'object') return null;
  if (v.id === id && typeof v.research === 'string' && v.research.trim()) return v.research;
  for (const x of Array.isArray(v) ? v : Object.values(v)) { const r = findResearch(x, id); if (r) return r; }
  return null;
};
const ws = new WebSocket(`ws://127.0.0.1:${port}`);
ws.on('message', raw => {
  let m; try { m = JSON.parse(String(raw)); } catch { return; }
  for (const it of items) if (sent[it.id] && !took[it.id] && findResearch(m, it.id)) {
    took[it.id] = (Date.now() - sent[it.id]) / 1000;
    console.log(`${took[it.id].toFixed(1)} s  ${it.title.slice(0, 70)}`);
  }
});
ws.on('open', async () => {
  for (const it of items) {
    sent[it.id] = Date.now();
    ws.send(JSON.stringify({ type: 'run_research_item', id: it.id, feedUrl: it.feedUrl }));
    await new Promise(r => setTimeout(r, gap));
  }
  const until = Date.now() + 5 * 60e3;
  while (Object.keys(took).length < items.length && Date.now() < until) await new Promise(r => setTimeout(r, 1000));
  for (const it of items) if (!took[it.id]) console.log(`no result in 5 min  ${it.title.slice(0, 70)}`);
  process.exit(0);
});
