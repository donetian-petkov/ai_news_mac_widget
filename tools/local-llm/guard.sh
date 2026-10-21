#!/bin/bash
# Safety net around a local-model run, on top of the limits inside lean.mjs's pool:
# - pauses the run while macOS reports serious heat or free memory is under 6 GB, and resumes after a calm minute;
# - stops the run and the model server outright if free memory falls under 6 GB, swap grows by more than
#   1.5 GB during the run (other apps may already be swapping before it starts), or free disk falls under 15 GB.
# Fans are not a trigger. Logs a status line every 30 s, with fan speed and load for reference.
S=$(dirname "$0"); calm=0; paused=0; tick=0
test_pids() { pgrep -f "local-llm/lean\.mjs" ; }
while true; do
  heat=$("$S/bin/thermal")
  mem=$(vm_stat | awk '/Pages free/ {f=$3} /Pages inactive/ {i=$3} /Pages speculative/ {s=$3} END {printf "%d", (f+i+s)*16384/1e9}')
  disk=$(df -g ~ | tail -1 | awk '{print $4}')
  gpu=$(ioreg -r -d 1 -c IOAccelerator 2>/dev/null | grep -o '"Device Utilization %"=[0-9]*' | head -1 | cut -d= -f2)
  # swapusage prints "584,31M" in this locale: keep only the whole megabytes.
  swap=$(sysctl -n vm.swapusage | awk '{print $6}' | tr -d 'M' | cut -d, -f1 | cut -d. -f1)
  [ -z "$swap0" ] && swap0=${swap:-0}
  if [ "$mem" -lt 6 ] || [ $(( ${swap:-0} - swap0 )) -gt 1500 ] || [ "$disk" -lt 15 ]; then
    for p in $(test_pids); do kill -STOP $p; done; pkill -f "llama-server.*8081"
    echo "$(date +%T) EMERGENCY stop: mem=${mem}GB swap=${swap}MB (+$(( ${swap:-0} - swap0 ))MB since start) disk=${disk}GB"; exit 0
  fi
  fan=$("$S/bin/fans" | awk '{print ($2>$1?$2:$1)}')
  cpu=$(ps -axo %cpu | awk -v n=$(sysctl -n hw.ncpu) 'NR>1 {s+=$1} END {printf "%d", s/n}')
  if [ "$heat" -ge 2 ]; then
    calm=0; [ $paused -eq 0 ] && { for p in $(test_pids); do kill -STOP $p; done; paused=1; echo "$(date +%T) PAUSED: heat=$heat mem=${mem}GB gpu=${gpu}% fan=${fan}rpm"; }
  else
    calm=$((calm+5))
    if [ $paused -eq 1 ] && [ $calm -ge 60 ]; then for p in $(test_pids); do kill -CONT $p; done; paused=0; echo "$(date +%T) RESUMED after 60s calm: mem=${mem}GB gpu=${gpu}%"; fi
  fi
  tick=$((tick+5)); [ $((tick % 30)) -eq 0 ] && echo "$(date +%T) status: fan=${fan}rpm cpu=${cpu}% heat=$heat paused=$paused mem=${mem}GB gpu=${gpu}% disk=${disk}GB swap=${swap}MB"
  sleep 5
done
