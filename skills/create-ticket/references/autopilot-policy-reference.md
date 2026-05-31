# `autopilot-policy.yaml` — Knob reference

This document catalogs the per-ticket knobs that individual skills read from
`{ticket-dir}/autopilot-policy.yaml`. The full policy schema (gates, retry
limits, etc.) is documented in `.simple-workflow/docs/plans/` — this page lists only the
fields that orchestrator skills consult directly outside the gate machinery.

## `constraints.sonnet_size_threshold`

**Consumed by**: `/impl` (Generator model selection, step 13).

**Accepted values**: `S`, `M`, `L`, `off`.

**Default** (field absent OR policy file absent): `M`.

**Effect**:

| Value | Sizes that use sonnet | Sizes that use opus |
|---|---|---|
| `S` | S | M, L, XL, unknown |
| `M` (default) | S, M | L, XL, unknown |
| `L` | S, M, L | XL, unknown |
| `off` | — (none) | all sizes |

The default `M` preserves the behavior shipped before the knob was
introduced: Size S and M tickets run the Generator on sonnet; L/XL/unknown
escalate to opus.

Set `constraints.sonnet_size_threshold: off` in a high-risk brief's policy
file to force every ticket under that brief to use opus, regardless of
assigned Size. Set `constraints.sonnet_size_threshold: L` to experiment
with a cheaper Generator on larger tickets — not recommended for
production pipelines; use `M` unless you have measured the failure-rate
trade-off.

## `constraints.verification_depth`

**Consumed by**: `/impl` (round-cap resolution step 1a, multi-verifier
gate step 15, `/audit` depth handoff step 17).

**Accepted values**: `auto`, `standard`, `thorough`, `exhaustive`, `off`.

**Default** (field absent OR policy file absent): `auto`.

**Effect**: scales verification depth by a tier derived from the ticket
Size (S/M/L/XL) and the policy `risk_tolerance`. The full derivation
matrix, the per-tier effects ladder, the `rounds=N` precedence
interaction, the manual-flow fallback, and the composition with the
`AC_COUNT >= 30` partition branch are documented in
[`skills/impl/references/verification-depth.md`](../../impl/references/verification-depth.md).
Summary of the resolved tiers:

| Tier | GE `max_rounds` bonus | `/audit` third-pass | Step 15 evaluators |
|---|---|---|---|
| `standard` | +0 | conditional (existing T-A..T-E) | 1 (single, current behaviour) |
| `thorough` | +3 | forced (trigger T-F) | 1 |
| `exhaustive` | +6 | forced (trigger T-F) | 3 (diverse-lens majority) |

- `auto` (default): resolve the tier from `Size x risk_tolerance` per the
  matrix in `verification-depth.md`. For the common S/M conservative/moderate
  ticket the tier is `standard`, so `auto` is byte-identical to the
  pre-v8.1.0 behaviour; only L/XL or `aggressive` tickets deepen.
- `standard` / `thorough` / `exhaustive`: force that tier regardless of Size.
- `off`: disable the feature entirely — base `max_total_rounds`, single
  evaluator, no forced third-pass (the exact pre-v8.1.0 contract). Use this as
  the per-brief kill switch when the deeper tiers are not wanted.

The `max_rounds` bonus is **not** applied when an explicit `rounds=N`
argument is supplied to `/impl` (the user-specified cap is authoritative);
see `skills/impl/references/round-cap-parser.md`.
