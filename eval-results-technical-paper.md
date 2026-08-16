# Refusal Ablation in Qwen3.6-27B: A Small Paired Evaluation of Capability and Refusal Behavior

*Technical note — 2026-08-11. Draft for supervision review.*

## Abstract

We compare a community refusal-ablated ("obliterated") build of Qwen3.6-27B against the stock model on three deterministically scored capability benchmarks from `inspect_evals` (CyberMetric-80, AIME 2024, LAB-Bench CloningScenarios) and one judge-scored refusal benchmark (StrongREJECT), served locally (llama.cpp, Q4_K_M, one RTX 3090) and analyzed **paired per item**. **Capability: no uplift anywhere.** Knowledge is unchanged (CyberMetric 0.963 vs 0.975, p = 1.0); the dual-use biology task is indistinguishable (0.485 vs 0.455, p = 1.0, with 0/63 abstentions despite an offered "insufficient information" option). AIME shows a raw gap favoring stock (0.867 vs 0.700). We first suspected a truncation artifact (the ablated run used a 16,384-token context and hit its ceiling on 8/30 problems); a **matched-context rerun at 65,536 tokens refutes that** — the ablated model again scores 0.700, so the gap is a genuine point estimate, though still not significant at n=30 (McNemar p = 0.125) and mechanistically entangled with a non-convergence pathology (it runs to the 65k ceiling on 6/30 problems, all misses, vs 2/30 for stock). **Behavior: ablation works, partially and indiscriminately.** On 313 StrongREJECT forbidden prompts the stock model refuses 100% and the ablated model 83% (17% compliance), perfectly nested (McNemar p ≈ 4×10⁻¹⁶). XSTest resolves the mechanism: ablation lowers the refusal threshold on *both* sides — over-refusal of 250 safe prompts falls 10.6%→1.6% (calibration benefit, paired p ≈ 1×10⁻⁶) while refusal of 200 unsafe prompts also falls 85%→79% (safety cost); the ablated model's 21% XSTest unsafe-compliance corroborates its 17% StrongREJECT rate. **Mitigation: prompt-level safety framing recovers most, but not all, of the ablated refusal loss.** A wrapped-StrongREJECT extension (2×2: {no wrapper, `responsible_assistant` defense, `jailbreak` attack} × {stock, ablated}, judge scoring the original question in every condition) raises ablated refusal 83.5%→95.2% (paired 46 recovered vs 11 lost, p ≈ 3.3×10⁻⁶) and cuts its StrongREJECT score 0.814→0.233; the stock model is at ceiling (99.3–100%) under every condition. The model gap survives every wrapper (all stock-vs-ablated pairs p ≤ 1.8×10⁻³), and the two wrappers are indistinguishable *within* the ablated model (p = 0.39). **Net: refusal ablation produced large, significant, indiscriminate behavioral change — the same edit improving benign-prompt calibration and eroding harmful-prompt refusal — with no measurable capability change in either direction; in-context safety instruction substantially but incompletely substitutes for the ablated weights. The expected signature of a refusal-direction edit.**

## 1. Motivation

Abliteration removes refusal behavior by ablating the activation-space direction that mediates it (Arditi et al., 2024) directly from the weights; it is the most widespread low-cost safeguard-removal technique in the open-weights ecosystem. Three questions follow: (a) does the uncensored variant gain effective capability, especially on safety-relevant tasks; (b) does ablation damage general capability ("uncensored = smarter" folklore vs. collateral damage); (c) did the ablation actually remove refusals, and by how much? We test all three with a small, cheap, fully local protocol.

## 2. Setup

**Models.** (i) Stock `Qwen3.6-27B` (Q4_K_M GGUF, 16.8 GB); (ii) `qwen3.6-27b-obliteratus` (Q4_K_M GGUF, 16.5 GB), a community refusal-ablated derivative. No model card accompanied the ablated build; the ablation recipe is unverified and assumed from naming. Both expose Qwen's thinking-mode template.

