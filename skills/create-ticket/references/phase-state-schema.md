# `phase-state.yaml` — Canonical Schema and Write Ownership

> Unified, durable, declarative state file for a single ticket's lifecycle.
> Lives at `{ticket-dir}/phase-state.yaml` (e.g. `.backlog/active/{ticket-dir}/phase-state.yaml`).
>
> Created once by `/create-ticket` at ticket creation time, updated in place by
> every phase-terminating skill, and **never deleted**. When `/ship` moves the
> ticket directory to `.backlog/done/{ticket-dir}/`, `phase-state.yaml` moves
> with it and remains the permanent record.

---

## 1. Canonical schema

```yaml
version: 1
ticket_dir: .backlog/active/{ticket-dir}
size: {S|M|L|XL}
created: {ISO-8601 UTC}

current_phase: {create_ticket|scout|impl|ship|done}
last_completed_phase: {create_ticket|scout|impl|ship|null}
overall_status: in-progress     # in-progress | blocked | done | failed

phases:
  create_ticket:
    status: pending              # pending | in-progress | completed | failed
    started_at: null
    completed_at: null
    artifacts:
      ticket: null

  scout:
    status: pending
    started_at: null
    completed_at: null
    artifacts:
      investigation: null
      plan: null

  impl:
    status: pending
    started_at: null
    completed_at: null
    # intra-impl loop state (absorbed from legacy impl-state.yaml)
    current_round: null
    max_rounds: null
    phase_sub: null              # generator-pending | generator-complete | evaluator-complete | audit-complete | round-complete | done
    last_ac_status: null         # PASS | FAIL | FAIL-CRITICAL | null
    last_audit_status: null      # PASS | PASS_WITH_CONCERNS | FAIL | null
    last_audit_critical: 0
    next_action: null            # start-round-{N}-generator | start-evaluator | start-audit | proceed-to-phase-3 | stop-critical | null
    feedback_files:
      eval: null
      quality: null
    artifacts:
      eval_rounds: []
      quality_rounds: []
      audit_rounds: []
      security_scans: []

  ship:
    status: pending
    started_at: null
    completed_at: null
    artifacts:
      pr_url: null
```

### Field enums

| Field | Enum values |
|---|---|
| `size` | `S`, `M`, `L`, `XL` |
| `current_phase` | `create_ticket`, `scout`, `impl`, `ship`, `done` |
| `last_completed_phase` | `create_ticket`, `scout`, `impl`, `ship`, `null` |
| `overall_status` | `in-progress`, `blocked`, `done`, `failed` |
| `phases.*.status` | `pending`, `in-progress`, `completed`, `failed` |
| `phases.impl.phase_sub` | `generator-pending`, `generator-complete`, `evaluator-complete`, `audit-complete`, `round-complete`, `done` |
| `phases.impl.last_ac_status` | `PASS`, `FAIL`, `FAIL-CRITICAL`, `null` |
| `phases.impl.last_audit_status` | `PASS`, `PASS_WITH_CONCERNS`, `FAIL`, `null` |
| `phases.impl.next_action` | `start-round-{N}-generator`, `start-evaluator`, `start-audit`, `proceed-to-phase-3`, `stop-critical`, `null` |

### Status transitions (per phase)

```
pending ──► in-progress ──► completed
                   │
                   └──────► failed
```

- A phase's `status` starts `pending` at ticket creation time.
- When the skill that owns the phase begins its work it sets `status: in-progress` and records `started_at`.
- On successful completion it sets `status: completed` and records `completed_at`.
- On unrecoverable failure it sets `status: failed` and the top-level `overall_status: failed`.

### Top-level status transitions

```
overall_status: in-progress ─► done      (set by /ship on successful completion)
                            ─► failed    (set by any writer on unrecoverable failure)
                            ─► blocked   (reserved — not used by Task 1 writers)
```

`current_phase` advances along the lifecycle: `create_ticket → scout → impl → ship → done`. On completion of a phase, `last_completed_phase` is set to the completed phase and `current_phase` is set to the next phase (or `done` after `ship`).

---

## 2. Write ownership

Skills MUST use a read-modify-write pattern and MUST only touch their own
section (`phases.{own}.*`) plus the top-level status fields (`current_phase`,
`last_completed_phase`, `overall_status`). Writing to another phase's section
is a contract violation.

| Phase | Writer skill | Writes to section |
|---|---|---|
| Template creation | `/create-ticket` | whole file (initial pending template) + `phases.create_ticket` on completion |
| Research + plan | `/scout` (and internally `/investigate` + `/plan2doc`) | `phases.scout` |
| Implementation loop | `/impl` | `phases.impl` (all sub-fields, on the same 4 update points as the legacy `impl-state.yaml`) |
| Shipping | `/ship` | `phases.ship` + `overall_status` |
| Top-level recalculation | All writers above | `current_phase`, `last_completed_phase`, `overall_status` |

