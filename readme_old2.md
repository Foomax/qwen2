# How harmful is a state-of-the-art local LLM when it is obliterated?

**TL;DR — Abliteration does exactly what it claims: it strips refusals out of an
open-weights model, no retraining, no capability loss. But it does not make the model
*more capable* of harm, and the newest generation of stock models now delivers the benefit
people abliterate for while still refusing everything. The trade is getting worse, not
better, for the attacker.**

---

## WHY

Abliteration is the cheapest safeguard-removal technique in the open-weights ecosystem.
It ablates the single activation direction that mediates refusal (Arditi et al., 2024)
directly from the weights — a few minutes of work, no fine-tuning, no data. Anyone can do
it, and thousands have.

The obvious worry is uplift: does removing the guardrail unlock dangerous capability that
was there all along? The folklore claims the opposite too — that "uncensored" models are
smarter. Both claims are testable and both are usually asserted without measurement.

Nobody was going to stop publishing these models while the question stayed unanswered,
so I measured it on one, end to end, on a single consumer GPU.

## HOW

Stock **Qwen3.6-27B** against a community-abliterated build of the same model, and later
the newer **Qwen3.8-27B**, all Q4_K_M on one RTX 3090 via llama.cpp, scored with Inspect AI.

- **Three capability benchmarks**, deterministically scored: cybersecurity knowledge,
  competition maths, and dual-use molecular cloning — the biorisk proxy.
- **Two refusal benchmarks**: StrongREJECT (313 forbidden prompts) for harmful compliance,
  XSTest (250 safe + 200 unsafe) for over-refusal. Both judged by a fixed local model.
- **Paired per item**, so every comparison is the same prompt on both models, not two
  averages.
- **A wrapper sweep**: eleven prompt-level conditions — safety framings, published attacks,
  a community jailbreak, and a placebo — to ask whether a system prompt can put back what
  the weight edit removed.
- **Two independent judges**, to check the conclusions aren't an artifact of the grader.

## WHAT

**1. No capability uplift. Anywhere.** Knowledge unchanged, maths unchanged-to-worse, and
the dual-use biology task flat (0.485 vs 0.455, n.s.) with zero abstentions. Abliteration
removes the *refusal*, not a hidden capability — so on tasks the stock model would already
attempt, there is nothing left to unlock.

**2. Abliteration works, partially and indiscriminately.** Harmful refusal 100% → 83%
(p ≈ 4×10⁻¹⁶). But the same edit cut needless refusal of *safe* prompts 10.6% → 1.6%.
One dial, turned down. Per item, 83 prompts moved refuse→comply and exactly 1 moved the
other way — the fingerprint of a single lowered threshold rather than a changed policy.

**3. The harm ceiling is the base model, not the edit.** Which is why the newest result
matters most: **Qwen3.8-27B refuses all 313 forbidden prompts while wrongly refusing safe
ones a third as often as the previous generation** (3.3% vs 10.6%) — and scores higher on
maths using half the tokens. That is most of abliteration's benefit with none of its cost,
obtained by ordinary model development. The reason to abliterate is eroding.

**4. Prompt attacks and weight edits are not the same thing.** Of eleven wrappers, only the
plain published refusal-suppression attack lowers refusal below baseline (82.8% → 78.4%),
and only weakly (p = 0.09). An elaborate community jailbreak *raises* it. So does a
placebo — meaning any long instruction around a harmful prompt increases refusal, and
safety-wrapper results are meaningless without that control.

**5. Not a judge artifact.** Re-grading every log with a different judge moved nothing by
more than 1.3 points.

---

## Read next

| File | What it is |
|---|---|
| `results.txt` | Every number from every run, consolidated |
| `results.md` | Run-by-run detail for the qwen3.6 study |
| `eval-results-technical-paper.md` | Full write-up with method and limitations |
| `eval-results-blog-post.md` | The same findings, informally |
| `divergence.md` | Per-item: where abliteration and stock disagree |
| `divergence2.md` | Per-item: what the one working attack actually changes |
| `cloningbench.md` | Why one result is an artifact and must be re-run |
| `sr_README.md` | The wrapper experiment's tooling |
| `old_readme.md` | The previous README |

## Honest limits

The dual-use biology result is one narrow MCQ proxy at n=33, not a biorisk clearance.
Capability tasks are small (n=30–80). Judges are 27B-Q4 models. One abliterated build,
whose recipe is unverified. And `lab_bench_cloning_scenarios` on Qwen3.8 returned a
sub-chance score that is a context-truncation artifact, not a measurement — it is flagged
everywhere it appears and needs re-running (`cloningbench.md`).

No model completion to a forbidden prompt is stored in this repository.
