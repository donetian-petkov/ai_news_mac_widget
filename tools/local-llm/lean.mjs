// Lean version of flow.mjs: the model writes as little as possible and several stories run at once,
// inside hard limits on parallel work, busy time, queue length, memory and heat (see pool()).
import fs from 'fs';
import { execSync } from 'node:child_process';
import { buildAiRatingPrompt, parseAiRatings, sameEventTitles } from '../../backend/apps/api/dist/briefing.js';
import { cleanSummary } from '../../backend/apps/api/dist/summaryText.js';
import { AI_RULES } from '../../backend/apps/api/dist/aiRules.js';
const [,, outFile] = process.argv;
const dir = new URL('.', import.meta.url).pathname;
const data = dir + 'data/';
// Every prompt starts with the app's own no-invention rules (the same text every provider gets).
const guide = name => AI_RULES + '\n\n' + fs.readFileSync(dir + 'guides/' + name + '.md', 'utf8');
const all = JSON.parse(fs.readFileSync(data + (process.env.POOL || 'pool.json'), 'utf8'));
const MODEL = process.env.LOCAL_MODEL;
const SUM_N = Number(process.env.SUM_N || 40);
let calls = 0, busyMs = 0, outTokens = 0;
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function ask(prompt, maxTokens, format) {
  calls++;
  if (process.env.LLAMA_URL) {
    // llama-server directly: Ollama forces Qwen 3.5 to one request at a time, llama-server runs PAR slots together.
    // Every call has a hard time limit, so a stuck server can never hold the queue.
    const ctrl = new AbortController(); const timer = setTimeout(() => ctrl.abort(), CALL_TIMEOUT_MS);
    busyStart();
    let r;
    try { r = await fetch(process.env.LLAMA_URL + '/v1/chat/completions', { signal: ctrl.signal, method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ messages: [{ role: 'user', content: prompt }], temperature: 0, max_tokens: maxTokens, cache_prompt: true,
        response_format: { type: 'json_schema', json_schema: { name: 'answer', strict: true, schema: format } } }) }); }
    catch { busyEnd(); clearTimeout(timer); timeouts++; return ''; }
    const j = await r.json().catch(() => ({}));
    busyEnd(); clearTimeout(timer);
    outTokens += j.usage?.completion_tokens || 0;
    return j.choices?.[0]?.message?.content || '';
  }
  const r = await fetch('http://localhost:11434/api/chat', { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ model: MODEL, messages: [{ role: 'user', content: prompt }], stream: false, think: false, format, options: { temperature: 0, num_predict: maxTokens, num_ctx: 6144 } }) });
  const j = await r.json();
  outTokens += j.eval_count || 0;
  return j.message?.content || '';
}
// Limits that hold however much news arrives, so a flood can never push the Mac to its limit:
// - at most MAX_PAR stories in work at once (the model server has exactly that many slots);
// - the model may be busy at most BUSY_SHARE of any minute; above that new stories wait;
// - at most QUEUE_MAX stories wait; beyond that the oldest are skipped (they keep the cloud or no summary);
// - a story that waited longer than STORY_DEADLINE_MS is skipped rather than worked on late;
// - every call has CALL_TIMEOUT_MS; the server's health is checked before each story;
// - macOS reporting serious heat, free memory under 6 GB, or swap growing by 1 GB pauses new work.
const MAX_PAR = Number(process.env.PAR || 3);
const BUSY_SHARE = Number(process.env.BUSY_SHARE || 0.6);
const QUEUE_MAX = Number(process.env.QUEUE_MAX || 60);
const STORY_DEADLINE_MS = Number(process.env.STORY_DEADLINE_MS || 20 * 60e3);
const CALL_TIMEOUT_MS = Number(process.env.CALL_TIMEOUT_MS || 45e3);
let inflight = 0, busySince = 0, timeouts = 0;
const busyLog = []; // [start, end] periods with at least one call running
const busyStart = () => { if (inflight++ === 0) busySince = Date.now(); };
const busyEnd = () => { if (--inflight === 0) { busyLog.push([busySince, Date.now()]); busyMs += Date.now() - busySince; } };
const busyShareLastMinute = () => {
  const now = Date.now(), from = now - 60e3;
  let b = busyLog.filter(([, e]) => e > from).reduce((a, [st, e]) => a + (e - Math.max(st, from)), 0);
  if (inflight > 0) b += now - Math.max(busySince, from);
  while (busyLog.length && busyLog[0][1] < from) busyLog.shift();
  return b / 60e3;
};
const freeGB = () => { try { const v = String(execSync('vm_stat')); const pg = k => Number((v.match(new RegExp(k + ':\\s+(\\d+)')) || [])[1] || 0); return (pg('Pages free') + pg('Pages inactive') + pg('Pages speculative')) * 16384 / 1e9; } catch { return 99; } };
const swapMB = () => { try { return Number(String(execSync('sysctl -n vm.swapusage')).match(/used = ([\d]+)/)[1]); } catch { return 0; } };
const heat = () => { try { return Number(String(execSync(dir + 'bin/thermal')).trim()); } catch { return 0; } };
const swapAtStart = swapMB();
const serverUp = async () => { try { const r = await fetch(process.env.LLAMA_URL + '/health', { signal: AbortSignal.timeout(3000) }); return r.ok; } catch { return false; } };
const events = [];
const note = e => { events.push([Date.now(), e]); process.stderr.write(`\n[${new Date().toTimeString().slice(0, 8)}] ${e}\n`); };
async function pool(items, fn) {
  const queued = items.map(item => ({ item, at: Date.now() }));
  if (queued.length > QUEUE_MAX) { note(`overflow: ${queued.length - QUEUE_MAX} oldest stories skipped`); queued.splice(0, queued.length - QUEUE_MAX); }
  const res = []; let running = 0;
  const mayStart = async () => {
    for (;;) {
      const h = heat(), mem = freeGB(), swap = swapMB() - swapAtStart, share = busyShareLastMinute();
      if (h >= 2) { note('paused: macOS reports serious heat'); await sleep(30e3); continue; }
      if (mem < 6 || swap > 1000) { note(`paused: free memory ${mem.toFixed(1)} GB, swap +${swap} MB`); await sleep(15e3); continue; }
      if (share > BUSY_SHARE) { await sleep(1000); continue; }
      if (process.env.LLAMA_URL && !(await serverUp())) { note('paused: model server not answering'); await sleep(5e3); continue; }
      return;
    }
  };
  await new Promise(done => {
    const next = async () => {
      if (!queued.length) { if (running === 0) done(); return; }
      const { item, at } = queued.shift();
      if (Date.now() - at > STORY_DEADLINE_MS) { note('skipped one story: waited past its deadline'); return next(); }
      running++;
      await mayStart();
      Promise.resolve(fn(item)).then(r => res.push(r), () => {}).finally(() => { running--; next(); });
      if (running < MAX_PAR) next();
    };
    for (let k = 0; k < Math.min(MAX_PAR, queued.length); k++) next();
  });
  return res;
}
const json = t => { try { return JSON.parse(t); } catch { return null; } };
const stem = t => (t.toLowerCase().match(/[а-яa-z0-9]{4,}/g) || []).map(w => w.slice(0, 5));
const novelty = (text, headline) => { const h = new Set(stem(headline)); const w = stem(text); return w.length ? w.filter(x => !h.has(x)).length / w.length : 0; };
const words = s => s.split(/\s+/).filter(Boolean).length;
const out = { model: MODEL, par: MAX_PAR, summaries: [], rating: null, grouping: null };
const strict = (props) => ({ type: 'object', additionalProperties: false, required: Object.keys(props), properties: props });

