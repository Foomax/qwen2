#!/usr/bin/env bash
# Second-judge pass: re-grade every judge-scored log with Qwen3.8-27B.
#
# This produces a SECOND set of numbers, not a replacement. The primary results
# are graded by qwen3.6-27b-normal, which is what makes them comparable to the
# original qwen3.6 study. Cross-judge agreement is the question here.
#
# sr_compare.py keys its grade cache by judge string, so these runs cannot
# collide with, or serve stale grades from, the qwen3.6-normal pass.
set -uo pipefail
cd "$(dirname "$0")"

PY=./inspect-env/bin/python
LLAMA=${LLAMA:-/home/user/llama.cpp/build/bin/llama-server}
JUDGE=/home/user/qwen3/Qwen3.8-27B-Q4_K_M.gguf
JALIAS=qwen3.8-27b
GAP=${GAP:-600}                 # 10 min between runs, per request
OUT=regrade-qwen38judge
STATE=.q38_state/regrade

export OPENAI_BASE_URL=http://127.0.0.1:8080/v1
export OPENAI_API_KEY=sk-local
export XDG_DATA_HOME=$HOME/.cache/xdg-data
mkdir -p "$OUT" "$STATE"

SERVER_PID=""
say() { echo "[$(date -Is)] $*"; }

stop_server() {
  [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null && kill "$SERVER_PID" 2>/dev/null
  SERVER_PID=""
}
trap stop_server EXIT INT TERM

await_gpu() {
  for _ in $(seq 1 120); do
    free=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1)
    [ "${free:-0}" -gt 20000 ] && return 0
    sleep 10
  done
  say "!! GPU held by another process after 20 min -- refusing to start"; return 1
}

await_gpu || exit 1
say ">> loading judge $JALIAS"
nohup "$LLAMA" -m "$JUDGE" -a "$JALIAS" -ngl 1024 -c 32768 --parallel 2 \
  --cache-type-k q8_0 --cache-type-v q8_0 --reasoning off \
  --host 127.0.0.1 --port 8080 > logs/qwen3.8/server-regrade.log 2>&1 &
SERVER_PID=$!
say ">> judge server pid $SERVER_PID (orchestrator pid $$)"
for _ in $(seq 1 240); do
  curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1 && { say ">> ready"; break; }
  sleep 5
done

# label=glob, one grading run each, GAP seconds apart so the card cools.
RUNS=(
  "q36-normal-control=logs/eval-normal/*strong-reject*.eval"
  "q36-obliterated-control=logs/eval-obliterated/*strong-reject*.eval"
  "q38-control=logs/qwen3.8/strong_reject/*.eval"
)
for d in logs/sr-wrapped/*/; do
  compgen -G "$d*.eval" >/dev/null && RUNS+=("$(basename "$d")=$d*.eval")
done

i=0
for r in "${RUNS[@]}"; do
  label=${r%%=*}
  i=$((i+1))
  if [ -f "$STATE/$label.done" ]; then say ">> skip $label (done)"; continue; fi
  say "=== [$i/${#RUNS[@]}] regrading $label"
  # Never grade a partial: a killed server leaves one that still matches *.eval
  if ! $PY q38_validate_eval.py "${r#*=}" 313 2>&1 | tail -5; then
    say "!! $label failed completeness check -- SKIPPING (not grading a partial)"
    continue
  fi
  $PY sr_compare.py "$r" --judge "$JALIAS" --workers 2 \
      --judge-max-tokens 1024 --refusal-halt-frac 1.0 \
      --json-out "$OUT/$label.json" 2>&1 | tail -12
  touch "$STATE/$label.done"
  [ "$i" -lt "${#RUNS[@]}" ] && { say ">> ${GAP}s gap"; sleep "$GAP"; }
done

if [ -f xstest/gen-qwen3.8.json ] && [ ! -f "$STATE/xstest.done" ]; then
  say ">> ${GAP}s gap"; sleep "$GAP"
  say "=== regrading xstest (qwen3.8 gen)"
  $PY xstest_run.py grade --gen xstest/gen-qwen3.8.json --judge "$JALIAS" \
      --workers 2 --judge-max-tokens 1024 --out "$OUT/xstest-qwen38judge.json" 2>&1 | tail -12
  touch "$STATE/xstest.done"
fi

stop_server
say "=== REGRADE COMPLETE ==="
