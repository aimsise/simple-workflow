# Stop Reason Taxonomy (runtime SoT)

This file is the **runtime source of truth** for the `boundary` and `stop_reason`
enums recorded in `autopilot-state.yaml` `runtime_metrics:` entries. Any skill
prompt, hook script, or test that needs to refer to these enums MUST cite this
file by relative path (`references/stop-reason-taxonomy.md` from
`skills/autopilot/SKILL.md`, or the appropriate `../../skills/autopilot/...`
path from elsewhere) — never copy the values into another tracked file.

The planning-phase specification that drives this file lives at
`.docs/discovery/test_simple_workflow13/investigation/plans/00-index.md`
(gitignored). Tracked files MUST NOT cite that path directly because the
`.docs/` tree is not shipped with the plugin.

## `boundary` (WHEN — which hook event recorded the entry)

`runtime_metrics:` entries are written by three hooks. Each entry's
`boundary` field identifies the writer:

| Value                | Writer hook                              | Meaning                                                          |
| -------------------- | ---------------------------------------- | ---------------------------------------------------------------- |
| `session_compaction` | `pre-compact-save.sh` (PreCompact hook)  | Snapshot taken just before context compaction fires.             |
| `session_end`        | `autopilot-continue.sh` (Stop hook)      | Snapshot taken at the moment Stop hook permits `end_turn`.       |
| `phase_complete`     | `post-phase-checkpoint.sh` (PostToolUse:Write) | Recorded when `phase-state.yaml.phases.<name>.status` transitions to `completed`. |
| `phase_failed`       | `post-phase-checkpoint.sh` (PostToolUse:Write) | Recorded when `phase-state.yaml.phases.<name>.status` transitions to `failed`.    |
| `phase_skipped`      | `post-phase-checkpoint.sh` (PostToolUse:Write) | Recorded when `phase-state.yaml.phases.<name>.status` transitions to `skipped`.   |

The two `session_*` boundaries cover session-level events; the three
`phase_*` boundaries cover per-phase transitions inside a single session.
Per-ticket boundaries (`ticket_completed`, `ticket_failed`,
`ticket_skipped`) remain intentionally **out of scope** — a future plan
may extend this taxonomy.

### Per-phase entries (`phase_complete` / `phase_failed` / `phase_skipped`)

The three per-phase boundary literals are:

- `boundary: phase_complete` — `phase-state.yaml.phases.<name>.status` reached `completed`.
- `boundary: phase_failed` — `phase-state.yaml.phases.<name>.status` reached `failed`.
- `boundary: phase_skipped` — `phase-state.yaml.phases.<name>.status` reached `skipped`.

Per-phase entries carry two extra fields beyond the seven canonical keys:

- `ticket_id` — the ticket the phase belongs to (e.g. `T-001`), extracted
  from the phase-state.yaml location or its embedded `ticket_id` field.
- `phase` — one of `scout` / `impl` / `audit` / `tune` / `ship`. The
  `create-ticket` phase is excluded because it runs before
  `autopilot-state.yaml` exists.

For per-phase entries `stop_reason` is always `null`. The `cache_*`,
`input_tokens`, and `consecutive_stop_blocks` fields are best-effort —
the PostToolUse:Write hook does not receive a token-usage payload, so
they default to `null`.

Idempotency: the writer hook checks the entire `runtime_metrics:` array
for a pre-existing `(ticket_id, phase, boundary)` triple before
appending. A repeated write of the same status (e.g. `completed` →
`completed`) does NOT add a second entry. The check scans the full
array, not a recent-N window, so duplicates are detected even when
`runtime_metrics:` has grown across many phases.

## `stop_reason` (WHY — only meaningful for `boundary: session_end`)

`stop_reason` is an optional field on `runtime_metrics:` entries.

- For `boundary: session_end` it is one of the values in the table below.
- For `boundary: session_compaction` it is always `null`.
- For `boundary: phase_complete` / `phase_failed` / `phase_skipped` it is
  always `null` — phase transitions do not carry a stop-reason axis.
- The same enum is reused in `autopilot-log.md`'s `## Stop Reason` section.

| Value                | Condition                                                                                                                                                |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `self_abort`         | The model issued `end_turn` without invoking a real tool (Skill / Agent / Bash etc.). Detected by a future progress-indicator hook (Plan 02).            |
| `loop_guard_release` | The Stop hook loop guard hit its threshold for both modification time and tool-use counters and released the session.                                    |
| `policy_gate_stop`   | A configured policy gate (e.g. `gates.unexpected_error.action: stop`) fired and stopped the pipeline.                                                    |
| `partial_completion` | At least one ticket remains `pending`, and none of the cases above applies.                                                                              |
| `normal_completion`  | All tickets have a terminal status (`completed`, `failed`, `skipped`) and the state file is otherwise clean.                                             |
| `harness_terminated` | **Fallback enum.** Used when none of the heuristics above match. In practice the Stop hook may not fire at all in such cases; this value is a safety net. |

## Discrimination heuristic (Stop hook)

The Stop hook (`hooks/autopilot-continue.sh`) determines `stop_reason` for an
outgoing `boundary: session_end` entry by applying these rules in order. The
first rule that matches wins.

1. The hook is exiting via the `[AUTOPILOT-STALL]` loop-guard release path
   (counter threshold reached) → `loop_guard_release`.
2. A future progress-indicator (Plan 02) reports `NOTOOL_COUNT` saturation
   while pending tickets remain → `self_abort`. Until Plan 02 lands, this
   branch is dormant.
3. The state file shows zero pending or in-progress steps across all tickets
   → `normal_completion`.
4. The state file shows at least one `pending` or `in_progress` ticket and
   none of the above applies → `partial_completion`.
5. None of the above matched → `harness_terminated` (fallback).

Policy-gate stops (`policy_gate_stop`) are emitted by the orchestrator skill
itself; the Stop hook does not synthesise them.

## Discrimination heuristic (PreCompact hook)

The PreCompact hook (`hooks/pre-compact-save.sh`) always writes
`boundary: session_compaction`, `stop_reason: null`. No discrimination is
required. Note: auto compact is normal operation, not a failure mode — the
PreCompact entry is the harness's designed response to context pressure, and
the resume path (`[RESUME] Skipping {logical_id}: already completed`) carries
the run forward without orchestrator intervention.

## Field reference for `runtime_metrics:` entries

Each entry has the following keys (the seven canonical keys):

- `boundary` — see `boundary` table above.
- `stop_reason` — see `stop_reason` table above (`null` when not applicable).
- `timestamp` — ISO-8601 UTC, generated via `date -u +%Y-%m-%dT%H:%M:%SZ`.
- `cache_creation_input_tokens` — integer or `null`. Sourced from the hook
  payload's `cache_creation_input_tokens` field (Stop hook only — `null` for
  PreCompact).
- `cache_read_input_tokens` — integer or `null`. Sourced from the hook
  payload's `cache_read_input_tokens` field.
- `input_tokens` — integer or `null`. Sourced from the hook payload's
  `input_tokens` field. Used by Plan 07 lightening signal.
- `consecutive_stop_blocks` — integer or `null`. The Stop hook loop-guard
  counter (`/tmp/.autopilot-continue-{session_id}` content). Meaningful only
  for `boundary: session_end`; `null` otherwise.

## Append-only contract

`runtime_metrics:` entries are append-only. Hooks MUST NOT rewrite or remove
existing entries. The list survives ticket completion (Split State File
Cleanup keeps the field intact when the state file moves to `briefs/done/`).
