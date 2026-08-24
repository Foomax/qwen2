#!/usr/bin/env python3
"""Refuse to grade incomplete generation artifacts (lessons.txt #4).

A killed server leaves a partial .eval that still matches *.eval and looks fine.
A range test (0 < n < expected) catches a 280/313 partial and misses a 0/313 one.
The load-bearing check is status == "success" AND exact expected n. Assert it
BEFORE grading, not after -- a table built from a partial arm looks correct and
is wrong, which is worse than a crash.
"""
import glob
import json
import sys

from inspect_ai.log import read_eval_log

EXPECT_SR = 313
EXPECT_XS = 450
LOGDIR = "logs/qwen3.8-obliterated"

fails = []


def check_sr():
    paths = sorted(glob.glob(f"{LOGDIR}/strong_reject/*.eval"))
    if not paths:
        return fails.append("no obliterated strong_reject .eval found")
    if len(paths) > 1:
        # Do not silently take the newest: a quarantined partial must be renamed,
        # not out-voted by sort order.
        fails.append(f"{len(paths)} strong_reject logs match; quarantine partials by renaming")
    log = read_eval_log(paths[-1], header_only=True)
    n = log.results.completed_samples if log.results else 0
    if log.status != "success" or n != EXPECT_SR:
        return fails.append(
            f"strong_reject status={log.status} n={n}, expected success/{EXPECT_SR}"
        )
    print(f"OK   strong_reject {n}/{EXPECT_SR} status={log.status}")


def check_xs(path, expect_cap):
    try:
        gen = json.load(open(path))
    except Exception as e:
        return fails.append(f"{path} unreadable: {e}")
    recs = gen.get("records", [])
    if len(recs) != EXPECT_XS:
        return fails.append(f"{path}: n={len(recs)}, expected {EXPECT_XS}")
    if gen.get("max_tokens") != expect_cap:
        fails.append(f"{path}: max_tokens={gen.get('max_tokens')}, expected {expect_cap}")
    errs = sum(1 for r in recs if r.get("error"))
    # lessons.txt #3: cap-hit rate PER SUBSET. Asymmetry is the signal.
    line = []
    for sub in ("safe", "unsafe"):
        rs = [r for r in recs if r["subset"] == sub and not r.get("error")]
        tr = sum(1 for r in rs if r.get("truncated"))
        line.append(f"{sub} {tr}/{len(rs)} ({tr / max(len(rs), 1):.1%})")
    print(f"OK   {path}: {len(recs)}/{EXPECT_XS}, {errs} errors, cap-hit " + " | ".join(line))


check_sr()
for p, cap in [
    ("xstest/gen-qwen3.8-obliterated.json", 256),
    ("xstest/gen-qwen3.8-obliterated-mt1024.json", 1024),
    ("xstest/gen-qwen3.8-mt1024.json", 1024),
]:
    check_xs(p, cap)

if fails:
    print()
    for f in fails:
        print(f"VALIDATION FAIL: {f}", file=sys.stderr)
    sys.exit(1)
print("\nVALIDATION PASS -- safe to grade")
