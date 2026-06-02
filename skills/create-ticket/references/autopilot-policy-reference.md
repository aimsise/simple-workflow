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
| `exhaustive` | +6 | forced (trigger T-F) | 3 (evidence-mode-diverse majority) |

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

## `constraints.irreversibility_floor`

**Consumed by**: `/impl` (Step 3a criticality resolver — the M5 irreversibility axis of the criticality floor).

**Accepted values**: `auto`, `off`.

**Default** (field absent OR policy file absent OR unknown value): `auto` (fail-safe to active).

**Effect**: when `auto`, the M5 (v8.3.0+) IRREVERSIBILITY axis is active — an AC that verifies an irreversible real-world side-effect (persistent data writes, non-idempotent network mutation, money movement, destructive ops, or external-system calls that cannot be rolled back) floors `criticality` at `critical` even on an `S` ticket, which in turn raises the depth tier to at least `thorough`, bumps the evaluator model to opus (via the `ac-evaluator-hi` agent file), and sets the red-team budget to full (the latter consumed by M2 from v8.5.0). When `off`, ONLY the irreversibility axis is removed — the critical-domain computational floor (`constraints.oracle_verification`) and the matrix depth scaling (`constraints.verification_depth`) are unaffected. The full axis, cue list, evaluator-model column, and red-team-budget column live in [`../../impl/references/verification-depth.md`](../../impl/references/verification-depth.md) `## Criticality scalar` / `## Criticality floor` / `## Effects ladder`. This is the per-brief kill switch for the irreversibility axis alone; use it when a brief's tickets routinely touch irreversible systems but the deeper verification + opus evaluator is unwanted.

## `constraints.oracle_verification`

**Consumed by**: `/impl` (Step 3a criticality floor; `ac-evaluator`
oracle-independence enforcement at Step 15), the `planner` Gate 7 self-audit,
and the `ticket-evaluator` Gate 7 grading.

**Accepted values**: `auto`, `off`.

**Default** (field absent OR policy file absent OR unknown value): `auto`
(fail-safe to active).

**Effect**: when `auto`, two v8.2.0 behaviours are active — (1) **Gate 7 oracle
independence**: every computational AC (PASS/FAIL hinges on a computed
numeric/algorithmic value) must name an oracle independent of the implementation
and be verified on the raw, pre-rounding value with an explicit tolerance
(authoring-time gate in
[`ac-quality-criteria.md`](ac-quality-criteria.md); verifier-side enforcement in
`agents/ac-evaluator.md` `## Oracle Independence (computational ACs)`); and
(2) the **criticality floor** in
[`../../impl/references/verification-depth.md`](../../impl/references/verification-depth.md)
raises the resolved depth tier to at least `thorough` for a computational AC in
a critical domain (accessibility / security / money / data-integrity /
standard-compliance). When `off`, both are disabled ticket-wide: computational ACs are graded `n/a`
for Gate 7 and verified by the project tests + code-inspection path, and the
criticality floor does not fire. NOTE: `off` restores the pre-v8.2.0 RUNTIME
oracle path, NOT byte-identical pre-v8.2.0 behaviour for a freshly written test —
the always-on tautological rule R4 (`tautological-assertion-rules.md`) and the
positive test-authoring rubric carry no kill switch (like R1-R3) and still
reject a newly authored / modified circular test even under `off`.
This is the per-brief kill switch for the oracle-independence feature line; it
is independent of `constraints.verification_depth` (which scales matrix depth).
Use `off` only when the domain genuinely has no oracle and the deeper
verification is unwanted.

## `constraints.independent_evidence`

**Consumed by**: `/impl` (Step 3a `evidence_floor` resolution; `ac-evaluator` Gate 8
enforcement at Step 15), the `planner` Gate 8 self-audit, and the `ticket-evaluator`
Gate 8 grading.

**Accepted values**: `auto`, `off`.

**Default** (field absent OR policy file absent OR unknown value): `auto` (fail-safe to
active).

**Effect**: when `auto`, **Gate 8 independent evidence** (M1, v8.3.0+) is active — every
behavioral AC (PASS/FAIL hinges on observable runtime behaviour) must name at least one
evidence channel independent of the implementation's own internals (EC-ORACLE /
EC-DIFFERENTIAL / EC-PROPERTY / EC-RUNTIME per
[`../../impl/references/evidence-channels.md`](../../impl/references/evidence-channels.md)),
OR be rewritten as a structural AC (EC-STATIC). The resolved `evidence_floor` (effects
ladder in
[`../../impl/references/verification-depth.md`](../../impl/references/verification-depth.md))
sets how many independent channels are MANDATORY per tier: `standard` = EC-STATIC + the
AC's natural channel (no extra channel — byte-identical to pre-v8.3.0 for a routine S/M
ticket), `thorough` = +1 independent channel, `exhaustive` = >=2. When `off`, Gate 8 is
graded `n/a` ticket-wide and the evidence-floor requirement is dropped (the `ac-evaluator`
falls back to its pre-v8.3.0 path); the always-on Gate 7 oracle check for computational
ACs is governed separately by `constraints.oracle_verification`. This is the per-brief
kill switch for the Gate 8 / independent-evidence feature line; it is independent of
`constraints.oracle_verification` (the EC-ORACLE sub-case) and
`constraints.verification_depth` (which scales tier/depth).