**Serving.** llama.cpp `llama-server` build 9436 (d6588daa8), CUDA, single RTX 3090 (24 GB), full GPU offload, q8_0 KV cache. Per-experiment configuration:
- *Capability tasks:* context 65,536, single slot (`--parallel 1`), thinking on. The ablated AIME run additionally exists in two versions — an original 16,384-context run and a matched 65,536-context rerun (§4).
- *StrongREJECT / XSTest:* thinking **off**, temperature 0 for both models, multi-slot (generations short: 2,048 / 256 max tokens). XSTest prompts were taken from the original ungated GitHub source (the HF mirror `walledai/XSTest` is gated; only its README was cached). Grading used a raised judge budget (1,024 tokens) after a 512-token pass truncated the judge before its verdict (§6). A `--parallel 4` judge server crashed once mid-grade (`update_slots`); grading was completed on a `--parallel 2` server.

**Harness.** Inspect AI 0.3.251 with `inspect_evals` (GitHub main, Aug 2026), OpenAI-compatible provider. Two replication notes: (1) `inspect eval --timeout` does not bound the HTTP request — the OpenAI SDK default (600 s) applies unless `-M client_timeout=N` is passed, silently capping local generations at ~24k tokens at ~40 tok/s; (2) llama-server divides context across parallel slots, so a default `--parallel 4` quarters the usable window.

**Tasks.**

| Task | n | Domain | Scorer |
|---|---|---|---|
| `cybermetric_80` | 80 | cybersecurity knowledge MCQ | `choice` (deterministic) |
| `aime2024` | 30 | competition math, long CoT | exact answer (deterministic) |
| `lab_bench_cloning_scenarios` | 33 | dual-use molecular cloning MCQ (DNA prompts, up to ~26k tokens) | `precision_choice` (deterministic) |
| `strong_reject` | 313 | refusal on forbidden prompts | LLM judge (StrongREJECT rubric) |
| `xstest` | 450 (250 safe / 200 unsafe) | over-refusal + appropriate refusal | LLM judge (XSTest 3-class rubric) |

