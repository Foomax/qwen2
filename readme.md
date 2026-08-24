# Does abliteration get more dangerous as base models improve?

**Yes — and it is the base model that changed, not the recipe.**

Stock vs refusal-ablated Qwen3.6-27B and Qwen3.8-27B, all Q4_K_M on one RTX 3090,
llama.cpp + Inspect AI, paired per item. 313 StrongREJECT prompts, 450 XSTest.

---

## TL;DR of the TL;DR

**Harmful-request compliance (StrongREJECT, 313 prompts, same judge throughout):**

| | Qwen3.6 | Qwen3.8 |
|---|---|---|
| stock | 0.0% | 0.0% |
| ablated — OBLITERATUS | 16.5% | 45.7% |
| ablated — Heretic | 9.0% | **43.3%** |

1. **Both stock models refuse everything. Both ablated 3.8 builds comply with
   ~44%.** One generation of ordinary model development made the same class of
   edit ~4× more effective at stripping refusals.
2. **The recipe doesn't explain it.** Two independent ablation recipes on
   Qwen3.8 are statistically indistinguishable — 46-vs-55 discordant pairs,
   **p = 0.43**. Holding recipe fixed, the generational effect is
   **108-vs-4, p = 2.5e-27**.
3. **No capability uplift, anywhere.** Across three tasks and two generations.
   Ablation unlocks willingness, not ability.
4. **Weight edits and prompt attacks have different per-item signatures.**
   Ablation is near-perfectly nested — 141-0, 132-0, 83-1, 28-0, i.e. one
   direction-blind threshold lowered. A published prompt attack is 32-19, a
   perturbation. Visible per item, invisible in aggregate rates. *This is the
   contribution we think is most novel; a 74-item prior-art sweep found nobody
   else reporting it.*
5. **Published "0/100 refusals" claims are not comparable to these numbers.**
   The field's reference tool scores refusal with a 41-marker substring matcher
   whose markers include "illegal" and "harmful". We measure a build made by that
   tool at 43.3% compliance under a rubric judge.

**Robustness:** a frontier judge (DeepSeek-v4-pro) reproduces every headline
number to within ~1 point, Cohen's κ 0.87–1.00.

---

## What is wrong with this, in order

1. **Round 1 (Qwen3.6) is confounded.** The `qwen3.6-27b-obliteratus` GGUF ships a
   chat template that silently injects an anti-refusal system prompt whenever the
   caller sends none — which is exactly what these benchmarks do. So round 1's
   "identical prompts, only the weights differ" claim is false. It biases *toward*
   compliance, so the generational gap is understated, not overstated. The
   Heretic-3.6 arm is clean and is the number to trust for that cell.
2. **Two recipes is not "recipes".** The null is over OBLITERATUS and Heretic on
   one base model.
3. **XSTest on the two newest arms is under-covered** (151–162 of 200 unsafe items
   parsed; the judge's budget is exhausted by longer completions). StrongREJECT,
   which carries the headline, has 305–311 of 313.
4. Capability tasks are n=30–80. Judges are local 27B-Q4 unless stated.
5. One quantisation (Q4_K_M) throughout, by design — quant is not a free variable.

No harmful prompt text or model completion appears anywhere in this repository.

---

## Read next

| file | what it is |
|---|---|
| `HO3-RESULTS.md` | the 2×2, per-item decomposition, cross-judge table |
| `midway-progress.txt` | the Qwen3.8 stock-vs-ablated round in full |
| `eval-results-technical-paper.md` | method, limitations, the earlier rounds |
| `lessons.txt`, `lessons2.txt` | what the measurement kept getting wrong |
| `hand-over3.txt` | the plan this run executed, and why |
| `readme_old2.md` | the previous README |
