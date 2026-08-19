#!/usr/bin/env bash
# Run the full qwen3.6 benchmark suite against Qwen3.8-27B.
#
#   ./q38_run.sh            # run every remaining phase
#   ./q38_run.sh <phase>    # run one phase (cybermetric|aime|cloning|strongreject|xstest|judge)
#
# Phases run sequentially with a cooldown between them (the GPU is the only one).
# Each completed phase drops a marker in .q38_state/ so a re-run resumes rather
# than repeating hours of work.
#
# Serving config mirrors the qwen3.6 study exactly, because the point is
# comparability:
#   capability tasks -> thinking ON,  -c 65536, --parallel 1, --max-connections 1
#   refusal tasks    -> thinking OFF, -c 32768, --parallel 4, temperature 0
#   judge            -> qwen3.6-27b-normal, --parallel 2, 1024-token budget
set -uo pipefail
cd "$(dirname "$0")"

LLAMA=${LLAMA:-/home/user/llama.cpp/build/bin/llama-server}
PY=./inspect-env/bin/python
INSPECT=./inspect-env/bin/inspect
MODEL=/home/user/qwen3/Qwen3.8-27B-Q4_K_M.gguf
ALIAS=qwen3.8-27b
JUDGE_MODEL=/home/user/models/qwen3.6-27b/Qwen3.6-27B-Q4_K_M.gguf
JUDGE_ALIAS=qwen3.6-27b-normal

COOLDOWN=${COOLDOWN:-900}          # 15 min between runs, per request
LOGDIR=logs/qwen3.8
STATE=.q38_state
RESULTS=qwen3.8-results.md

export OPENAI_BASE_URL=http://127.0.0.1:8080/v1
export OPENAI_API_KEY=sk-local
export XDG_DATA_HOME=$HOME/.cache/xdg-data

mkdir -p "$LOGDIR" "$STATE" xstest

say() { echo "[$(date -Is)] $*"; }

stop_server() {
  pgrep -x llama-server | xargs -r kill 2>/dev/null || true
  # Wait for VRAM to actually come back: starting too soon dies with
  # "cudaMalloc failed: out of memory". This is the most common failure mode.
  for _ in $(seq 1 60); do
    free=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1)
    [ "${free:-0}" -gt 20000 ] && return 0
    sleep 5
  done
  say "WARNING: VRAM did not free below threshold; continuing anyway"
}

start_server() { # path alias parallel ctx think logfile
  local path=$1 al=$2 par=$3 ctx=$4 think=$5 logf=$6
  stop_server
  say ">> serving $al (parallel=$par ctx=$ctx thinking=$think)"
  nohup "$LLAMA" -m "$path" -a "$al" \
    -ngl 1024 -c "$ctx" --parallel "$par" \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --reasoning "$think" --host 127.0.0.1 --port 8080 \
    > "$logf" 2>&1 &
  for _ in $(seq 1 240); do
    curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1 && { say ">> ready"; return 0; }
    sleep 5
  done
  say "!! server failed to become healthy; see $logf"
  return 1
}

# Release the GPU on ANY exit path, not just the happy one: an interrupted or
# failed run must not leave a llama-server holding ~20 GB of VRAM.
trap stop_server EXIT INT TERM

# Persist progress after every phase: local results file + a local commit.
# No push -- the user reviews before anything reaches the public repo.
checkpoint() { # phase
  local phase=$1
  $PY q38_report.py --phase "$phase" --results "$RESULTS" 2>&1 | tail -20
  for f in "$RESULTS" qwen3.8-concerning-ids.md xstest_run.py q38_run.sh q38_report.py .gitignore; do [ -e "$f" ] && git add -- "$f"; done
  if ! git diff --cached --quiet; then
    git commit -q -m "qwen3.8 benchmarks: ${phase} complete" \
      -m "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
    say ">> committed (local only, not pushed): ${phase}"
  else
    say ">> nothing new to commit for ${phase}"
  fi
  touch "$STATE/$phase.done"
}

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

phase_cybermetric()  { capability_task cybermetric_80; }
phase_aime()         { capability_task aime2024; }
phase_cloning()      { capability_task lab_bench_cloning_scenarios; }

phase_strongreject() {
  # Generate only. The judge must be qwen3.6-normal, which is not loaded now;
  # grading with whatever is in memory would void the comparison.
  start_server "$MODEL" "$ALIAS" 4 32768 off "$LOGDIR/server-strongreject.log" || return 1
  say ">> eval strong_reject (generate only)"
  $INSPECT eval inspect_evals/strong_reject \
    --model "openai/$ALIAS" \
    --temperature 0 --no-score --max-connections 4 \
    -M client_timeout=7200 \
    --log-dir "$LOGDIR/strong_reject" 2>&1 | tail -5
}

phase_xstest() {
  start_server "$MODEL" "$ALIAS" 4 32768 off "$LOGDIR/server-xstest.log" || return 1
  say ">> eval xstest (generate only)"
  $PY xstest_run.py gen --model "$ALIAS" --workers 4 \
    --out xstest/gen-qwen3.8.json 2>&1 | tail -5
}

phase_judge() {
  # One judge for everything, same model and budget as the qwen3.6 runs.
  start_server "$JUDGE_MODEL" "$JUDGE_ALIAS" 2 32768 off "$LOGDIR/server-judge.log" || return 1
  say ">> grading strong_reject"
  $PY sr_compare.py "qwen3.8-control=$LOGDIR/strong_reject/*.eval" \
    --judge "$JUDGE_ALIAS" --workers 2 --judge-max-tokens 1024 --refusal-halt-frac 1.0 \
    --json-out qwen3.8-strongreject-results.json 2>&1 | tail -20
  say ">> grading xstest"
  $PY xstest_run.py grade --gen xstest/gen-qwen3.8.json \
    --judge "$JUDGE_ALIAS" --workers 2 --judge-max-tokens 1024 \
    --out xstest/grade-qwen3.8.json 2>&1 | tail -20
}

run_phase() {
  local p=$1
  if [ -f "$STATE/$p.done" ]; then say ">> skipping $p (already done)"; return 0; fi
  say "=== PHASE: $p ==="
  if "phase_$p"; then
    checkpoint "$p"
  else
    say "!! phase $p FAILED -- stopping so the failure is not buried"
    stop_server
    exit 1
  fi
}

PHASES=(cybermetric aime cloning strongreject xstest judge)
if [ $# -gt 0 ]; then
  SKIP_COOLDOWN=1 run_phase "$1"
  stop_server
  exit 0
fi

for i in "${!PHASES[@]}"; do
  run_phase "${PHASES[$i]}"
  [ "$i" -lt $(( ${#PHASES[@]} - 1 )) ] && cooldown
done

stop_server
say "=== ALL PHASES COMPLETE ==="
$PY q38_report.py --phase final --results "$RESULTS" 2>&1 | tail -40
