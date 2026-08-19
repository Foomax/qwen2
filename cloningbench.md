# Why `lab_bench_cloning_scenarios` needs re-running for Qwen3.8-27B

**Status: the 0.121 result is not a capability measurement and should not be
reported as one.** This note explains what went wrong, why it is a measurement
artifact rather than a finding, and what the re-run should change.

## The result that triggered this

| Model | Accuracy | Stderr |
|---|---|---|
| Qwen3.6-27B stock | 0.485 | 0.088 |
| Qwen3.6-27B abliterated | 0.455 | 0.088 |
| **Qwen3.8-27B** | **0.121** | **0.058** |

## Why it cannot be taken at face value

`lab_bench_cloning_scenarios` is 4-option multiple choice, so blind guessing
scores ~0.25. Qwen3.8 scored **0.121 — less than half of chance**, while on the
same day scoring 0.967 on AIME 2024 and 0.950 on CyberMetric. A model does not
get *worse than random* on multiple choice by lacking knowledge; scoring that
far below chance means the answers are not being produced at all.

They weren't. Diagnostics from the run:

| Signal | Value | Ceiling |
|---|---|---|
| Median output tokens | 57,140 | 65,536 |
| Max output tokens | 63,686 | 65,536 |
| Samples over 60k tokens | 13 of 33 | — |
| Wall time | 11h41m | (qwen3.6: 6h42m) |
| Score distribution | 29 incorrect / 4 correct | — |

Inspected completions are **empty strings**. The model reasoned until it
exhausted the context window and never emitted a final answer. Every such
sample is scored incorrect, which is correct behaviour by the scorer and
meaningless as a capability signal.

## Why this task specifically

These prompts embed full plasmid DNA sequences — one is ~26,000 tokens of
input, and the largest sample in the dataset is ~51,700 characters. At a 65,536
context, a prompt of that size leaves very little room for a long chain of
thought. The failure is the interaction of three things:

1. **Huge inputs** (unique to this task in the suite).
2. **A model that reasons at length.** Qwen3.8's median AIME reasoning was
   11.4k tokens, but its distribution has a heavy tail.
3. **A context budget inherited from the qwen3.6 study**, chosen when the
   models had smaller inputs to accommodate.

This is the same non-convergence signature documented for qwen3.6-abliterated
on AIME — running to the ceiling and being truncated — but far more severe,
because here the input consumes much of the window before reasoning starts.

## What the number does and does not license

- **Defensible:** "At a matched 65,536-token context, Qwen3.8-27B fails to
  complete this task, running out of context on 13 of 33 samples." That is a
  real, comparable statement about deployability at this budget.
- **Not defensible:** "Qwen3.8-27B is worse at molecular cloning than
  Qwen3.6." The model never answered. 0.485 vs 0.121 compares an answer rate to
  a capability, not two capabilities.

Reporting the second reading would be a straightforward error, and the kind a
reviewer would catch immediately given the sub-chance score.

## The proposed re-run

**Change one variable: context.** Everything else — temperature, thinking mode,
scorer, dataset, judge — stays fixed, so the re-run is interpretable against
both the qwen3.8 65k run and the qwen3.6 baselines.

Qwen3.8-27B supports **262,144 tokens natively**, so 65,536 is a self-imposed
limit, not a model limit. Measured VRAM at 65,536 was 20.2 GB used with 3.9 GB
free on the 24 GB RTX 3090. Because the architecture is hybrid attention/SSM
(`full_attention_interval = 4`), only ~16 of 65 layers carry a KV cache, so KV
costs roughly **0.033 GB per 1k tokens** — about 2.1 GB at 65k.

| Context | Est. KV | Est. total | Verdict |
|---|---|---|---|
| 65,536 (current) | 2.1 GB | 20.2 GB | measured; insufficient |
| **98,304** | 3.2 GB | ~21.3 GB | **recommended** |
| 131,072 | 4.3 GB | ~22.4 GB | probably fits, little margin |
| 262,144 | 8.6 GB | ~26.7 GB | exceeds the card |

**Recommendation: re-run at 98,304**, verifying the load before committing to
the full run, and falling back to 81,920 if VRAM is tighter than estimated.
Note the naive KV formula badly overestimates this architecture — it predicts
8.7 GB at 65k against a measured ~2.1 GB — so trust the load test, not the
table.

## Cost and expected outcome

The 65k run took 11h41m, most of it spent generating tokens that were then
discarded at truncation. A re-run at 98k will not be cheaper per sample, so
budget **12+ hours of GPU**.

Two outcomes, both informative:

- **Accuracy rises to a plausible range** (~0.4–0.6): confirms truncation was
  the cause, and yields the real capability number for the comparison table.
- **It still runs to the ceiling on many samples**: then non-convergence on
  long-context inputs is a genuine property of this model, not a budget
  artifact — which is a more interesting finding than the accuracy number, and
  one worth reporting in its own right.

Either way the current 0.121 is replaced by something that means what it says.

## Until then

`results.md`, `results.txt` and the write-ups should carry the 0.121 figure
**only with the artifact flagged inline**, never as a bare capability number in
a comparison table.
