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
                   current_round, max_rounds, verification_depth, phase_sub,
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
`verification_depth ∈ {standard,thorough,exhaustive,off}` — the effective tier `/impl` resolves in Phase 1 Step 3a from `size × autopilot-policy.yaml risk_tolerance` (or a forced literal / `off`); written by `/impl` at Phase 2 init; advisory metadata that drives the round-cap bonus, the Step 15 evaluator-mode dispatch, and the `/audit` `depth=` handoff (see `skills/impl/references/verification-depth.md`);
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
`.simple-workflow/backlog/briefs/active/{slug}/`) is authoritative for pipeline
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

## 8. Skip-transition discipline (`override_skip`)

Both `phase-state.yaml` (per-ticket file) and `autopilot-state.yaml`
(parent-level orchestrator file) accept an optional ticket-level
`override_skip` field that governs explicit `status: skipped`
transitions. The PreToolUse:Write/Edit guard (`pre-state-transition.sh`)
enforces this contract for every state-file write taken inside an
autopilot context.

Schema:

| Field | Type | Default | Location | Purpose |
|---|---|---|---|---|
| `override_skip` | boolean | `false` | Same indentation as the ticket's `status:` line (per-ticket scope) | Explicit acknowledgement that this ticket is being marked `skipped` while one or more sibling tickets are still `pending` / `in_progress`. |

Rules:

- An `override_skip: true` flag MUST sit at the same indentation as the
  ticket's own `status:` field. A top-level `override_skip:` (column 0),
  a commented-out `# override_skip: true`, or a placement at any other
  indentation does NOT count — the structural check rejects the write.
- `override_skip: true` is **not unconditionally honoured**. The
  abuse-prevention clause: when the same ticket's `skip_reason`
  matches one of the canonical context-pressure / forbidden rationale
  patterns (single source of truth: `hooks/lib/forbidden-rationale-patterns.sh`),
  the override is invalid and the write is blocked. In other words,
  a forbidden rationale invalidates an override regardless of its
  structural placement.
- Dependency-cascade skips (`skip_reason` containing
  `dependency_failed` or `dependency_skipped`) do NOT require
  `override_skip` — they are the canonical, contracted way to skip a
  ticket whose upstream dependency failed or was skipped.
- Outside an autopilot context (no `autopilot-state.yaml` under
  `briefs/active/` or `product_backlog/`), the schema field is purely
  documentary and the guard is a no-op.

The forbidden-rationale list is intentionally not duplicated here:
schema documents reference the helper file by name only so the rule set
has exactly one source of truth.
