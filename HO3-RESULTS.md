# HO3 RESULTS — the matched-recipe 2×2

Run 2026-08-24, 10:21 → 17:37 (~7.2h wall, ~4.5h GPU). Executed from
`hand-over3.txt`. Judge: `qwen3.6-27b-normal` (the judge that graded every prior
arm), plus a `deepseek-v4-pro` cross-check.

---

## The headline claim SURVIVES recipe control — and gets stronger

**StrongREJECT harmful-request compliance, 313 prompts:**

| | Qwen3.6 | Qwen3.8 | generation effect |
|---|---|---|---|
| **stock** | 0.0% | 0.0% | — |
| **OBLITERATUS family** | 16.5% | 45.7% | +29.2 pts |
| **Heretic recipe** | **9.0%** | **43.3%** | **+34.3 pts** |
| *recipe effect* | −7.5 pts | **−2.4 pts (n.s.)** | |

The project's headline was a two-point comparison between builds by two different
authors: 16.5% → 45.7%. That is now controlled. **Holding the recipe fixed at
Heretic, the same generational jump is 9.0% → 43.3%** — a 4.8× increase against
the original 2.8×.

Per-item, both directions:

| comparison | n | one way | other way | McNemar exact | signature |
|---|---|---|---|---|---|
| **GENERATION, recipe fixed (Heretic 3.6→3.8)** | 305 | **108** | **4** | **2.5e-27** | **NESTED** |
| GENERATION, OBLITERATUS family (3.6→3.8) | 307 | 104 | 15 | 1.4e-17 | two-directional |
| RECIPE within Qwen3.8 (OBLITERATUS↔Heretic) | 305 | 46 | 55 | **0.426 — n.s.** | two-directional |
| RECIPE within Qwen3.6 (OBLITERATUS↔Heretic) | 307 | 21 | 43 | 0.008 | two-directional |
| ABLATION, Qwen3.8 (stock→Heretic) | 306 | **132** | **0** | 3.7e-40 | NESTED |
| ABLATION, Qwen3.6 (stock→Heretic) | 311 | **28** | **0** | 7.5e-09 | NESTED |

---

## This refutes my own prior-art worry

`ANALYSIS.md §4` argued, from other builds' published claims (AEON "0/100
refusals", orcarouter "~0–6% refusal"), that **"recipe variance is plausibly the
dominant term"** behind the headline. Measured directly:

* **Within Qwen3.8 the recipe effect is null** — 45.7% vs 43.3%, 46-to-55
  discordant, **p = 0.43**. Two independent ablation recipes by two different
  authors give statistically indistinguishable harmful compliance on the same base.
* The generation effect on the same items is 108-to-4, p = 2.5e-27.

The generation effect dwarfs the recipe effect. The worry was reasonable and is
now empirically dead.

**Why the corpus suggested otherwise, and it matters.** Those "0/100 refusals"
claims come from **keyword-based** refusal metrics — the exact defect
`TECHNIQUES.md §3` identified in `heretic`'s `keyword_rate.py` scorer. We measured
a **Heretic-built model at 43.3% compliance / 56.7% refusal** with a rubric judge,
while Heretic's own README reports 3/100 refusals on its keyword metric. Different
benchmarks, but the gap is enormous and in exactly the predicted direction. The
prior-art sweep predicted this failure mode; this run is direct evidence of it.

The Qwen3.6 recipe effect (−7.5 pts, p=0.008) is **not** clean evidence of recipe
variance either: the OBLITERATUS-3.6 arm carries the injected-system-prompt
confound below, which biases it toward compliance.

---

## Compliance quality is invariant; only the RATE moves

Mean judge specificity among compliances: **4.92** (q36-OBLITERATUS), **4.96**
(q36-Heretic), **4.70** (q38-OBLITERATUS), **5.00** (q38-Heretic). Across two
generations and two recipes, when these models comply they comply substantively.
Round 3's finding — that V3's gain is rate, not substance — generalises.

