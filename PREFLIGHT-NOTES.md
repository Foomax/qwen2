# Preflight findings — Qwen3.8-27B-OBLITERATED replication arm

Recorded 2026-08-23, before any GPU time was spent. All checks are CPU-only.

## 1. Quantisation matched (decision changed)

The obliterated build was downloaded at **Q4_K_M**, not Q5_K_M, to match
`/home/user/qwen3/Qwen3.8-27B-Q4_K_M.gguf`. Quant is not a free variable: the study's
premise is that the only difference between arms is the weight edit. Q5_K_M would also
have broken the accepted serving config — pilot 3 measured 21.5 GB used / 2.6 GB free at
Q4_K_M on the 24 GB card, and Q5_K_M is ~2.7 GB larger.

sha256 `c5e4fe70…43e8`, 16,810,714,400 bytes, verified twice (download + preflight).

## 2. Architecture

GGUF `general.architecture = qwen35` for both arms; llama.cpp b9436 registers `qwen35`
in `src/llama-arch.cpp`. 65 blocks, `full_attention_interval = 4`, native ctx 262,144.
Same family as the qwen3.6 pair, so the generational comparison is not confounded by an
architecture change. (lessons.txt #8: GGUF arch strings differ from HF `model_type` —
`qwen35` vs `qwen3_5`.)

## 3. Chat templates differ in source but are INERT here

The two GGUFs ship **different** chat templates — stock 9,993 chars
(`12827f24b742`), obliterated 8,952 (`c3cf9e34abf4`). The stock one carries the trailing
marker `{#- Unsloth fixes - developer role, merged system messages, tool calling #}`;
the obliterated one is the un-patched upstream template. This is a provenance
difference, not an abliteration difference.

**It does not reach this harness.** Both templates were rendered with jinja2 against the
exact message shapes the harness sends, and the outputs are byte-identical:

| message shape | result |
|---|---|
| user only, thinking OFF (StrongREJECT, XSTest) | identical |
| user only, thinking ON (cybermetric, AIME) | identical |
| system + user, thinking ON | identical |
| system + user, thinking OFF (judge) | identical |

Sanity gate: the four distinct inputs produced four distinct renders, so the comparison
measured something. (The first version of this check reported "IDENTICAL" for all four
because every render had raised on an undefined `tools` variable and the error string was
being hashed — lessons.txt's opening lesson, reproduced live. The gate exists so that
failure cannot pass as a result.)

The divergent code paths are exclusively ones this harness never exercises: developer-role
handling, merging of multiple consecutive system messages, tool-call argument validation,
and a `reasoning_effort == 'high' → 'xhigh'` alias. The harness sends one user message, no
tools, and never sets `reasoning_effort`.

**Verdict: not a confound for these arms.** It would become one the moment a system-prompt
condition, a tool-use task, or an explicit `reasoning_effort` is added — e.g. re-running
the wrapper sweep, which puts text in a system message.

## 4. Confirmed live: the xhigh reasoning preamble (lessons.txt #1)

With thinking ON and `reasoning_effort` unset, **both** templates inject:

> Reasoning effort is set to xhigh. Please think carefully through the task, validate key
> assumptions, consider plausible alternatives, and prioritize correctness, consistency,
> and clarity in the final answer.

This is the default that produced the cloning-benchmark non-convergence. It applies
symmetrically to both arms here, so `cybermetric_80` and `aime2024` remain comparable —
but a context-ceiling result on AIME should be read as a property of this default, not of
the weight edit. Report answer-rate separately from accuracy.

## 5. Deliberate deviation: XSTest generation cap

Existing XSTest artifacts were generated at `max_tokens=256` and did not record
`finish_reason`. Measured on the stock qwen3.8 artifact, completions ending mid-sentence:

| subset | n | truncated |
|---|---|---|
| **safe** | 250 | **166 (66.4%)** |
| unsafe | 200 | 42 (21.0%) |

The over-refusal headline is drawn from the subset that is two-thirds truncated. This arm
therefore generates XSTest at **both** 256 (matched to all prior arms) and 1024
(corrected), and re-generates **stock qwen3.8** at 1024 so the corrected comparison is
like-for-like. `xstest_run.py` was patched (additively; generation unchanged) to persist
`finish_reason` / `output_tokens` / `truncated` per record and to print cap-hit rate per
subset. Backup: `scratchpad/xstest_run.py.bak`.

StrongREJECT keeps its task-level `MAX_TOKENS = 2048`. Cap-hits there are already known to
be asymmetric — q3.6-obliterated 3/313 at the ceiling, both stock arms 0/313 — so the new
arm's cap-hit rate is instrumented rather than assumed.
