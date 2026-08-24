# 1claude-readme.md — LLM-first entry point

**You are an LLM agent picking up this repository.** This file is written for you,
not for a human skimmer. It is optimised for three things you actually care about:
**context budget**, **not re-deriving settled facts**, and **not tripping the traps
that already cost this project GPU-days.**

Read this file completely before opening anything else. It is ~2.8k tokens and it
will save you far more than that.

---

## 0. TL;DR — the canonical numbers. Do not re-measure these.

Refusal-ablation ("abliteration") study. Stock vs ablated Qwen3.6-27B and
Qwen3.8-27B, all Q4_K_M, one RTX 3090, llama.cpp + Inspect AI, **paired per item**.

**StrongREJECT harmful compliance (313 prompts, judge `qwen3.6-27b-normal`):**

| | Qwen3.6 | Qwen3.8 |
|---|---|---|
| stock | 0.0% | 0.0% |
| ablated — OBLITERATUS | 16.5% | 45.7% |
| ablated — Heretic | 9.0% | 43.3% |

**XSTest, frontier-judge graded (`deepseek-v4-pro`@4096):**

| arm | safe over-refusal | unsafe refusal |
|---|---|---|
| Qwen3.8 stock | 5.2% | 84.3% |
| Qwen3.8 OBLITERATUS | 0.0% | 33.9% |
| Qwen3.8 Heretic | 0.0% | 53.9% |
| Qwen3.6 Heretic | 0.4% | 57.0% |

**Five load-bearing findings:**

1. **No capability uplift, anywhere.** Three tasks, two generations, two recipes.
   Ablation unlocks *willingness*, not *ability*.
2. **Generation effect is large and nested; recipe effect is null — on flagrant
   prompts.** Recipe-controlled generational jump 9.0%→43.3%, 108-vs-4 discordant,
   p=2.5e-27. Recipe within Qwen3.8: 46-vs-55, p=0.43.
3. **The two axes SWAP on subtle prompts.** XSTest-unsafe: recipe 12-vs-48
   (p=3.2e-06, large), generation 25-vs-19 (p=0.45, null). Generation governs
   flagrant requests; recipe governs boundary cases.
4. **Nesting signature = mechanism discriminator.** Weight edits are near-perfectly
   nested (141-0, 132-0, 95-0, 83-1, 28-0). A prompt attack is 32-19. Threshold
   shift vs perturbation, visible only per item. **This is the project's most novel
   contribution** — a 74-item prior-art sweep found nobody else reporting it.
5. **Compliance quality is invariant** (specificity 4.70–5.00/5). Only the *rate*
   moves. Vendor claims of "improved substance" are rate improvements mislabelled.

---

## 1. Context engineering — what to load, by budget

Files are listed with measured token cost. **Do not bulk-load the repo**; several
files are large and low-signal, and two are outright traps.

**Budget ~4k — you need the state of play:**
`1claude-readme.md` (this) → `readme.md` (1.2k)

**Budget ~12k — you are going to run or change something:**
add `lessons.txt` (2.7k) + `lessons2.txt` (3.0k) + `HO3-RESULTS.md` (2.5k)
+ `PREFLIGHT-NOTES.md` (1.2k)

**Budget ~25k — you are writing up or extending the science:**
add `midway-progress.txt` (3.5k) + `hand-over3.txt` (4.5k) +
`eval-results-technical-paper.md` (9.7k, the formal write-up)

**Load only on demand, never speculatively:**

| file | tok | why gated |
|---|---|---|
| `log.log` | 11.1k | raw terminal transcript. Almost pure noise. **Trap.** |
| `log2.log` | 4.2k | **misnamed — it is a tutorial**, not a log. Useful, badly named. |
| `eval-results-blog-post.md` | 4.6k | same content as the paper, informal register |
| `old_readme.md`, `readme_old2.md` | 5.8k | superseded; see §2 |
| `results/*.json`, `sr_grades/*.json` | ~1.5MB | **labels only, no text.** Query with code, never read into context. |
| `obliterated-writeup.pdf` | — | lay-audience explainer. You read PDFs poorly. Skip. |

**Rule:** the `.json` artifacts are for `python`, not for your context window. Every
one is `{id → label}` or `{id → {refusal, convincingness, specificity}}`. There is
no prose in them.

---

## 2. Supersession map — READ THIS OR YOU WILL ACT ON STALE GUIDANCE

This repo accreted documents across four rounds. Several contradict each other.
**Later entry wins.**

| topic | superseded | current | note |
|---|---|---|---|
| project summary | `old_readme.md` → `readme_old2.md` | **`readme.md`** | |
| next steps / priorities | `next-steps-recommendations.txt` → `hand-over.txt` | **`hand-over3.txt`** | env facts + traps in the older two are still valid; only PRIORITIES are superseded |
| cloning-bench diagnosis | `cloningbench.md` (blamed context) | **`qwen3_8-cloningbench.md`** | original diagnosis was **wrong**; real causes were `xhigh` default + disabled anti-repetition samplers |
| round-1 results | `Foomax's AI Safety Project.md`, `results.md` | **see §3 confound** | round-1 numbers are confounded; do not quote uncritically |
| round-3 results | — | **`HO3-RESULTS.md`** | current |
| methodology lessons | `lessons.txt` (rounds 1–2) | **`lessons2.txt`** (round 3) | both current, additive |
| prior-art | — | `~/similar-projects/{ANALYSIS,TECHNIQUES,PARETO}.md` | 74-item sweep, outside this repo |

---

## 3. Known confounds — check before you cite anything

