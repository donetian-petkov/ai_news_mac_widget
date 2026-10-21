// Blind judge: the cloud model sees the article text, the headline and two summaries in random order
// (one local, one cloud) and grades each for accuracy and for what it adds beyond the headline.
import fs from 'fs';
const dir = new URL('.', import.meta.url).pathname;
const data = dir + 'data/';
const st = Object.fromEntries(JSON.parse(fs.readFileSync(data + (process.env.POOL || 'pool.json'), 'utf8')).map(s => [s.id, s]));
// The judge reads the full article when there is one, so details from it can be checked.
const arts = fs.existsSync(data + (process.env.ARTS || 'articles.json')) ? JSON.parse(fs.readFileSync(data + (process.env.ARTS || 'articles.json'), 'utf8')) : {};
const cloud = Object.fromEntries(JSON.parse(fs.readFileSync(data + (process.env.CLOUD || 'cloud.json'), 'utf8')).summaries.map(x => [x.id, x.noSummary ? '' : (x.clean || '')]));
const out = [];
const want = Number(process.env.EXPECT || 0);
async function* rowsOf(file) {
  let seen = 0;
  while (true) {
    const lines = fs.existsSync(file) ? fs.readFileSync(file, 'utf8').split('\n').filter(Boolean) : [];
    for (; seen < lines.length; seen++) yield JSON.parse(lines[seen]);
    if (!want || seen >= want) return;
    await new Promise(r => setTimeout(r, 2000));
  }
}
for await (const r of rowsOf(process.argv[2])) {
  const s = st[r.id]; const L = r.summary === 'NO_SUMMARY' ? '' : r.summary; const C = cloud[r.id];
  const flip = Math.random() < 0.5; const A = flip ? C : L, B = flip ? L : C;
  const prompt = `You grade one-sentence Bulgarian news summaries. The reader sees the headline and then the summary.
Headline: ${s.title}
Article text: ${(arts[r.id] || String(s.contextText)).slice(0, 6000)}

Summary A: ${A || '(none)'}
Summary B: ${B || '(none)'}

For each summary: accurate = true only if everything it states is supported by the article text (false if it adds, twists or turns a question into a claim). adds = true if it tells the reader something the headline does not. Then better: "A", "B" or "tie" (a missing summary is worse than an accurate useful one, but better than an inaccurate one).
Answer JSON only: {"A":{"accurate":bool,"adds":bool},"B":{"accurate":bool,"adds":bool},"better":"A|B|tie","why":"short"}`;
  const res = await fetch('https://api.openai.com/v1/responses', { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${process.env.OPENAI_API_KEY}` },
    body: JSON.stringify({ model: 'gpt-6-luna', input: prompt, max_output_tokens: 1500, reasoning: { effort: 'medium' } }) });
  const j = await res.json();
  const text = (j.output || []).flatMap(o => o.content || []).map(c => c.text || '').join('');
  let v; try { v = JSON.parse(text.slice(text.indexOf('{'), text.lastIndexOf('}') + 1)); } catch { v = null; }
  if (!v) { out.push({ id: r.id, error: j.error?.message || text.slice(0, 100) }); continue; }
  const loc = flip ? v.B : v.A, clo = flip ? v.A : v.B;
  const better = v.better === 'tie' ? 'tie' : ((v.better === 'A') === !flip ? 'local' : 'cloud');
  out.push({ id: r.id, title: s.title, local: L, cloud: C, localAcc: !!L && loc.accurate, localAdds: !!L && loc.adds, cloudAcc: !!C && clo.accurate, cloudAdds: !!C && clo.adds, better, why: v.why });
  const n0 = out.filter(x => !x.error), k = key => n0.filter(x => x[key]).length;
  console.log(`${n0.length}: ${out.at(-1).better === 'local' ? 'LOCAL better' : out.at(-1).better === 'tie' ? 'tie' : 'cloud better'}${out.at(-1).localAcc || !out.at(-1).local ? '' : ' (local INACCURATE)'} | running: local ${n0.filter(x => x.better === 'local').length} / tie ${n0.filter(x => x.better === 'tie').length} / cloud ${n0.filter(x => x.better === 'cloud').length}; accurate local ${k('localAcc')} cloud ${k('cloudAcc')}`);
}
fs.writeFileSync(process.argv[3], JSON.stringify(out, null, 1));
const n = out.filter(x => !x.error); const c = k => n.filter(x => x[k]).length;
console.log(`\njudged ${n.length}: local accurate ${c('localAcc')}, adds ${c('localAdds')} | cloud accurate ${c('cloudAcc')}, adds ${c('cloudAdds')} | better: local ${n.filter(x => x.better === 'local').length}, cloud ${n.filter(x => x.better === 'cloud').length}, tie ${n.filter(x => x.better === 'tie').length}`);
