// Load gate in front of the local model server, so any client (the app's own AI calls included) stays inside
// the same limits as lean.mjs however much news arrives:
// - at most MAX_PAR requests reach the model at once, and background work leaves one slot free for clicks;
// - the model is busy at most BUSY_SHARE of any minute; above that, requests wait;
// - at most QUEUE_MAX requests wait; more are refused with 503 (the app records the job as failed and moves on);
// - a request that waited longer than WAIT_MS is refused, and one that runs longer than RUN_MS is cut off.
// Usage: node gate.mjs   (listens on GATE_PORT, default 18082, forwards to MODEL_URL, default http://127.0.0.1:8081)
import http from 'http';
import { AI_RULES } from '../../backend/apps/api/dist/aiRules.js';

// The no-invention rules go to the model with every request, whichever tool sent it. Answers are then checked:
// a sentence with a number, or a name in the source's own script, that the request text does not contain is
// removed, so an invented figure, person or outlet cannot reach the app.
const RULES = AI_RULES;
const cyr = t => /[а-яА-Я]/.test(t);
const tokensOf = t => (t.match(/\d+(?:[.,]\d+)?|[A-ZА-Я][a-zа-я]{2,}/g) || []);
const supported = (sentence, source) => {
  const src = source.toLowerCase();
  return tokensOf(sentence).every(tok => {
    if (/^\d/.test(tok)) return src.includes(tok.replace(',', '.')) || src.includes(tok.replace('.', ','));
    if (cyr(tok) !== cyr(source)) return true; // another script: a translation or transliteration, not checkable here
    return src.includes(tok.toLowerCase().slice(0, Math.max(4, tok.length - 2)));
  });
};
function withRules(body, path) {
  try {
    const j = JSON.parse(body.toString());
    if (path.startsWith('/v1/responses')) j.instructions = [RULES, j.instructions].filter(Boolean).join('\n\n');
    else if (path.startsWith('/v1/chat/completions') && Array.isArray(j.messages)) {
      // The chat template allows one system message, first: rules join an existing one (once) instead.
      const first = j.messages[0];
      if (first?.role === 'system') { if (!String(first.content).includes(RULES)) first.content = `${RULES}\n\n${first.content}`; }
      else j.messages = [{ role: 'system', content: RULES }, ...j.messages];
    }
    else return { body, source: '' };
    const source = JSON.stringify(j.input ?? j.messages ?? '');
    return { body: Buffer.from(JSON.stringify(j)), source };
  } catch { return { body, source: '' }; }
}
function checkAnswer(text, source) {
  if (!source || /^\s*[\[{]/.test(text)) return { text, removed: 0 }; // JSON answers are checked by their caller
  const sentences = text.match(/[^.!?\n]+[.!?]*\s*/g) || [text];
  const kept = sentences.filter(x => supported(x, source));
  return { text: kept.join('').trim() || text, removed: sentences.length - kept.length };
}

const MODEL_URL = new URL(process.env.MODEL_URL || 'http://127.0.0.1:8081');
const GATE_PORT = Number(process.env.GATE_PORT || 18082);
const MAX_PAR = Number(process.env.MAX_PAR || 2);
const BUSY_SHARE = Number(process.env.BUSY_SHARE || 0.4);
// Even clicks wait once the model has been busy this share of the last minute: a bulk run of research jobs
// carries the same task name as a click and kept the model at 97% busy.
const HARD_SHARE = Number(process.env.HARD_SHARE || 0.75);
const QUEUE_MAX = Number(process.env.QUEUE_MAX || 60);
const WAIT_MS = Number(process.env.WAIT_MS || 10 * 60e3);
// Long enough for a briefing rating batch (about 1,500 words written at a busy model's pace).
const RUN_MS = Number(process.env.RUN_MS || 300e3);

let running = 0, busySince = 0;
const busyLog = [];
const queue = [];
const stats = { served: 0, refusedFull: 0, refusedLate: 0, cutOff: 0 };

const busyShare = () => {
  const now = Date.now(), from = now - 60e3;
  while (busyLog.length && busyLog[0][1] < from) busyLog.shift();
  let b = busyLog.reduce((a, [s, e]) => a + (e - Math.max(s, from)), 0);
  if (running > 0) b += now - Math.max(busySince, from);
  return b / 60e3;
};
const start = () => { if (running++ === 0) busySince = Date.now(); };
const end = () => { if (--running === 0) busyLog.push([busySince, Date.now()]); };

// What the user clicked (research, Ask) goes first and is not held by the busy limit; background work
// (summaries, translations, labels) waits for its turn. The app names the task in the x-ai-task header.
const PRIORITY = /^(Research|Ask agent)/i;
const urgent = job => PRIORITY.test(String(job.req.headers['x-ai-task'] || ''));
function pump() {
  for (;;) {
    if (!queue.length || running >= MAX_PAR) return;
    const i = queue.findIndex(urgent);
    // Background work never takes the last slot, so a click always finds one free.
    if (i < 0 && (busyShare() > BUSY_SHARE || running >= MAX_PAR - 1)) return;
    if (i >= 0 && busyShare() > HARD_SHARE) return;
    // Above the normal limit, clicks go one at a time: a run of many research jobs otherwise took both slots.
    if (i >= 0 && busyShare() > BUSY_SHARE && urgentRunning > 0) return;
    const job = queue.splice(i >= 0 ? i : 0, 1)[0];
    if (Date.now() - job.at > WAIT_MS) { stats.refusedLate++; job.res.writeHead(503).end('{"error":"waited too long"}'); continue; }
    forward(job);
  }
}
setInterval(pump, 500);

let urgentRunning = 0;
function forward({ req, body: raw, res }) {
  const { body, source } = req.method === 'POST' ? withRules(raw, req.url) : { body: raw, source: '' };
  const isUrgent = PRIORITY.test(String(req.headers['x-ai-task'] || ''));
  start(); if (isUrgent) urgentRunning++;
  let done = false;
  const finish = () => { if (!done) { done = true; end(); if (isUrgent) urgentRunning--; pump(); } };
  const up = http.request({ host: MODEL_URL.hostname, port: MODEL_URL.port, path: req.url, method: req.method,
    // The body may have grown (rules added), so its length is set again.
    headers: { ...req.headers, host: MODEL_URL.host, 'content-length': String(body.length) } }, upRes => {
    const chunks = [];
    upRes.on('data', c => chunks.push(c));
    upRes.on('end', () => {
      let out = Buffer.concat(chunks);
      try {
        const j = JSON.parse(out.toString());
        const fix = t => { const r = checkAnswer(t, source); stats.sentencesRemoved = (stats.sentencesRemoved || 0) + r.removed; return r.text; };
        for (const o of j.output || []) for (const c of o.content || []) if (typeof c.text === 'string') c.text = fix(c.text);
        for (const ch of j.choices || []) if (typeof ch.message?.content === 'string') ch.message.content = fix(ch.message.content);
        out = Buffer.from(JSON.stringify(j));
      } catch {}
      const headers = { ...upRes.headers, 'content-length': String(out.length) }; delete headers['transfer-encoding'];
      res.writeHead(upRes.statusCode || 502, headers).end(out);
      stats.served++; finish();
    });
    upRes.on('error', finish);
  });
  up.setTimeout(RUN_MS, () => { stats.cutOff++; up.destroy(); if (!res.headersSent) res.writeHead(504).end('{"error":"model took too long"}'); finish(); });
  up.on('error', () => { if (!res.headersSent) res.writeHead(502).end('{"error":"model server not answering"}'); finish(); });
  up.end(body);
}

http.createServer((req, res) => {
  // Health and model-list requests pass straight through; they cost the model nothing.
  if (req.url === '/gate') { res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ running, queued: queue.length, busyShare: +busyShare().toFixed(2), ...stats })); return; }
  const chunks = [];
  req.on('data', c => chunks.push(c));
  req.on('end', () => {
    const job = { req, body: Buffer.concat(chunks), res, at: Date.now() };
    if (req.method === 'GET') return forward(job);
    if (queue.length >= QUEUE_MAX) { stats.refusedFull++; res.writeHead(503).end('{"error":"queue full"}'); return; }
    // A client that gave up while waiting (timed out, restarted) is dropped, so the model never works for nobody.
    res.on('close', () => { const i = queue.indexOf(job); if (i >= 0) { queue.splice(i, 1); stats.abandoned = (stats.abandoned || 0) + 1; } });
    queue.push(job); pump();
  });
}).listen(GATE_PORT, '127.0.0.1', () => console.log(`gate on 127.0.0.1:${GATE_PORT} -> ${MODEL_URL.host}, ${MAX_PAR} at once, busy <= ${BUSY_SHARE * 100}% of a minute, queue <= ${QUEUE_MAX}`));
