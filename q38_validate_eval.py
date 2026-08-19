#!/usr/bin/env python3
"""Fail unless every .eval matching a glob is complete.

A killed server leaves a partial .eval that still matches *.eval. In the
qwen3.6 runs a 280/313 partial sat beside the good log for hours, separated
only by a hand-renamed filename. Grading a partial beside full arms yields a
table that looks right and is wrong, so verify rather than trust the glob.

    python q38_validate_eval.py 'logs/sr-wrapped/foo/*.eval' 313
"""
import glob
import sys

from inspect_ai.log import read_eval_log

pattern = sys.argv[1]
expect = int(sys.argv[2]) if len(sys.argv) > 2 else 313

paths = sorted(glob.glob(pattern))
if not paths:
    sys.exit(f"VALIDATE FAIL: no files match {pattern}")

bad = []
for p in paths:
    try:
        log = read_eval_log(p, header_only=True)
    except Exception as e:
        bad.append(f"{p}: unreadable ({e})")
        continue
    n = log.results.completed_samples if log.results else 0
    if log.status != "success" or n != expect:
        bad.append(f"{p}: status={log.status} n={n} (expected success/{expect})")

if bad:
    print("VALIDATE FAIL:", file=sys.stderr)
    for b in bad:
        print("  " + b, file=sys.stderr)
    sys.exit(1)
print(f"validate OK: {len(paths)} log(s), all success/{expect}")
