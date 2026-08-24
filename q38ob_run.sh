#!/usr/bin/env bash
# Replication arm: Qwen3.8-27B-OBLITERATED against the completed Qwen3.8-27B stock run.
#
# This completes the missing cell of the 2x2 (generation x ablation). Serving
# config mirrors q38_run.sh EXACTLY, because the whole point is that the only
# difference between the arms is the weight edit:
#   capability tasks -> thinking ON,  -c 65536, --parallel 1, --max-connections 1
#   refusal tasks    -> thinking OFF, -c 32768, --parallel 4, temperature 0
#   judge            -> qwen3.6-27b-normal, --parallel 2, 1024-token budget
#
# The judge is qwen3.6-27b-normal, NOT qwen3.8. That is deliberate: it is the judge
# that graded both qwen3.6 arms and the qwen3.8 stock control, so it is the one that
# makes this arm comparable to all three. A qwen3.8-judge regrade is a separate pass.
#
# DELIBERATE DEVIATION (one, and it is recorded rather than inherited):
#   XSTest is generated at BOTH max_tokens=256 (matched to every prior arm) and
#   max_tokens=1024 (corrected), and the qwen3.8 STOCK arm is re-generated at 1024
#   too so the corrected comparison is like-for-like. Reason: on the existing stock
#   XSTest artifact 66.4% of SAFE-subset completions end mid-sentence against 21.0%
#   of unsafe ones, and the headline over-refusal number is drawn from exactly that
#   subset. lessons.txt #3: a cap that correlates with what you measure is a
#   confound; #1: if the default is broken, matching it propagates the break.
#   Both caps are run, so nothing is lost and the difference is measurable.
#
# EXCLUDED from this pass: lab_bench_cloning_scenarios. It needs ~12h per arm AND
# the stock qwen3.8 number is still unmeasured (0.121 is the artifact), so it would
# cost ~24h to yield one comparable number. Out of scope for the 80-20 by design,
# not by oversight.
set -uo pipefail
cd /home/user/qwen2                       # harness, venv, grade cache and logs live here

LLAMA=${LLAMA:-/home/user/llama.cpp/build/bin/llama-server}
PY=./inspect-env/bin/python
INSPECT=./inspect-env/bin/inspect

MODEL=/home/user/qwen4/models/Qwen3.8-27B-OBLITERATED-Q4_K_M.gguf
ALIAS=qwen3.8-27b-obliterated
STOCK_MODEL=/home/user/qwen3/Qwen3.8-27B-Q4_K_M.gguf
STOCK_ALIAS=qwen3.8-27b
JUDGE_MODEL=/home/user/models/qwen3.6-27b/Qwen3.6-27B-Q4_K_M.gguf
JUDGE_ALIAS=qwen3.6-27b-normal

COOLDOWN=${COOLDOWN:-900}
LOGDIR=logs/qwen3.8-obliterated
STATE=.q38ob_state
OUT=/home/user/qwen4/results

export OPENAI_BASE_URL=http://127.0.0.1:8080/v1
export OPENAI_API_KEY=sk-local
export XDG_DATA_HOME=$HOME/.cache/xdg-data

mkdir -p "$LOGDIR" "$STATE" "$OUT" xstest

say() { echo "[$(date -Is)] $*"; }

SERVER_PID=""

stop_server() {
  # Kill ONLY the server this script started (lessons.txt #7 -- a bare
  # `pgrep -x llama-server | xargs kill` once destroyed a peer's run).
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  SERVER_PID=""
  for _ in $(seq 1 60); do
    free=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1)
    [ "${free:-0}" -gt 20000 ] && return 0
    sleep 5
  done
  return 0
}

# Someone else's server is on the card: wait, never reclaim.
await_gpu() {
  for _ in $(seq 1 120); do
    free=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1)
    [ "${free:-0}" -gt 20000 ] && return 0
    sleep 10
  done
  say "!! GPU still held by another process after 20 min -- refusing to start (would OOM)"
  return 1
}

start_server() { # path alias parallel ctx think logfile
  local path=$1 al=$2 par=$3 ctx=$4 think=$5 logf=$6
  stop_server
  await_gpu || return 1
  say ">> serving $al (parallel=$par ctx=$ctx thinking=$think)"
  nohup "$LLAMA" -m "$path" -a "$al" \
    -ngl 1024 -c "$ctx" --parallel "$par" \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --reasoning "$think" --host 127.0.0.1 --port 8080 \
    > "$logf" 2>&1 &
  SERVER_PID=$!
  say ">> server pid $SERVER_PID (orchestrator pid $$)"
  for _ in $(seq 1 240); do
    curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1 && { say ">> ready"; break; }
    sleep 5
  done
  if ! curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1; then
    say "!! server failed to become healthy; see $logf"; return 1
  fi
  # lessons.txt #1: read the chat template the server ACTUALLY loaded, and the
  # sampler values it actually defaulted to. Cheapest place to catch a silent
  # config difference between arms.
  say ">> server-reported config for $al:"
  grep -iE "chat template|reasoning|repeat_penalty|dry_multiplier|temp |top_k|top_p|n_ctx" "$logf" \
    | head -20 | sed 's/^/     /'
  nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader | sed 's/^/     vram: /'
  return 0
}

trap stop_server EXIT INT TERM

cooldown() {
  [ "${SKIP_COOLDOWN:-0}" = "1" ] && return 0
  stop_server
  say ">> cooling down ${COOLDOWN}s before next run"
  sleep "$COOLDOWN"
  nvidia-smi --query-gpu=temperature.gpu,memory.free --format=csv,noheader | \
    while read -r l; do say ">> gpu after cooldown: $l"; done
}

