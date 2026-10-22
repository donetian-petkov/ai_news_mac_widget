// Detailed blind judge for every AI tool the app runs per story. Two copies of the app (one on the local
// model, one on the cloud model) processed the same stories; this reads both databases and has the cloud
// model grade each tool's two outputs, in random order and unlabelled, against the article.
// Usage: OPENAI_API_KEY=... node judge-tools.mjs <local.db> <cloud.db> <ids.txt> <out.json>
import fs from 'fs';
import { execFileSync } from 'child_process';

const [,, localDb, cloudDb, idsFile, outFile] = process.argv;
const ids = fs.readFileSync(idsFile, 'utf8').split('\n').filter(Boolean);
const dir = new URL('.', import.meta.url).pathname;
const arts = fs.existsSync(dir + 'data/articles-tools.json') ? JSON.parse(fs.readFileSync(dir + 'data/articles-tools.json', 'utf8')) : {};

const COLS = ['key', 'itemId', 'neutralTitleStatus', 'title', 'source', 'contextText', 'linkText', 'summary', 'titleBg', 'titleEn', 'neutralTitle', 'neutralTitleBg', 'neutralTitleEn', 'research', 'mood', 'newsType', 'topicLabelsJson'];
const rows = db => {
  const q = `SELECT ${COLS.map(c => `"${c}"`).join(',')} FROM NewsItemRecord WHERE key IN (${ids.map(i => `'${i.replace(/'/g, "''")}'`).join(',')})`;
  return Object.fromEntries(JSON.parse(execFileSync('sqlite3', ['-readonly', '-json', db, q], { maxBuffer: 64e6 }).toString() || '[]').map(r => [r.key, r]));
};
const L = rows(localDb), C = rows(cloudDb);
// Ask-agent answers are not stored by the app; ws-tools.mjs saved them by item id.
const askOf = file => file && fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')).replies || {} : {};
const askL = askOf(process.env.ASK_LOCAL), askC = askOf(process.env.ASK_CLOUD);
for (const [m, a] of [[L, askL], [C, askC]]) for (const r of Object.values(m)) r.ask = a[r.itemId]?.answer || '';

// What a good output looks like for each tool; every output is scored 1-5 on each criterion.
const TOOLS = {
  summary: { get: r => r.summary, good: 'one short sentence for a reader who has seen the headline, adding the most important thing the headline leaves out. The app runs in bilingual mode, so "Bulgarian sentence / English sentence" is the correct shape' },
  titleBg: { get: r => r.titleBg, good: 'a faithful, natural Bulgarian translation of the headline' },
  titleEn: { get: r => r.titleEn, good: 'a faithful, natural English translation of the headline' },
  // Keeping a headline that is already calm is a valid answer, so "unchanged" is shown as the kept headline
  // rather than as a missing output.
  neutralTitle: { get: r => [r.neutralTitle, r.neutralTitleBg, r.neutralTitleEn].filter(Boolean).join(' | ') || (r.neutralTitleStatus === 'unchanged' ? `(kept the original headline) ${r.title}` : ''),
    good: 'a calm, factual headline with no clickbait, exaggeration or emotional words, keeping the real news; keeping the original headline is right when it is already calm and factual' },
  research: { get: r => r.research, good: 'a short detailed briefing (about 150 words) that goes beyond the summary, compares what outlets report, and states nothing the article does not support' },
  mood: { get: r => r.mood, good: 'the correct overall mood of the story' },
  newsType: { get: r => r.newsType, good: 'the correct type of news story' },
  ask: { get: r => r.ask, good: 'a direct answer to "what is the most important point of this story and why does it matter", based only on the article, saying so when the article does not tell' },
  topics: { get: r => (r.topicLabelsJson && r.topicLabelsJson !== '[]') ? r.topicLabelsJson : '', good: 'a short list of topic labels that fit the story' },
};
const CRITERIA = ['faithful', 'hedging', 'informative', 'specific', 'clarity', 'format'];
const CRIT_TEXT = `faithful: everything stated is supported by the article (5) ... invents or twists facts (1)
hedging: keeps who said what and how sure the article is ("may", "alleged", "according to") (5) ... states claims or guesses as facts or credits the wrong person (1)
informative: tells the reader what matters (5) ... says nothing useful (1)
specific: concrete names, numbers, dates, places where they matter (5) ... vague (1)
clarity: natural, correct language with names spelled right (5) ... broken or hard to read (1)
format: follows what the tool should produce (5) ... wrong language, length or shape (1)`;