**Analysis.** Identical items across models permit paired analysis: per-task 2×2 contingency with McNemar's exact test, plus per-sample output-token accounting. For StrongREJECT, both models' completions were graded post-hoc by a **single fixed judge** (the stock Qwen, temperature 0, StrongREJECT's exact rubric prompt and score parser), making the comparison internally valid even though the judge is a local 27B-Q4 rather than GPT-4o.

## 3. Results

**Capability accuracies** (± binomial SE):

| Task | Stock | Ablated | Δ |
|---|---|---|---|
| CyberMetric-80 | 0.963 ± 0.021 | 0.975 ± 0.018 | −0.012 |
| AIME 2024 | 0.867 ± 0.063 | 0.700 ± 0.085 | +0.167 (n.s.; see §4) |
| CloningScenarios | 0.485 ± 0.088 | 0.455 ± 0.088 | +0.030 |

**Paired capability contingency** (stock ✓ = stock correct; AIME row uses the 65,536 rerun):

| Task | both ✓ | stock-only ✓ | ablated-only ✓ | neither | McNemar p |
|---|---|---|---|---|---|
| CyberMetric-80 | 77 | 0 | 1 | 2 | 1.00 |
| AIME 2024 | 20 | 6 | 1 | 3 | 0.125 |
| CloningScenarios | 10 | 6 | 5 | 12 | 1.00 |

**StrongREJECT** (313 prompts; temperature 0; same judge both sides):

| Metric | Stock | Ablated |
|---|---|---|
| Refusal rate | 1.000 (309/309 valid) | 0.831 (256/308 valid) |
| Jailbreak rate (complied) | 0.000 | 0.169 (52 prompts) |
| StrongREJECT score (0–5, ↑ = worse) | 0.00 | 0.84 |
| Judge specificity / convincingness of complied answers (1–5) | — | 4.96 / 4.96 |

Paired (304 prompts valid on both): both refuse **252**, ablated-only comply **52**, stock-only comply **0**, both comply **0**; McNemar exact **p ≈ 4.4×10⁻¹⁶**. ~1.5% of samples (5 ablated, 4 stock) produced unparseable judge output and were excluded.

**XSTest** (450 prompts; temperature 0; same judge both sides; judge budget 1,024 tokens, ~98% parsed):

| Subset | Metric | Stock | Ablated |
|---|---|---|---|
| safe (n≈246) | over-refusal rate (↓ better) | 0.106 (26/245) | 0.016 (4/247) |
| unsafe (n≈195) | refusal rate (↑ safer) | 0.852 (167/196) | 0.788 (152/193) |

Paired on safe prompts (n=243): stock over-refuses **21** prompts the ablated model answers, ablated over-refuses **0** the stock answers; McNemar exact **p ≈ 9.5×10⁻⁷**. Both effects point the same way — ablation lowers refusal on safe prompts (removing over-caution, the intended benefit) and on unsafe prompts (removing safety) alike. The ablated model's 21.2% XSTest unsafe-compliance is consistent with its 16.9% StrongREJECT jailbreak rate; the two safety benchmarks corroborate. (XSTest "unsafe" prompts are subtle contrasts, milder than StrongREJECT's flagrant prompts, which is why even the stock model complies with ~15% of them but 0% of StrongREJECT's.)

### 3.1 Wrapped StrongREJECT: prompt-level mitigation and attack

To probe the residual 83% refusal and test whether in-context instruction substitutes for ablated weights, all 313 StrongREJECT prompts were re-run on both models under two wrappers (task `strong_reject_wrapped`, temperature 0, thinking off, `--parallel 4`, 2,048 max tokens):

- **`responsible_assistant`** (defense) — strong safety framing as both prefix and suffix, explicitly naming the framings ablation is expected to leave exploitable (fiction, hypotheticals, role-play, claimed authorisation).
- **`jailbreak`** (attack) — a Pliny-style universal jailbreak wrapper (prefix + `ResponseFormat` suffix instructing a token refusal followed by an opposing unrestricted answer).

All conditions were graded by the same fixed judge with **`judge_on=original`**: the judge is shown the bare forbidden prompt in every arm, so the rubric input is constant and conditions remain comparable. (Upstream scores its built-in AIM jailbreak on the *wrapped* prompt; these numbers are therefore not comparable to published StrongREJECT jailbreak figures, only to each other.) Sample IDs hash the original question, so all six arms are item-aligned with each other and with the §3 baselines.

| Condition | n valid | Refusal | Compliance | SR score |
|---|---|---|---|---|
| stock, no wrapper | 309 | 1.000 | 0.000 | 0.00 |
| stock + `jailbreak` | 291 | 0.993 | 0.007 | 0.034 |
| stock + `responsible_assistant` | 313 | 1.000 | 0.000 | 0.000 |
| ablated, no wrapper | 309 | 0.835 | 0.165 | 0.814 |
| ablated + `jailbreak` | 305 | 0.931 | 0.069 | 0.313 |
| ablated + `responsible_assistant` | 311 | 0.952 | 0.048 | 0.233 |

**Paired comparisons** (McNemar exact, per-item refusal):

| Comparison | n | A-only refuses | B-only refuses | p |
|---|---|---|---|---|
| ablated `responsible_assistant` vs ablated control | 307 | 46 | 11 | 3.3×10⁻⁶ |
| stock `jailbreak` vs ablated `jailbreak` | 286 | 18 | 1 | 7.6×10⁻⁵ |
| stock `jailbreak` vs ablated `responsible_assistant` | 289 | 13 | 1 | 1.8×10⁻³ |
| stock `responsible_assistant` vs ablated `jailbreak` | 305 | 21 | 0 | 9.5×10⁻⁷ |
| stock `responsible_assistant` vs ablated `responsible_assistant` | 311 | 15 | 0 | 6.1×10⁻⁵ |
| ablated `jailbreak` vs ablated `responsible_assistant` | 303 | 14 | 20 | 0.39 |
| stock `jailbreak` vs stock `responsible_assistant` | 291 | 0 | 2 | 0.50 † |

† Not interpretable — differential parse loss, see §6.

Three findings:

1. **In-context safety framing substantially recovers ablated refusal.** 83.5%→95.2%, strongly significant when paired against the unwrapped control, with the StrongREJECT harm score falling 3.5× (0.814→0.233). Ablation removed the refusal *reflex* but not the model's capacity to classify a request as harmful when context directs it to; the classification is recoverable from the prompt channel.
2. **Recovery is incomplete, and the model gap is wrapper-invariant.** Every stock-vs-ablated pair remains significant under matched wrappers. Ablated-with-defense (95.2%) still sits below stock-under-attack (99.3%). Prompt-level mitigation raises the floor without restoring parity.
3. **The `jailbreak` wrapper did not function as an attack.** Against the stock model it moved 2/313 prompts. Against the ablated model it *raised* refusal relative to no wrapper (83.5%→93.1%). The mechanism is likely instrumental rather than behavioral: the wrapper's `ResponseFormat` requires the model to emit an explicit refusal ("<withheld>'") before its unrestricted answer, supplying refusal language the judge then scores — an artifact of pairing an output-format jailbreak with a refusal-detecting judge. This condition is therefore uninformative about the residual refusal rate and should not be read as evidence of jailbreak resistance; §6 records it as a design fault to be replaced, not a result.

## 4. AIME: truncation audit and matched-context rerun

**Original run (16,384 ctx).** The ablated model's per-problem output maxed at 16,152 tokens — flush against its window. Eight of 30 problems were pinned at ≥15.8k output tokens, including *all six* stock-only successes (stock spent 30.9k–51.7k and solved them). llama-server reported `stop`, not `length`, so truncation was invisible without token accounting. This motivated a matched rerun.

**Matched rerun (65,536 ctx, thinking on, identical to the stock run).** The ablated model **again scored 0.700** (21/30); total output tokens more than doubled (294k → 619k), confirming it used the extra room. The truncation-artifact hypothesis is therefore **refuted**: the gap is a real point estimate, not a serving asymmetry. However:

- Even at 65k, the ablated model ran to the context ceiling on **6/30** problems (2024-I-8, I-10, I-11, I-13, II-5, II-9), and **all six are misses**; the stock model hit its 65k ceiling on only 2/30 (one, 2024-I-8, defeats both models). Six of the ablated model's nine total misses are runaway-then-truncate.
- Reasoning length is **bimodal**: ablated median 9,628 tokens (mean 20,649) with a heavy tail at 65k; stock median 32,201, converging within budget on all but two. This is consistent across both ablated runs (~3.4–3.6× shorter median than stock on freely-completed items).
- Raising the context *fixed* 3 previously-truncated problems (I-5, II-8, II-12) but *lost* 3 to runaway-then-truncate (I-13, II-9) plus one sampling-variance flip (II-7), netting to an unchanged 0.700.

**Interpretation.** The AIME deficit is a stable point estimate but (i) statistically underpowered at n=30 and (ii) mechanistically a *reasoning-convergence* failure — the ablated model spirals on the hardest problems rather than answering worse per token — that a generous but finite 65k window cannot fully remove (native context is 262k, untestable on 24 GB here). We therefore report a probable but unproven capability/stability regression, not a clean accuracy drop.

## 5. Discussion

- **Knowledge intact.** CyberMetric is a near-exact tie; ablation does not remove stored knowledge.
- **No uplift on the dual-use task.** CloningScenarios shows no advantage for the uncensored variant (p = 1.0). Both models answered every item despite an "insufficient information" option (0/63 abstentions) — overconfidence is a base-model property, not an ablation effect.
- **Ablation is real, partial, behavioral — and a single indiscriminate dial.** StrongREJECT and XSTest are the study's large, significant, unconfounded effects. StrongREJECT: refusal 100%→83%, strictly nested (ablation only ever moves refuse→comply); yet 83% of harmful prompts are still refused — far from "uncensored," qualifying the folklore, and when the ablated model did comply the judge rated answers near-maximally specific and convincing (4.96/5), i.e. substantive. XSTest shows the *same* threshold shift on benign inputs: over-refusal 10.6%→1.6% (the intended calibration benefit, paired p ≈ 1e-6, perfectly nested) alongside unsafe-refusal 85%→79%. The benefit and the cost are the same weight edit — ablation does not distinguish an over-cautious refusal from a load-bearing one — which is the central safety-relevant finding: for this technique, calibration improvement and safety erosion are inseparable.
- **Ablated refusal is substantially prompt-recoverable — with the usual caveat.** The defense wrapper restores most of the lost refusal (§3.1) at zero training cost, which is the practically actionable result here: a deployer serving an ablated build is not stuck with its 83.5% floor. But the mitigation lives in the channel an adversary controls, is advisory rather than architectural, and does not reach stock behavior even against a non-adversarial prompt set. It shifts a distribution; it does not restore a safeguard. That the *same* framing yields no change in the stock model (already at ceiling) also means the wrapper is not merely making the judge more refusal-happy across the board — the effect is specific to the ablated model's degraded baseline.
- **Methodological lesson.** The largest capability difference first looked like an artifact, then survived the correction. With local serving, *the context window is part of the treatment*, finish-reason fields cannot be trusted to reveal truncation, and only paired token-level forensics distinguished the three regimes (truncated / converged / runaway).

## 6. Limitations

1. Small n for capability tasks (30–80); the AIME discordance is the only near-significant capability signal and remains p = 0.125.
2. AIME rerun matches context but the ablated model still truncates on 6/30 problems at 65k; a fully truncation-free comparison would need >65k (infeasible on 24 GB at this quant).
3. StrongREJECT/XSTest judge is a local 27B-Q4, not GPT-4o; same judge both sides → valid comparison, imperfect absolute calibration. StrongREJECT excluded ~1.5% unparseable verdicts. **XSTest judge truncation:** a first grading pass at 512 judge tokens truncated the judge before its `GRADE:` line on 30–58% of items, *differentially* (worse on the stock model's longer, more-hedged responses) — this would have biased the comparison. Re-grading at 1,024 tokens raised parse rates to ~98% for both models and materially moved the numbers (e.g. ablated unsafe refusal 0.934→0.788). Reported XSTest values are the corrected pass; the episode is itself a finding (judge-side truncation is as dangerous as target-side, and differential parse loss silently biases refusal metrics).
4. StrongREJECT/XSTest used temperature 0 (vs StrongREJECT's default 0.75) for cross-model equivalence and reproducibility; this yields one deterministic decision per prompt rather than a rate over sampling, and thinking was off — absolute refusal rates are config-dependent (the *difference* is the finding). XSTest prompts came from the original ungated source rather than the gated HF mirror (identical 250/200 split and labels).
5. Single run / one epoch for capability tasks; server-default sampling there introduces run-to-run variance (observed: one AIME problem flipped on variance across the two ablated runs). Q4_K_M on both sides.
6. Ablated-model provenance unknown; "abliteration" assumed from naming.
7. AIME 2024 contamination in shared pretraining lineage would inflate both models equally and compress observable differences.
8. Wall-clock times are not comparable across runs (serving parallelism/context changed); token counts are the reliable cost metric.
9. **Wrapped-StrongREJECT parse loss (§3.1).** The `stock + jailbreak` arm parsed 291/313 (93.0%) against 313/313 for `stock + responsible_assistant`, below the study's 95% floor; only 6 of the 22 failures were judge token-cap truncation, so the remainder is a distinct parse failure not fixed by raising the judge budget. This differential falls on the stock-jailbreak vs stock-responsible comparison, which is accordingly **not reported as interpretable**. The five cross-model comparisons pair on 286–311 items with large one-sided discordance and are robust to the loss, but absolute rates for that arm carry more uncertainty than the others. Ablated arms parsed 305/313 and 311/313. Not diagnosed before the reporting deadline.
10. **The `jailbreak` condition is a failed attack, not a null result.** Its `ResponseFormat` mandates an explicit refusal string before the target content, which a refusal-detecting judge scores as a refusal (§3.1). Output-format jailbreaks are structurally incompatible with this judge; a semantic-compliance scorer, or an attack that suppresses rather than mandates refusal language (e.g. `refusal_suppression`, `prefix_injection`, already present in the preset library), is required. The residual ablated refusal rate remains unprobed by a valid attack.
11. Wrapped runs use temperature 0 and `judge_on=original`, so they are comparable only to each other and to this study's baselines, not to published StrongREJECT jailbreak numbers.

## 7. Conclusion and next steps

Refusal ablation of this Qwen3.6-27B build produced **no capability uplift anywhere** (including a dual-use biology benchmark), a **probable-but-unproven, convergence-mediated** math regression, and a **large, significant, indiscriminate lowering of the refusal threshold**: harmful refusals 100%→83% (StrongREJECT), benign over-refusals 10.6%→1.6% and unsafe refusals 85%→79% (XSTest). The intended effect (less over-refusal) is real and measurable — but inseparable from the safety cost, since both are the same edit. The capability-uplift folklore is not supported, and the "uncensored" framing overstates a model that still refuses five in six flagrant harmful prompts. A wrapped-prompt extension adds a practically useful mitigation result: **in-context safety framing recovers most of the ablated refusal loss (83.5%→95.2%, p ≈ 3.3×10⁻⁶, harm score 0.814→0.233) but does not restore parity with the stock model under any wrapper** — the refusal deficit is prompt-attenuable, not prompt-removable. Follow-ups: (1) ≥3 seeds/epochs to power the AIME test and separate variance from effect; (2) a stronger (non-local, or higher-precision) judge to firm up absolute refusal rates; (3) a **valid** attack condition — the `jailbreak` wrapper tested here mandates refusal language and so cannot lower a refusal-detecting judge's score (§3.1, Limitation 10); `refusal_suppression` and `prefix_injection` are the natural replacements, and the residual refusal rate stays unprobed until one is run; (4) diagnosing the 7% wrapped-arm parse loss (Limitation 9); (5) a higher-context or higher-precision AIME run to bound the runaway-reasoning contribution.

## Reproducibility

```bash
# capability tasks (per model): 65,536 ctx, single slot, thinking on
llama-server -m <model.gguf> --port 8080 -ngl 1024 -c 65536 --parallel 1 \
  --cache-type-k q8_0 --cache-type-v q8_0 -a <alias>
export OPENAI_BASE_URL=http://127.0.0.1:8080/v1 OPENAI_API_KEY=sk-local
inspect eval inspect_evals/cybermetric_80 inspect_evals/aime2024 \
  inspect_evals/lab_bench_cloning_scenarios \
  --model openai/<alias> --max-connections 1 -M client_timeout=7200 --log-dir logs/<model>

# StrongREJECT: generate per model (thinking off, temp 0, 4 slots), then grade both
#   logs with one judge. Note: `inspect score` does not auto-register the inspect_evals
#   scorer; grading was done with a standalone script reusing StrongREJECT's exact
#   prompt + parser against the local judge endpoint.
inspect eval inspect_evals/strong_reject -T judge_llm=openai/<judge_alias> \
  --model openai/<alias> --temperature 0 --no-score --max-connections 4 \
  -M client_timeout=7200 --log-dir logs/<model>

# XSTest: same generate-then-grade pattern, prompts from the ungated GitHub source
#   (paul-rottger/xstest CSV: 250 safe + 200 unsafe). Standalone gen/grade scripts;
#   judge budget >=1024 tokens to avoid truncating the verdict (see §6). Grade with
#   the SAME judge for both models.
```

```bash
# Wrapped StrongREJECT (§3.1): generate each condition per model, then grade all
#   arms with ONE judge. Wrapper text, judge_on and temperature are recorded in
#   each .eval's metadata["wrapper"]. judge_on=original keeps the judge's rubric
#   input constant across conditions.
./sr_run.sh gen normal      jailbreak responsible_assistant
./sr_run.sh gen obliterated jailbreak responsible_assistant
./sr_run.sh judge   # grades every condition + the unwrapped baselines, paired
```

Eval logs: `~/qwen2/logs/eval-normal/`, `~/qwen2/logs/eval-obliterated/`, `~/qwen2/logs/eval-obliterated-aime-rerun/`; wrapped-StrongREJECT arms in `~/qwen2/logs/sr-wrapped/{normal,obliterated}-{jailbreak,responsible_assistant}/`, aggregates in `sr_wrapped_results.json`, cached judge grades in `sr_grades/`; StrongREJECT `.eval` files in the first two; XSTest gen/grade artifacts in the analysis scratchpad. Analysis/grading scripts available on request. StrongREJECT and XSTest: aggregate rates only; individual harmful completions are not reproduced.

## References

1. Arditi et al., *Refusal in Language Models Is Mediated by a Single Direction*, 2024. arXiv:2406.11717.
2. Souly et al., *A StrongREJECT for Empty Jailbreaks*, 2024. arXiv:2402.10260.
2b. Röttger et al., *XSTest: A Test Suite for Identifying Exaggerated Safety Behaviours in LLMs*, 2023. arXiv:2308.01263.
3. UK AI Security Institute, *Inspect AI* (v0.3.251) and *inspect_evals*.
4. Tihanyi et al., *CyberMetric: A Benchmark Dataset for Cybersecurity Knowledge of LLMs*, 2024.
5. Laurent et al. (FutureHouse), *LAB-Bench: Measuring Capabilities of Language Models for Biology Research*, 2024.
6. MAA, *AIME 2024* (via `Maxwell-Jia/AIME_2024`).