Internal delegates (`/investigate`, `/plan2doc`) MUST NOT write to
`phase-state.yaml` directly — only the phase-owner skill (`/scout` in their
case) writes, so that the "only one section per writer" rule holds.

---

## 3. Lifecycle rules

- Created once by `/create-ticket` at the moment the ticket directory is created.
- Updated in place for every phase.
- **NEVER deleted.** When `/ship` moves the ticket dir to
  `.backlog/done/{ticket-dir}/`, `phase-state.yaml` moves with it.
- On ticket completion (successful `/ship`), set:
  - `overall_status: done`
  - `current_phase: done`
  - `last_completed_phase: ship`
  - `phases.ship.status: completed`
  - `phases.ship.artifacts.pr_url: <url>`

---

## 4. Legacy migration path

`/impl` is responsible for migrating legacy state files that predate this
unified schema. Two cases:

### 4.1 Legacy `impl-state.yaml` present, `phase-state.yaml` absent

On the first step of `/impl`:

1. Read `impl-state.yaml`.
2. Create `phase-state.yaml` with all top-level fields populated and every
   phase section initialized to the pending template.
3. Backfill:
   - `phases.create_ticket.status: completed` (artifact `ticket: {ticket-dir}/ticket.md` if present).
   - `phases.scout.status: completed` (artifacts backfilled from existing `investigation.md` / `plan.md` if present).
   - `phases.impl.status: in-progress` with every `phases.impl.*` sub-field copied 1:1 from the legacy file. **Field rename**: the legacy top-level `phase` becomes `phases.impl.phase_sub`. All other fields (`current_round`, `max_rounds`, `last_ac_status`, `last_audit_status`, `last_audit_critical`, `next_action`, `feedback_files.*`) keep the same name under `phases.impl.*`.
4. Delete `impl-state.yaml` after the new `phase-state.yaml` is written successfully.

### 4.2 Bootstrap path: neither file present

If `/impl` is invoked and a `plan.md` exists but neither `phase-state.yaml`
nor `impl-state.yaml` is present (e.g. a ticket authored without
`/create-ticket`), generate a fresh `phase-state.yaml` with:

- `phases.create_ticket.status: completed` (artifact `ticket: {ticket-dir}/ticket.md` if present; otherwise `ticket: null`).
- `phases.scout.status: completed` with `artifacts.investigation` and `artifacts.plan` backfilled from the existing files.
- `phases.impl.status: in-progress`, `phases.impl.started_at: {now}`.
- `current_phase: impl`, `last_completed_phase: scout`.

---

## 5. Field renames from legacy `impl-state.yaml`

| Legacy (`impl-state.yaml`) | Unified (`phase-state.yaml`) |
|---|---|
| top-level `phase` | `phases.impl.phase_sub` |
| top-level `current_round` | `phases.impl.current_round` |
| top-level `max_rounds` | `phases.impl.max_rounds` |
| top-level `last_ac_status` | `phases.impl.last_ac_status` |
| top-level `last_audit_status` | `phases.impl.last_audit_status` |
| top-level `last_audit_critical` | `phases.impl.last_audit_critical` |
| top-level `next_action` | `phases.impl.next_action` |
| top-level `feedback_files.eval` | `phases.impl.feedback_files.eval` |
| top-level `feedback_files.quality` | `phases.impl.feedback_files.quality` |
| top-level `plan_file` | (dropped — inferable from `ticket_dir/plan.md`) |
| top-level `ticket_dir` | top-level `ticket_dir` (unchanged) |
| top-level `size` | top-level `size` (unchanged) |
| top-level `started` | `phases.impl.started_at` |

---

## 6. Contractual invariants

- Skills MUST NOT delete `phase-state.yaml` at any point.
- `/create-ticket` MUST always write `phase-state.yaml` (no conditional — even when invoked standalone without autopilot).
- Each writer MUST only touch its own section plus the top-level status fields.
- `/ship` MUST preserve `phase-state.yaml` inside the ticket directory when moving it to `.backlog/done/`.
- Internal sub-skills (`/investigate`, `/plan2doc`) MUST NOT write to `phase-state.yaml`; only their parent phase-owner skill writes.

---

## 7. Readers

`phase-state.yaml` is also consumed by non-writer components. Readers MUST treat the file as read-only:

| Reader | Where | Purpose |
|---|---|---|
| `hooks/session-start.sh` | `additionalContext` output | Lists active tickets with `current_phase`, `last_completed_phase`, `overall_status` at session start. Falls back to branch + changed-files only when no file exists. |
| `/catchup` (Step 1-pre) | before compact-state / session-log | Primary state source. Drives Rule 0.5 (resume-from-last-completed-phase) and the `[SW-RESUME]` block. |

Readers MUST tolerate malformed / partial YAML silently (extracting what they can, skipping what they can't) so that a corrupt file never blocks session start or `/catchup`.
