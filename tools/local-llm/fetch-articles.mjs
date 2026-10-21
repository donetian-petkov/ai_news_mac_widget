// Fetches each story's page the way the app's Research does (prefer <article>, strip tags), up to 6000 chars.
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
    const art = html.match(/<article[\s\S]*?<\/article>/i)?.[0];
    out[s.id] = strip(art || html).slice(0, 6000);
  } catch {}
}));
fs.writeFileSync(data + (process.env.ARTS || 'articles.json'), JSON.stringify(out));
const L = Object.values(out).map(x => x.length).sort((a, b) => a - b);
console.log(`fetched ${L.length}/${stories.length}; median ${L[L.length >> 1]} chars`);
