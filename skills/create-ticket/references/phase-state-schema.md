# `phase-state.yaml` — Canonical Schema and Write Ownership

Unified state for a ticket's lifecycle at `{ticket-dir}/phase-state.yaml`.
Created once by `/create-ticket`, updated in place by each phase-owner
skill, **never deleted**. Legacy migration: `phase-state-migration.md`.

## 1. Canonical schema

```yaml
version: 1
size: {S|M|L|XL}
created: {ISO-8601 UTC}
current_phase: {create_ticket|scout|impl|ship|done}
last_completed_phase: {create_ticket|scout|impl|ship|null}
overall_status: in-progress    # in-progress|blocked|done|failed
phases:
  create_ticket: { status, started_at, completed_at, artifacts: { ticket } }
  scout:         { status, started_at, completed_at, artifacts: { investigation, plan } }
  impl:          { status, started_at, completed_at,
                   current_round, max_rounds, phase_sub,
                   last_ac_status, last_audit_status, last_audit_critical,
                   last_round, next_action,
                   feedback_files: { eval, quality } }
  ship:          { status, started_at, completed_at, artifacts: { pr_url } }
```

Enums: `status ∈ {pending,in-progress,completed,failed}`;
`phase_sub ∈ {generator-pending,generator-complete,evaluator-complete,audit-complete,round-complete,done}`;
`last_ac_status ∈ {PASS,FAIL,FAIL-CRITICAL,null}`;
`last_audit_status ∈ {PASS,PASS_WITH_CONCERNS,FAIL,null}`;
`next_action ∈ {start-round-{N}-generator,start-evaluator,start-audit,proceed-to-phase-3,stop-critical,null}`;
`last_round` is a scalar round number set at impl completion.

File path encodes location — no top-level `ticket_dir:` is serialized.
Per-round artifact filenames are discoverable by Glob; no write-only
`{eval,quality,audit}_rounds` / `security_scans` lists are stored.

## 2. Write ownership

| Writer | Owned section |
|---|---|
| `/create-ticket` | whole file (template) + `phases.create_ticket` |
| `/scout` | `phases.scout` (delegates `/investigate`, `/plan2doc` MUST NOT write) |
| `/impl` | `phases.impl` |
| `/ship` | `phases.ship` + `overall_status` |
| All | `current_phase`, `last_completed_phase` |

Read-modify-write; touch only the owned section plus top-level status.

## 3. Lifecycle rules

Created once; updated in place; **never deleted**. Per-phase status
advances `pending → in-progress → completed` (or `→ failed`).
`current_phase` advances `create_ticket → scout → impl → ship → done`.

## 4. Readers

`hooks/session-start.sh` (session-start summary) and `/catchup` Step 1-pre
(primary state; drives Rule 0). Readers tolerate malformed YAML silently.

## 5. Dual-state precedence

During `/autopilot`, `autopilot-state.yaml` (under
`.backlog/briefs/active/{slug}/`) is authoritative for pipeline
orchestration; `phase-state.yaml` is maintained in parallel. Outside
autopilot, `phase-state.yaml` is authoritative. On conflict, prefer the
more recently-modified file and emit a warning. Fold-in deferred — see `skills/create-ticket/references/autopilot-foldin.md`.

## 6. Contractual invariants

No skill deletes `phase-state.yaml`. `/create-ticket` always writes the
initial template. Each writer touches only its own section plus top-level
status. `/ship` preserves the file inside the ticket dir when moving to
`done/`.

## 7. Legacy migration path

Legacy `impl-state.yaml` handling (both-files-exist branch, rename table,
`legacy_extras`, `.bak` cleanup, sunset) lives in
`phase-state-migration.md`. `/impl` §11a reads it at migration time.
