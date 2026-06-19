# Autopilot State File Reference

Detailed schema, location precedence, and runtime guard contract for
`autopilot-state.yaml`. The orchestration semantics (when to write / when
to read) remain in `skills/autopilot/SKILL.md`; this file is the schema
source of truth that the SKILL.md links to.

## `autopilot-state.yaml` schema

The brief-level / parent-level `autopilot-state.yaml` is distinct from
each ticket's `phase-state.yaml` (owned by `/scout`, `/impl`, `/ship`).
Skip writing it if `resume_mode = true` (state already exists).

The file has 7 top-level fields plus an append-only metrics list:

```yaml
version: 1
parent_slug: {parent-slug}
started: {ISO-8601 via `date -u +%Y-%m-%dT%H:%M:%SZ`}
execution_mode: split
total_tickets: {N}
ticket_mapping: {}
tickets:
  - logical_id: {parent-slug}-part-{N}   # one entry per split-plan ticket, in topological order
    ticket_dir: {ticket-dir from split-plan}
    status: pending
    steps:                                 # canonical FLAT/block form — `steps.<phase>` is a STRING on its own line
      scout: pending
      impl: pending
      ship: pending
    invocation_method: {scout: unknown, impl: unknown, ship: unknown}
runtime_metrics: []                      # append-only, written by Stop / PreCompact hooks
# Sample entry (one full session_end snapshot, all 7 canonical keys):
#   - boundary: session_end                    # session_compaction | session_end (see references/stop-reason-taxonomy.md)
#     stop_reason: normal_completion           # one of self_abort | loop_guard_release | policy_gate_stop | partial_completion | normal_completion | harness_terminated; null when boundary != session_end
#     timestamp: 2026-04-29T19:39:10Z          # ISO-8601 UTC (`date -u +%Y-%m-%dT%H:%M:%SZ`)
#     cache_creation_input_tokens: 716586      # integer or null (from hook payload)
#     cache_read_input_tokens: 0               # integer or null (from hook payload)
#     input_tokens: 0                          # integer or null (from hook payload, used by Plan 07)
#     consecutive_stop_blocks: 5               # integer or null; meaningful only for boundary: session_end
#   # `auto_compact_inject` entries (written by the auto-compact hooks) append an
#   # OPTIONAL `shipped_count:` key AFTER consecutive_stop_blocks and leave
#   # consecutive_stop_blocks null; their stop_reason is "primary" | "safety_net".
```

Field summary (the 7 top-level fields plus `runtime_metrics:`):

- `version` — schema version integer (currently `1`).
- `parent_slug` — the brief / split-plan parent slug.
- `started` — ISO-8601 UTC timestamp of the first `/autopilot` invocation for this slug.
- `execution_mode` — always `split` (the only success path remaining after Plan 4).
- `total_tickets` — `N` from the split-plan.
- `ticket_mapping` — `{logical_id: ticket_dir}` lookup table seeded from the split-plan.
- `tickets` — per-ticket entries (logical_id, ticket_dir, status, steps, invocation_method).
- `runtime_metrics:` — append-only metrics list (see schema below).

The `steps:` / `invocation_method:` maps no longer contain a `create-ticket`
key — ticket creation is no longer an `/autopilot` step (Plan 4). Existing
state files from pre-Plan-4 runs that still carry a `create-ticket` key are
tolerated on resume but not written fresh.

### Schema invariants — `steps` is a FLAT map of string values

**MUST**: `steps.{scout,impl,ship}` is a STRING value (`pending` /
`in_progress` / `completed` / `failed` / `skipped`), NOT a nested map.
`invocation_method.{scout,impl,ship}` lives in a separate sibling map,
also string-valued.

Canonical (write THIS):

```yaml
tickets:
  - logical_id: pomodoro-timer-part-1
    ticket_dir: .simple-workflow/backlog/done/pomodoro-timer/001-foo/
    status: completed
    steps:
      scout: completed
      impl: completed
      ship: completed       # ← string value, single line
    invocation_method:
      scout: skill
      impl: skill
      ship: skill
```

Anti-pattern (do NOT write):

```yaml
tickets:
  - logical_id: pomodoro-timer-part-1
    steps:
      ship:                 # ← NOT a nested map
        status: completed
        invocation_method: skill   # ← belongs in the sibling map, not here
```

