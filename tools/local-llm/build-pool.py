#!/usr/bin/env python3
"""Builds a test pool from the app's own database: N recent stories (one per headline) with the summary
the app actually showed, which is the cloud reference the judge compares against.
Usage: build-pool.py N HOURS [seed]  ->  data/pool.json, data/cloud.json"""
import json, random, sqlite3, sys, time, os
n, hours = int(sys.argv[1]), float(sys.argv[2]); seed = int(sys.argv[3]) if len(sys.argv) > 3 else 11
here = os.path.dirname(os.path.abspath(__file__))
db = sqlite3.connect(f"file:{here}/../../backend/apps/api/prisma/dev.db?mode=ro", uri=True)
since = int((time.time() - hours * 3600) * 1000)
rows = db.execute('SELECT key, title, contextText, link, source, publishedMs, summary FROM NewsItemRecord '
                  'WHERE publishedMs > ? AND title <> "" AND summary IS NOT NULL AND summary <> "" AND summary <> "NO_SUMMARY"', (since,)).fetchall()
random.Random(seed).shuffle(rows)
seen, pool = set(), []
for key, title, ctx, link, source, ms, summary in rows:
    t = title.strip().lower()
    if t in seen: continue
    seen.add(t); pool.append({'id': key, 'title': title, 'contextText': ctx or '', 'link': link, 'source': source, 'publishedMs': ms, 'summary': summary})
    if len(pool) == n: break
os.makedirs(f"{here}/data", exist_ok=True)
json.dump([{k: v for k, v in p.items() if k != 'summary'} for p in pool], open(f"{here}/data/pool.json", 'w'), ensure_ascii=False)
json.dump({'summaries': [{'id': p['id'], 'clean': p['summary'].strip(), 'noSummary': False} for p in pool]}, open(f"{here}/data/cloud.json", 'w'), ensure_ascii=False)
open(f"{here}/data/pool-ids.txt", 'w').write('\n'.join(p['id'] for p in pool))
print(f"{len(pool)} stories from {len(rows)} in the last {hours:g}h, {len({p['source'] for p in pool})} sources")
