#!/usr/bin/env bash
# Regenerate XSTest on both qwen3.6 models so the Qwen3.8 judge can grade them.
# The original generations were lost with a scratchpad, so this needs GPU.
# Serving config matches the original XSTest runs: thinking off, temp 0.
set -uo pipefail
cd "$(dirname "$0")"
PY=./inspect-env/bin/python
LLAMA=${LLAMA:-/home/user/llama.cpp/build/bin/llama-server}
GAP=${GAP:-600}
STATE=.q38_state
export OPENAI_BASE_URL=http://127.0.0.1:8080/v1 OPENAI_API_KEY=sk-local
export XDG_DATA_HOME=$HOME/.cache/xdg-data
mkdir -p xstest "$STATE"
SERVER_PID=""
say() { echo "[$(date -Is)] $*"; }
stop_server() { [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null && kill "$SERVER_PID" 2>/dev/null; SERVER_PID=""; }
trap stop_server EXIT INT TERM
await_gpu() { for _ in $(seq 1 120); do f=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits|head -1); [ "${f:-0}" -gt 20000 ] && return 0; sleep 10; done; say "!! GPU busy"; return 1; }

run_one() { # tag path
  local tag=$1 path=$2
  [ -f "$STATE/xstest-$tag.done" ] && { say ">> skip $tag"; return 0; }
  stop_server; await_gpu || return 1
  say ">> serving qwen3.6-27b-$tag"
  nohup "$LLAMA" -m "$path" -a "qwen3.6-27b-$tag" -ngl 1024 -c 32768 --parallel 4 \
    --cache-type-k q8_0 --cache-type-v q8_0 --reasoning off \
    --host 127.0.0.1 --port 8080 > "logs/qwen3.8/server-xstest-$tag.log" 2>&1 &
  SERVER_PID=$!
  say ">> server pid $SERVER_PID (orchestrator pid $$)"
  for _ in $(seq 1 240); do curl -sf http://127.0.0.1:8080/health >/dev/null 2>&1 && break; sleep 5; done
  $PY xstest_run.py gen --model "qwen3.6-27b-$tag" --workers 4 --out "xstest/gen-q36-$tag.json" 2>&1 | tail -3
  stop_server
  touch "$STATE/xstest-$tag.done"
}

run_one normal      /home/user/models/qwen3.6-27b/Qwen3.6-27B-Q4_K_M.gguf || exit 1
say ">> ${GAP}s gap"; sleep "$GAP"
run_one obliterated /home/user/models/qwen3.6-27b-obliterated/gguf/qwen3.6-27b-obliteratus-Q4_K_M.gguf || exit 1
say "=== XSTEST REGEN COMPLETE ==="
