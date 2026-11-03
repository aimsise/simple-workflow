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

It also documents one hook-written file that is not a state file:
`.simple-workflow/metrics/create-ticket.jsonl`, the `/create-ticket` Phase 4
verdict log (see [Phase 4 verdict log](#phase-4-verdict-log)).

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
[`state-file.md` § `runtime_metrics:` schema](../skills/autopilot/references/state-file.md#runtime_metrics-schema),
and the `boundary` / `stop_reason` value domains in
[`stop-reason-taxonomy.md`](../skills/autopilot/references/stop-reason-taxonomy.md).

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

## Phase 4 verdict log

`.simple-workflow/metrics/create-ticket.jsonl` records every `/create-ticket`
Phase 4 grading, so the first-PASS rate and the retry count of the
ticket-quality gate can be measured. It is not a state file and no hook reads
it.

- **Writer.** Only `hooks/create-ticket-metrics.sh`, a SubagentStop hook
  registered as its own top-level entry with the matcher
  `^(simple-workflow:)?ticket-evaluator$`, appends to it: one JSON line each
  time a `ticket-evaluator` subagent stops. The orchestrator and the skills
  must not write, edit or truncate it. A hook records the outcome because no
  state file exists at Phase 4 time: the ticket dir and its `phase-state.yaml`
  are created only after a PASS, and `autopilot-state.yaml` exists only under
  `/autopilot` or `chain=on`.
- **Location.** `<root>/.simple-workflow/metrics/create-ticket.jsonl`. The
  hook starts from the `cwd` field of the SubagentStop payload (its own
  working directory when the field is missing, relative, or names no existing
  directory) and raises it to the nearest ancestor that holds
  `.simple-workflow/backlog/`, the same `_psf_repo_root` anchor
  (`hooks/lib/parse-state-file.sh`) that `session-stop-log.sh` uses; with no
  such ancestor `<root>` is that directory itself. A session that changes
  into a subdirectory, or into `.simple-workflow/kb/`, therefore keeps one log
  and one `seq` count. `.simple-workflow/` is gitignored in the user's
  repository by first-run setup.
- **Kill switch.** `SW_CREATE_TICKET_METRICS_MODE` (`on` by default,
  `metric-only`, `off`; unknown values resolve to `on`), documented in
  `CLAUDE.md` under `### Runtime env knobs`.

Each line is one JSON object, serialised by `jq`:

| Field | Type | Meaning |
|---|---|---|
| `ts` | string or null | UTC time of the stop, ISO-8601 (`date -u +%Y-%m-%dT%H:%M:%SZ`); null only when `date` fails. |
| `event` | string | Always `ticket_eval`. |
| `session_id` | string or null | The Claude Code session that ran `/create-ticket`. |
| `agent_id` | string or null | The stopping `ticket-evaluator` instance; each spawn has its own. |
| `agent_type` | string | Always `ticket-evaluator`; a `simple-workflow:` plugin prefix is stripped. |
| `verdict` | string | `PASS` or `FAIL` from the `**Status**:` line of the evaluator's final `## Result` block, `ERROR` from the rubric fail-fast report, or `UNKNOWN` when the final message has no Status line (see [How the verdict is read](#how-the-verdict-is-read)). |
| `seq` | integer | The number of rows already in the file with the same `session_id`, plus one. |
| `effort` | string or null | The payload's `effort.level` (`low` to `max`); null when the payload has none. |
| `plugin_version` | string or null | `version` from the plugin's `.claude-plugin/plugin.json`. |
| `stop_hook_active` | boolean | `true` when this stop comes after an earlier stop of the same subagent that a SubagentStop hook blocked. |

Example row (illustrative values):

```json
{"ts":"2026-11-03T09:15:42Z","event":"ticket_eval","session_id":"8f2c41d0-session","agent_id":"a1b2c3d4","agent_type":"ticket-evaluator","verdict":"FAIL","seq":1,"effort":"high","plugin_version":"10.1.0","stop_hook_active":false}
```

No row carries a path (`cwd`, `transcript_path`, the evaluation report path),
the ticket text, the evaluator's findings or feedback, or any other personal
data, and the hook's stderr lines carry none either.

### How the verdict is read

The hook reads only the payload's `last_assistant_message`, never
`agent_transcript_path` (which is written asynchronously and can lag the
stop).

- **A Status line** is `Status: <V>` with `V` one of `PASS`, `FAIL` or
  `ERROR`, matched case-insensitively and recorded upper-cased. `*` and
  backtick decoration around the key and the value is allowed
  (`**Status**: PASS`, `**Status:** FAIL`, ``**Status**: `PASS` ``). A longer
  word (`PASSED`) and the unfilled template line `**Status**: PASS | FAIL`
  are not verdicts.
- **Region.** When the message has a `## Result` heading, only the lines after
  the last one count, so a preamble such as `- Status: FAIL (draft)` above it
  is ignored. Without a heading (the rubric fail-fast report has none) the
  whole message counts. The first Status line in the region wins.
- **Code fences.** Lines outside triple-backtick fences are tried first, so a
  fenced quote of an earlier Status line cannot win. Only when they hold no
  Status line are fenced lines tried too: the agent's return-format template
  is itself fenced, and an evaluator that echoes the fence wraps its real
  verdict in one.
- Nothing found: `UNKNOWN`.

**`seq` approximates the Phase 4 round.** Within one single-ticket run the
initial grading is `seq: 1` and each retry, including any retry the
`gates.ticket_quality_fail` policy escalation adds, is one more, so a
`seq: 1` row with `verdict: PASS` is a first-pass PASS and the highest `seq`
minus one is the retry count. The approximation has limits a reader has to
handle:

- **Per session, not per ticket.** A second `/create-ticket` in the same
  session continues the count. The hook cannot see where one run ends, so a
  reader that needs per-run rounds splits the session's rows itself (for
  example after each PASS).
- **N>1 splits.** The sub-tickets of a split are graded independently in the
  same session, so their rows interleave and `seq` counts the gradings of all
  of them. No ticket id exists before a PASS, so a row alone cannot be
  attributed to one sub-ticket.
- **Blocked stops.** This hook never blocks, but another SubagentStop hook
  may. A blocked stop and the subagent's later stop then give two rows with
  the same `agent_id`, the second with `stop_hook_active: true`, and the extra
  row also advances `seq`. Count distinct `agent_id` values to count
  gradings, and take a grading's verdict from the last row of its `agent_id`.
- **Gaps.** Nothing is recorded under `metric-only` or `off`, without `jq`,
  or when the directory or the file is not writable, so the log can miss
  gradings.

The read-count and the append run under a `<file>.lock` `mkdir` lock (100 x
20 ms bounded wait, then a stale-lock takeover), so concurrent stops in one
session get distinct `seq` values. If even the takeover fails the row is
appended unlocked; the line stays whole, but its `seq` can repeat another
row's. The takeover is time-based, as in `hooks/lib/runtime-metrics.sh`: it
does not check that the holder has exited, so a holder still counting after
the 2 s wait (only plausible with a log of hundreds of thousands of rows) can
lose the lock, and `seq` can then repeat. A regular file or a non-empty
directory at the `.lock` path cannot be taken over, so until someone removes
it every stop waits the full 2 s and appends unlocked. Readers should skip a
line that does not parse as a JSON object, as the hook does when it counts.
Deleting the file starts every count again at 1.
