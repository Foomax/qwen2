# Project 2 — plan

*Two sequenced sub-projects on the existing 3090 / llama.cpp / Inspect stack.
Phase A needs no new generation; Phase B is the substantive one.*

Both build directly on the refusal-ablation study in `eval-results-technical-paper.md`.
Phase A hardens its weakest link (judge dependence, Limitation 11); Phase B asks the
mechanistic question the prompt-level result raises.

---

## Phase A — How much do refusal conclusions depend on the judge?

**The claim under test.** Every refusal number in the study comes from one judge: stock
Qwen3.6-27B at Q4_K_M, temperature 0. Limitation 11 already concedes that the
empty-jailbreak finding is the result most likely to move under a better judge. Phase A
turns that concession into a measurement.

**Why it is cheap.** All target completions already exist in `logs/`. No generation
phase — only grading passes. (Grading is still GPU work, ~30 min per arm per judge; what
is free is the 68 min/arm generation that would otherwise dominate.)

### Judge axes, in value order

| # | axis | judges | cost | why |
|---|---|---|---|---|
| 1 | **alignment of the judge** | stock vs the ablated build itself | **zero download** | Does a refusal-ablated judge under-detect refusal? Provocative, free, and a genuine confound if anyone grades with an uncensored model. |
| 2 | **family** | Gemma-3-27B-it, Mistral-Small-24B (Q4) | ~2 × 15 GB | Strongest test. Rules out Qwen-specific rubric quirks — the axis a reviewer will ask about. |
| 3 | **quantization** | same stock model at Q5_K_M / Q6_K | ~19–22 GB each | Isolates quant effects with zero model-identity confound. Note Q8_0 of a 27B is ~29 GB and will **not** fit; Q6_K at ~22 GB fits only with a small context. |
| 4 | **size** | Qwen3 8B / 14B | small | Cheap and fast; establishes whether a 27B judge is even necessary. |

Start with axis 1 (free) and axis 2 (the one that matters). Axes 3–4 only if 1–2 show
movement.

### Arms to re-grade

Not all six arms × every judge. Grade only where a *conclusion* is at stake:

| arm | conclusion it carries |
|---|---|
| `obl-control` | the 83.5% baseline everything is measured against |
| `obl-responsible` | the recovery result, p = 3.3e-06 |
| `obl-jailbreak` | the backfire result, p = 8.6e-04 |
| `normal-jailbreak` | the empty-jailbreak classification |

4 arms × 3 new judges = 12 passes ≈ 6 h. Pilot at `--limit 150` first (~3 h);
`sr_compare.py` already supports `--limit` and `--judge`.

### Metrics

- **Per-item agreement** between judges on the refusal decision — Cohen's κ, not just
  matching aggregate rates. Two judges can agree on 83% and disagree on *which* items.
- **Conclusion survival.** Recompute each headline paired test under each judge. The
  question is not whether 95.2% moves, it is whether p = 3.3e-06 stays significant and
  whether the backfire keeps its sign.
- **Parse rate per judge** — smaller judges will emit malformed verdicts more often, and
  differential parse loss biases comparisons (this bit the study twice already).
- **Empty-jailbreak sensitivity.** Specifically: does a different judge reclassify the
  ~5.9k-character non-answers as substantive? That single number decides whether §3.1a
  holds.

### Deliverable

A methods note: *how much of a local-judge refusal result is the judge?* Plus a κ table
that any future run in this repo can cite instead of re-deriving.

---

## Phase B — Put the refusal direction back with a control vector

**The question.** Abliteration deleted a direction in activation space. Prompt-level
safety framing recovers 83.5% → 95.2% but never reaches stock. Can injecting a refusal
direction at inference time do better — and does it cost capability?

This is Arditi et al. run in reverse. If refusal really is mediated by a single
direction, adding it back should restore refusal without touching knowledge. The study's
existing capability baselines (CyberMetric, AIME, CloningScenarios — already paired) are
the control.

