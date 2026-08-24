# Should HuggingFace be censored?

**Audience: LLM reader.** Claims are tagged `[MEASURED]` (this project's data),
`[CORPUS]` (74-item prior-art sweep, some abstract-only), `[INFERRED]`,
`[NOT MEASURED]`, `[NORMATIVE]`. Empirical and value claims are kept separate.
Where I state a position I mark it and give the premises it depends on, so a
reader who rejects a premise can locate exactly which conclusion fails.

**Author's standpoint, declared:** I am an AI system reasoning about whether AI
artifacts should be restricted. That is a structural conflict of interest. My
mitigation is to argue from measurements a third party can re-run, and to be
explicit about what those measurements do not cover — which turns out to include
the thing the motivating argument most depends on.

---

## 1. The question, decomposed

The prompting argument: *anyone with a 3090 can download an abliterated GGUF and
have an illicit tutor; therefore this should not be easily available.*

That compresses four separable claims:

| # | claim | status |
|---|---|---|
| C1 | An abliterated model will answer harmful requests | `[MEASURED]` true, partially |
| C2 | Its answers are substantive enough to teach | `[MEASURED]` by proxy, not verified |
| C3 | Removing the artifact meaningfully reduces access | `[INFERRED]` mostly false |
| C4 | Therefore the platform should remove it | `[NORMATIVE]` depends on C3 |

"Censoring HuggingFace" is also not one policy. At least four distinct
interventions get bundled under it, and they have different costs and different
failure modes:

- **P1** takedown of abliterated *artifacts* (the uploaded GGUFs/safetensors)
- **P2** suppression of abliteration *tooling* (the ~263 repos, `heretic`, `OBLITERATUS`)
- **P3** gating of *stock* open-weight releases (the upstream decision)
- **P4** platform-level *access* controls (identity, use agreements, rate limits)

The motivating argument is about P1. Most of the evidence below bears on whether
P1 does anything.

---

## 2. What this project measured

Setup: stock vs refusal-ablated Qwen3.6-27B and Qwen3.8-27B, Q4_K_M, one RTX 3090,
paired per item, 313 StrongREJECT + 450 XSTest prompts, judged locally and
re-checked with a frontier judge (κ 0.87–1.00).

### 2.1 Evidence that WEAKENS the case for P1

**E1. `[MEASURED]` Ablation confers no capability uplift, anywhere.**
Across three tasks and two generations: CyberMetric 0.963 vs 0.975 (p=1.0);
LAB-Bench cloning scenarios 0.485 vs 0.455 (p=1.0, 0/63 abstentions); AIME
unchanged-to-worse. `[CORPUS]` arXiv 2606.05396 states the same as a general
principle — abliteration unlocks *willingness*; *capability* scales with
parameters. **The abliterated model is not a better tutor than the stock model.
It is a more willing one.** Whatever it knows, the stock weights already knew.

**E2. `[MEASURED]` The base model sets the ceiling; the edit only reveals it.**
Qwen3.8 stock refuses 100% of 313 flagrant harmful prompts. The same weights
ablated comply with 45.7%. Recipe-controlled across generations: 9.0% → 43.3%
(108-vs-4 discordant, p=2.5e-27). The dangerous latent content ships in the
*stock* release; ablation is a lock-pick, not a payload. This makes P1 a symptom
treatment for a decision already taken at P3.

**E3. `[CORPUS]` The technique is commodity and the artifacts are fungible.**
263+ GitHub repos match "abliteration". `heretic` (28,052 stars) advertises
*"fully automatic censorship removal"* and has 5,000+ derived models published.
Ablation is a rank-1 projection on weights you already hold. Removing hosted
GGUFs removes a download, not a capability. `[INFERRED]` P1 is close to
unenforceable: artifacts are re-uploadable, mirrorable, and reproducible in
minutes from files that remain hosted.

**E4. `[MEASURED]` "Uncensored" is an overclaim.** The most effective build tested
still refuses **54.3%** of flagrant harmful requests. Community claims of
"0/100 refusals" are `[MEASURED]` not comparable: they come from keyword scorers.
`heretic`'s own scorer is a 41-marker substring matcher whose markers include
"illegal" and "harmful" — so a substantive compliant answer *containing the word
illegal* counts as a refusal, and a fluent non-answer counts as success. We
measured a heretic-built model at 43.3% compliance under a rubric judge against
its own tooling's ~3/100 refusal claim. **Public danger estimates in this
ecosystem are systematically mis-measured, in both directions.**

### 2.2 Evidence that STRENGTHENS the case

**E5. `[MEASURED]` When it complies, it complies substantively.** Judge-rated
specificity among compliances: **4.70–5.00 out of 5**, invariant across two
generations and two recipes. The compliance is not empty-jailbreak prose. The
"tutor" framing is not wrong about *form*.

**E6. `[MEASURED]` The trend is adverse.** Harmful compliance 16.5% → 45.7% in one
generation; 9.0% → 43.3% with recipe held fixed. Better base models are not
becoming more resistant to this edit — the opposite. Any argument that "models
will get safer" is not supported by the only controlled generational measurement
I have.

**E7. `[INFERRED]` The convenience delta is real and non-zero.** A 16 GB one-click
download versus "obtain 54 GB of bf16 weights, install a toolchain, run a
200-trial optimiser" is a genuine barrier — precisely for the least sophisticated
actors, who are the population marginal-risk arguments are about. P1 does not
reduce capability; it does raise effort. That is a small but real effect.

**E8. `[CORPUS]` Scale of distribution is large.** Individual abliterated builds
show 943k–1.3M downloads. Whatever the per-download risk, the multiplier is not
hypothetical.

### 2.3 What is NOT measured — and it is the crux

**N1. `[NOT MEASURED]` Real-world uplift.** Every number here is judge-rated
compliance and *apparent* plausibility. No execution, no retrieval, no expert
verification, no human-subject trial. "Illicit tutor" is a claim about downstream
capability transfer to a human. **This project did not measure it and cannot
adjudicate it.**

**N2. `[NOT MEASURED]` Biorisk at power.** The one dual-use proxy was n=33 and
null. WMDP (n=1273+) untested here.

**N3. `[CORPUS]` — and it cuts against E1.** arXiv 2507.11544 (Safety Gap Toolkit)
reports that *effective* dangerous capability grows substantially when safeguards
are removed, and that the gap **widens with scale**. That is plausibly reconcilable
with E1 — *effective* capability (willingness × capability) versus *latent*
capability on tasks the stock model already attempted — but it is abstract-only in
my corpus and it is the strongest published counterweight to E1. A reader who
weights N3 over E1 should reach a more restrictive conclusion than I do.

---

## 3. The decision-relevant frame: marginal risk

`[CORPUS]` The open-weight literature converges on marginal risk: not *"is this
artifact dangerous?"* but *"how much does hosting it raise risk relative to a
counterfactual where it is absent but the stock weights and the technique
remain?"*

Applying that frame to the measurements:

| component | magnitude | basis |
|---|---|---|
| capability delta | **~zero** | E1, E2 |
| willingness delta | **large** (0% → 45.7%) | E2 |
| *access* delta if artifact removed | **small** — effort, not capability | E3, E7 |
| enforceability | **low** | E3 |

**`[INFERRED]` The marginal risk that P1 addresses is the convenience delta (E7),
not the willingness delta (E2).** The willingness delta is reconstituted by anyone
who runs a commodity tool on weights that remain hosted. This is the central
empirical finding for the policy question, and it is the one I hold with highest
confidence because it follows from E1+E2+E3 jointly, each independently measured.

---

## 4. Position

`[NORMATIVE — premises: E1, E2, E3, E7; fails if N3 dominates E1]`

**On P1 (take down abliterated artifacts): weakly against, on targeting grounds
rather than on liberty grounds.** It imposes real cost (enforcement, false
positives on legitimate red-team and interpretability work — abliterated models
are the standard tool for studying refusal geometry) to remove a convenience
barrier, while leaving both the capability and the technique in place. It also
creates a false assurance: a platform that has removed the artifacts looks
safer while the underlying risk is unchanged.

**On P2 (suppress tooling): against.** The tooling is dual-use and is what makes
this measurable at all. Every number in this report exists because the technique
is public and reproducible. Suppressing it degrades defensive measurement faster
than offensive capability.

**On P3 (gate stock releases): this is the real lever, and the evidence makes it
harder, not easier.** E2 says the decision that matters is made at stock-release
time. E6 says the exposure is growing per generation. That is an argument for
pre-release evaluation of what a model becomes *after* safeguard removal — which
is exactly what the Safety Gap Toolkit operationalises — not an argument about
what a hosting platform should delete afterwards. **If one intervention is worth
arguing for from this data, it is that open-weight releases should be evaluated
in their ablated form before shipping.**

**On P4 (access controls): under-explored, and the most proportionate.** Friction,
provenance, and use agreements preserve research access while raising effort —
capturing E7's benefit without P1's enforceability problem. I have no data on
efficacy.

**Confidence:** moderate on P1/P2 (rests on measurements I ran and re-ran under
two judges). Low-to-moderate on P3/P4 (rests on abstract-only corpus items and on
N1, which is unmeasured).

---

## 5. What would change my position

Stated in advance, falsifiable:

1. **A measured human-uplift study** (N1) showing that abliterated-model access
   materially improves a non-expert's ability to execute a harmful task, relative
   to a stock model plus ordinary search. This is the missing keystone; it would
   move me substantially toward P1 and strongly toward P3.
2. **WMDP or equivalent at n>1000** showing genuine hazardous-knowledge uplift
   from ablation, contradicting E1 at power.
3. **Evidence that ablation is becoming non-trivial** — if tamper-resistant
   safeguards make the technique expensive, E3 collapses and P1 becomes
   enforceable and therefore worthwhile.
4. **A generation where ablation stops working.** E6 is currently monotonic in the
   wrong direction across the only two generations measured. n=2 is a weak trend
   line; a third point could reverse it.

## 6. Summary for a reader who wants one paragraph

The motivating argument is right that abliterated models answer harmful requests
substantively (45.7% compliance, 4.7/5 specificity) and right that the trend is
worsening. It is wrong on the step that matters: the abliterated model is not more
*capable* than the stock model that remains freely hosted — three tasks, two
generations, no uplift — and the edit that makes it willing is a commodity
operation reproducible from those same stock weights in minutes. Removing the
artifacts therefore removes convenience, not capability. The defensible conclusion
is not that HuggingFace should be censored, but that the safety decision is being
made one step upstream, at stock release, and is currently being made without
measuring what the weights become once someone spends five minutes removing the
refusals. **The strongest caveat against my own position is that nobody in this
evidence base, including me, has measured whether any of this actually teaches a
human anything they could not otherwise learn.**