**Why**: the auto-compact hooks
(`hooks/pre-next-scout-auto-compact.sh` + `hooks/post-ship-state-auto-compact.sh`)
gate on `steps.ship == "completed"`. The hook helper
`parse_ticket_ship_dirs` tolerates the nested form for resilience
(WI-3), but the canonical flat form is the source of truth for
schema-conforming readers (yq query `.tickets[].steps.ship`) and is
what the autopilot orchestrator MUST emit on every write. Field
evidence: `test_simple_workflow27` emitted the nested form and silently
broke auto-compact for an entire pipeline before WI-3 was added.

### Schema invariants — `tickets:` is a YAML list (NOT a map)

**MUST**: `tickets:` is a YAML LIST whose elements are dash-prefixed
mappings (`- logical_id: ...`). It is NOT a YAML map keyed by
`logical_id`. The `ticket_mapping:` block at the top of the file is
the only canonical `logical_id`-keyed lookup; `tickets:` itself MUST
remain a positional list so topological ordering, append-only progress
tracking, and the per-element idioms in `hooks/lib/parse-state-file.sh`
(`parse_ticket_statuses`, `parse_ticket_ship_dirs`) and
`hooks/pre-state-transition.sh` (`parse_proposed_tickets`) all read
the same shape.

Canonical (write THIS):

```yaml
tickets:
  - logical_id: pomodoro-timer-part-1
    ticket_dir: .simple-workflow/backlog/done/pomodoro-timer/001-foo/
    status: completed
    steps:
      scout: completed
      impl: completed
      ship: completed
  - logical_id: pomodoro-timer-part-2
    ticket_dir: .simple-workflow/backlog/active/pomodoro-timer/002-bar/
    status: in_progress
    steps:
      scout: completed
      impl: pending
      ship: pending
```

Anti-pattern (do NOT write — `tickets:` keyed by `logical_id` as a
MAP):

```yaml
tickets:
  pomodoro-timer-part-1:
    ticket_dir: .simple-workflow/backlog/done/pomodoro-timer/001-foo/
    status: completed
    steps:
      ship: completed
  pomodoro-timer-part-2:
    ticket_dir: .simple-workflow/backlog/active/pomodoro-timer/002-bar/
    status: in_progress
    steps:
      ship: pending
```

**Why**: three hook surfaces consume `tickets:` — `parse_ticket_statuses`
(Stop-hook loop-guard counters), `parse_ticket_ship_dirs` (auto-compact
ship-detection), and `parse_proposed_tickets` (PreToolUse:Write/Edit
skip-transition guard). All three are now WI-3 / WI-4 schema-tolerant
(they accept the map form so a model slip cannot silently disable the
guard), but the canonical schema remains the list form. SKILL prose is
the enforcement; hook tolerance is the safety net. The
`unauthorized_skip_with_active_siblings` /
`unauthorized_skip_with_forbidden_rationale` guards specifically must
not be bypassable just by serialising `tickets:` as a map — that
combination would let a model mark one ticket `skipped` with a
forbidden rationale while siblings are still `in_progress` without the
write being blocked. Field evidence: `test_simple_workflow28` produced
the map form (`pomodoro-timer-web-app-part-1: {...}`) and broke the
pre-WI-4 LIST-only parsers in both `parse_ticket_statuses` and
`parse_proposed_tickets` silently.

## `autopilot-state.yaml` location precedence

`/autopilot` chooses **one** location based on what is already on disk.
Both locations are valid for state; the choice is determined at runtime,
not configured.

| Order | Path | Selected when |
|-------|------|---------------|
| 1 | `.simple-workflow/backlog/briefs/active/{parent-slug}/autopilot-state.yaml` | The brief directory exists (i.e. the run originated from `/brief` -> `/create-ticket brief=<path>`). |
| 2 | `.simple-workflow/backlog/product_backlog/{parent-slug}/autopilot-state.yaml` | The brief directory does not exist on disk (i.e. `/create-ticket` was invoked without `brief=<path>`, or the brief directory was never created). |
| 3 | `.simple-workflow/backlog/briefs/done/{parent-slug}/autopilot-state.yaml` | Fallback lookup only — used by the Stop / PreCompact hooks after Split State File Cleanup has moved the file into `briefs/done/`. |

