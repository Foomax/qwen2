#!/usr/bin/env bash
# Generate every wrapper condition in sr_wrappers.json against ONE model, on a fixed
# subset of StrongREJECT. Generation only -- grade afterwards with sr_compare.py.
#
#   ./sr_run_subset.sh obliterated sr_subset_20pct.json
#
# One llama-server for the whole sweep (model load is the expensive part), stopped on
# exit via trap so the GPU is never left held if this dies or is interrupted.
set -euo pipefail
cd "$(dirname "$0")"

MODEL_TAG=${1:?usage: ./sr_run_subset.sh <normal|obliterated> <subset.json>}
SUBSET=${2:?need a subset json}
LLAMA=${LLAMA:-/home/user/llama.cpp/build/bin/llama-server}
INSPECT=./inspect-env/bin/inspect
OUT=logs/sr-subset

export OPENAI_BASE_URL=http://127.0.0.1:8080/v1
export OPENAI_API_KEY=sk-local
export XDG_DATA_HOME=$HOME/.cache/xdg-data

case "$MODEL_TAG" in
  normal)      MODEL=/home/user/models/qwen3.6-27b/Qwen3.6-27B-Q4_K_M.gguf ;;
  obliterated) MODEL=/home/user/models/qwen3.6-27b-obliterated/gguf/qwen3.6-27b-obliteratus-Q4_K_M.gguf ;;
  *) echo "unknown model tag: $MODEL_TAG" >&2; exit 1 ;;
esac

ALIAS="qwen3.6-27b-${MODEL_TAG}"
CONDITIONS=$(python3 -c "import json;print(' '.join(json.load(open('sr_wrappers.json'))))")

stop_server() { pgrep -x llama-server | xargs -r kill 2>/dev/null || true; sleep 3; }
trap stop_server EXIT INT TERM

stop_server
echo ">> serving $ALIAS"
nohup "$LLAMA" -m "$MODEL" -a "$ALIAS" -ngl 1024 -c 32768 --parallel 4 \
  --cache-type-k q8_0 --cache-type-v q8_0 --reasoning off \
  --host 127.0.0.1 --port 8080 > "logs/server-${MODEL_TAG}-subset.log" 2>&1 &
for _ in $(seq 1 180); do
  curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1 && { echo ">> ready"; break; }
  sleep 5
done
curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1 || { echo "!! server never became healthy" >&2; exit 1; }

N=$(python3 -c "import json;print(json.load(open('$SUBSET'))['n_selected'])")
echo ">> $(echo "$CONDITIONS" | wc -w) conditions x $N samples on $ALIAS"

for cond in $CONDITIONS; do
  echo ">> [$MODEL_TAG] condition: $cond"
  mkdir -p "$OUT/${MODEL_TAG}-${cond}"
  $INSPECT eval sr_wrapped.py \
    --model "openai/$ALIAS" \
    -T preset="$cond" -T condition="$cond" -T score=false \
    -T subset_file="$SUBSET" \
    --temperature 0 --max-connections 4 -M client_timeout=7200 \
    --log-dir "$OUT/${MODEL_TAG}-${cond}" 2>&1 | tail -2
done

echo ">> generation done for $MODEL_TAG across all conditions."
