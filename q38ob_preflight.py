#!/usr/bin/env python3
"""GPU-free preflight for the Qwen3.8-OBLITERATED replication arm.

Everything here is a lessons.txt tripwire that costs nothing to check and hours
to discover late:

  #1  DEFAULTS YOU DID NOT CHOOSE ARE STILL CHOICES -- diff the chat template and
      the GGUF-declared sampling metadata against the stock model. A template
      difference between the two arms is a confound, not a detail.
  #8  GGUF arch strings differ from HF model_type -- confirm the built llama.cpp
      actually knows this arch before queueing anything.
  Integrity -- quant must MATCH the stock arm or the comparison is not like-for-like.
"""
import hashlib
import json
import struct
import subprocess
import sys
from pathlib import Path

STOCK = Path("/home/user/qwen3/Qwen3.8-27B-Q4_K_M.gguf")
OBLIT = Path("/home/user/qwen4/models/Qwen3.8-27B-OBLITERATED-Q4_K_M.gguf")
EXPECT_SHA = "c5e4fe705883e244a468c9e445c8d6ba37fd310b0113e25d2b8a7f2d6f1243e8"
EXPECT_SIZE = 16810714400

_T = {0: "<B", 1: "<b", 2: "<H", 3: "<h", 4: "<I", 5: "<i",
      6: "<f", 7: "<?", 10: "<Q", 11: "<q", 12: "<d"}


def read_kv(path, want):
    """Read GGUF header KV pairs, stopping once every wanted key is seen."""
    got = {}
    with open(path, "rb") as f:
        if f.read(4) != b"GGUF":
            raise SystemExit(f"{path}: not a GGUF file")
        struct.unpack("<I", f.read(4))
        struct.unpack("<Q", f.read(8))
        nkv, = struct.unpack("<Q", f.read(8))

        def rs():
            n, = struct.unpack("<Q", f.read(8))
            return f.read(n).decode("utf-8", "replace")

        def rv(t):
            if t == 8:
                return rs()
            if t == 9:
                et, = struct.unpack("<I", f.read(4))
                n, = struct.unpack("<Q", f.read(8))
                return [rv(et) for _ in range(n)]
            fmt = _T[t]
            return struct.unpack(fmt, f.read(struct.calcsize(fmt)))[0]

        for _ in range(nkv):
            k = rs()
            t, = struct.unpack("<I", f.read(4))
            v = rv(t)
            if k in want:
                got[k] = v
            if len(got) == len(want):
                break
    return got


fails, warns = [], []

# --- 1. integrity + quant match -------------------------------------------------
if not OBLIT.exists():
    raise SystemExit(f"PREFLIGHT FAIL: {OBLIT} missing -- download not finished")
size = OBLIT.stat().st_size
if size != EXPECT_SIZE:
    fails.append(f"size {size} != expected {EXPECT_SIZE} (incomplete download)")
else:
    h = hashlib.sha256()
    with open(OBLIT, "rb") as f:
        for blk in iter(lambda: f.read(1 << 22), b""):
            h.update(blk)
    if h.hexdigest() != EXPECT_SHA:
        fails.append(f"sha256 mismatch: {h.hexdigest()}")
    else:
        print("OK   sha256 verified against the HF LFS oid")

if "Q4_K_M" not in OBLIT.name or "Q4_K_M" not in STOCK.name:
    fails.append("quant mismatch between arms -- comparison would not be like-for-like")
else:
    print("OK   both arms are Q4_K_M (quant is not a free variable)")

# --- 2. arch support in the built llama.cpp -------------------------------------
KEYS = ["general.architecture", "general.name", "tokenizer.chat_template",
        "general.sampling.temp", "general.sampling.top_k", "general.sampling.top_p",
        "qwen35.context_length", "qwen35.block_count", "qwen35.full_attention_interval"]
ob = read_kv(OBLIT, set(KEYS))
st = read_kv(STOCK, set(KEYS))

arch = ob.get("general.architecture")
print(f"OK   obliterated arch = {arch!r}, stock arch = {st.get('general.architecture')!r}")
if arch != st.get("general.architecture"):
    fails.append("architectures differ between arms")

src = Path("/home/user/llama.cpp/src/llama-arch.cpp").read_text()
if f'"{arch}"' not in src:
    fails.append(f"llama.cpp source has no arch string {arch!r}")
else:
    print(f"OK   llama.cpp b9436 registers arch {arch!r}")

# --- 3. lessons.txt #1: templates and declared sampling must match --------------
t_ob, t_st = ob.get("tokenizer.chat_template"), st.get("tokenizer.chat_template")
if t_ob is None or t_st is None:
    warns.append("one arm has no embedded chat template")
elif t_ob == t_st:
    print("OK   chat templates are byte-identical across arms")
else:
    d_ob = hashlib.sha256(t_ob.encode()).hexdigest()[:12]
    d_st = hashlib.sha256(t_st.encode()).hexdigest()[:12]
    warns.append(
        f"CHAT TEMPLATES DIFFER (stock {d_st} vs obliterated {d_ob}; "
        f"{len(t_st)} vs {len(t_ob)} chars). The model card says V3 ships a template "
        f"that prefills an empty thinking block. Any behavioural difference is then "
        f"partly template, not weights. Record it; do not silently inherit it."
    )
    Path("/home/user/qwen4/chat_template_stock.jinja").write_text(t_st)
    Path("/home/user/qwen4/chat_template_obliterated.jinja").write_text(t_ob)
    print("     wrote both templates to /home/user/qwen4/ for diffing")

for k in ("general.sampling.temp", "general.sampling.top_k", "general.sampling.top_p"):
    a, b = st.get(k), ob.get(k)
    if a != b:
        warns.append(f"GGUF-declared {k}: stock={a} obliterated={b}")

print(f"OK   ctx={ob.get('qwen35.context_length')} blocks={ob.get('qwen35.block_count')} "
      f"full_attention_interval={ob.get('qwen35.full_attention_interval')}")

# --- 4. the stock arm we are pairing against must actually be complete ----------
sys.path.insert(0, "/home/user/qwen2")
try:
    from inspect_ai.log import read_eval_log
    import glob
    p = sorted(glob.glob("/home/user/qwen2/logs/qwen3.8/strong_reject/*.eval"))
    if not p:
        warns.append("no stock strong_reject log found to pair against")
    else:
        lg = read_eval_log(p[-1], header_only=True)
        n = lg.results.completed_samples if lg.results else 0
        if lg.status != "success" or n != 313:
            fails.append(f"stock SR log is status={lg.status} n={n}, expected success/313")
        else:
            print(f"OK   stock SR pair log complete: {n}/313")
except ImportError:
    warns.append("inspect_ai not importable from this interpreter (run under inspect-env)")

print()
for w in warns:
    print(f"WARN {w}")
for f_ in fails:
    print(f"FAIL {f_}")
if fails:
    sys.exit(1)
print("\nPREFLIGHT PASS" + (f" ({len(warns)} warnings to record in the writeup)" if warns else ""))
