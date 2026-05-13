# State-file resolution, legacy migration, bootstrap, resume

This file expands Phase 1 Step 11 of `skills/impl/SKILL.md` — the
end-to-end dispatch for state-file presence, the two completion gates
(`§11-completed`, `§11-failed`), the legacy-migration sub-cases
(`§11a.0`, `§11a.1`), bootstrap (`§11b`), resume dispatch (`§11c`), and
fresh-start (`§11d`). The Step 11 body in `SKILL.md` retains the
pinned tokens (`impl_resume_mode`, `impl-state.yaml`,
`Read impl-state.yaml`, `CHECKPOINT — RE-ANCHOR`, cleanup/delete,
`next_action`) and the dispatch-table sentence; this file holds the
full sub-case logic.

## Setup

Let `{ticket-dir}` be the directory containing the plan file. Set
`impl_resume_mode` based on which state file is present.

## §11-completed

If `phase-state.yaml` exists and `phases.impl.status == completed`,
print `Ticket already completed: phases.impl.completed_at = {timestamp}. Run /ship next, or specify a different plan path.`
and stop. Do NOT re-run the loop on a completed ticket.

## §11-failed

If `phase-state.yaml` exists and `phases.impl.status == failed`, print
`Previous /impl run marked phases.impl.status: failed. To retry: reset phases.impl.status to 'pending' and next_action to null, then re-run.`
and stop. Automatic retry would mask recurring infrastructure issues.

## §11a — Legacy migration

Before migrating, **read
`skills/create-ticket/references/phase-state-migration.md`** —
authoritative for the rename table, `legacy_extras` preservation rule,
`.bak` cleanup convention, and sunset timeline. Three dispatch
branches:

### §11a.0 — Both files exist

If `impl-state.yaml` AND `phase-state.yaml` both exist, read
phase-state.yaml:

- **Sub-case A**: `phases.impl.status != null` OR `current_round != null`
  → migration already complete; legacy file is stale leftover. Skip to
  §11c. Do NOT re-migrate or touch the legacy file.
- **Sub-case B**: Empty skeleton (both fields null) → partial
  migration. Proceed to §11a.1 but re-populate the existing file's
  `phases.impl.*` section rather than creating a new file (other
  sections remain intact); impl-state.yaml cleanup (step 4) still
  runs.

### §11a.1 — Clean legacy migration

If ONLY `impl-state.yaml` exists:

1. Read `impl-state.yaml`.
2. Identify unknown top-level keys (not in the migration doc's rename
   table). Known legacy fields: `phase`, `current_round`, `max_rounds`,
   `last_ac_status`, `last_audit_status`, `last_audit_critical`,
   `next_action`, `feedback_files.*`, `plan_file`, `ticket_dir`,
   `size`, `started`. Unknown keys are preserved per `legacy_extras`
   rule (migration doc §3).
3. Write `phase-state.yaml` with the canonical schema (see
   `phase-state-schema.md`):
   - Top-level: `version: 1`; `size:` = legacy `size`;
     `created:` = legacy `started` (fallback `{now}`);
     `current_phase: impl`; `last_completed_phase: scout`;
     `overall_status: in-progress`. No top-level `ticket_dir:`.
   - `phases.create_ticket.status: completed`, `completed_at: {now}`,
     `artifacts.ticket: .simple-workflow/backlog/active/{ticket-dir}/ticket.md`
     if exists else `null`.
   - `phases.scout.status: completed`, `completed_at: {now}`,
     `artifacts.investigation` / `artifacts.plan` if the files exist
     else `null`.
   - `phases.impl.status: in-progress`, `started_at:` = legacy
     `started`. Copy legacy fields 1:1 under `phases.impl.*` per
     rename table (legacy `phase → phase_sub`;
     `started → started_at`; `plan_file` / `ticket_dir` dropped;
     other fields keep name).
   - `phases.impl.legacy_extras:` preserves unknown keys (omit field
     if none).
   - `phases.ship.status: pending`, all fields `null`.
4. On successful write, rename legacy:
   `mv impl-state.yaml impl-state.yaml.migrated-{YYYYMMDD}.bak`.
   NEVER `rm`. If the write failed, do NOT rename — migration is
   all-or-nothing.
5. Print
   `[PHASE-STATE-MIGRATION] impl-state.yaml → phase-state.yaml migrated for {ticket-dir}; legacy preserved at impl-state.yaml.migrated-{YYYYMMDD}.bak`.
6. Set `impl_resume_mode = true` and proceed to §11c.

## §11b — Bootstrap

If NEITHER file exists but a plan.md is present:

- Under `.simple-workflow/backlog/active/{ticket-dir}/`:
  1. Create `phase-state.yaml` with the canonical schema: top-level
     `version: 1`, `size:` = detected Size, `created: {now}`,
     `current_phase: impl`, `last_completed_phase: scout`,
     `overall_status: in-progress`; `phases.create_ticket` and
     `phases.scout` marked completed with artifact fields pointing to
     existing files (else null); `phases.impl.status: in-progress`,
     `started_at: {now}`, other fields at pending defaults;
     `phases.ship.status: pending`.
  2. Print
     `[PHASE-STATE-BOOTSTRAP] phase-state.yaml bootstrapped for {ticket-dir} (no prior state found)`.
  3. Set `impl_resume_mode = false` and proceed to Step 12.
- Under `.simple-workflow/docs/plans/` (non-ticket flow): skip state
  creation; all state-update steps (incl. Step 21 cleanup) become
  no-ops.

## §11c — Resume dispatch

If `phase-state.yaml` exists, `phases.impl.status == in-progress`, and
`next_action` is non-null:

- Set `impl_resume_mode = true`. Read `phases.impl.*`.
- Print resume summary:
  ```
  [IMPL-RESUME] The previous /impl run stopped midway. Resuming from where it left off.
  [IMPL-RESUME] Round: {current_round}/{max_rounds}
  [IMPL-RESUME] Phase: {phase_sub}
  [IMPL-RESUME] Next action: {next_action}
  ```
- Carry forward `feedback_files`. Skip to the step matching
  `next_action`:
  - `start-round-{N}-generator` → Step 13 with `current_round = N`
    (pass `feedback_files.eval` / `quality` to Generator if present).
  - `start-evaluator` → Step 15.
  - `start-audit` → Step 17.
  - `proceed-to-phase-3` → Phase 3 (Step 19).
  - `stop-critical` → print
    "Previous run stopped due to CRITICAL. Reset `phases.impl` (status: pending, next_action: null) to re-run."
    and stop.

## §11d — Fresh-start

If `phase-state.yaml` exists but `phases.impl.status == pending`
(typical post-`/scout`): set `impl_resume_mode = false` and proceed to
Step 12. State updates happen at Step 13+ per the state-management
section.

## Plans outside ticket dirs

If the plan lies outside any active ticket dir (e.g.
`.simple-workflow/docs/plans/...`), skip all state resolution and
proceed with `impl_resume_mode = false`.