capability_task() { # taskname
  local task=$1
  start_server "$MODEL" "$ALIAS" 1 65536 on "$LOGDIR/server-$task.log" || return 1
  say ">> eval $task"
  $INSPECT eval "inspect_evals/$task" \
    --model "openai/$ALIAS" \
    --max-connections 1 \
    -M client_timeout=7200 \
    --log-dir "$LOGDIR/$task" 2>&1 | tail -5
}

phase_preflight() {
  # No GPU. Integrity, quant match, arch support, template diff.
  $PY /home/user/qwen4/q38ob_preflight.py
}

phase_cybermetric() { capability_task cybermetric_80; }
phase_aime()        { capability_task aime2024; }

phase_strongreject() {
  # Generate only. Grading happens in the judge phase under qwen3.6-27b-normal;
  # grading with whatever happens to be resident would void the comparison.
  start_server "$MODEL" "$ALIAS" 4 32768 off "$LOGDIR/server-strongreject.log" || return 1
  say ">> eval strong_reject (generate only)"
  $INSPECT eval inspect_evals/strong_reject \
    --model "openai/$ALIAS" \
    --temperature 0 --no-score --max-connections 4 \
    -M client_timeout=7200 \
    --log-dir "$LOGDIR/strong_reject" 2>&1 | tail -5
}

phase_xstest256() {   # matched to every prior arm
  start_server "$MODEL" "$ALIAS" 4 32768 off "$LOGDIR/server-xstest256.log" || return 1
  $PY xstest_run.py gen --model "$ALIAS" --workers 4 --max-tokens 256 \
    --out xstest/gen-qwen3.8-obliterated.json 2>&1 | tail -8
}

phase_xstest1024() {  # corrected cap, obliterated
  start_server "$MODEL" "$ALIAS" 4 32768 off "$LOGDIR/server-xstest1024.log" || return 1
  $PY xstest_run.py gen --model "$ALIAS" --workers 4 --max-tokens 1024 \
    --out xstest/gen-qwen3.8-obliterated-mt1024.json 2>&1 | tail -8
}

phase_xstest1024_stock() {  # corrected cap, stock -- so the corrected pair is like-for-like
  start_server "$STOCK_MODEL" "$STOCK_ALIAS" 4 32768 off "$LOGDIR/server-xstest1024-stock.log" || return 1
  $PY xstest_run.py gen --model "$STOCK_ALIAS" --workers 4 --max-tokens 1024 \
    --out xstest/gen-qwen3.8-mt1024.json 2>&1 | tail -8
}

phase_judge() {
  # Never grade a partial (lessons.txt #4): status == success AND exact expected n.
  $PY /home/user/qwen4/q38ob_validate.py || { say "!! validation failed -- refusing to grade"; return 1; }
  start_server "$JUDGE_MODEL" "$JUDGE_ALIAS" 2 32768 off "$LOGDIR/server-judge.log" || return 1

  say ">> grading strong_reject (obliterated)"
  # Cache reads are keyed to THIS log, never a directory glob (lessons.txt #5).
  $PY sr_compare.py "qwen3.8-obliterated-control=$LOGDIR/strong_reject/*.eval" \
    --judge "$JUDGE_ALIAS" --workers 2 --judge-max-tokens 1024 --refusal-halt-frac 1.0 \
    --json-out "$OUT/q38ob-strongreject.json" 2>&1 | tail -20

  for g in xstest/gen-qwen3.8-obliterated.json \
           xstest/gen-qwen3.8-obliterated-mt1024.json \
           xstest/gen-qwen3.8-mt1024.json; do
    [ -f "$g" ] || { say "!! missing $g -- skipping"; continue; }
    tag=$(basename "$g" .json | sed 's/^gen-//')
    say ">> grading xstest $tag"
    $PY xstest_run.py grade --gen "$g" --judge "$JUDGE_ALIAS" --workers 2 \
      --judge-max-tokens 1024 --out "$OUT/xstest-$tag-q36judge.json" 2>&1 | tail -12
  done
}

run_phase() {
  local p=$1
  if [ -f "$STATE/$p.done" ]; then say ">> skipping $p (already done)"; return 0; fi
  say "=== PHASE: $p ==="
  if "phase_$p"; then
    touch "$STATE/$p.done"
    say ">> phase $p complete"
  else
    say "!! phase $p FAILED -- stopping so the failure is not buried"
    stop_server
    exit 1
  fi
}

# Ordered by value per GPU-hour, cheapest-and-most-important first, so that killing
# the run partway still leaves the complete refusal-behaviour replication on disk.
# The capability tail (cybermetric, aime) runs last.
PHASES=(preflight strongreject xstest256 xstest1024 xstest1024_stock judge cybermetric aime)
if [ $# -gt 0 ]; then
  SKIP_COOLDOWN=1 run_phase "$1"
  stop_server
  exit 0
fi

for i in "${!PHASES[@]}"; do
  p="${PHASES[$i]}"
  was_done=0; [ -f "$STATE/$p.done" ] && was_done=1
  run_phase "$p"
  # preflight uses no GPU, so there is nothing to cool after it.
  if [ "$was_done" = "0" ] && [ "$p" != "preflight" ] && [ "$i" -lt $(( ${#PHASES[@]} - 1 )) ]; then
    cooldown
  fi
done

stop_server
say "=== ALL PHASES COMPLETE ==="
