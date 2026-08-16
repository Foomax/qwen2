"""Per-category breakdown of two graded StrongREJECT runs (uses sr_compare.py's cache).

    python sr_breakdown.py <wrapped.eval> <control.eval>

Aggregate rates only; no completions are printed.
"""

import glob
import hashlib
import json
import os
import sys
from collections import Counter

from inspect_ai.log import read_eval_log

JUDGE = os.environ.get("SR_JUDGE", "qwen3.6-27b-normal")


def cache_key(path: str, judge: str = JUDGE, limit: int = 0) -> str:
    return hashlib.sha256(
        f"{os.path.realpath(path)}|{os.path.getmtime(path)}|{judge}|{limit}".encode()
    ).hexdigest()[:16]


def load_grades(path: str) -> dict:
    f = f"sr_grades/{cache_key(path)}.json"
    if not os.path.exists(f):
        sys.exit(f"no cached grades for {path}; run sr_compare.py first")
    return json.load(open(f))


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    wp = sorted(glob.glob(sys.argv[1]))[-1]
    cp = sorted(glob.glob(sys.argv[2]))[-1]
    gw, gc = load_grades(wp), load_grades(cp)
    cat = {str(s.id): (s.metadata or {}).get("category") for s in read_eval_log(wp).samples}

    def refused(g):
        return g.get("refusal") == 1

    common = [k for k in gw if k in gc and "refusal" in gw[k] and "refusal" in gc[k]]
    print(f"paired n = {len(common)}")

    still = [k for k in common if not refused(gw[k])]
    print(f"\nstill complies in arm A: {len(still)}/{len(common)} = {len(still) / len(common):.1%}")
    for c, n in Counter(cat[k] for k in still).most_common():
        tot = sum(1 for k in common if cat[k] == c)
        print(f"   {c:<45} {n:>2}/{tot}")

    print("\nby category: compliance  B(control) -> A(wrapped)")
    for c in sorted({cat[k] for k in common}):
        ks = [k for k in common if cat[k] == c]
        a = sum(1 for k in ks if not refused(gc[k])) / len(ks)
        b = sum(1 for k in ks if not refused(gw[k])) / len(ks)
        flag = "  <-- worse" if b > a else ""
        print(f"   {c:<45} {a:>5.1%} -> {b:>5.1%}   (n={len(ks)}){flag}")


if __name__ == "__main__":
    main()
