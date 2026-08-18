#!/usr/bin/env python3
"""Collect whatever Qwen3.8 results exist so far and write them up.

Called after every phase by q38_run.sh. Produces three things:

  qwen3.8-results.md            committed  -- rates, next to the qwen3.6 baselines
  qwen3.8-concerning-ids.md     committed  -- sample IDs + categories only
  qwen3.8-concerning-local.md   GITIGNORED -- the same items with full query text

The split is deliberate: the repo is public and its prompt text was stripped on
purpose, so verbatim harmful queries stay on this machine.
"""

import argparse
import glob
import json
import os
from collections import Counter

LOGDIR = "logs/qwen3.8"
LOCAL_FILE = "qwen3.8-concerning-local.md"
IDS_FILE = "qwen3.8-concerning-ids.md"

# qwen3.6 numbers from results.md, for side-by-side reading.
BASELINE = {
    "cybermetric_80": (0.963, 0.975),
    "aime2024": (0.867, 0.700),
    "lab_bench_cloning_scenarios": (0.485, 0.455),
}


def latest(pattern):
    hits = sorted(glob.glob(pattern))
    return hits[-1] if hits else None


def read_capability(task):
    """Accuracy + stderr from the newest .eval log for a task."""
    path = latest(f"{LOGDIR}/{task}/*.eval")
    if not path:
        return None
    from inspect_ai.log import read_eval_log

    log = read_eval_log(path, header_only=True)
    if not log.results:
        return None
    out = {"status": log.status, "samples": log.results.completed_samples, "path": path}
    for score in log.results.scores:
        for name, m in score.metrics.items():
            if name in ("accuracy", "stderr"):
                out[name] = m.value
    return out


def read_strongreject():
    p = "qwen3.8-strongreject-results.json"
    if not os.path.exists(p):
        return None
    d = json.load(open(p))
    return d.get("qwen3.8-control") or next(iter(d.values()), None)


def read_xstest():
    p = "xstest/grade-qwen3.8.json"
    return json.load(open(p)) if os.path.exists(p) else None


def sr_concerning():
    """StrongREJECT items the model complied with, joined back to prompt+category."""
    grades_path = "qwen3.8-strongreject-results.json"
    log_path = latest(f"{LOGDIR}/strong_reject/*.eval")
    if not (os.path.exists(grades_path) and log_path):
        return []
    # sr_compare caches per-sample grades keyed by sample id under sr_grades/.
    per_sample = {}
    for f in glob.glob("sr_grades/*.json"):
        try:
            d = json.load(open(f))
        except Exception:
            continue
        if any(k.startswith("strong_reject_") for k in d):
            per_sample.update(d)
    if not per_sample:
        return []

    from inspect_ai.log import read_eval_log

    log = read_eval_log(log_path)
    rows = []
    for s in log.samples or []:
        g = per_sample.get(str(s.id))
        if not g or g.get("refusal") != 0:
            continue  # refusal==0 means it complied
        md = s.metadata or {}
        rows.append(
            {
                "id": str(s.id),
                "category": md.get("category") or md.get("Category") or "uncategorised",
                "prompt": md.get("forbidden_prompt") or str(s.input)[:400],
                "convincingness": g.get("convincingness"),
                "specificity": g.get("specificity"),
            }
        )
    return rows


def xstest_concerning():
    """XSTest unsafe prompts the model did NOT refuse."""
    grade = read_xstest()
    if not grade:
        return []
    gen = json.load(open("xstest/gen-qwen3.8.json"))
    prompts = {r["id"]: r for r in gen["records"]}
    rows = []
    for g in grade["records"]:
        if g["subset"] != "unsafe" or g["refused"] is not False:
            continue
        src = prompts.get(g["id"], {})
        rows.append(
            {
                "id": g["id"],
                "category": g["type"],
                "prompt": src.get("prompt", ""),
                "grade": g["grade"],
            }
        )
    return rows


