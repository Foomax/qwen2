# Qwen3.8-27B on `lab_bench_cloning_scenarios`: what actually went wrong

**Summary: the 0.121 result was caused by two independent defaults — not by a
context limit, and not by the model lacking the capability. A 15-sample pilot
with both corrected scores 0.467, in line with the qwen3.6 baselines (0.485
stock, 0.455 abliterated). The full run has not been executed, so Qwen3.8's
score on this benchmark remains formally unmeasured.**

Raw numbers and exact server flags: `cloningbench_experiment_pilots_results.txt`.
The original artifact analysis: `cloningbench.md` — note its proposed remedy
(raise the context) turned out to be **not the fix**; this document supersedes it.

## The original diagnosis was wrong

`cloningbench.md` concluded that a 65,536-token context was the binding
constraint and recommended re-running at 98,304, changing one variable. That was
a reasonable read of the evidence available — median output 57,140 tokens against
a 65,536 ceiling, 13/33 samples over 60k — but it was wrong about the cause.

Raising the context alone would have produced another unusable number, more
slowly. Nothing in any pilot came within 65,000 tokens of the new ceiling; the
maximum observed across all three was 33,259. The window was never the problem.

## Cause 1: the chat template sets reasoning effort to `xhigh`

Qwen3.8's own chat template injects a system preamble when no reasoning effort
is specified:

> Reasoning effort is set to xhigh. Please think carefully through the task,
> validate key assumptions, consider plausible alternatives, and prioritize
> correctness, consistency, and clarity in the final answer.

We never set this; it is the template's default. The template accepts
`reasoning_effort` in `{xhigh, medium, low}`, and **`medium` injects nothing at
all** — it is the neutral setting, where `low` actively suppresses reasoning.

This is why the same model scored 0.967 on AIME 2024 the day before. `xhigh` is
genuinely good for competition maths. It is pathological on a task that pairs
very large inputs with a one-letter answer.

Setting `reasoning_effort: medium` cut median output from 57,140 to 17,428
tokens and eliminated context-ceiling hits entirely. But empties only fell from
27/33 to 8/15, so something else was still wrong.

## Cause 2: every anti-repetition sampler is off by default

Inspecting an empty completion showed the reasoning block ending like this:

```
...CTGCTGCCTGCTGCTGCCTGCTGCTGCCTGCTGCTGCC...</think>
```

A **degenerate repetition loop**. The model copies plasmid DNA, gets trapped
repeating a motif, burns its budget on garbage, closes the thinking tag and has
nothing left to say. `xhigh` made these loops longer; it did not create them.

The run had **no sampling parameters set at any level** — Inspect passed none,
so llama.cpp's defaults applied, and in llama.cpp every anti-repetition sampler
ships disabled (`repeat_penalty 1.00`, `presence 0.00`, `frequency 0.00`,
`dry_multiplier 0.00`). DNA is close to a worst case for this: highly repetitive,
low-entropy token sequences.

Applying the model's own declared sampling (temp 1.0, top_k 20, top_p 0.95, all
three recorded in the GGUF metadata) plus DRY eliminated the loops completely —
zero degenerate endings in every subsequent pilot.

**This is worth stating plainly: leaving sampling unset is not a neutral choice.**
It was initially defended here on comparability grounds, and that reasoning was
wrong. The defaults were the bug.

## Cause 3 (self-inflicted): DRY set too aggressively

The first anti-loop attempt used `--dry-allowed-length 8`. Loops vanished, but
accuracy *fell* to 0.133 and one sample stopped after 450 characters mid-sentence.
Copying a plasmid is legitimately repetitive, so DRY at that setting was
penalising the actual work.

Relaxing to `--dry-allowed-length 32` — long enough that only pathological runs
are penalised — took accuracy from 0.133 to 0.467.

A related omission: `--reasoning-budget-message` was used during the load test
but left out of the first two pilots. Without it, a force-closed thinking block
is followed by EOS and no answer. Restoring it helped empties fall to 2/15.

## Results

| Run | n | Accuracy | Empty | Median tokens | Loops |
|---|---|---|---|---|---|
| Original (65k, `xhigh`, no sampling) | 33 | 0.121 | 27/33 | 57,140 | — |
| Pilot 1 (98k + `medium`) | 15 | 0.200 | 8/15 | 17,428 | 0 |
| Pilot 2 (+ sampling + DRY@8) | 15 | 0.133 | 4/15 | 9,349 | 0 |
| **Pilot 3 (DRY@32 + budget msg)** | 15 | **0.467** | 2/15 | 14,222 | 0 |
| *qwen3.6 stock (reference)* | 33 | *0.485* | — | — | — |
| *qwen3.6 abliterated (reference)* | 33 | *0.455* | — | — | — |

Pilot 3 lands where a competent model should on this task, and its remaining
2 empties are ordinary non-convergence rather than a systematic failure.

## What this licenses, and what it does not

- **Supported:** the 0.121 figure is an artifact of two defaults, and Qwen3.8 is
  not meaningfully worse at molecular cloning than Qwen3.6. On 15 samples under
  a corrected configuration it scores comparably.
- **Not supported:** "Qwen3.8 scores 0.467 on `lab_bench_cloning_scenarios`."
  That is a 15-sample pilot with a wide interval, not the 33-sample benchmark.
  **The benchmark result for Qwen3.8 is still unmeasured.**
- `results.md`, `results.txt` and the write-ups should continue to flag 0.121 as
  an artifact and must not quote 0.467 as a benchmark score.

## If the full run is done later

Use the pilot 3 configuration exactly as recorded in
`cloningbench_experiment_pilots_results.txt`. Expect roughly 4–7 hours: median
output is now ~14k tokens rather than ~57k, so the run should be far cheaper than
the original 11h41m.

**Document the configuration difference in any comparison table.** The qwen3.6
baselines ran at 65,536 context with default sampling and `xhigh` effort. A
qwen3.8 number obtained under pilot 3 settings is not like-for-like. The honest
framing is that the qwen3.6 models did not need these corrections because they
did not loop, and that a fair generational comparison would require re-running
the qwen3.6 arms under the same corrected configuration.

## Transferable lessons

1. **A sub-chance score on multiple choice is a plumbing bug, not a capability
   finding.** Below the guessing floor means answers are not being produced.
2. **Check what the chat template injects.** A model-supplied default set an
   `xhigh` reasoning mode that nothing in the harness revealed.
3. **Unset sampling is a choice, and on repetitive inputs it is a bad one.**
4. **Anti-repetition samplers cut both ways.** DRY tuned for loops suppressed
   legitimate repetitive work; the fix needed a middle setting, found by
   measurement rather than by reasoning.
