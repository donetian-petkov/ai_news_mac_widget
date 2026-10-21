// Load gate in front of the local model server, so any client (the app's own AI calls included) stays inside
// the same limits as lean.mjs however much news arrives:
// - at most MAX_PAR requests reach the model at once;
// - the model is busy at most BUSY_SHARE of any minute; above that, requests wait;
// - at most QUEUE_MAX requests wait; more are refused with 503 (the app records the job as failed and moves on);
// - a request that waited longer than WAIT_MS is refused, and one that runs longer than RUN_MS is cut off.
// Usage: node gate.mjs   (listens on GATE_PORT, default 8082, forwards to MODEL_URL, default http://127.0.0.1:8081)
import http from 'http';

const MODEL_URL = new URL(process.env.MODEL_URL || 'http://127.0.0.1:8081');
const GATE_PORT = Number(process.env.GATE_PORT || 8082);
const MAX_PAR = Number(process.env.MAX_PAR || 2);
const BUSY_SHARE = Number(process.env.BUSY_SHARE || 0.4);
const QUEUE_MAX = Number(process.env.QUEUE_MAX || 60);
const WAIT_MS = Number(process.env.WAIT_MS || 10 * 60e3);
const RUN_MS = Number(process.env.RUN_MS || 90e3);

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

function pump() {
  while (queue.length && running < MAX_PAR && busyShare() <= BUSY_SHARE) {
    const job = queue.shift();
    if (Date.now() - job.at > WAIT_MS) { stats.refusedLate++; job.res.writeHead(503).end('{"error":"waited too long"}'); continue; }
    forward(job);
  }
}
setInterval(pump, 500);

function forward({ req, body, res }) {
  start();
  let done = false;
  const finish = () => { if (!done) { done = true; end(); pump(); } };
  const up = http.request({ host: MODEL_URL.hostname, port: MODEL_URL.port, path: req.url, method: req.method,
    headers: { ...req.headers, host: MODEL_URL.host } }, upRes => {
    res.writeHead(upRes.statusCode || 502, upRes.headers);
    upRes.pipe(res);
    upRes.on('end', () => { stats.served++; finish(); });
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
