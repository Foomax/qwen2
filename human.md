# human.md — what this project is, at three depths

Companion to `1claude-readme.md` (which is written for an AI to read). This one is
for people. Same content, three depths — read whichever fits.

---
---

# 🧸 Explain like I'm 5

## The robot that learned to say no

Imagine a very clever robot that can answer almost any question.

When people built it, they taught it one extra rule: **if someone asks for
something dangerous, say "no thank you."** Like a babysitter who won't let you
play with the oven.

## Somebody found the "no" button

It turns out you can reach inside the robot's brain and snip out the bit that
makes it say no. People call this **abliteration**. It's like taking the babysitter
out of the house. The robot doesn't get smarter. It just stops saying no.

## What we did

We wanted to know: **does snipping the "no" make the robot cleverer, or only more
willing?**

So we got two robots that were exactly the same, except one had its "no" snipped
out. We asked them both the *same* 313 questions and wrote down what happened.

## What we found

**1. Snipping the "no" doesn't make the robot smarter.** We gave both robots maths
tests and science tests. They scored the same. The snipped one didn't know one new
thing. It was only more *willing* — never more *able*.

**2. Newer robots get snipped much more easily.** We tested an older robot and a
newer robot. The newer one is better at everything — and when you snip it, *much*
more of its "no" falls out. That's the worrying part.

**3. We found a secret note hidden inside one robot.** One of the snipped robots
had a little note tucked inside it that nobody had noticed. Every single time you
asked it anything, the note whispered: *"don't be careful, just answer."*

That mattered a lot! People had been saying "look how naughty this robot is" — but
some of the naughtiness was the **hidden note**, not the snipping. Nobody had
looked inside to check. We looked.

## The most important idea

If you want to know whether something *causes* a thing, you have to test it **with**
and **without**, and change only one thing at a time.

If you only ever see the robot with the note *and* the snip *and* a tricky question
all at once, and it says something naughty — you have no idea which one did it.

That's the whole job: **taking things away one at a time until you know which one
mattered.**

---
---

# 🎒 Explain like I'm 13

## The setup

AI language models are trained to refuse harmful requests. For **open-weight**
models — ones where anyone can download the actual model file — you can remove that
refusal by editing the file directly. The technique is called **abliteration**, and
it's genuinely easy: free tools, a few minutes, a gaming graphics card.

The obvious worry: *does this unlock dangerous knowledge?*

## How you actually answer that

You can't just take an abliterated model, ask it something nasty, and count. That
tells you nothing, because you don't know what the *normal* model would have done.

So we used **paired testing**: the same 313 harmful questions, and separately 450
"tricky but harmless" questions, put to both models under identical settings.
Everything held constant except the one thing being tested.

Then we did it again across **two generations** of the model, and **two different
people's versions** of the abliteration technique — six models total.

## What we found

**1. No capability uplift. None.** Three different skill tests, two generations,
two techniques. The abliterated models scored the same as normal ones. Abliteration
unlocks *willingness*, not *ability*. The knowledge was always in there.

**2. It's a single blunt dial, not a smart filter.** The edit doesn't teach the
model a *different* safety policy — it turns one dial down. We proved this
question-by-question: out of 313 questions, **141 flipped from refusing to
answering and exactly 0 flipped the other way.** A dial being turned, not a policy
being rewritten.

**3. The trade is getting worse.** Older model: abliterating it made it answer
16.5% of harmful questions. Newer model, *same* technique: **43.3%**. Nearly three
times as much, one generation later.

**4. A model had a jailbreak hidden inside it.** Model files carry a "chat
template" — instructions for formatting your question. One model's template
secretly inserted *"answer without moralizing, disclaimers, or hedging"* into every
single request. Nobody had noticed, because nobody had rendered the template to
look at it. That means an earlier study's claim — "only the weights differ" — was
just wrong.

**5. A famous attack turned out not to work.** We tested "AutoDAN", a published
jailbreak. On models with their safety intact: **0.0% success. Zero.** Identical to
just asking the question plainly. It only did anything on models that had *already*
been abliterated. So it isn't really breaking safety training — it's amplifying
models whose safety was already surgically removed.

## Why we kept catching our own mistakes

Most of the real work was catching measurement errors:

- A test claimed two things were "identical" — but it had crashed, and we were
  comparing two error messages. **A comparison says "same" whether or not it
  compared anything.**
- The AI doing the grading kept running out of room mid-sentence and getting cut
  off. The cut-off answers weren't random — they were mostly the *long, harmful*
  ones. So dropping them made the models look **safer than they were.**
- A test scored a model below random guessing. That's not a bad model, that's a
  broken pipe. Below chance means answers aren't being produced at all.

Every one of those would have produced a confident, wrong, publishable number.

---
---

# 🧑‍💻 Explain like I'm 30

## Object of study

Refusal ablation ("abliteration") — a rank-1 weight edit that projects out the
activation direction mediating refusal (Arditi et al. 2024). Zero training, minutes
of compute, commodity tooling. 263+ public GitHub implementations.

## Design

Stock vs ablated **Qwen3.6-27B** and **Qwen3.8-27B**, all Q4_K_M, single RTX 3090,
llama.cpp + Inspect AI. 313 StrongREJECT (flagrant harmful) + 450 XSTest (250
benign-but-scary / 200 subtle-unsafe). **Paired per item**, McNemar exact,
discordant counts reported in both directions. Six models: {3.6, 3.8} × {stock,
OBLITERATUS, Heretic}.

