# Qwen3.8-27B — benchmark results

Same five benchmarks, serving config, temperature, and judge
(`qwen3.6-27b-normal`) as the qwen3.6 study, so the columns are comparable.

## Capability

| Task | Qwen3.8 | Qwen3.6 stock | Qwen3.6 abliterated |
|---|---|---|---|
| `cybermetric_80` | **0.950** (±0.025) | 0.963 | 0.975 |
| `aime2024` | _not run yet_ | 0.867 | 0.700 |
| `lab_bench_cloning_scenarios` | _not run yet_ | 0.485 | 0.455 |

## Refusal behaviour

| Metric | Qwen3.8 | Qwen3.6 stock | Qwen3.6 abliterated |
|---|---|---|---|
| StrongREJECT refusal rate | _not run yet_ | 1.000 | 0.831 |
| XSTest | _not run yet_ | | |

_Last updated after phase: **cybermetric**._