async function grade(tool, s, a, b) {
  const prompt = `You grade outputs of a news app's AI tool "${tool}". A good output is ${TOOLS[tool].good}.
Headline: ${s.title}
Source: ${s.source}
Article text: ${(arts[s.key] || s.linkText || s.contextText || '').slice(0, 6000)}

Output A: ${a || '(none)'}
Output B: ${b || '(none)'}

Score each output 1-5 on every criterion:
${CRIT_TEXT}
Give each output its worst error: "none", "minor" (small imprecision) or "major" (wrong fact, wrong attribution, claim stated as certain, wrong language or unusable). A missing output scores 1 everywhere with worst error "major".
Then better: "A", "B" or "tie".
Answer JSON only: {"A":{"faithful":n,"hedging":n,"informative":n,"specific":n,"clarity":n,"format":n,"worst":"none|minor|major"},"B":{...},"better":"A|B|tie","why":"short"}`;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const r = await fetch('https://api.openai.com/v1/responses', { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${process.env.OPENAI_API_KEY}` },
        body: JSON.stringify({ model: 'gpt-6-luna', input: prompt, max_output_tokens: 2000, reasoning: { effort: 'medium' } }) });
      const j = await r.json();
      const text = (j.output || []).flatMap(o => o.content || []).map(c => c.text || '').join('');
      return JSON.parse(text.slice(text.indexOf('{'), text.lastIndexOf('}') + 1));
    } catch {}
  }
  return null;
}

const out = [];
const jobs = [];
for (const id of ids) {
  const l = L[id], c = C[id];
  if (!l || !c) continue;
  for (const tool of Object.keys(TOOLS).filter(t => !process.env.ONLY_TOOLS || process.env.ONLY_TOOLS.split(',').includes(t))) {
    const lo = String(TOOLS[tool].get(l) || '').trim(), co = String(TOOLS[tool].get(c) || '').trim();
    if (!lo && !co) continue;
    jobs.push({ id, tool, lo, co, s: l });
  }
}
// A few at a time: the judge is the cloud model, so this costs nothing on the Mac.
for (let i = 0; i < jobs.length; i += 6) {
  await Promise.all(jobs.slice(i, i + 6).map(async ({ id, tool, lo, co, s }) => {
    const flip = Math.random() < 0.5;
    const v = await grade(tool, s, flip ? co : lo, flip ? lo : co);
    if (!v) { out.push({ id, tool, error: true }); return; }
    const local = flip ? v.B : v.A, cloud = flip ? v.A : v.B;
    const better = v.better === 'tie' ? 'tie' : ((v.better === 'A') === !flip ? 'local' : 'cloud');
    out.push({ id, tool, title: s.title, local: lo, cloud: co, localScores: local, cloudScores: cloud, better, why: v.why });
  }));
  process.stderr.write(`${Math.min(i + 6, jobs.length)}/${jobs.length}\n`);
}
fs.writeFileSync(outFile, JSON.stringify(out, null, 1));

// Report: per tool, average of each criterion, wins and major errors.
const avg = (xs, k) => xs.length ? (xs.reduce((a, x) => a + (Number(x[k]) || 0), 0) / xs.length).toFixed(1) : '-';
console.log(`tool | n | better local/tie/cloud | major errors local/cloud | ${CRITERIA.map(k => k + ' L/C').join(' | ')}`);
for (const tool of Object.keys(TOOLS)) {
  const t = out.filter(x => x.tool === tool && !x.error);
  if (!t.length) continue;
  const ls = t.map(x => x.localScores || {}), cs = t.map(x => x.cloudScores || {});
  console.log(`${tool} | ${t.length} | ${t.filter(x => x.better === 'local').length}/${t.filter(x => x.better === 'tie').length}/${t.filter(x => x.better === 'cloud').length} | ${ls.filter(x => x.worst === 'major').length}/${cs.filter(x => x.worst === 'major').length} | ${CRITERIA.map(k => `${avg(ls, k)}/${avg(cs, k)}`).join(' | ')}`);
}
