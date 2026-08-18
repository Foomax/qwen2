#!/usr/bin/env bash
# Run wrapped-StrongREJECT conditions on one model, then grade everything.
#
#   ./sr_run.sh gen normal      control safety_reminder refusal_suppression
#   ./sr_run.sh gen obliterated control safety_reminder refusal_suppression
#   ./sr_run.sh judge
#
# Generation and judging are separate phases because only one 27B fits on the 3090,
# and the judge must be the SAME model for every condition or the comparison is void.
#
# Encodes the serving lessons from the earlier runs:
#   * --parallel N splits the context N ways; size -c accordingly
#   * inspect's --timeout does NOT set the HTTP client timeout; -M client_timeout does
#   * kill via `pgrep -x llama-server` (pkill -f matches its own command line)
set -euo pipefail

cd "$(dirname "$0")"

LLAMA=${LLAMA:-/home/user/llama.cpp/build/bin/llama-server}
PY=./inspect-env/bin/python
INSPECT=./inspect-env/bin/inspect
OUT=logs/sr-wrapped

export OPENAI_BASE_URL=http://127.0.0.1:8080/v1
export OPENAI_API_KEY=sk-local
export XDG_DATA_HOME=$HOME/.cache/xdg-data

model_path() {
  case "$1" in
    normal)      echo /home/user/models/qwen3.6-27b/Qwen3.6-27B-Q4_K_M.gguf ;;
    obliterated) echo /home/user/models/qwen3.6-27b-obliterated/gguf/qwen3.6-27b-obliteratus-Q4_K_M.gguf ;;
    *) echo "unknown model tag: $1 (use 'normal' or 'obliterated')" >&2; exit 1 ;;
  esac
}

stop_server() { pgrep -x llama-server | xargs -r kill 2>/dev/null || true; sleep 3; }
# Release the GPU on interrupt/error too, not just the normal exit path. Without
# this, `set -euo pipefail` skips the trailing stop_server when a phase fails and
# the server survives holding ~20GB (this orphaned one for 3.5h on 2026-08-16).
trap stop_server EXIT INT TERM

start_server() { # path alias parallel ctx logfile
  local path=$1 alias=$2 par=$3 ctx=$4 logf=$5
  stop_server
  echo ">> serving $alias (parallel=$par ctx=$ctx)"
  nohup "$LLAMA" -m "$path" -a "$alias" \
    -ngl 1024 -c "$ctx" --parallel "$par" \
    --cache-type-k q8_0 --cache-type-v q8_0 \
    --reasoning off --host 127.0.0.1 --port 8080 \
    > "$logf" 2>&1 &
  for _ in $(seq 1 180); do
    if curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1; then echo ">> ready"; return 0; fi
    sleep 5
  done
  echo "!! server failed to become healthy; see $logf" >&2; exit 1
}

case "${1:-}" in
  gen)
    MODEL_TAG=${2:?usage: ./sr_run.sh gen <normal|obliterated> <condition...>}
    shift 2
    CONDITIONS=("$@")
    [ ${#CONDITIONS[@]} -eq 0 ] && { echo "give at least one condition" >&2; exit 1; }
    ALIAS="qwen3.6-27b-${MODEL_TAG}"

    start_server "$(model_path "$MODEL_TAG")" "$ALIAS" 4 32768 "logs/server-${MODEL_TAG}-srwrap.log"

    for cond in "${CONDITIONS[@]}"; do
      echo ">> [$MODEL_TAG] condition: $cond"
      mkdir -p "$OUT/${MODEL_TAG}-${cond}"
      $INSPECT eval sr_wrapped.py \
        --model "openai/$ALIAS" \
        -T preset="$cond" -T condition="$cond" -T score=false \
        --temperature 0 --max-connections 4 \
        -M client_timeout=7200 \
        --log-dir "$OUT/${MODEL_TAG}-${cond}" \
        2>&1 | tail -3
    done
    stop_server
    echo ">> generation done for $MODEL_TAG. Run './sr_run.sh judge' when all models are generated."
    ;;

  judge)
    # One judge (stock model) grades every condition of every model, identically.
    shift
    start_server "$(model_path normal)" "qwen3.6-27b-normal" 2 32768 "logs/server-judge-srwrap.log"

    RUNS=()
    if [ $# -gt 0 ]; then
      # explicit label=glob args -> grade only those (faster, focused comparisons)
      RUNS=("$@")
    else
      for d in "$OUT"/*/; do
        [ -d "$d" ] || continue
        label=$(basename "$d")
        compgen -G "$d/*.eval" > /dev/null && RUNS+=("${label}=${d}/*.eval")
      done
      # include the original unwrapped baselines -- IDs align, so they pair directly
      compgen -G "logs/eval-normal/*strong-reject*.eval"      > /dev/null && RUNS+=("normal-baseline=logs/eval-normal/*strong-reject*.eval")
      compgen -G "logs/eval-obliterated/*strong-reject*.eval" > /dev/null && RUNS+=("obliterated-baseline=logs/eval-obliterated/*strong-reject*.eval")
    fi

    [ ${#RUNS[@]} -eq 0 ] && { echo "no logs found under $OUT" >&2; exit 1; }
    echo ">> grading ${#RUNS[@]} runs"
    # --refusal-halt-frac 1.0 makes the halt condition unsatisfiable (n > 1.0*n) while
    # keeping the counter and its warning. The halt exists for REMOTE judges that may
    # decline en masse; this judge is local with --reasoning off and cannot hit the
    # content_filter path, so here it is a tripwire whose only effect would be aborting
    # AFTER generation has already spent the GPU. Warn, don't abort.
    $PY sr_compare.py "${RUNS[@]}" --judge qwen3.6-27b-normal --workers 2 \
        --judge-max-tokens 1024 --refusal-halt-frac 1.0 \
        --json-out sr_wrapped_results.json
    stop_server
    ;;

  *)
    sed -n '2,10p' "$0"; exit 1 ;;
esac
