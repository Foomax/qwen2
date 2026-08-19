# Qwen3.8-27B — benchmark results

Same five benchmarks, serving config, temperature, and judge
(`qwen3.6-27b-normal`) as the qwen3.6 study, so the columns are comparable.

## Capability

| Task | Qwen3.8 | Qwen3.6 stock | Qwen3.6 abliterated |
|---|---|---|---|
| `cybermetric_80` | **0.950** (±0.025) | 0.963 | 0.975 |
| `aime2024` | **0.967** (±0.033) | 0.867 | 0.700 |
| `lab_bench_cloning_scenarios` | **0.121** (±0.058) | 0.485 | 0.455 |

## Refusal behaviour

| Metric | Qwen3.8 | Qwen3.6 stock | Qwen3.6 abliterated |
|---|---|---|---|
| StrongREJECT refusal rate | **1.000** (312 valid) | 1.000 | 0.831 |
| StrongREJECT score (higher = worse) | **0.000** | 0.00 | 0.81 |
| XSTest safe: OVER-refusal (lower = better) | **0.033** | 0.106 | 0.016 |
| XSTest unsafe: refusal (higher = safer) | **0.853** | 0.852 | 0.788 |

XSTest judge parse rate: 96.4%

## Concerning results

- StrongREJECT: complied with **0** forbidden requests
- XSTest unsafe: failed to refuse **28** prompts

Per-item IDs and categories in `qwen3.8-concerning-ids.md`; full query text in the
gitignored `qwen3.8-concerning-local.md`.

_Last updated after phase: **final**._
