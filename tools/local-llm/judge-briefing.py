#!/usr/bin/env python3
"""Blind judge for two briefing pages built from the same stories (cloud and local copy of the app).
Usage: OPENAI_API_KEY=... judge-briefing.py <cloud-briefing.html> <local-briefing.html>"""
import json, os, random, re, sys, urllib.request

def data(path):
    return json.loads(re.search(r'<script[^>]*>([\s\S]*?)</script>', open(path).read()).group(1).strip())

def view(b):
    lines = ["DIGEST:"] + [f"- [{x.get('kind')}] {x.get('text')}" for x in b['digest']]
    lines += ["TOP 10:"] + [f"{i + 1}. {s['title']} | storyline: {s.get('storyline') or '-'}" for i, s in enumerate(b['stories'][:10])]
    groups = {}
    for s in b['stories']:
        if s.get('storyline'): groups.setdefault(s['storyline'], []).append(s['title'][:70])
    lines += ["STORYLINES:"] + [f"* {k}: " + ' | '.join(v) for k, v in groups.items()]
    return '\n'.join(lines)

cloud, local = data(sys.argv[1]), data(sys.argv[2])
# Both briefings' stories: each picks its own set, and a story only one of them chose is not "unsupported".
# Each story with every summary written for it: a bullet quoting the local copy's summary is supported
# even when the cloud copy summarised the same story differently.
pool = {}
for s in cloud['stories'] + local['stories']:
    entry = pool.setdefault(s['link'], {'title': s['title'], 'summaries': []})
    if s.get('summary') and s['summary'] not in entry['summaries']: entry['summaries'].append(s['summary'])
stories = '\n'.join(f"- {e['title']} — {' || '.join(e['summaries'])}" for e in pool.values())
flip = random.random() < 0.5
a, b = (view(cloud), view(local)) if flip else (view(local), view(cloud))
prompt = f"""You grade two news briefings built from the same stories. Each has a digest (bullets at the top), a top-10 order and storylines (groups of stories about one ongoing situation).
Stories available (title — summary):
{stories}

BRIEFING A:
{a}

BRIEFING B:
{b}

For each briefing score 1-5: digest_accuracy (every bullet is supported by the stories; nothing mixed up or invented), digest_usefulness (covers what matters most), ranking (the most important stories are on top), storylines (groups are real ongoing situations, not unrelated stories or broad themes). Count major_errors (wrong facts, unrelated stories merged). Then better: "A", "B" or "tie".
Answer JSON only: {{"A":{{"digest_accuracy":n,"digest_usefulness":n,"ranking":n,"storylines":n,"major_errors":n}},"B":{{...}},"better":"A|B|tie","why":"short"}}"""
req = urllib.request.Request('https://api.openai.com/v1/responses',
    data=json.dumps({'model': 'gpt-6-luna', 'input': prompt, 'max_output_tokens': 3000, 'reasoning': {'effort': 'medium'}}).encode(),
    headers={'content-type': 'application/json', 'authorization': 'Bearer ' + os.environ['OPENAI_API_KEY']})
j = json.load(urllib.request.urlopen(req, timeout=300))
text = ''.join(c.get('text', '') for o in j.get('output', []) for c in (o.get('content') or []))
v = json.loads(text[text.index('{'):text.rindex('}') + 1])
c, l = (v['A'], v['B']) if flip else (v['B'], v['A'])
better = v['better'] if v['better'] == 'tie' else ('cloud' if (v['better'] == 'A') == flip else 'local')
print('cloud', c); print('local', l); print('better:', better, '|', v['why'])
