#!/usr/bin/env bash
# Wait for the download to finish and verify, then start the replication run.
# Kept separate from q38ob_run.sh so that editing the run script is safe right up
# to the moment it actually starts (lessons.txt #7: edits never reach a RUNNING
# bash script -- it holds its own parsed copy).
set -uo pipefail
DL=/home/user/qwen4/download.log
MODEL=/home/user/qwen4/models/Qwen3.8-27B-OBLITERATED-Q4_K_M.gguf
say() { echo "[$(date -Is)] queue: $*"; }

say "waiting for download to complete and verify"
for _ in $(seq 1 720); do            # up to 6h
  if grep -q "ALL DONE" "$DL" 2>/dev/null; then break; fi
  sleep 30
done

if ! grep -q "ALL DONE" "$DL" 2>/dev/null; then
  say "!! download did not finish in time -- NOT starting the GPU run"; exit 1
fi
if ! grep -q "OK  sha256 verified: Qwen3.8-27B-OBLITERATED-Q4_K_M.gguf" "$DL"; then
  say "!! Q4_K_M did not pass sha256 verification -- NOT starting the GPU run"
  grep -E "MISMATCH|rc=|sha256" "$DL" | tail -5
  exit 1
fi
say "download verified: $(stat -c%s "$MODEL") bytes"
say "starting q38ob_run.sh"
exec /home/user/qwen4/q38ob_run.sh
