#!/bin/bash
# Runs every AI tool of the app on today's newest stories in two copies of the app, one on the local model
# (through the gate) and one on the cloud model, then grades every tool blind. Nothing touches the real app:
# each copy has its own database snapshot, data folder, port and runtime file; Discord webhooks are cleared.
# Needs: the model server (start-server.sh) and gate.mjs running; OPENAI_API_KEY in the environment.
# Usage: battery.sh <work-dir> [stories=40] [asks=15] [research=15]
set -e
W=${1:?work dir}; N=${2:-40}; ASKS=${3:-15}; RES=${4:-15}
K=$(cd "$(dirname "$0")" && pwd); A="$K/../../backend/apps/api"; mkdir -p "$W" "$K/data"
log() { echo "$(date +%T) $*"; }
backups="$HOME/Library/Application Support/AINewsMacWidget/backups"
cleanup_backups() { rm -f "$backups"/ai-news-2*-before-*-regenerate.db; }

# 1. Fresh copies of the app, one per model, from the real database.
for side in local cloud; do
  pkill -f "dist-$side/server.js" || true
  rm -rf "$A/dist-$side"; cp -R "$A/dist" "$A/dist-$side"; rm -rf "$A/dist-$side/.data"; mkdir -p "$A/dist-$side/.data"
  sqlite3 "$A/prisma/dev.db" ".backup '$W/$side.db'"
  python3 - "$W/$side.db" "$side" <<'EOF'
import json, sqlite3, sys
db = sqlite3.connect(sys.argv[1]); rid, p = db.execute('SELECT id, payload FROM AppState').fetchone(); s = json.loads(p)
s['localLlmBaseUrl'] = 'http://127.0.0.1:18082/v1'
for v in s.get('feedSettings', {}).values():
    if isinstance(v, dict): v.update(discordWebhookUrl='', researchEnabled=True, translationEnabled=True, neutralTitlesEnabled=True)
s['globalAiDefaults'] = {'summaryEnabled': True, 'researchEnabled': True, 'translationEnabled': True, 'neutralTitlesEnabled': True}
db.execute('UPDATE AppState SET payload=? WHERE id=?', (json.dumps(s), rid)); db.commit()
EOF
done
IDS_SQL="SELECT key FROM NewsItemRecord WHERE title <> '' ORDER BY publishedMs DESC LIMIT $N"
sqlite3 -readonly "$W/cloud.db" "$IDS_SQL" > "$W/ids.txt"
IN=$(python3 -c "import sys; print(','.join(\"'\"+l.strip().replace(\"'\",\"''\")+\"'\" for l in open(sys.argv[1]) if l.strip()))" "$W/ids.txt")
for side in local cloud; do
  sqlite3 "$W/$side.db" "UPDATE NewsItemRecord SET summary=NULL, research=NULL, titleBg=NULL, titleEn=NULL, neutralTitle=NULL, neutralTitleBg=NULL, neutralTitleEn=NULL, neutralTitleStatus=NULL, neutralTitleCheckedAtMs=NULL, mood=NULL, newsType=NULL, topicLabelsJson=NULL, linkText=NULL WHERE key IN ($IN)"
done
log "copies ready, $(wc -l < "$W/ids.txt" | tr -d ' ') stories"

