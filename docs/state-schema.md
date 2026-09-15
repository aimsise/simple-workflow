# `autopilot-state.yaml` schema reference

`autopilot-state.yaml` is the brief-level run state that `/autopilot` writes
and the lifecycle hooks read through `hooks/lib/parse-state-file.sh`. Each
ticket's own lifecycle lives in a separate `phase-state.yaml`
(`skills/create-ticket/references/phase-state-schema.md`).

**Source of truth.** The field-by-field writer contract — every field, when it
is written, and how it survives resume — is
[`skills/autopilot/references/state-file.md`](../skills/autopilot/references/state-file.md),
which `/autopilot` writes from. This document does not repeat it. It covers
what the hooks depend on, the fields that belong to hooks, the older shapes
the parsers still accept, and the legacy migration tool. If the two ever
disagree, `state-file.md` is right and this file is the one to fix.

## What the hooks read

| Field | Read by | Used for |
|---|---|---|
| `tickets[].status`, `tickets[].steps.{scout,impl,ship}`, `tickets[].ticket_dir` | `parse_ticket_statuses` / `parse_ticket_ship_dirs`, the Stop and checkpoint guards, the auto-compact hooks | Detecting an active run, pending work and ticket boundaries. The ticket count is the number of `tickets[]` entries. |
| `parallel_mode` | `resolve_parallel_mode` (overridden by `SW_PARALLEL_HOOKS_MODE`) | Choosing the serial or the wave-aware path; an absent field means `off`. |
| `wave_count`, `current_wave`, `wave_status` | `autopilot-continue.sh`, `post-ship-state-auto-compact.sh`, `pre-next-scout-auto-compact.sh` | Wave-boundary decisions under `parallel_mode: on`. |
| `main_checkout_root` | `impl-checkpoint-guard.sh`, `scout-checkpoint-guard.sh` | Finding the authoritative state from inside a per-ticket worktree. |

`runtime_metrics` is written by hooks rather than read (see
[Hook-owned fields](#hook-owned-fields)). Everything else a run records —
`total_tickets`, `ticket_mapping`, `execution_mode`, `ultracode_mode`,
`invocation_method`, and the per-ticket `pr_url` / `branch` / `head_sha` /
`failure_reason` transcribed on the wave-parallel path — is orchestrator state
that no hook consumes.

Two properties the hooks rely on:

1. **`tickets` is a list and `steps.<phase>` is a string.** Writers emit
   `tickets:` as a YAML list of `- logical_id: …` entries, each with a flat
   `steps:` map whose values are strings on their own line.
2. **`ticket_dir` is a fullpath.** Every `tickets[].ticket_dir` (and every
   `ticket_mapping` value) is a fullpath under `.simple-workflow/backlog/`,
   never a bare directory name.

New fields may be added at the top level or inside `tickets[]` without bumping
`version:`; renaming or removing a field is a breaking change.

## Hook-owned fields

`HOOK_OWNED_FIELDS` in `hooks/lib/state-authority.sh` currently holds one
field, `.runtime_metrics`: an append-only list that only hooks write. Six hooks
append to it — the Stop and checkpoint guards (`autopilot-continue.sh`,
`impl-checkpoint-guard.sh`, `scout-checkpoint-guard.sh`), `pre-compact-save.sh`,
and the two auto-compact hooks — all through `append_runtime_metrics_entry`
(`hooks/lib/runtime-metrics.sh`), which serialises the append with a
`<state_file>.lock` directory lock. The entry shape is documented in
`state-file.md` under `## runtime_metrics: schema`.

The orchestrator must not rewrite or blank this list with `Write` / `Edit`: a
hook may have appended to it earlier in the same turn, and rewriting the whole
list silently drops that entry. `hooks/pre-write-safety.sh` and
`hooks/pre-edit-safety.sh` detect such a change and, depending on
`SW_STATE_FIELD_GUARD_MODE`, log it (`metric-only`, the default) or block it
(`on`) with a reason that points to this file.

Status fields are guarded separately: `hooks/pre-state-transition.sh` vets
status transitions made with `Write` / `Edit`, and detection 3 of
`hooks/pre-bash-contract-guard.sh` (`SW_BASH_STATE_GUARD_MODE`) catches the
same mutation done through Bash (`yq -i`, `sed -i`, a redirect). Route status
changes through the owning skill (`/scout`, `/impl`, `/ship`) or through
`Write` / `Edit` so these guards see them.

## Older shapes the parsers still accept

Writers must not produce these, but the helpers in
`hooks/lib/parse-state-file.sh` read them so an older or slightly malformed
run can still be resumed:

- `steps.<phase>` written as a nested map instead of a string
  (`parse_ticket_ship_dirs`, an orchestrator slip observed in
  `test_simple_workflow27`).
- `tickets:` written as a map keyed by `logical_id` instead of a list
  (`parse_ticket_statuses`, observed in `test_simple_workflow28`).
- The v7 cached counters `completed_tickets` / `failed_tickets` /
  `skipped_tickets` and `boundary: pipeline_start` — ignored; the hooks derive
  progress from `tickets[]`.
- A `create-ticket` key under `steps` / `invocation_method`, left by runs from
  before ticket creation moved out of `/autopilot`.

## Migration guidance

`tools/migrate-state-schema.sh` normalises a v7-era file. It was written for a
"canonical v8" shape planned for v8.0.0 that the `/autopilot` writer never
adopted, so its output differs from what a current run writes, although the
hooks read both:

```bash
bash tools/migrate-state-schema.sh \
  --in  <path/to/v7/autopilot-state.yaml> \
  --out <path/to/migrated/autopilot-state.yaml>
```

The migration is idempotent (a second run produces zero diff) and
non-destructive:

1. Drop `total_tickets`, `completed_tickets`, `failed_tickets`,
   `skipped_tickets` and `boundary`. A current run still writes
   `total_tickets`; dropping it is harmless because the hooks count
   `tickets[]`.
2. Add `processing_order` from `tickets[].logical_id` in document order when
   it is missing.
3. Add `human_overrides: []`, `kb_overrides: []`, `decisions_made: []` and
   `manual_bash_fallbacks: []` when missing.
4. Add `pr_url: null` and `failure_reason: null` to every `tickets[]` entry
   that lacks them.
5. Rewrite each `ticket_mapping` value that is a bare directory name into the
   matching `tickets[].ticket_dir` fullpath.

`processing_order`, `human_overrides`, `kb_overrides` and `decisions_made`
exist only in migrated files: no writer emits them and no hook reads them.
Human overrides are reported in `autopilot-log.md`, and `risk_tolerance` stays
in `autopilot-policy.yaml`. A state file written by v8.0.0 or later needs no
migration.

The tool follows the project's dependency fallback: `yq` (mikefarah v4) first,
then `python3 + PyYAML`, and a loud failure when neither is available.
