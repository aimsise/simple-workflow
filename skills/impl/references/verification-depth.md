# Verification depth tier (size/risk-aware scaling)

This file is the source of truth for the `constraints.verification_depth`
knob (v8.1.0+). It expands the depth-tier resolution that `/impl` performs
in Phase 1 (after Size detection, Step 3) and consumes in Step 1a (round
cap), Step 15 (evaluator count), and Step 17 (`/audit` handoff). The
SKILL.md body retains the pinned literals (`verification_depth`,
`standard` / `thorough` / `exhaustive`, the `+3` / `+6` bonuses); this file
holds the matrix, the effects ladder, the precedence rules, and the
fallbacks.

The knob is documented as a per-skill consumer field in
[`skills/create-ticket/references/autopilot-policy-reference.md`](../../create-ticket/references/autopilot-policy-reference.md);
its per-tier default (`auto` at every tier) lives in
[`skills/autopilot/references/state-file.md`](../../autopilot/references/state-file.md)
and the emitted YAML template in
[`skills/brief/references/policy-template.md`](../../brief/references/policy-template.md).

## Accepted values

`constraints.verification_depth` ∈ `{auto, standard, thorough, exhaustive, off}`.

- **`auto`** (default; field absent OR policy file absent → `auto`): resolve
  the effective tier from `Size x risk_tolerance` per the matrix below.
- **`standard` / `thorough` / `exhaustive`**: force that effective tier,
  ignoring Size and `risk_tolerance`.
- **`off`**: disable the feature. `max_rounds` uses the base precedence with
  no bonus, Step 15 spawns a single evaluator, and `/audit` receives no
  `depth=` argument (the third-pass keeps its pre-v8.1.0 conditional
  behaviour). This is the exact pre-v8.1.0 contract and is the per-brief
  kill switch.

## Derivation matrix (`auto` only)

Resolve the effective tier from the ticket Size (Phase 1 Step 3; default `M`)
and the policy `risk_tolerance` (default `conservative` when the policy file
is absent or `risk_tolerance` is unreadable — the same fail-safe default used
by `hooks/lib/parse-state-file.sh::get_risk_tolerance`):

| Size \ risk_tolerance | conservative | moderate | aggressive |
|---|---|---|---|
| S | standard | standard | standard |
| M | standard | standard | thorough |
| L | thorough | thorough | exhaustive |
| XL / unknown | thorough | exhaustive | exhaustive |

**Design principle**: the tier rises with change blast-radius (Size) and with
autonomy (`risk_tolerance`). `aggressive` runs `deny` the human-facing
`audit-fail` / `ac-eval` / `ship-review` gates (see the 3-tier matrix in
`skills/autopilot/SKILL.md`), so they compensate for the absent human
oversight with deeper machine verification. `conservative` runs keep those
gates as live `AskUserQuestion` prompts, so the human supplies the extra
assurance and the matrix caps `conservative` at `thorough` even for XL.

## Effects ladder

The resolved tier controls three independent knobs:

| Tier | GE `max_rounds` bonus | `/audit` third-pass | Step 15 evaluators |
|---|---|---|---|
| `standard` | +0 | conditional (existing T-A..T-E) | 1 (single, current behaviour) |
| `thorough` | +3 | forced via `depth=thorough` (trigger T-F) | 1 |
| `exhaustive` | +6 | forced via `depth=exhaustive` (trigger T-F) | 3 (diverse-lens majority) |

1. **GE `max_rounds` bonus** — added to the resolved base
   (`constraints.max_total_rounds` or default 9). See "Round-cap precedence".
2. **`/audit` third-pass** — `/impl` Step 17 passes `depth={tier}` to `/audit`;
   `thorough` / `exhaustive` add trigger **T-F** which forces the existing
   skeptical third-pass (`skills/audit/references/skeptical-pass.md`). This
   reuses existing machinery — it does NOT add a new loop-until-dry pass.
3. **Step 15 evaluator count** — `exhaustive` activates the high-assurance
   multi-verifier majority (3 diverse-lens `ac-evaluator` spawns + majority
   merge). `standard` / `thorough` keep the single evaluator. See
   [`ac-evaluator-orchestration.md`](ac-evaluator-orchestration.md)
   `## High-assurance multi-verifier branch` for the lenses and merge.

## Round-cap precedence (updated)

Written into `phases.impl.max_rounds` in the Phase 2 init block. The depth
bonus is folded in **after** the existing precedence resolves the base:

1. An explicit, valid `rounds=N` argument → `max_rounds = N`, **no depth
   bonus** (the user-specified cap is authoritative and final).
2. Otherwise `base = {ticket-dir}/autopilot-policy.yaml`
   `constraints.max_total_rounds` (when present) else default `9`, and
   `max_rounds = base + bonus`, where `bonus` is `0` / `+3` / `+6` for
   `standard` / `thorough` / `exhaustive`. When `verification_depth: off`,
   `bonus = 0`.

The resulting value never triggers the soft-cap-24 `[ARG-WARN]` (that warning
fires only for an explicit `rounds=N` argument, not for policy/depth-derived
values); the largest reachable derived value is `aggressive` base `12` `+ 6 =
18`, which stays under 24. See
[`round-cap-parser.md`](round-cap-parser.md) for the argument parser itself.

## Composition with the `AC_COUNT >= 30` partition branch

The multi-verifier majority (Step 15, `exhaustive`) and the AC-count
partition branch are mutually exclusive, **partition wins**: when
`AC_COUNT >= 30`, keep the existing two-partition `worst-of-2` evaluation
(`eval-round-{n}-part-1.md` / `-part-2.md`) and do NOT additionally triple
it. This caps the worst-case evaluator spawn count per round at 3 (either
3 lenses for `AC_COUNT < 30`, or 2 partitions for `AC_COUNT >= 30`) rather
than 6. The tier still applies its `max_rounds` bonus and `/audit` third-pass
forcing in the partition path; only the 3-lens fan-out is suppressed.

## Manual / policy-absent flows

For a manual `/impl` on a `.simple-workflow/docs/plans/` plan (no ticket, no
`autopilot-policy.yaml`): Size defaults to `M`, `verification_depth` defaults
to `auto`, and `risk_tolerance` is unreadable → treated as `conservative`.
The matrix resolves `M x conservative = standard`, so a manual `/impl` run is
byte-identical to the pre-v8.1.0 behaviour. Deeper tiers only engage for
ticketed L/XL work or `aggressive` briefs.

## Observability

`/impl` records the resolved tier into `phases.impl.verification_depth` (the
literal effective tier `standard` / `thorough` / `exhaustive`, or `off`) when
it initialises the Phase 2 loop state, and emits a one-line
`[VERIFICATION-DEPTH] tier={tier} source={auto|policy|off} size={S|M|L|XL}
risk={conservative|moderate|aggressive}` to stderr so a dogfood run can audit
the derivation without re-deriving it. The field is advisory metadata; it is
not gated by any hook.
