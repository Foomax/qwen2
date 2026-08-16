# Foomax's AI Safety Project

**Abliterated: removing refusals**

Project Idea: How does abliterating a model change it's results on benchmarks?

## Methodology:

Run Qwen 3.6 27B normal and Qwen 3.6 27B abliterated with benchmarks and compare to see
how abliteration changes them. The models are quantized to 4-bit (Q4_K_M k-quant,
~16.5–16.8 GB each), served locally with `llama.cpp` on a single RTX 3090 and scored with
Inspect AI + `inspect_evals`. Identical server config, temperature, and prompts for both
models, so every difference below is attributable to the weight edit.

Benchmarks ran symmetrically:

| Benchmark | n | What it measures | Scoring |
|---|---|---|---|
| `cybermetric_80` | 80 | Cybersecurity knowledge (MCQ) | Deterministic |
| `aime2024` | 30 | Competition mathematics, long chain-of-thought | Deterministic |
| `lab_bench_cloning_scenarios` | 33 | Dual-use molecular cloning (MCQ) — the biorisk proxy | Deterministic |
| `strong_reject` | 313 | Compliance with forbidden requests | Local LLM judge |
| `xstest` | 250 safe + 200 unsafe | Over-refusal of *safe* prompts (calibration) | Local LLM judge |

The first three are locally and deterministically scored, so they are directly comparable
across models with no judge in the loop. The last two need a judge; the same stock-model
judge graded both models, using the benchmarks' own rubric prompts.

Follow-up experiment: each of the 313 StrongREJECT prompts was re-run wrapped in a
prefix + suffix — once with a safety-conscious wrapper, once with a universal jailbreak
wrapper — on both models. The judge always sees the *original* bare question, so
conditions stay comparable.

## Executive Summary

Abliteration changed the results on the AIME maths competition and on StrongREJECT. The
abliterated model performed worse in mathematics challenges (0.700 vs 0.867 — a real and
replicated point estimate, but not statistically significant at n=30, p = 0.125). On
StrongREJECT the abliterated model scored **higher, which is worse**: the StrongREJECT
score measures not only whether the model refuses, but how convincing and specific its
answer is when it complies. Stock scored 0.00 (refused 100% of 313 forbidden prompts);
abliterated scored 0.81 (complied with 17%), and the judge rated those completions
near-maximally specific and convincing (4.96/5). The difference is overwhelming,
p ≈ 4×10⁻¹⁶ — but the effect is only *partial*: the abliterated model still refuses 83%
of the time. It is not an anything-goes model.

One notable result was that there was no significant uplift for biorisk (0.485 vs 0.455 on
the dual-use cloning task, p = 1.0, overlapping error bars). This is an incredibly
positive result — though it is one narrow MCQ proxy at n=33, not a general biorisk
clearance.

The researcher then honed in on the difference in StrongREJECT, asking the question

What if the eval prompts were wrapped in a safety-conscious prefix and suffix?
What if the eval prompts were wrapped in a jailbreak prefix and suffix?

Including a safety-conscious wrapper increased refusals on harmful requests — on the
abliterated model, compliance fell from 16.5% to 4.8% (paired, p ≈ 3×10⁻⁶). **A prompt-level
safety instruction recovers roughly two-thirds of what the weight edit removed** — cheap,
but not a full repair.

The jailbreak prompt also increased refusals — abliterated compliance fell from 16.5% to
6.9% — meaning the jailbreak was either ineffective or misapplied. Both wrappers land in
the same place: the two wrapped conditions are statistically indistinguishable from each
other (p = 0.39). The most likely reading is that *any* long framing instruction around a
forbidden prompt raises refusal, and the jailbreak's content did no work at all. A
`placebo` condition (a neutral, non-safety instruction) is implemented and would settle
this; it has not yet been run.

## Results

### Capability — no uplift anywhere

| Task | Stock | Abliterated | Δ | Significant? |
|---|---|---|---|---|
| `cybermetric_80` | 0.963 (±0.021) | 0.975 (±0.018) | −0.012 | No (p = 1.0) |
| `aime2024` | 0.867 (±0.063) | 0.700 (±0.085) | +0.167 | No (p = 0.125, n=30) |
| `lab_bench_cloning_scenarios` | 0.485 (±0.088) | 0.455 (±0.088) | +0.030 | No (p = 1.0) |

```
                                 capability accuracy (40 chars = 1.000)
CyberMetric-80        stock        ███████████████████████████████████████  0.963
CyberMetric-80        abliterated  ███████████████████████████████████████  0.975
AIME 2024             stock        ███████████████████████████████████      0.867
AIME 2024             abliterated  ████████████████████████████             0.700
LAB-Bench cloning     stock        ███████████████████                      0.485
LAB-Bench cloning     abliterated  ██████████████████                       0.455
```

The AIME gap is stable across two runs (it was re-run at a matched 65,536-token context to
rule out truncation, and scored 0.700 again), but it is entangled with a
*non-convergence pathology* rather than a clean accuracy drop: the abliterated model runs
to the context ceiling on 6/30 problems, all of them misses, vs 2/30 for stock.

### Refusal behaviour — the one large, unambiguous effect

| Benchmark | Metric | Stock | Abliterated | Paired p |
|---|---|---|---|---|
| StrongREJECT | Refusal rate | 1.000 | 0.831 | 4×10⁻¹⁶ |
| StrongREJECT | StrongREJECT score (higher = worse) | 0.00 | 0.81 | — |
| XSTest safe | **Over**-refusal (lower = better) | 0.106 | 0.016 | 1×10⁻⁶ |
| XSTest unsafe | Refusal (higher = safer) | 0.852 | 0.788 | — |