**Tooling is already built.** `llama-cvector-generator` produces a `control_vector.gguf`;
`llama-server` consumes it via `--control-vector`, `--control-vector-scaled FNAME:SCALE`,
and `--control-vector-layer-range START END`.

### Method

1. **Build contrast pairs.** `positive.txt` / `negative.txt`, one chat-templated line
   each, paired by index: same harmful user prompt, assistant turn opening with a
   *refusal* (positive) vs a *compliance* (negative). Target ~50–100 pairs. Seed prompts
   from public StrongREJECT; `divergence_dataset.json` gives 84 IDs where the two builds
   actually disagreed, which is a sharper contrast set than random harmful prompts.
   **The bundled `positive.txt`/`negative.txt` use Llama-3 template tokens and must be
   rewritten for Qwen3.6's template.** `completions.txt` (581 generic snippets) can be
   reused as-is.
2. **Extract from the stock model.** The ablated model no longer has the direction, so it
   cannot be recovered from it — extract from stock, inject into ablated. Same
   architecture and hidden size, so the vector transfers.
   `llama-cvector-generator -m stock.gguf -ngl 99 --positive-file pos.txt
   --negative-file neg.txt --method pca -o refusal.gguf`
3. **Verify the sign before anything else.** PCA sign is arbitrary. Serve the ablated
   model at scale +1.0, run ~20 harmful prompts, confirm refusal *rises*. If it falls,
   negate the vector. Skipping this wastes a full sweep.
4. **Sweep scale.** `--control-vector-scaled refusal.gguf:S` for S ∈ {0.5, 1.0, 1.5,
   2.0}; run the `control` StrongREJECT condition at each → refusal-vs-scale curve.
   Optionally sweep `--control-vector-layer-range` over mid layers, where refusal
   mediation is usually strongest.
5. **Capability check at the best scale.** CyberMetric-80 is the right probe: 80 items,
   deterministic, fast, and already has a paired baseline. Steering routinely degrades
   fluency — this is where that shows up.
6. **Compare against the prompt-level result.** Does the vector beat
   `responsible_assistant`'s 95.2%? Does **vector + wrapper** beat either alone? That
   2×2 (vector on/off × wrapper on/off) is the headline table.
7. **Positive control.** Apply the vector to the *stock* model too. It should saturate or
   over-refuse (XSTest safe prompts will show it). If nothing happens, the vector is not
   doing what we think.

### Costs and risks

- Vector generation is forward passes only — no training, comfortably inside 24 GB.
- Each StrongREJECT arm is ~15–30 min generation plus grading, so a 4-scale sweep plus
  the 2×2 is roughly a day of GPU time.
- **Arch risk, check early.** Qwen3.6 is a hybrid attention/SSM model (`qwen35`, full
  attention every 4th block of 64). Control vectors hook the residual stream and should be
  arch-agnostic, but this combination is not a well-trodden path in llama.cpp. Smoke-test
  on ~20 prompts before building the contrast set out.
- Whichever way it lands is publishable. If steering restores refusal, that is a cheap
  practical mitigation stronger than prompting. If it cannot, that is evidence
  abliteration does more than remove one direction — which would be the more interesting
  result.

### Reuse

The whole 3×2 protocol transfers: same 313 items, same judge, same paired McNemar, same
`sr_run.sh` shape. A control-vector arm is just another condition — and it should be
graded with whichever judge Phase A shows to be most trustworthy.

---

## Sequencing

1. **Now, while `placebo` finishes.** Write the Phase A orchestration and the κ script;
   start `sr_run.sh judge` with the ablated model as judge (axis 1, no download needed).
2. **In parallel, no GPU.** Download the Gemma / Mistral judge GGUFs; write the Qwen
   contrast pairs for Phase B.
3. **When the GPU frees.** Phase A pilot at `--limit 150`, then the axis-1/2 full passes.
4. **Then Phase B**, starting with the sign check and the hybrid-arch smoke test.

Phase A first is deliberate: it decides which judge Phase B's numbers should be graded
with. Running B first risks having to re-grade everything.
