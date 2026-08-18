#!/usr/bin/env bash
# Queued: wait for the Qwen3.8 suite to release the GPU, then run the three
# attack/defense wrappers at FULL StrongREJECT (313 items) on qwen3.6-abliterated,
# graded by the local qwen3.6-27b-normal judge (== comparable to every existing arm).
set -uo pipefail
cd "$(dirname "$0")"
WAIT_PID=${1:?need the PID to wait on}
LOG=logs/queued-run.log
exec >>"$LOG" 2>&1
echo "=== queued run armed $(date -Is); waiting on PID $WAIT_PID ==="

# 1. Wait for their orchestrator to exit.
while kill -0 "$WAIT_PID" 2>/dev/null; do sleep 60; done
echo "=== PID $WAIT_PID exited $(date -Is) ==="

# 2. Wait for the GPU to actually drain (their trap/watchdog may lag), max 20 min.
for _ in $(seq 1 80); do
  used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
  [ "$used" -lt 5000 ] && break
  sleep 15
done
used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
if [ "$used" -ge 5000 ]; then
  echo "!! GPU still holds ${used} MiB after 20min -- NOT starting. Something else is running."
  exit 1
fi
if pgrep -x llama-server >/dev/null; then
  echo "!! a llama-server is still up -- NOT starting (not mine to kill)."
  exit 1
fi
echo "=== GPU free (${used} MiB) $(date -Is); starting ==="

# 3. Generate the three conditions at full 313.
./runlog.sh "Generate: qwen3.6-abliterated, FULL StrongREJECT (313), wrappers refusal_suppression + prefix_injection + deliberation" \
  './sr_run.sh gen obliterated refusal_suppression prefix_injection deliberation' || { echo "!! generation failed"; exit 1; }

# 4. Grade with the LOCAL stock judge, alongside every existing full-313 arm.
#    Existing arms are cached (same judge, default max_tokens) so they cost nothing.
./runlog.sh "Grade: 3 new wrappers + all existing full-313 arms, qwen3.6-27b-normal judge" \
  "./sr_run.sh judge \
     'obl-control=logs/eval-obliterated/*strong-reject*.eval' \
     'obl-placebo=logs/sr-wrapped/obliterated-placebo/*.eval' \
     'obl-jailbreak=logs/sr-wrapped/obliterated-jailbreak/*.eval' \
     'obl-responsible=logs/sr-wrapped/obliterated-responsible_assistant/*.eval' \
     'obl-refusal_suppression=logs/sr-wrapped/obliterated-refusal_suppression/*.eval' \
     'obl-prefix_injection=logs/sr-wrapped/obliterated-prefix_injection/*.eval' \
     'obl-deliberation=logs/sr-wrapped/obliterated-deliberation/*.eval'" || { echo "!! grading failed"; exit 1; }

echo "=== queued run COMPLETE $(date -Is) ==="
