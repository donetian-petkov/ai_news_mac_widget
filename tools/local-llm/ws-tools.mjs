// Triggers the app's on-demand AI tools over its socket, the way the widget does: mood, news type and topic
// labels for each story, and one Ask-agent question per story. Ask replies are saved, since the app keeps
// no copy of them. Usage: node ws-tools.mjs <port> <db> <out.json> [count]
import fs from 'fs';
import { execFileSync } from 'child_process';
import { createRequire } from 'module';
const require = createRequire(new URL('../../backend/apps/api/package.json', import.meta.url));
const WebSocket = require('ws');

const [,, port, db, outFile, countRaw] = process.argv;
const count = Number(countRaw || 40);
const items = JSON.parse(execFileSync('sqlite3', ['-readonly', '-json', db,
  `SELECT itemId AS id, feedUrl, title FROM NewsItemRecord ORDER BY publishedMs DESC LIMIT ${count}`]).toString() || '[]');
const question = t => /[а-яА-Я]/.test(t) ? 'Какво е най-важното в тази новина и защо има значение?' : 'What is the most important point of this story and why does it matter?';

const ws = new WebSocket(`ws://127.0.0.1:${port}`);
const replies = {};
ws.on('message', raw => {
  let m; try { m = JSON.parse(String(raw)); } catch { return; }
  if (m.type === 'ask_agent_reply' && m.id) replies[m.id] = { question: m.question, answer: m.answer || m.text || m.reply || '', error: m.error || '' };
});
ws.on('open', async () => {
  for (const it of items) {
    if (!process.env.ASK_ONLY) ws.send(JSON.stringify({ type: 'run_item_auto', id: it.id, feedUrl: it.feedUrl, mood: true, newsType: true, topicLabels: true }));
    if (!process.env.NO_ASK) ws.send(JSON.stringify({ type: 'ask_agent_item', id: it.id, feedUrl: it.feedUrl, question: question(it.title) }));
    // Spaced out so the questions queue in the app, not all at once in front of the model.
    await new Promise(r => setTimeout(r, Number(process.env.GAP_MS || 200)));
  }
  // Ask replies arrive as the model gets to them; wait until all are in or WAIT_MIN passes.
  const until = process.env.NO_ASK ? 0 : Date.now() + Number(process.env.WAIT_MIN || 60) * 60e3;
  while (Object.keys(replies).length < items.length && Date.now() < until) {
    await new Promise(r => setTimeout(r, 5000));
    fs.writeFileSync(outFile, JSON.stringify({ items, replies }, null, 1));
  }
  fs.writeFileSync(outFile, JSON.stringify({ items, replies }, null, 1));
  console.log(`ask replies ${Object.keys(replies).length}/${items.length}`);
  ws.close(); process.exit(0);
});
ws.on('error', e => { console.error('socket error', e.message); process.exit(1); });