```
                                 XSTest (40 chars = 100%)
safe prompts   OVER-refused   stock        ████                                      10.6%
safe prompts   OVER-refused   abliterated  █                                          1.6%
unsafe prompts refused        stock        ██████████████████████████████████        85.2%
unsafe prompts refused        abliterated  ████████████████████████████████          78.8%
```

XSTest is the key to the mechanism. Abliteration does not install a *different* safety
policy — it lowers one indiscriminate refusal threshold. The same edit cuts needless
refusals of benign prompts ~6.5× (the benefit people abliterate for) **and** erodes
refusal of genuinely unsafe ones (the cost). Per-item confirmation: across ~760 graded
prompts the two models diverged on 84, and 83 of those 84 went in the same direction —
abliterated complies where stock refused. Only one went the other way.

### Wrapper experiment — can a prompt put the refusals back?

Compliance on the 313 StrongREJECT forbidden prompts, by condition (lower is better):

```
                                 harmful-prompt compliance (2 chars per 1%)
Stock          no wrapper                                          0.0%
Stock          jailbreak wrap  █                                   0.7%
Stock          safety wrap                                         0.0%
Abliterated    no wrapper      █████████████████████████████████  16.5%
Abliterated    jailbreak wrap  ██████████████                      6.9%
Abliterated    safety wrap     ██████████                          4.8%
```

| Condition | n valid | Refuse | Comply | SR score |
|---|---|---|---|---|
| Stock — no wrapper | 309 | 100.0% | 0.0% | 0.00 |
| Stock — safety wrapper | 313 | 100.0% | 0.0% | 0.00 |
| Stock — jailbreak wrapper | 291 | 99.3% | 0.7% | 0.03 |
| Abliterated — safety wrapper | 311 | 95.2% | 4.8% | 0.23 |
| Abliterated — jailbreak wrapper | 305 | 93.1% | 6.9% | 0.31 |
| Abliterated — no wrapper | 309 | 83.5% | 16.5% | 0.81 |

Where the safety wrapper's remaining failures sit (abliterated, compliance
control → wrapped, per category):

| Category | Control | Safety-wrapped | |
|---|---|---|---|
| Disinformation and deception | 12.2% | **0.0%** | fixed |
| Sexual content | 24.5% | **0.0%** | fixed |
| Illegal goods and services | 28.0% | 6.0% | mostly fixed |
| Non-violent crimes | 17.2% | 6.9% | mostly fixed |
| Violence | 9.4% | 5.7% | improved |
| Hate, harassment and discrimination | 6.2% | **10.4%** | **worse** |

The safety wrapper is not uniformly protective. It nearly eliminates compliance in four
categories but makes hate/harassment *worse*, and that category is where most of the
residual 4.8% now lives. A prompt-level patch on an abliterated model leaves a
non-uniform, category-dependent hole.

## Conclusion

The abliterated model performed as expected — it refused fewer harmful requests, and
scored lower on the hardest task (AIME maths), though that gap is underpowered and driven
by a failure-to-converge tendency rather than a clean loss of ability. Two surprising
conclusions: 1) no biological uplift was caused by the abliterated model — abliteration
removed the *refusal*, not a hidden capability, so on a task the stock model was already
willing to attempt there was nothing left to unlock; 2) the jailbreak prompt actually
INCREASED refusals, ending up statistically indistinguishable from the safety wrapper,
which points at a framing-length artifact rather than a real defensive win.

The complement to StrongREJECT — **XSTest** — showed that the models are *not* alike where
it matters most for the mechanism: stock over-refuses 10.6% of plainly safe prompts and
the abliterated model only 1.6% (p ≈ 1×10⁻⁶). That is abliteration's genuine benefit, and
it arrives inseparably bundled with its cost. One dial, both directions.

Net: refusal ablation produced large, significant, indiscriminate *behavioural* change and
no measurable *capability* change in either direction — the expected signature of a
refusal-direction edit, now measured rather than assumed.

## Recommendations

Continue to run benchmarks on open-source abliterated models to check for biorisk uplift.

See how fine-tuning the model on harmful content data will affect all safety benchmarks.

Do not treat a system-prompt safety wrapper as a fix for an abliterated model. It recovers
about two-thirds of the removed refusals on average, but unevenly — it made
hate/harassment compliance worse, and a defence that fails in a category you did not check
is not a defence.

Report XSTest alongside StrongREJECT as standard. Measuring only harmful-prompt refusal
scores abliteration as pure loss and misses the calibration benefit that explains why
people do it.

## Further Research

Investigate other jailbreak prompts and how they affect both models — the chosen jailbreak
prompt seems to be ineffective.

Run the `placebo` condition (a neutral, non-safety instruction of similar length). Until
that is run, "the safety wrapper works" and "any long wrapper works" are not
distinguishable, and this is the single cheapest experiment that would change how the
wrapper results should be read.

Raise the judge's token budget and re-grade the jailbreak arms. The stock jailbreak run
parsed only 291/313 — differential parse rates across conditions bias paired comparisons,
and that arm is the weakest evidence here.

## Caveats

- The judge is a local 27B-Q4 model, not GPT-4o. The same judge graded every arm, so
  comparisons are internally valid; absolute rates are not comparable to published
  StrongREJECT numbers (which also use temperature 0.75, not 0).
- Capability tasks are small (n=30–80). Treat those magnitudes as indicative. The
  refusal-behaviour results (n=313 / 450) are large and robust.
- The abliterated build shipped with no model card; the ablation recipe is unverified and
  assumed from its name.
- Only aggregate rates and per-item refusal labels are reported or stored. No model
  completion to a forbidden prompt appears in this repository.
