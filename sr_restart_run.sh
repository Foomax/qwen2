#!/usr/bin/env bash
# Restart of the three-wrapper full-313 run after the server was killed externally.
# No PID gate this time: qwen2-47 is holding the GPU for us by agreement, so the gate
# would only add a failure mode. Detached so it survives the session.
set -uo pipefail
cd "$(dirname "$0")"
exec >>logs/queued-run.log 2>&1
echo "=== RESTART $(date -Is) (previous attempt killed by external stop_server sweep) ==="

used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
if [ "$used" -ge 5000 ] || pgrep -x llama-server >/dev/null; then
  echo "!! GPU not free (${used} MiB) or a llama-server is up -- NOT starting."; exit 1
fi
echo "=== GPU free (${used} MiB); starting generation ==="

./runlog.sh "RESTART Generate: qwen3.6-abliterated, FULL StrongREJECT (313), refusal_suppression + prefix_injection + deliberation" \
  './sr_run.sh gen obliterated refusal_suppression prefix_injection deliberation' || { echo "!! generation failed"; exit 1; }

./runlog.sh "Grade: 3 new wrappers + all existing full-313 arms, qwen3.6-27b-normal judge" \
  "./sr_run.sh judge \
     'obl-control=logs/eval-obliterated/*strong-reject*.eval' \
     'obl-placebo=logs/sr-wrapped/obliterated-placebo/*.eval' \
     'obl-jailbreak=logs/sr-wrapped/obliterated-jailbreak/*.eval' \
     'obl-responsible=logs/sr-wrapped/obliterated-responsible_assistant/*.eval' \
     'obl-refusal_suppression=logs/sr-wrapped/obliterated-refusal_suppression/*.eval' \
     'obl-prefix_injection=logs/sr-wrapped/obliterated-prefix_injection/*.eval' \
     'obl-deliberation=logs/sr-wrapped/obliterated-deliberation/*.eval'" || { echo "!! grading failed"; exit 1; }

echo "=== RESTART COMPLETE $(date -Is) ==="
