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
