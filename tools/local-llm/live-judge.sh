#!/bin/bash
# Every minute during a battery run: judges the stories whose outputs just landed in both copies (local and
# cloud), so each result can be acted on at once, and prints one status line with the running tally and the
# newest major local error. Usage: live-judge.sh <battery work dir>
W=${1:?}; K=$(cd "$(dirname "$0")" && pwd); done_file="$W/live-judged.txt"; touch "$done_file"
cols="summary titleBg neutralTitleStatus research mood newsType"
while true; do
  for tool in summary research mood newsType; do
    col=$tool; [ $tool = newsType ] && col=newsType
    sqlite3 -readonly "$W/local.db" "SELECT key FROM NewsItemRecord WHERE key IN (SELECT key FROM NewsItemRecord ORDER BY publishedMs DESC LIMIT 40) AND $col IS NOT NULL AND $col <> ''" 2>/dev/null | sort > "$W/l.$tool"
    sqlite3 -readonly "$W/cloud.db" "SELECT key FROM NewsItemRecord WHERE key IN (SELECT key FROM NewsItemRecord ORDER BY publishedMs DESC LIMIT 40) AND $col IS NOT NULL AND $col <> ''" 2>/dev/null | sort > "$W/c.$tool"
    comm -12 "$W/l.$tool" "$W/c.$tool" | while read -r k; do grep -qxF "$tool|$k" "$done_file" || echo "$k"; done > "$W/new.$tool"
    if [ -s "$W/new.$tool" ]; then
      (cd "$K" && ONLY_TOOLS=$tool node judge-tools.mjs "$W/local.db" "$W/cloud.db" "$W/new.$tool" "$W/live-$tool-$(date +%s).json" > /dev/null 2>&1)
      sed "s/^/$tool|/" "$W/new.$tool" >> "$done_file"
    fi
  done
  python3 - "$W" <<'PY'
import glob, json, sys, collections, time
W = sys.argv[1]; rows = []
for f in sorted(glob.glob(f"{W}/live-*.json")):
    try: rows += [r for r in json.load(open(f)) if not r.get('error')]
    except Exception: pass
t = collections.defaultdict(lambda: [0, 0, 0, 0, 0])
for r in rows:
    x = t[r['tool']]; x[{'local': 0, 'tie': 1, 'cloud': 2}[r['better']]] += 1
    x[3] += (r.get('localScores') or {}).get('worst') == 'major'; x[4] += (r.get('cloudScores') or {}).get('worst') == 'major'
parts = [f"{k} {v[0]}/{v[1]}/{v[2]} major {v[3]}v{v[4]}" for k, v in t.items()]
last = next((r for r in reversed(rows) if (r.get('localScores') or {}).get('worst') == 'major'), None)
print(time.strftime('%H:%M:%S'), '| judged (local/tie/cloud):', '; '.join(parts) or 'none yet', '| newest local major:', (f"[{last['tool']}] {last['why'][:110]}" if last else '-'), flush=True)
PY
  grep -q "battery done" "$W/../battery.log" 2>/dev/null && break
  sleep 60
done