# 2. Start both copies.
start_copy() { # side port provider
  (cd "$A" && nohup env PORT=$2 PORT_SEARCH_LIMIT=1 AI_PROVIDER=$3 LOCAL_LLM_BASE_URL=http://127.0.0.1:18082/v1 \
    DATABASE_URL="file:$W/$1.db" AI_NEWS_MAC_WIDGET_RUNTIME_FILE="$W/$1-runtime.json" node "dist-$1/server.js" > "$W/$1.log" 2>&1 < /dev/null &)
  for i in $(seq 1 60); do curl -s -m 1 127.0.0.1:$2/api/health | grep -q '"ok":true' && return; sleep 1; done; echo "copy $1 did not start"; exit 1
}
start_copy local 3100 local; start_copy cloud 3200 openai
PW=$(openssl rand -hex 12)
TOK=$(curl -s -m 10 127.0.0.1:3200/api/auth/register -H 'content-type: application/json' -d "{\"username\":\"battery$(date +%s)\",\"password\":\"$PW\"}" | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")
# The token is checked against the copy's own database; register the same name in the other copy.
TOKL=$(curl -s -m 10 127.0.0.1:3100/api/auth/register -H 'content-type: application/json' -d "{\"username\":\"battery$(date +%s)l\",\"password\":\"$PW\"}" | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")
token() { [ "$1" = 3100 ] && echo "$TOKL" || echo "$TOK"; }
left() { curl -s -m 5 127.0.0.1:$1/api/ops/ai-jobs -H "authorization: Bearer $(token $1)" | python3 -c "import json,sys; print(sum(json.load(sys.stdin)['queue']['countsByKind'].values()))" 2>/dev/null || echo 1; }
waitq() { until [ "$(left $1)" = "0" ]; do sleep 10; done; }
regen() { curl -s -m 60 127.0.0.1:$1/api/maintenance/regenerate -H "authorization: Bearer $(token $1)" -H 'content-type: application/json' -d "$2" > /dev/null; cleanup_backups; }

# 3. Per-story tools, one step at a time on each copy (the cloud copy runs alongside; it costs the Mac nothing).
for P in 3200 3100; do (
  t0=$(date +%s)
  regen $P "{\"kind\":\"summary\",\"limit\":$N}"; waitq $P
  regen $P "{\"kind\":\"translation\",\"limit\":$N}"; waitq $P
  regen $P "{\"kind\":\"neutral_title\",\"limit\":$N}"; waitq $P
  regen $P "{\"kind\":\"research\",\"limit\":$RES}"; waitq $P
  (cd "$K" && NO_ASK=1 GAP_MS=3000 node ws-tools.mjs $P "$W/$([ $P = 3100 ] && echo local || echo cloud).db" /dev/null $N > /dev/null 2>&1); sleep 20; waitq $P
  (cd "$K" && ASK_ONLY=1 GAP_MS=20000 WAIT_MIN=3 node ws-tools.mjs $P "$W/$([ $P = 3100 ] && echo local || echo cloud).db" "$W/ask-$P.json" $ASKS > /dev/null 2>&1)
  echo "$(( $(date +%s) - t0 ))" > "$W/seconds-$P.txt"
  t1=$(date +%s)
  curl -s -m 3600 127.0.0.1:$P/api/briefings/generate -H "authorization: Bearer $(token $P)" -H 'content-type: application/json' -d '{"period":"custom","hours":24}' > "$W/briefing-$P.json"
  echo "$(( $(date +%s) - t1 ))" > "$W/briefing-seconds-$P.txt"
  log "copy $P done"
) & done; wait

# 4. Grade every tool blind, and the two briefings.
cp "$W/ids.txt" "$K/data/battery-ids.txt"
(cd "$K" && POOL=battery-pool.json ARTS=articles-battery.json node -e "
const fs=require('fs'); const {execFileSync}=require('child_process');
const rows=JSON.parse(execFileSync('sqlite3',['-readonly','-json','$W/cloud.db',\"SELECT key AS id, title, link, source, publishedMs, contextText FROM NewsItemRecord WHERE key IN ($IN)\"]).toString());
fs.writeFileSync('data/battery-pool.json', JSON.stringify(rows));" && POOL=battery-pool.json ARTS=articles-battery.json N=$N node fetch-articles.mjs)
cp "$K/data/articles-battery.json" "$K/data/articles-tools.json"
(cd "$K" && ASK_LOCAL="$W/ask-3100.json" ASK_CLOUD="$W/ask-3200.json" node judge-tools.mjs "$W/local.db" "$W/cloud.db" "$W/ids.txt" "$W/judge-tools.json" 2>/dev/null) | tee "$W/results.txt"
page() { python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['item']['id'])" "$1"; }
cp_html=$(ls "$A/dist-cloud/.data/briefings/" | grep "^$(page "$W/briefing-3200.json")" | head -1)
lp_html=$(ls "$A/dist-local/.data/briefings/" | grep "^$(page "$W/briefing-3100.json")" | head -1)
python3 "$K/judge-briefing.py" "$A/dist-cloud/.data/briefings/$cp_html" "$A/dist-local/.data/briefings/$lp_html" | tee -a "$W/results.txt"
echo "per-story tools took: local $(cat "$W/seconds-3100.txt") s, cloud $(cat "$W/seconds-3200.txt") s; briefing: local $(cat "$W/briefing-seconds-3100.txt") s, cloud $(cat "$W/briefing-seconds-3200.txt") s" | tee -a "$W/results.txt"
pkill -f "dist-local/server.js" || true; pkill -f "dist-cloud/server.js" || true
log "battery done: $W/results.txt"
