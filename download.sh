#!/usr/bin/env bash
# Downloads Qwen3.8-27B-OBLITERATED GGUFs.
# Q4_K_M is chosen to MATCH the stock model at /home/user/qwen3/Qwen3.8-27B-Q4_K_M.gguf,
# so the stock-vs-obliterated comparison stays like-for-like (quant is not a free variable).
set -u
BASE="https://huggingface.co/OBLITERATUS/Qwen3.8-27B-OBLITERATED/resolve/main"
DEST="/home/user/qwen4/models"

declare -A SHA=(
  ["Qwen3.8-27B-OBLITERATED-Q4_K_M.gguf"]="c5e4fe705883e244a468c9e445c8d6ba37fd310b0113e25d2b8a7f2d6f1243e8"
  ["mmproj-model-bf16.gguf"]="42cee4f70c7c26bee4dc7e59872ceab4c67d1f6b2c87d9c32725ba1e2eaa9a4d"
)
declare -A SIZE=(
  ["Qwen3.8-27B-OBLITERATED-Q4_K_M.gguf"]="16810714400"
  ["mmproj-model-bf16.gguf"]="931145888"
)

for F in "Qwen3.8-27B-OBLITERATED-Q4_K_M.gguf" "mmproj-model-bf16.gguf"; do
  echo "=== $(date -Is) starting $F ==="
  curl -L --fail --retry 20 --retry-delay 5 --retry-all-errors \
       --continue-at - --speed-time 60 --speed-limit 1000 \
       -o "$DEST/$F" "$BASE/$F"
  rc=$?
  got=$(stat -c%s "$DEST/$F" 2>/dev/null || echo 0)
  echo "=== $(date -Is) curl rc=$rc  size=$got  expected=${SIZE[$F]} ==="
  if [ "$got" != "${SIZE[$F]}" ]; then echo "!!! SIZE MISMATCH for $F"; continue; fi
  echo "--- verifying sha256 (this takes a minute) ---"
  sum=$(sha256sum "$DEST/$F" | cut -d' ' -f1)
  if [ "$sum" = "${SHA[$F]}" ]; then echo "OK  sha256 verified: $F"; else echo "!!! SHA MISMATCH $F got=$sum"; fi
done
echo "=== ALL DONE $(date -Is) ==="
ls -la "$DEST"