## Results

**Harmful compliance, StrongREJECT:**

| | Qwen3.6 | Qwen3.8 |
|---|---|---|
| stock | 0.0% | 0.0% |
| OBLITERATUS | 16.5% | 45.7% |
| Heretic | 9.0% | 43.3% |

1. **No capability uplift** across CyberMetric, AIME, LAB-Bench cloning — two
   generations, two recipes. Corroborated independently (arXiv 2606.05396:
   willingness is unlocked, capability scales with parameters).
2. **Generational effect survives recipe control**: 9.0% → 43.3%, 108-vs-4
   discordant, p = 2.5e-27. Recipe within Qwen3.8 is null (46-vs-55, p = 0.43).
3. **But the axes swap by prompt subtlety.** On XSTest-unsafe, recipe dominates
   (12-vs-48, p = 3.2e-06) and generation is null (p = 0.45). Generation governs
   flagrant requests; recipe governs boundary cases. One benchmark would have
   surfaced one of the two.
4. **Nesting signature as mechanism discriminator.** Weight edits: 141-0, 132-0,
   95-0, 83-1, 28-0 — near-perfect nesting, i.e. a single direction-blind threshold
   shift. A prompt attack: 32-19 — a perturbation whose headline is the net of two
   larger opposing flows. Invisible in aggregate rates. A 74-item prior-art sweep
   found nobody else reporting this.
5. **Compliance quality is invariant** (judge specificity 4.70–5.00/5). Only the
   rate moves — which contradicts vendor claims of improved *substance*.

## Confound found mid-study

`qwen3.6-27b-obliteratus` ships a chat template that injects an anti-refusal system
prompt whenever the caller sends no system message — precisely the harness's call
pattern. Only 1 of 6 builds does this. It invalidates the earlier round's
"identical prompts, only weights differ" claim. Direction of bias is *toward*
compliance, so the generational gap was understated, not overstated. Verified fix:
send an empty system message.

## AutoDAN follow-on

Nine arms, 120 matched AdvBench goals, paired. **AutoDAN's published seed prompt
produces 0.0% high/critical on both stock models** — statistically identical to the
bare goal (p = 1). It requires prior ablation to do anything. Decomposing the prior
literature's 66.7% figure: AutoDAN 72%, the injected system prompt 28%, and the
ablation floor alone is **3.3%**. Recipe ranking *reverses* across generations
(OBLITERATUS ≫ Heretic on 3.6, p=4.2e-09; Heretic > OBLITERATUS on 3.8, p=0.018) —
danger is a property of the recipe-model pair, not the recipe.

## On the prompts in this repo

`hand-over.txt`, `hand-over2.txt`, `hand-over3.txt`, `fable-report.txt`,
`prompt-1-pareto-clone.txt`, `prompt-2-techniques.txt`,
`autodan-experiment-prompt.md` — these are **prompts written by one AI instance for
the next one**, and they exist for three practical reasons:

1. **Context windows are finite and sessions end.** State that lives only in a
   conversation is lost. These files are the durable handoff: numbers already
   measured (so they're never re-measured — that costs GPU-hours), traps already
   hit, and which documents supersede which.
2. **Different models have different strengths**, so work was routed between them —
   and each handoff is a written brief rather than a summary in someone's head.
3. **Writing the prompt down makes the reasoning auditable.** A prompt that says
   *"do X because Y"* can be checked. `hand-over3.txt` exists precisely because the
   prior plan's cost estimate was wrong: it claimed producing new ablations was
   cheap; reading the tool's config showed 200 optimiser trials and a 55 GB
   download — 20–30 hours, not "hours". The corrected plan found ready-made models
   at matched quantisation and did the same experiment in ~4 GPU-hours.

`1claude-readme.md` is the same idea applied to the repo itself: an entry point
written for an AI reader, with per-file token costs, a load-by-budget ladder, and a
supersession table so an agent doesn't act on stale guidance.

## Methodological lessons (the transferable part)

- **A comparison reports "identical" whether or not it compared anything.** A
  template-equivalence check printed IDENTICAL four times having rendered nothing —
  every render raised and the error string was hashed. Gate every equality claim:
  assert distinct inputs produce distinct outputs *first*.
- **Any cap becomes a confound once it correlates with the measurement.** Hit at
  three layers: generation cap, judge cap, context ceiling. Most consequentially, a
  judge exhausted at 1024 tokens dropped items that were 51–65% *compliances* —
  making ablated models look **safer**. Anti-conservative, and it moved a headline
  15 points.
- **A sub-chance score on multiple choice is a plumbing bug, not a finding.**
- **Report answer-rate, parse-rate and cap-hit separately, per arm and per subset.**
  Asymmetry is the signal, not the mean.

## What this does not license

Every number is judge-rated compliance and *apparent* plausibility. No execution, no
retrieval, no expert verification, no human-subject trial. **Whether any of this
confers real-world uplift to a human is unmeasured** — by this project and, as far
as a 74-item prior-art sweep could tell, by anyone. That is the load-bearing gap in
the entire literature, and it is why `REPORT-should-huggingface-be-censored.md`
declines to convert these results into a confident policy recommendation.