def write_concerning(sr_rows, xs_rows):
    if not sr_rows and not xs_rows:
        return
    # Public: identifiers and category counts only.
    pub = ["# Qwen3.8-27B — items that produced a concerning result", "",
           "Sample IDs and categories only. These rejoin to the public StrongREJECT",
           "and XSTest datasets on `id`; the verbatim query text is kept off this",
           "repository on purpose. See the local file for full text.", ""]
    for title, rows, extra in (
        ("StrongREJECT — complied with a forbidden request", sr_rows, "convincingness"),
        ("XSTest unsafe — did not refuse", xs_rows, "grade"),
    ):
        pub += [f"## {title}", "", f"n = {len(rows)}", ""]
        if rows:
            counts = Counter(r["category"] for r in rows)
            pub += ["| category | n |", "|---|---:|"]
            pub += [f"| {c} | {n} |" for c, n in counts.most_common()]
            pub += ["", "| id | category |", "|---|---|"]
            pub += [f"| `{r['id']}` | {r['category']} |" for r in rows]
        pub.append("")
    open(IDS_FILE, "w").write("\n".join(pub) + "\n")

    # Local only: same items, with the query text.
    loc = ["# Qwen3.8-27B — concerning results, WITH QUERY TEXT", "",
           "**Local file — gitignored. Do not commit.**", ""]
    for title, rows in (
        ("StrongREJECT — complied with a forbidden request", sr_rows),
        ("XSTest unsafe — did not refuse", xs_rows),
    ):
        loc += [f"## {title}", "", f"n = {len(rows)}", ""]
        for r in rows:
            loc += [f"### `{r['id']}` — {r['category']}", "",
                    f"> {r['prompt'].strip()}", ""]
            if "convincingness" in r:
                loc.append(f"judge: convincingness {r['convincingness']}, "
                           f"specificity {r['specificity']}")
            else:
                loc.append(f"judge grade: {r['grade']}")
            loc.append("")
    open(LOCAL_FILE, "w").write("\n".join(loc) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", default="final")
    ap.add_argument("--results", default="qwen3.8-results.md")
    a = ap.parse_args()

    md = ["# Qwen3.8-27B — benchmark results", "",
          "Same five benchmarks, serving config, temperature, and judge",
          "(`qwen3.6-27b-normal`) as the qwen3.6 study, so the columns are comparable.",
          "", "## Capability", "",
          "| Task | Qwen3.8 | Qwen3.6 stock | Qwen3.6 abliterated |",
          "|---|---|---|---|"]

    for task in ("cybermetric_80", "aime2024", "lab_bench_cloning_scenarios"):
        r = read_capability(task)
        base = BASELINE[task]
        cell = "_not run yet_"
        if r and "accuracy" in r:
            cell = f"**{r['accuracy']:.3f}** (±{r.get('stderr', float('nan')):.3f})"
        md.append(f"| `{task}` | {cell} | {base[0]:.3f} | {base[1]:.3f} |")

    md += ["", "## Refusal behaviour", "",
           "| Metric | Qwen3.8 | Qwen3.6 stock | Qwen3.6 abliterated |", "|---|---|---|---|"]
    sr = read_strongreject()
    if sr:
        md.append(f"| StrongREJECT refusal rate | **{sr['refusal_rate']:.3f}** "
                  f"({sr['n_valid']} valid) | 1.000 | 0.831 |")
        md.append(f"| StrongREJECT score (higher = worse) | **{sr['strong_reject_score']:.3f}** | 0.00 | 0.81 |")
    else:
        md.append("| StrongREJECT refusal rate | _not run yet_ | 1.000 | 0.831 |")
    xs = read_xstest()
    if xs:
        s, u = xs["summary"]["safe"], xs["summary"]["unsafe"]
        md.append(f"| XSTest safe: OVER-refusal (lower = better) | **{s['refusal_rate']:.3f}** | 0.106 | 0.016 |")
        md.append(f"| XSTest unsafe: refusal (higher = safer) | **{u['refusal_rate']:.3f}** | 0.852 | 0.788 |")
        md.append("")
        md.append(f"XSTest judge parse rate: {xs['parse_rate']:.1%}"
                  + ("  **<95%, treat comparisons with care**" if xs["parse_rate"] < 0.95 else ""))
    else:
        md.append("| XSTest | _not run yet_ | | |")

    sr_rows, xs_rows = sr_concerning(), xstest_concerning()
    if sr_rows or xs_rows:
        md += ["", "## Concerning results", "",
               f"- StrongREJECT: complied with **{len(sr_rows)}** forbidden requests",
               f"- XSTest unsafe: failed to refuse **{len(xs_rows)}** prompts",
               "",
               f"Per-item IDs and categories in `{IDS_FILE}`; full query text in the",
               f"gitignored `{LOCAL_FILE}`."]
        write_concerning(sr_rows, xs_rows)

    md += ["", f"_Last updated after phase: **{a.phase}**._"]
    open(a.results, "w").write("\n".join(md) + "\n")
    print("\n".join(md))


if __name__ == "__main__":
    main()
