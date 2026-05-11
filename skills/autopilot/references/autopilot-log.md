# Autopilot Log Reference

Detailed schema and section format for the split-run `autopilot-log.md`
artifacts written at the end of `/autopilot`. The SKILL.md summarises
the orchestration moves (when to write the overall vs per-ticket log,
which dir to write to); this file is the schema source of truth for the
log contents.

## Overall log frontmatter

```yaml
parent_slug: {parent-slug}
started: {ISO-8601 UTC}
completed: {ISO-8601 UTC}
final_status: {completed | completed-with-warnings | partial | failed}
ticket_count: {N}
tickets_completed: {N}
tickets_failed: {N}
tickets_skipped: {N}
ticket_mapping:
  {parent-slug}-part-{N}: {ticket-dir}
```

## `final_status` discrimination

- `completed` — all tickets reached `status: completed` AND every
  ticket's `manual_bash_fallbacks[]` is empty.
- `completed-with-warnings` — all tickets reached `status: completed`
  but at least one ticket has a non-empty `manual_bash_fallbacks[]`.
- `partial` — mix of `completed` plus `failed`/`skipped`.
- `failed` — the first ticket already failed.

## Per-ticket subsection format

The overall log's `## Pipeline Execution` section emits one subsection
per ticket (also written verbatim to each ticket's own `autopilot-log.md`):

```markdown
### Ticket: {parent-slug}-part-{N} → {ticket-dir} ({status})
- scout: {status}
- impl: {status} ({rounds} rounds)
- ship: {status} → PR: {url}
- Manual Bash Fallbacks: {rendered from manual_bash_fallbacks[]}
```

**Manual Bash Fallback rendering**: the structured
`manual_bash_fallbacks[]` list in each ticket's `autopilot-state.yaml`
is the single source of truth. Render each entry verbatim as

```
{timestamp} | {command} | {reason} (exit={exit_code}, destructive={destructive})
```

Print `none` when the list is empty. The per-step `invocation_method ==
manual-bash` flag MUST be set iff a matching entry exists — the flag is
derived from the structured list, never the other way round.

## Common log sections

Every `autopilot-log.md` (overall + per-ticket) includes the following
sections in this order:

- `## Pipeline Execution` — per-step status per ticket (the
  per-ticket subsection format above).
- `## Warnings` — appears only on `completed-with-warnings`; replays
  every `manual_bash_fallbacks[]` entry verbatim as
  `timestamp | command | reason | exit_code | destructive`.
- `## Human Overrides` — Step 5 rows with `human_override` only;
  `kb_override` rows go to `## KB Overrides`. Format:
  `| {gate} | {expected_action} | {actual_action} | human_override |`.
  When none, write "No human overrides detected."
- `## KB Overrides` — Step 5 rows with `kb_override`. Same format with
  `kb_override` in the trailing column. When none, write "No KB
  overrides detected."
- `## Decisions Made` — table parsed from `[AUTOPILOT-POLICY]` stdout
  lines, one row per gate. "No policy decisions were triggered" when
  none. Distinguish `human_override` and `kb_override` types in the
  notes column.
- `## Unreached Gates` — only when at least one canonical gate was not
  considered; MUST NOT appear when every gate was evaluated. See
  `references/gate-decisions.md` for the enumeration discipline.
- `## Stop Reason` — only on stopped / failed runs; see
  `references/stop-reason-taxonomy.md` for the tag enum.