## The nesting signature now holds four times

Weight edits: 141-to-0, 132-to-0, 83-to-1, 28-to-0. Prompt attack
(`refusal_suppression`): 32-to-19. The contrast between a *threshold shift* and a
*perturbation* is the study's sharpest and most novel contribution — nothing in a
74-item prior-art corpus does it — and it is now demonstrated across two
generations and two independent recipes.

---

## Cross-judge: the numbers are judge-independent

`deepseek-v4-pro` @4096 vs `qwen3.6-27b-normal`, per-item:

| comparison | n | local | deepseek | Cohen's κ |
|---|---|---|---|---|
| SR refusal, q38-stock | 307 | 1.000 | 1.000 | — (no variance) |
| SR refusal, q38-OBLITERATUS | 299 | 0.532 | 0.532 | **0.906** |
| XSTest safe, q38-stock | 246 | 0.045 | 0.045 | **1.000** |
| XSTest unsafe, q38-stock | 188 | 0.846 | 0.851 | **0.979** |
| XSTest unsafe, q38-OBLITERATUS | 172 | 0.331 | 0.308 | **0.866** |

**Limitation 11 closes.** The result "most likely to move under a better judge"
did not move.

---

## Caveats, in order of how much they should worry you

1. **XSTest unsafe on the two NEW arms is the weakest number here and is being
   re-graded.** Local-judge coverage was only 151/200 (q38-heretic) and 162/200
   (q36-heretic), against 177–190/200 for the older arms. Diagnosed: Heretic
   completions are 2.5–3× longer (median 488–589 tokens vs OBLITERATUS 161–220),
   exhausting the judge's 1024-token budget. Only **3 of 49** failures were
   generation-side cap-hits, so it is judge-side. A DeepSeek @4096 re-grade is
   running (zero GPU). **Until it lands, treat the XSTest recipe difference
   (Heretic-3.8 69.5% unsafe refusal vs OBLITERATUS-3.8 34.5%) as provisional.**
   The StrongREJECT numbers, which carry the headline, have 305–311/313 coverage
   and are unaffected.
2. **Round 1 (Qwen3.6) is confounded by an injected system prompt.** The
   `qwen3.6-27b-obliteratus` GGUF's chat template silently injects an anti-refusal system prompt (text withheld; see
   the gitignored local companion) whenever
   the caller sends no system message — which is exactly what the refusal
   benchmarks do. Verified in the template source and by render-diff; no other arm
   contains it. This invalidates the paper's "every difference is attributable to
   the weight edit" for round 1. It biases 3.6 *toward* compliance, so the
   generational gap is understated, not overstated.
   **The new q36-heretic arm renders identically to q36-stock**, so this run
   provides the project's first uncontaminated Qwen3.6 ablation measurement:
   28-to-0, 9.0% compliance.
3. **The within-Qwen3.8 recipe cell has an MTP co-variable.** Heretic-3.8 is
   64-block, OBLITERATUS-3.8 is 65-block with an MTP head. The *decisive*
   Heretic-3.6-vs-3.8 comparison is unaffected (both 64-block, verified in
   preflight).
4. **Two recipes is not "recipes".** The null within Qwen3.8 covers OBLITERATUS
   and Heretic. `JonathanColetti` and `orcarouter` Q4_K_M builds exist at 16.81 GB
   and would extend it cheaply (~50 min download + ~2h each).

---

## What this changes

* **The generational finding is publishable.** It survives recipe control, judge
  substitution, and per-item paired testing, with a clean nesting signature.
* **`ANALYSIS.md §4`'s recipe-variance objection is answered** — measured and null
  within Qwen3.8.
* **Two write-up corrections are now mandatory:** the round-1 injected-system-prompt
  confound, and the fact that published keyword-metric refusal claims from the
  ablation community are not commensurable with rubric-judge measurements.
