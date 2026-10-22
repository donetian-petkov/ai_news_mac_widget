#!/bin/bash
# Restarts the model server when it stops answering while the gate has work for it. At 14:40 on 10-22 the
# server stalled mid-run (its memory was pushed to swap by other apps): no answer to health checks, the
# gate showed one request running and the model 100% busy, and every job waited behind it.
# Checks every 30 s; three failed checks in a row (90 s) with work waiting means a restart.
# Usage: model-watch.sh [log file]   (SLOTS as for start-server.sh, default 2)
K=$(cd "$(dirname "$0")" && pwd); LOG=${1:-/dev/null}; failed=0
while true; do
  work=$(curl -s -m 3 127.0.0.1:18082/gate | python3 -c "import json,sys; j=json.load(sys.stdin); print(j['running'] + j['queued'])" 2>/dev/null || echo 0)
  if curl -s -m 5 127.0.0.1:8081/health | grep -q ok; then failed=0
  elif [ "${work:-0}" -gt 0 ]; then failed=$((failed + 1))
  fi
  if [ $failed -ge 3 ]; then
    echo "$(date +%T) model server not answering for 90 s with $work requests waiting: restarting"
    pkill -f "llama-server --model" ; sleep 3
    SLOTS=${SLOTS:-2} nohup bash "$K/start-server.sh" > "$LOG" 2>&1 < /dev/null &
    for i in $(seq 1 120); do curl -s -m 2 127.0.0.1:8081/health | grep -q ok && break; sleep 1; done
    echo "$(date +%T) model server back after ${i} s"; failed=0
  fi
  sleep 30
done