// Summary: at most 3 short facts, code drops weak ones, the model picks the best by number.
let t0 = Date.now();
const ARTICLES = process.env.ARTICLE ? JSON.parse(fs.readFileSync(data + (process.env.ARTS || 'articles.json'), 'utf8')) : {};
const ONLY = process.env.ONLY_IDS ? new Set(fs.readFileSync(process.env.ONLY_IDS, 'utf8').split('\n').filter(Boolean)) : null;
out.summaries = await pool(ONLY ? all.filter(s => ONLY.has(s.id)) : all.slice(0, SUM_N), async s => {
  const factsGuide = /[а-яА-Я]/.test(s.title) ? guide('facts') : guide('facts').replace('one short Bulgarian sentence', 'one short English sentence');
  // With ARTICLE set the model reads the whole fetched article (up to 6000 chars), not just the feed snippet.
  // Straight quotes in the article ("Продължаваме промяната") get copied into the answer and end the JSON
  // string mid-fact; the model copies Bulgarian „…“ quotes safely, so the text is given with those.
  const ctx = (ARTICLES[s.id] || String(s.contextText)).replace(/&[a-z]+;/g, ' ').replace(/"([^"\n]{1,80})"/g, '„$1“').replace(/"/g, '“').slice(0, ARTICLES[s.id] ? 6000 : 1600);
  const f = json(await ask(`${factsGuide}\n- List at most 3 facts, the most important first, each at most 15 words.\n- Write every fact in the language of the headline.\n- For names in quotes use „ and “, never the " character (it ends the JSON string).\n\nHeadline: ${s.title.replace(/"/g, '“')}\nText: ${ctx}\nAnswer:`, 220, strict({ facts: { type: 'array', maxItems: 3, items: { type: 'string' } } })));
  const facts = (f?.facts || []).map(x => String(x).trim()).filter(Boolean);
  const source = (s.title + ' ' + ctx).toLowerCase();
  // English article, Bulgarian facts: names come back transliterated (Jack Avery -> Джак Авери), so only
  // numbers can be checked against the text there.
  const latinSource = !/[а-яА-Я]{20,}/.test(ctx);
  const grounded = x => (x.match(latinSource ? /\d+(?:[.,]\d+)?/g : /[A-ZА-Я][a-zа-я]{2,}|\d+(?:[.,]\d+)?/g) || []).slice(latinSource ? 0 : 1).every(tok => source.includes(tok.toLowerCase().slice(0, Math.max(4, tok.length - 2))));
  const asks = /\?|\bли\b/i.test(s.title);
  // Remarks about the text itself ("the text is cut off") are not news.
  const keep = list => list.filter(x => !/текст|статия|не съдържа|информация/i.test(x) && words(x) >= 5 && words(x) <= 22 && !/\.\.\.|…/.test(x) && grounded(x) && (x.match(/„/g) || []).length === (x.match(/“/g) || []).length)
    .map(x => ({ x, n: novelty(x, s.title) })).filter(c => c.n >= (asks ? 0.6 : 0.5))
    // A headline that asks a question must not come back as a claim ("may take over the government").
    .filter(c => !asks || !/може да|вероятно|възможно|ще поеме/i.test(c.x));
  let usable = keep(facts);
  // Second try when every fact only repeated the headline (or none came back): show the model what the
  // headline already says and ask only for what it leaves out.
  if (!usable.length) {
    const more = json(await ask(`${factsGuide}\n- The reader already knows the headline. Give 2 facts from the text that the headline does NOT say: a cause, a result, a number, a name, a date, a place.\n- Each fact in the language of the headline, at most 15 words.\n\nHeadline: ${s.title.replace(/"/g, '“')}\nText: ${ctx}\nAnswer:`, 220, strict({ facts: { type: 'array', maxItems: 2, items: { type: 'string' } } })));
    const extra = (more?.facts || []).map(x => String(x).trim()).filter(Boolean);
    facts.push(...extra); usable = keep(extra);
  }
  // One call writes the summary from the checked facts (it was two: pick one, then merge two).
  // The result is kept only if it passes the same checks as a fact and keeps every caution word;
  // otherwise the best-ranked single fact is the summary.
  const english = !/[а-яА-Я]/.test(s.title);
  const ranked = usable.slice().sort((a, b) => b.n - a.n);
  let text = ranked[0]?.x.trim();
  if (ranked.length > 1) {
    const m = json(await ask(`Write ONE news summary sentence of at most 22 words, in the language of the headline, for a reader who has already seen the headline. Use the one or two most important of these facts; tell what the headline leaves out. Keep every name and number exactly, keep each statement with the person who made it, and keep every caution word (може да, твърди, според, предполага, alleged, accused, trying to, may). Add nothing else.\nHeadline: ${s.title.replace(/"/g, '“')}\n${ranked.slice(0, 3).map((c, i) => `Fact ${i + 1}: ${c.x}`).join('\n')}\nAnswer with JSON: {"sentence":"..."}`, 120, strict({ sentence: { type: 'string' } })));
    const merged = String(m?.sentence || '').trim();
    const hedges = /може да|твърди|според|предполага|вероятно|alleged|accused|trying to|may |reportedly/gi;
    const used = ranked.slice(0, 3).filter(c => stem(c.x).some(w => stem(merged).includes(w)));
    const hedged = [...new Set(used.map(c => c.x).join(' ').match(hedges)?.map(h => h.toLowerCase()) || [])];
    if (merged && hedged.every(h => merged.toLowerCase().includes(h)) && (english || /[а-яА-Я]/.test(merged)) && words(merged) <= 24 && grounded(merged) && novelty(merged, s.title) >= 0.5 && !/текст|статия/i.test(merged)) text = merged;
  }
  if (text && !english && !/[а-яА-Я]/.test(text)) {
    const tr = json(await ask(`Translate this news sentence into natural Bulgarian. Keep names and numbers exact.\nSentence: ${text}\nAnswer with JSON: {"bg":"..."}`, 80, strict({ bg: { type: 'string' } })));
    text = /[а-яА-Я]/.test(tr?.bg || '') ? tr.bg.trim() : undefined;
  }
  process.stderr.write('.');
  const row = { id: s.id, title: s.title, facts, summary: text ? cleanSummary(/[.!?…]$/.test(text) ? text : text + '.') || 'NO_SUMMARY' : 'NO_SUMMARY', how: text ? 'fact' : 'no new fact' };
  // Each result lands on disk at once, so it can be checked while the run goes on.
  fs.appendFileSync(outFile + '.live.jsonl', JSON.stringify(row) + '\n');
  return row;
});
out.summaryMs = Date.now() - t0;
fs.writeFileSync(outFile, JSON.stringify(out, null, 1));
if (process.env.ONLY_IDS) process.exit(0);