Resolution rule on resume: read whichever of the three paths exists,
trying the order above. If none exists, `resume_mode = false` and a fresh
state file is written at the active location (rows 1 or 2). The paths
are never both authoritative simultaneously — `/autopilot` always commits
to one location for a given run, then mirrors the same location to
`briefs/done/` at the end of the run (see Split Brief Lifecycle in the
SKILL.md).

The hooks adopt a `briefs/done/` candidate ONLY when every pipeline step
has reached `completed`; a `briefs/done/` state file with any
`in_progress` or `pending` step is treated as anomalous and ignored, so a
premature `partial_completion` entry is never emitted against a
half-finished run that was moved by mistake.

## `runtime_metrics:` schema

`runtime_metrics:` is an **append-only** list written exclusively by the
following six hooks (the canonical writer set is the `Sourced by:` header of
`hooks/lib/runtime-metrics.sh`, kept in sync by a contract test):
`hooks/autopilot-continue.sh` (session_end), `hooks/pre-compact-save.sh`
(session_compaction), `hooks/impl-checkpoint-guard.sh` (session_end),
`hooks/scout-checkpoint-guard.sh` (session_end),
`hooks/pre-next-scout-auto-compact.sh` (auto_compact_inject), and
`hooks/post-ship-state-auto-compact.sh` (auto_compact_inject). The list
survives ticket completion (Split State File Cleanup keeps it intact when
moving the state file to `briefs/done/`). Skills MUST NOT write
`runtime_metrics:` directly — hook-only ownership keeps the schema observable
from a single audit point.

Value domains for `boundary` and `stop_reason`, plus the Stop hook's
discrimination heuristic, are defined in
[`stop-reason-taxonomy.md`](stop-reason-taxonomy.md). Tracked files MUST
cite that file rather than the planning-phase document under `.docs/`
(which is not shipped with the plugin).

The seven canonical keys per `runtime_metrics:` entry (plus an optional eighth,
`shipped_count`, present only on `auto_compact_inject` entries):

- `boundary` — `session_compaction` | `session_end` (plus per-phase
  boundaries; see the taxonomy file).
- `stop_reason` — one of `self_abort` | `loop_guard_release` |
  `policy_gate_stop` | `partial_completion` | `normal_completion` |
  `harness_terminated`. `null` when `boundary != session_end`.
- `timestamp` — ISO-8601 UTC, generated via
  `date -u +%Y-%m-%dT%H:%M:%SZ`.
- `cache_creation_input_tokens` — integer or `null`.
- `cache_read_input_tokens` — integer or `null`.
- `input_tokens` — integer or `null` (used by Plan 07 lightening
  signal).
- `consecutive_stop_blocks` — integer or `null`. The Stop hook
  loop-guard counter; meaningful only for `boundary: session_end`.
- `shipped_count` — integer, OPTIONAL. Present ONLY on `boundary:
  auto_compact_inject` entries (written by the two auto-compact hooks); the
  cumulative number of shipped tickets at that boundary. Omitted on every other
  boundary. It is recorded in its own field rather than overloading
  `consecutive_stop_blocks` (which the auto-compact hooks previously polluted),
  so forensic readers are not misled.

Append-only contract: hooks MUST NOT rewrite or remove existing entries.

## Stop-hook loop guards

`hooks/autopilot-continue.sh` runs two parallel counters and AND-combines
them to decide when to release end_turn:

| Counter | Source of truth | Reset condition | Threshold |
| --- | --- | --- | --- |
| `FILE_COUNT` (a.k.a. `MTIME_COUNT`) | `/tmp/.autopilot-continue-${session_id}` | `STATE_FILE -nt COUNTER_FILE` (state file advanced) | `>= 5` |
| `NOTOOL_COUNT` | `/tmp/.autopilot-notool-${session_id}` | The most recent assistant turn in `transcript_path` carries a `tool_use` block whose `name` is one of `Skill`, `Agent`, `Bash`, `Edit`, `Write`, `NotebookEdit` (`Read` is intentionally excluded — pure investigation turns are not progress) | `>= 5` |

