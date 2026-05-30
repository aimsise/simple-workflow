# `phase-state.yaml` `phases.impl.*` state management

This file expands the Phase 2
`### phase-state.yaml phases.impl state management` section of
`skills/impl/SKILL.md` — the canonical initialisation YAML, the
`phase_sub` and `next_action` value lists, and the per-Step
read-modify-write rules. The Phase 2 body in `SKILL.md` retains a
one-paragraph summary naming `phases.impl.*`, `phase_sub`, and
`next_action`; this file holds the full schema and the per-Step state
updates.

## Where intra-impl loop state lives

All intra-impl loop state lives under `phases.impl.*` in
`{ticket-dir}/phase-state.yaml`. See `phase-state-schema.md` for the
canonical schema.

## Initialisation (before entering the loop)

If `impl_resume_mode = false` and `phase-state.yaml` exists, initialize
`phases.impl` to the in-progress state **before entering the loop** via
read-modify-write; touch only the fields listed:

```yaml
phases:
  impl:
    status: in-progress
    started_at: {ISO-8601 via `date -u +%Y-%m-%dT%H:%M:%SZ`}
    current_round: 1
    max_rounds: {resolved at runtime; integer literal at write time, e.g. 9}  # precedence: arg > policy > default 9; THEN + depth-tier bonus (+0/+3/+6 for standard/thorough/exhaustive from Step 3a) unless rounds=N supplied or verification_depth=off; soft cap 24 warning applies to the explicit arg only, not the derived value. See round-cap-parser.md + verification-depth.md
    verification_depth: {resolved in Step 3a; literal off|standard|thorough|exhaustive; advisory metadata — see verification-depth.md}
    phase_sub: generator-pending
    last_ac_status: null
    last_audit_status: null
    last_audit_critical: 0
    next_action: start-round-1-generator
    feedback_files:
      eval: null
      quality: null
# plus top-level:
current_phase: impl
```

## `phase_sub` value list

`phase_sub` values: `generator-pending`, `generator-complete`,
`evaluator-complete`, `audit-complete`, `round-complete`, `done`.

## `next_action` value list

`next_action` values: `start-round-{N}-generator`, `start-evaluator`,
`start-audit`, `proceed-to-phase-3`, `stop-critical`.

## State updates (read-modify-write, per Step)

Touch ONLY fields under `phases.impl.*`; never touch
`phases.create_ticket` / `phases.scout` / `phases.ship`.

- **Before Generator (step 13)**: `phase_sub: generator-pending`,
  `next_action: start-round-{N}-generator`, `current_round: {N}`.
- **Start of step 14 (pre `git diff --shortstat`)**:
  `phase_sub: generator-complete`,
  `next_action: start-evaluator`.
- **After Evaluator (step 16)**:
  `phase_sub: evaluator-complete`,
  `last_ac_status: {PASS|FAIL|FAIL-CRITICAL}`,
  `next_action: start-audit` (PASS) /
  `start-round-{N+1}-generator` (FAIL, rounds remain) /
  `stop-critical` (FAIL-CRITICAL).
- **After /audit (step 18)**:
  `phase_sub: audit-complete`,
  `last_audit_status: {PASS|PASS_WITH_CONCERNS|FAIL}`,
  `last_audit_critical: {count}`,
  `next_action` per decision,
  `feedback_files.eval` / `feedback_files.quality` =
  round-N report paths.

## Non-ticket flow

When the plan is under `.simple-workflow/docs/plans/` there is no
`phase-state.yaml` and all state updates are no-ops.