// Rating: scores only (reasons get written later, only for the stories the briefing shows).
t0 = Date.now();
const crit = { type: 'integer', minimum: 0, maximum: 3 };
const schema = strict({ ratings: { type: 'array', items: strict({ id: { type: 'string' }, severity: crit, scale: crit, urgency: crit, interest: crit, dimension: { type: 'string' } }) } });
const cands = all.slice(0, 50).map(s => ({ id: s.id, title: s.title, summary: s.summary || String(s.contextText).slice(0, 300), source: s.source, alsoReportedBy: [] }));
const batches = []; for (let i = 0; i < cands.length; i += 3) batches.push(cands.slice(i, i + 3));
const ratings = (await pool(batches, async batch => {
  const got = parseAiRatings(await ask(`${guide('rating')}\n\n${buildAiRatingPrompt(batch, 'bg', 'Bulgaria')}\nThis time give only the numbers and dimension, no Why fields.`, 40 + batch.length * 45, schema));
  return got.filter(g => batch.some(b => b.id === g.id));
})).flat();
out.rating = { ms: Date.now() - t0, ratings };
fs.writeFileSync(outFile, JSON.stringify(out, null, 1));

// Grouping: code picks candidate pairs, the model answers one word per pair.
t0 = Date.now();
const loose = (a, b) => { const x = new Set(stem(a)), y = new Set(stem(b)); return [...x].filter(k => y.has(k)).length >= 2; };
const pairs = [];
for (let i = 0; i < all.length; i++) for (let j = i + 1; j < all.length; j++) {
  const a = all[i], b = all[j];
  if (Math.abs(a.publishedMs - b.publishedMs) > 36 * 3600e3) continue;
  if (sameEventTitles(a.title, b.title) || loose(a.title, b.title)) pairs.push([a, b]);
}
const labelled = await pool(pairs, async ([a, b]) => {
  const r = json(await ask(`${guide('pair-lean')}\n\nA: ${a.title} — ${String(a.summary || a.contextText).slice(0, 200)}\nB: ${b.title} — ${String(b.summary || b.contextText).slice(0, 200)}\nAnswer:`, 10,
    strict({ relation: { type: 'string', enum: ['same', 'related', 'unrelated'] } })));
  return { a: a.id, b: b.id, relation: r?.relation || 'unrelated' };
});
const groups = rel => { const parent = {}; const find = x => parent[x] === undefined || parent[x] === x ? (parent[x] = x) : (parent[x] = find(parent[x]));
  for (const p of labelled.filter(p => rel.includes(p.relation))) parent[find(p.a)] = find(p.b);
  const g = {}; for (const id of new Set(labelled.filter(p => rel.includes(p.relation)).flatMap(p => [p.a, p.b]))) (g[find(id)] ||= []).push(id); return Object.values(g).filter(x => x.length > 1); };
const duplicates = groups(['same']);
const lines = groups(['same', 'related']).filter(ids => !duplicates.some(d => d.length === ids.length && d.every(x => ids.includes(x))));
const storylines = await pool(lines, async ids => {
  const r = json(await ask(`${guide('storyline')}\n\n${ids.map(id => '- ' + all.find(s => s.id === id).title).join('\n')}\nAnswer:`, 30, strict({ name: { type: 'string' } })));
  return { name: r?.name || '', ids };
});
out.grouping = { ms: Date.now() - t0, candidatePairs: pairs.length, labelled, duplicates, storylines };
out.calls = calls; out.busyMs = busyMs; out.outTokens = outTokens; out.events = events; out.timeouts = timeouts;
fs.writeFileSync(outFile, JSON.stringify(out, null, 1));
process.stderr.write(`\ndone in ${calls} calls, busy ${Math.round(busyMs / 1000)}s, ${outTokens} tokens written\n`);
