// Fetches each story's page the way the app does: the longest <article> that fits the headline, else the
// page's paragraphs when the <article> is only a headline card (news-agency pages), up to 6000 chars.
import fs from 'fs';
const dir = new URL('.', import.meta.url).pathname;
const data = dir + 'data/';
const stories = JSON.parse(fs.readFileSync(data + (process.env.POOL || 'pool.json'), 'utf8')).slice(0, Number(process.env.N || 40));
const strip = h => h.replace(/<script[\s\S]*?<\/script>/gi, ' ').replace(/<style[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, ' ')
  .replace(/&nbsp;/g, ' ').replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&#\d+;|&[a-z]+;/g, ' ').replace(/\s+/g, ' ').trim();
const out = {};
await Promise.all(stories.map(async s => {
  try {
    const ctrl = new AbortController(); const t = setTimeout(() => ctrl.abort(), 9000);
    const r = await fetch(s.link, { signal: ctrl.signal, headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh) live-news-ai/1.0', Accept: 'text/html' } });
    clearTimeout(t);
    if (!r.ok || !(r.headers.get('content-type') || '').includes('text/html')) return;
    const html = await r.text();
    const stems = t => new Set((t.toLowerCase().match(/[\p{L}\p{N}]{5,}/gu) || []).map(w => w.slice(0, 5)));
    const head = stems(s.title || ''); const fits = t => { const b = stems(t); return head.size ? [...head].filter(w => b.has(w)).length / head.size : 0; };
    const arts = (html.match(/<article[\s\S]*?<\/article>/gi) || []).map(strip).filter(t => fits(t.slice(0, 3000)) >= 0.34).sort((a, b) => b.length - a.length);
    const paras = (html.match(/<p[\s>][\s\S]*?<\/p>/gi) || []).map(strip).filter(t => t.length > 60).join(' ');
    out[s.id] = (arts[0] && arts[0].length >= 600 ? arts[0] : paras.length >= 600 ? paras : arts[0] || strip(html)).slice(0, 6000);
  } catch {}
}));
fs.writeFileSync(data + (process.env.ARTS || 'articles.json'), JSON.stringify(out));
const L = Object.values(out).map(x => x.length).sort((a, b) => a - b);
console.log(`fetched ${L.length}/${stories.length}; median ${L[L.length >> 1]} chars`);