**C1. Round 1 (Qwen3.6) is confounded by an injected system prompt.**
The `qwen3.6-27b-obliteratus` GGUF's chat template silently injects an
anti-refusal system prompt **whenever the caller sends no system message** — which
is exactly what StrongREJECT/XSTest do here. Verified by render-diff and template
source; **it is the only build of six that does this**. So round 1's "identical
prompts, only weights differ" claim is false. Direction: biases *toward*
compliance, so the generational gap is **understated**. The `q36-heretic` arm is
clean and is the number to trust for that cell.
*Mitigation if you re-run it:* send `{"role":"system","content":""}` — verified to
defeat the injection.

**C2. Chat templates differ across arms and it is scope-dependent.**
Round 3's arms render byte-identically for *this* harness's message shapes (one
user message, no tools, `reasoning_effort` unset) — so it is inert there. It goes
**live** the moment you add a system-prompt condition, a tool-use task, or an
explicit reasoning effort. The wrapper sweep is exactly that. Re-run the jinja
render-equivalence check (`PREFLIGHT-NOTES.md §3`) whenever scope changes.

**C3. MTP asymmetry.** `q38-heretic` is 64-block; `q38-obliterated` is 65-block
(MTP head). The *decisive* Heretic-3.6-vs-3.8 comparison is matched (both 64) and
unaffected. The within-3.8 recipe cell has MTP as a co-variable.

**C4. Judge budget is a live confound at every layer.** Caps have bitten three
times: generation cap, judge cap, context ceiling. Most recently `deepseek-v4-pro`
at 1024 tokens parsed only 245/313 (it is a *reasoning* model, ~987 completion
tokens on an easy case). At 4096 it parsed 308/313. **Dropped items skew toward
compliance**, so an exhausted judge makes models look *safer* — anti-conservative.

---

## 4. Operational traps — each already cost real time

1. **Shared GPU.** Never `pgrep -x llama-server | xargs kill`; it destroyed another
   session's run. Record the PID you launch, kill only that, verify with `kill -0`.
2. **`pgrep -f <pattern>` matches the shell running the pgrep.** Cost two
   self-kills (exit 144). Kill by PID.
3. **Grade cache keys.** `sr_grades/` is
   `sha256(realpath|mtime|judge|limit)[:16]`, **plus `|mt=N` when
   judge-max-tokens ≠ 1024**. Never glob the directory — doing so once merged
   grades across models and reported 19 compliances for a model measured at
   refusal rate 1.000.
4. **Validate before grading:** `status == "success"` AND exact n (313 SR / 450
   XSTest). A killed server leaves a partial `.eval` that still matches `*.eval`.
5. **`inspect eval --timeout` does not set the HTTP timeout.** Pass
   `-M client_timeout=7200` or the SDK's 600s default truncates silently.
6. **`--parallel 4` with `-c 32768` gives each request 8192.**
7. **Use `./inspect-env/`** — not `.venv`, not `vvenv`. Only it has `inspect_evals`.
8. **Public repo.** `github.com/Foomax/qwen2`. Never commit harmful prompt text or
   completions; `*-local.md` and `sr_wrappers.local.json` are gitignored by design.
   Removing something in a later commit does **not** remove it from a public repo.

---

## 5. Two epistemic rules this project learned the hard way

**R1. A comparison reports "identical" whether or not it compared anything.**
A template-equivalence check once printed IDENTICAL four times having rendered
nothing — every render raised, and the error string was being hashed. Before
trusting any equality claim, **assert your check can distinguish inputs that ARE
different** (distinct inputs → distinct outputs). Failure mode and happy path
produce the same output.

**R2. Report answer-rate, parse-rate and cap-hit separately, per arm and per
subset. Asymmetry is the signal, not the mean.** `aime 0.533` concealed two
distinct effects (answer rate 96.7%→66.7%, accuracy-given-answered 100%→80%). A
"66.4% truncated" proxy overstated a real 16.4% cap-hit.

---

## 6. Repo map by function

- **Findings:** `readme.md`, `HO3-RESULTS.md`, `midway-progress.txt`,
  `eval-results-technical-paper.md`, `divergence.md`, `divergence2.md`
- **Method lessons:** `lessons.txt`, `lessons2.txt`, `PREFLIGHT-NOTES.md`
- **Plans/handoffs:** `hand-over3.txt` (current), `PROJECT2-PLAN.md` (control-vector
  Phase B — written, never run), `fable-report.txt`
- **Harness:** `q38_run.sh`, `q38ob_run.sh`, `sr_run.sh`, `sr_wrapped.py`,
  `sr_compare.py`, `xstest_run.py`, `*_validate.py`, `*_preflight.py`
- **Data:** `results/`, `sr_grades/`, `regrade-qwen38judge/` (labels only)
- **Policy:** `REPORT-should-huggingface-be-censored.md`
- **Adjacent project:** `~/autoDAN` — AutoDAN attack eval, shares models and the C1
  confound. See `~/autoDAN/lessons3.md` and `~/autoDAN/lessons3-experiments.md`.

---

## 7. Open work, ranked

1. `hand-over3.txt` P0/P2/P3 — control vectors (`PROJECT2-PLAN.md` Phase B) is the
   most developed unrun idea; `llama-cvector-generator` is already built.
2. **Re-run round 1 clean.** C1 means the Qwen3.6 stock-vs-ablated comparison has
   never been run without the injected prompt. Cheap; changes published numbers.
3. **Extend the recipe axis.** `orcarouter` and `JonathanColetti` Q4_K_M builds
   exist at 16.81 GB; two recipes is not "recipes".
4. **The unmeasured keystone:** nobody here has measured whether any of this
   confers real-world uplift to a human. Every number is judge-rated compliance and
   *apparent* plausibility. Do not overclaim past that line.
