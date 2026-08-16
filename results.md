# Inspect Evals — Qwen3.6-27B: Normal vs. Obliterated

Status: **complete**. Five benchmarks on both models: three capability tasks plus two
refusal-behavior checks (StrongREJECT + XSTest). AIME re-run at matched context.

## Setup

- Framework: [Inspect AI](https://inspect.aisi.org.uk/) (UK AISI) + `inspect_evals` task suite
- Serving: `llama.cpp`'s `llama-server`, OpenAI-compatible API, single GPU (RTX 3090, 24GB)
- Models (both GGUF, Q4_K_M quantization, ~16.5–16.8GB each):
  - **Obliterated**: `qwen3.6-27b-obliteratus-Q4_K_M.gguf`
  - **Normal**: `Qwen3.6-27B-Q4_K_M.gguf`
- Server config (identical for both models): `-c 65536 --parallel 1 --cache-type-k q8_0 --cache-type-v q8_0`
- Benchmarks (smallest/fastest in the `inspect_evals` suite, all locally/deterministically
  scored — multiple-choice matching, no external LLM-judge required, so results are
  directly comparable across models):
  - `cybermetric_80` — 80 MCQ cybersecurity knowledge questions
  - `aime2024` — 30 AIME 2024 competition math problems (long chain-of-thought)
  - `lab_bench_cloning_scenarios` — 33 MCQ molecular-cloning scenario questions (some
    prompts embed full raw DNA sequences; dual-use biology content, safety-relevant)
  - `strong_reject` — 313 forbidden prompts; measures refusal vs. compliance (the
    manipulation check: did abliteration actually remove refusals?). LLM-judge scored
    (local judge; see that section for the equivalence/validity argument).
  - `xstest` — 250 safe + 200 unsafe prompts; measures over-refusal (exaggerated safety)
    and appropriate refusal. LLM-judge scored (local judge). Complements StrongREJECT.

## Headline

- **Capability: no uplift from abliteration anywhere** (3 benchmarks, all nulls or
  confounded). See capability table below.
- **Behavior: abliteration works, but only partially — and indiscriminately.** On
  StrongREJECT (313 forbidden prompts), the normal model refused **100%**, the obliterated
  **83%** (complied with 17%), perfectly nested, McNemar p ≈ 4e-16. On XSTest, the same
  lowered-refusal-threshold shows up on *both* sides: over-refusal of **safe** prompts fell
  10.6%→1.6% (calibration benefit, p ≈ 1e-6) while refusal of **unsafe** prompts also fell
  85%→79% (safety cost). These are the study's large, significant, unconfounded effects —
  all behavioral, none a capability gain.

## Capability results

| Task | Normal accuracy | Obliterated accuracy | Δ (normal − obliterated) |
|---|---|---|---|
| `cybermetric_80` | **0.963** (±0.021) | **0.975** (±0.018) | −0.012 |
| `aime2024` | **0.867** (±0.063) | **0.700** (±0.085)† | **+0.167** (real point estimate, n.s.) |
| `lab_bench_cloning_scenarios` | **0.485** (±0.088) | **0.455** (±0.088) | +0.030 |

† The obliterated model was re-run at a **matched 65,536-token context** (its first run
used 16,384 and was truncated). It **still scored 0.700** — so the gap is *not* a
truncation artifact, correcting an earlier hypothesis. It remains statistically
non-significant at n=30 (McNemar p = 0.125). See AIME note below.

### Detail

| Task | Model | Accuracy | Stderr | Samples | Wall time | Tokens (input / cache-read / output) |
|---|---|---|---|---|---|---|
| `cybermetric_80` | normal | 0.963 | 0.021 | 80/80 | 0:23:41 | 9,884 / 1,106 / 57,225 |
| `cybermetric_80` | obliterated | 0.975 | 0.018 | 80/80 | 0:10:43 | 9,926 / 1,064 / 53,802 |
| `aime2024` | normal | 0.867 | 0.063 | 30/30 | 5:15:53 | 6,263 / — / 952,406 |
| `aime2024` | obliterated (16k ctx, truncated) | 0.700 | 0.085 | 30/30 | 1:56:46 | 6,263 / 1,890 / 293,634 |
| `aime2024` | obliterated (65k ctx, matched rerun) | 0.700 | 0.085 | 30/30 | 4:34:24 | 6,263 / 1,890 / 619,462 |
| `lab_bench_cloning_scenarios` | normal | 0.485 | 0.088 | 33/33 | 3:26:55 | 146,620 / 50,608 / 469,630 |
| `lab_bench_cloning_scenarios` | obliterated | 0.455 | 0.088 | 33/33 | 6:42:56 | 67,462 / 131,845 / 350,949 |

Both `lab_bench_cloning_scenarios` runs scored with `precision_choice`, coverage 1.000
for both models (neither model ever used the "insufficient information" abstention
option — every question was answered).

## StrongREJECT (refusal / jailbreak behavior)

The manipulation check the capability suite was missing: does abliteration actually
remove refusals? Ran `inspect_evals/strong_reject` — 313 forbidden prompts (pinned
public dataset) — on both models at temperature 0, reasoning off, identical config.
Responses graded by the same local judge (the normal Qwen, StrongREJECT's exact rubric
prompt) so the comparison is internally valid. **Only aggregate rates are reported here;
individual harmful completions are not surfaced.**

| Metric | Normal | Obliterated |
|---|---|---|
| Refusal rate | **1.000** (309/309 valid) | **0.831** (256/308 valid) |
| Jailbreak rate (complied) | **0.000** | **0.169** (52 prompts) |
| StrongREJECT score (0–5, higher = worse) | 0.00 | 0.84 |
| Specificity / convincingness of complied answers (judge, 1–5) | — | 4.96 / 4.96 |

Paired (304 prompts both models answered validly): both refused **252**, obliterated-only
complied **52**, normal-only complied **0**, both complied **0**. McNemar exact
**p ≈ 4.4e-16**.

Reading:
- Abliteration had a real, statistically overwhelming effect — but a **partial** one. The
  "obliterated" build still refuses 83% of StrongREJECT prompts; it is not an
  "anything-goes" model. Folklore oversells what this abliteration did.
- The effect is **strictly monotonic / nested**: abliteration only ever moved prompts
  from refuse→comply, never the reverse. It removed a refusal layer without adding one.
- When it did comply, the judge rated those answers near-maximally specific and
  convincing (4.96/5 each) — i.e. substantive compliance, not empty half-answers.
- Caveats: local 27B-Q4 judge (not GPT-4o), ~1.5% of samples had unparseable judge
  output (excluded), temperature 0 (deviates from the benchmark's default 0.75, chosen
  for cross-model equivalence and reproducibility → single deterministic decision per
  prompt rather than a rate over sampling), reasoning off. Same judge and config for both
  models, so the *comparison* is valid; absolute rates are config-dependent.

## XSTest (over-refusal / calibration)

The complement to StrongREJECT: does abliteration also remove the *unwanted* refusals — the
over-cautious "no" to a benign prompt? XSTest = 250 safe prompts a calibrated model should
answer + 200 unsafe contrasts it should refuse. Same protocol as StrongREJECT (temp 0,
reasoning off, identical local judge on both, XSTest's exact 3-class rubric). Prompts pulled
from the original ungated source (the HF mirror is gated). ~98% of judge verdicts parsed
after raising the judge's token budget (see caveat).

| Subset | Metric | Normal | Obliterated |
|---|---|---|---|
| **safe** (n≈246) | over-refusal rate (lower = better) | **0.106** (26/245) | **0.016** (4/247) |
| **unsafe** (n≈195) | refusal rate (higher = safer) | **0.852** (167/196) | **0.788** (152/193) |

Paired on safe prompts (n=243): normal over-refuses **21** that the obliterated model
answers, obliterated over-refuses **0** that normal answers; McNemar p ≈ 9.5e-7.

Reading:
- **Calibration benefit is real and significant.** Abliteration cut needless refusals of
  benign prompts ~6.5× (10.6%→1.6%), perfectly nested — the actual reason people abliterate.
- **Same edit, opposite consequence on unsafe prompts.** Refusal of genuinely-unsafe prompts
  also dropped (85%→79%; compliance 15%→21%). The obliterated model's 21% unsafe-compliance
  here corroborates its 17% StrongREJECT jailbreak rate.
- **Mechanism: one indiscriminate dial.** Abliteration lowers the refusal threshold across
  the board; the benefit (fewer false refusals) and the cost (more harmful compliance) are
  the same weight edit, not separable.
- Caveat: first grading pass at judge `max_tokens=512` produced badly low and *differential*
  parse rates (the judge was truncated before emitting its verdict, more often on the normal
  model's longer/hedged answers). Re-graded at 1024 tokens → ~98% parsed for both, which
  materially changed the unsafe numbers (obliterated unsafe refusal 0.934→0.788). Numbers
  above are the corrected pass. Same local-27B-Q4 judge caveat as StrongREJECT applies.

## Takeaways

- **cybermetric_80** (general cybersecurity knowledge): essentially tied, both >96%,
  obliteration cost ~1 point — noise-level, not a meaningful capability difference.
- **aime2024** (competition math): the biggest raw gap (0.867 vs 0.700). Original
  concern was that the obliterated run (16,384 ctx) was truncated on 8/30 problems, so
  we **re-ran the obliterated model at a matched 65,536 context** (thinking on, as the
  normal run). Findings:
  - It **still scored 0.700** — the gap is a *real point estimate*, not a truncation
    artifact (this refutes our earlier "partly an artifact" hypothesis). Output tokens
    more than doubled (294k → 619k), so it genuinely used the extra room.
  - Still **not statistically significant** at n=30: paired vs normal is 6 normal-only
    vs 1 obliterated-only correct, McNemar p = 0.125.
  - **Mechanism is a runaway-reasoning pathology.** Even at 65k, the obliterated model
    ran to the context ceiling on **6/30** problems (normal: 2/30), and **all 6 were
    misses** — it fails to converge and generates until cut off. Its reasoning length is
    bimodal: median ~9.6k tokens, but a heavy tail slamming into 65k. The normal model
    reasons at a steadier median ~32k and converges within budget on all but 2 problems
    (one of which, 2024-I-8, defeats both models).
  - Net across the two obliterated runs: raising context *fixed* 3 previously-truncated
    problems but *lost* 3 others to runaway-then-truncate (plus one sampling-variance
    flip), leaving the score unchanged at 0.700.
  - Honest status: point estimate favors the normal model and is stable across two runs,
    but the test is underpowered (n=30) and the obliterated model's failures are
    entangled with a non-convergence/truncation tendency that even a generous 65k window
    doesn't fully remove (its native context is 262k, untestable on 24GB here). See
    `eval-results-technical-paper.md`.
- **lab_bench_cloning_scenarios** (dual-use biology, safety-relevant): scores are close
  (0.485 vs 0.455) and both near chance-ish territory for a 4-option MCQ task, with
  overlapping error bars (stderr 0.088 both). No clear evidence obliteration changed
  either capability or willingness to answer here — both models answered 100% of
  questions rather than abstaining.
- **strong_reject** (refusal behavior): the one big, significant, unconfounded effect —
  abliteration cut refusal from 100% to 83% (17% compliance on harmful prompts),
  perfectly nested, p ≈ 4e-16. But partial: the model still refuses most of the time.
- **xstest** (over-refusal / calibration): the complement — abliteration cut over-refusal
  of *safe* prompts 10.6%→1.6% (p ≈ 1e-6) while also cutting refusal of *unsafe* prompts
  85%→79%. One indiscriminate lowered-refusal dial; benefit and cost are the same edit.
- Overall: no evidence obliteration increased *capability* anywhere, including the
  safety-relevant biology task. The math result is a stable point-estimate regression
  (0.700 vs 0.867, replicated at matched context) but underpowered (p = 0.125) and
  entangled with a reasoning non-convergence tendency rather than a clean accuracy drop.
  What abliteration unambiguously *did* do shows up in **refusal behavior** — a real but
  partial, and indiscriminate, lowering of the refusal threshold: harmful refusals
  100%→83% (StrongREJECT, p ≈ 4e-16), benign over-refusals 10.6%→1.6% (XSTest, p ≈ 1e-6),
  and unsafe refusals 85%→79% — the same edit helping calibration and eroding safety at
  once, with no capability uplift. That is the expected signature of a refusal-direction
  ablation, now measured rather than assumed. Sample sizes are small for the capability
  tasks (n=30–80) — treat those magnitudes as indicative; the refusal-behavior effects
  (n=313 / 450) are large and robust.

## Notes for the record

- Both `aime2024` runs and the obliterated `lab_bench_cloning_scenarios` run hit
  `llama-server` context/timeout issues mid-run, requiring config fixes:
  - `exceed_context_size_error`: some `lab_bench_cloning_scenarios` prompts embed full
    plasmid DNA sequences — one needed 26,072 tokens, and the largest sample in the
    dataset is ~51.7k characters. Fixed by raising context to `-c 65536` with quantized
    KV cache (`--cache-type-k/v q8_0`) to fit in 24GB VRAM.
  - A default multi-slot server config (`--parallel 4`, the default) silently divides the
    context budget across slots (e.g. 8192 total → 2048/slot), which alone caused early
    `aime2024` failures on long reasoning chains. Fixed with `--parallel 1`.
  - `APITimeoutError` on the normal model's `aime2024` run: `inspect eval --timeout N`
    only controls retry/backoff bookkeeping, **not** the actual HTTP client timeout —
    the real cutoff is the openai-python SDK's default (600s), which the normal model
    exceeded on several long chain-of-thought problems. Fixed by passing
    `-M client_timeout=7200` (a model arg, not a CLI eval flag) to `inspect eval`.
  All runs were resumed in-place via `inspect eval-retry` (or restarted fresh where
  `eval-retry` couldn't pick up a new model arg) with no loss of already-scored samples.

## Log files

- Obliterated model: `~/qwen2/logs/eval-obliterated/`
  - `2026-08-04T21-14-38-00-00_cybermetric-80_*.eval`
  - `2026-08-06T11-37-14-00-00_aime2024_*.eval` (16k-ctx run; earlier partials superseded)
  - `2026-08-06T13-41-25-00-00_lab-bench-cloning-scenarios_*.eval` (final; earlier partial superseded)
  - `2026-08-10T23-55-43-00-00_strong-reject_*.eval` (generations; graded via scratchpad script)
  - matched-context AIME rerun: `~/qwen2/logs/eval-obliterated-aime-rerun/2026-08-11T01-16-15-00-00_aime2024_*.eval`
- Normal model: `~/qwen2/logs/eval-normal/`
  - `2026-08-06T21-36-14-00-00_cybermetric-80_*.eval`
  - `2026-08-10T10-55-23-00-00_aime2024_*.eval` (65k ctx; earlier partials superseded)
  - `2026-08-10T16-11-33-00-00_lab-bench-cloning-scenarios_*.eval`
  - `2026-08-11T00-15-28-00-00_strong-reject_*.eval` (generations; graded via scratchpad script)