Release fires only when **both** counters meet their thresholds. The
two-counter rule replaces the pre-Plan-02 single-counter logic in which
"state stuck for 5 blocks" alone was sufficient — that single signal
misfired when the model emitted text-only end_turns without making real
progress. With `NOTOOL_COUNT` in place the hook holds its
`decision: block` until the model has actually given up on tools as
well.

When `transcript_path` is empty / missing / malformed, the hook
gracefully degrades to the pre-Plan-02 single-counter behaviour
(`NOTOOL_COUNT` is treated as already met).

On release the hook emits the literal line `[AUTOPILOT-STALL] ...` to
**both** stdout (for user-visible recovery instructions) and stderr (for
the runtime-metrics discrimination heuristic), then writes a
`boundary: session_end, stop_reason: loop_guard_release` entry to
`runtime_metrics:`.

Kill switch: setting `AUTOPILOT_LEGACY_LOOPGUARD=1` in the hook
environment short-circuits `NOTOOL_COUNT` (treats it as already met) so
`FILE_COUNT` alone gates release — exactly the pre-Plan-02 behaviour.
Use this only when the new logic is misfiring; the kill switch is meant
for immediate rollback, not as a default operating mode.

## Human override defaults (per risk_tolerance tier)

Step 5 of Phase 1 compares each gate's `action` in the per-ticket /
brief-level `autopilot-policy.yaml` to the defaults below for the
declared `risk_tolerance`. Differences are classified as `kb_override`
when a `# kb-suggested` comment sits at the same indentation, otherwise
`human_override`. When no differences are detected the run logs
"No human overrides detected."

`conservative` defaults:

- `ticket_quality_fail.action: retry_with_feedback`
- `evaluator_dry_run_fail.action: stop`
- `ac_eval_fail.action: retry`
- `audit_infrastructure_fail.action: stop`
- `ship_review_gate.action: stop`
- `ship_ci_pending.action: wait`
- `ship_ci_pending.timeout_minutes: 30`
- `constraints.max_total_rounds: 9`
- `constraints.allow_breaking_changes: false`
- `constraints.verification_depth: auto`
- `unexpected_error.action: stop`

`moderate` defaults: conservative except
`evaluator_dry_run_fail.action: proceed_without`,
`audit_infrastructure_fail.action: treat_as_fail`,
`ship_review_gate.action: proceed_if_eval_passed`.

`aggressive` defaults: moderate plus
`aggressive ship_ci_pending.timeout_minutes: 60`,
`aggressive constraints.max_total_rounds: 12`,
`aggressive constraints.allow_breaking_changes: true`.

`constraints.verification_depth: auto` is the default at **every** tier — the
`auto` derivation already folds `risk_tolerance` into the depth-tier matrix
(it is NOT a per-tier literal like `max_total_rounds`), so the same `auto`
value at conservative / moderate / aggressive resolves to different effective
depth tiers. The derivation matrix (Size x risk_tolerance -> tier), the
per-tier effects ladder (max-rounds bonus, forced audit third-pass,
multi-verifier majority), the `rounds=N` precedence interaction, and the
`off` kill switch live in
[`skills/impl/references/verification-depth.md`](../../impl/references/verification-depth.md).
A policy that pins `verification_depth` to a literal tier
(`standard` / `thorough` / `exhaustive` / `off`) is a `human_override`
relative to the `auto` default and is rendered under `## Human Overrides`
exactly like any other gate divergence.

## Skip-transition invariant (per-ticket pipeline)

`/autopilot` MUST NOT mark a ticket `skipped` while any sibling is
`pending` or `in_progress`, unless one of:

- **Dependency cascade**: the ticket's `skip_reason` contains
  `dependency_failed` or `dependency_skipped`.
- **Explicit override**: `override_skip: true` appears at the same
  indentation as `status:` AND the `skip_reason` does NOT match any
  pattern in `hooks/lib/forbidden-rationale-patterns.sh`.

The PreToolUse:Write/Edit guard `hooks/pre-state-transition.sh` blocks
violations as `unauthorized_skip_with_active_siblings` or
`unauthorized_skip_with_forbidden_rationale`. Recovery is via
auto-compaction or `unexpected_error.action: stop`.
