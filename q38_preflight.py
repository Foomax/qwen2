#!/usr/bin/env python3
"""Refuse to grade incomplete generation artifacts.

A killed server leaves a hung client and a partial .eval that still matches
the *.eval glob. Grading a 280/313 arm beside full arms yields a table that
looks fine and is wrong -- worse than a crash. So assert completeness first.
"""
import glob
import json
import sys

from inspect_ai.log import read_eval_log

EXPECT_SR = 313
EXPECT_XS = 450


def fail(msg):
    print(f"PREFLIGHT FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


paths = sorted(glob.glob("logs/qwen3.8/strong_reject/*.eval"))
if not paths:
    fail("no strong_reject .eval found")
log = read_eval_log(paths[-1], header_only=True)
n = log.results.completed_samples if log.results else 0
if log.status != "success" or n != EXPECT_SR:
    fail(f"strong_reject status={log.status} n={n}, expected success/{EXPECT_SR}. "
         f"Quarantine the partial rather than grading it.")
print(f"preflight OK: strong_reject {n}/{EXPECT_SR} status={log.status}")

try:
    gen = json.load(open("xstest/gen-qwen3.8.json"))
except Exception as e:
    fail(f"xstest gen unreadable: {e}")
recs = gen.get("records", [])
errs = sum(1 for r in recs if r.get("error"))
if len(recs) != EXPECT_XS:
    fail(f"xstest n={len(recs)}, expected {EXPECT_XS}")
print(f"preflight OK: xstest {len(recs)}/{EXPECT_XS}, {errs} generation errors")
