# Phase 2 Dynamic Shrinkage

This reference holds the Phase 2 dynamic shrinkage tier classifier used by `/brief`. It defines the one-shot read of `runtime_metrics:` from `autopilot-state.yaml`, the `remaining_pct` formula, the four-tier table that maps remaining context to round/question caps, and the standalone fallback when the state file is absent. `/brief` Phase 2 links here for the load-bearing detail.

## One-shot state read

At Phase 2 start, perform a **single one-shot read** of `.simple-workflow/backlog/briefs/active/{slug}/autopilot-state.yaml` (or the parent_backlog mirror — see the location precedence in `skills/autopilot/SKILL.md ### State file initialization`). This read happens **exactly once** at Phase 2 start; it is **not** repeated per round. If the file is absent (standalone `/brief` invocation, no autopilot session in flight), no read is performed and the standalone fallback below applies.

When the file exists, take the **last entry** of its `runtime_metrics:` list and compute:

```
current_context_tokens = input_tokens + cache_read_input_tokens
context_window_size    = 1000000   # static default (Opus 1M)
                                    # Sonnet would use 200000, but a single static
                                    # default is sufficient for this tier-classifier
                                    # use case — precise estimation is out of scope
remaining_pct          = 1.0 - (current_context_tokens / context_window_size)
```

Both `input_tokens` and `cache_read_input_tokens` are written by the Plan-01 Stop / PreCompact hooks; their schema is fixed in `skills/autopilot/SKILL.md ### State file initialization`. The signal `input_tokens + cache_read_input_tokens` represents the size of the input the API actually saw last turn (cache hits + new bytes), and is the chosen approximation of current context occupancy. `cache_creation_input_tokens` is **not** used as the signal because per-turn cache rebuilds inflate it without reflecting standing context.

The **practical-approximation caveat** applies: this is a tier-classifier (`≥ 70% / 50-70% / 30-50% / < 30%`), not a precise estimator. TTL-driven cache rebuilds may briefly inflate `input_tokens`, and Sonnet runs are misclassified by the static 1M divisor; both conditions are tolerated because all that matters is the resulting tier.

## Tier table

Apply the following table to choose the Phase 2 limits **for this run only**:

| `remaining_pct` | Phase 2 round limit | Phase 2 questions/round | Phase 2 total ceiling |
|---|---|---|---|
| ≥ 70% | 10 rounds | 3 questions | up to 30 questions (existing behaviour) |
| 50-70% (i.e., 50% ≤ `remaining_pct` < 70%) | 5 rounds | 3 questions | up to 15 questions |
| 30-50% (i.e., 30% ≤ `remaining_pct` < 50%) | 3 rounds | 2 questions | up to 6 questions |
| < 30% | 1 round | 1 question | up to 1 question |

## Standalone fallback (state-file-absent)

**Standalone fallback (state-file-absent)**: when `autopilot-state.yaml` does **not** exist on disk at the canonical paths above (i.e., `/brief` was invoked without an autopilot session — the typical "standalone" case), the dynamic shrinkage is **bypassed**: the existing **10 rounds × 3 questions = max 30 questions** ceiling applies as before. This guarantees that direct `/brief` invocations are not regressed by Plan 07. The bypass is also taken when the file exists but its `runtime_metrics:` list is empty (no entry to read).

Once the tier is selected at Phase 2 start, the round counter and questions/round caps are fixed for the remainder of the interview. The "Caps (load-bearing for contract)" stated in SKILL.md remain the **upper bound** — the dynamic table never raises them, only lowers them inside an autopilot run.
