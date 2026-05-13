# Compact-state and session-log schema

This reference documents the YAML-frontmatter schema and parsing rules for compact-state and session-log files consumed by `### 1.` of `skills/catchup/SKILL.md`. The SKILL.md body summarises the contract (and pins the four H-2 field names plus the `tickets` / `in_progress_phase` Cat 20 patterns); the per-ticket `- dir:` schema and parsing recipe live here.

## Source files (most recent first)

Check for recent compact-state files in `.simple-workflow/docs/compact-state/compact-state-*.md` (most recent first).

## YAML-frontmatter compact-state: scalar fields

**If the latest file starts with a YAML frontmatter (`---`)**, parse the frontmatter and extract the following fields as variables (used in Step 4):

- `date` — when the compact happened
- `branch` — branch at compact time
- `active_tickets` — list of ticket directories that were active
- `active_plans` — list of plan files that were active
- `latest_eval_round` — highest round number across all tickets (aggregate)
- `latest_audit_round` — highest round number across all tickets (aggregate)
- `last_round_outcome` — `PASS` | `FAIL` | `PASS_WITH_CONCERNS` | `unknown` (aggregate — from the most relevant impl-loop ticket)
- `in_progress_phase` — `impl-loop` | `impl-done` | `unknown` (aggregate — `impl-loop` if any ticket is looping)
- `tickets` — per-ticket array with `{dir, latest_eval_round, latest_audit_round, last_round_outcome, in_progress_phase}` for each active ticket

## Per-ticket `tickets:` array parsing recipe

Use the `Read` tool to load the full compact-state file into context, then extract scalar fields by matching line prefixes (e.g., `latest_eval_round:`, `in_progress_phase:`). For list fields (`active_tickets`, `active_plans`) collect lines matching `^  - ` (2-space indent, dash, space) until the next non-list line.

For the per-ticket `tickets:` array, each ticket entry begins with the line prefix below (2-space indent, dash, space, then the literal `dir:` key) and its attributes are indented by 4 spaces (`    latest_eval_round:`, `    latest_audit_round:`, `    last_round_outcome:`, `    in_progress_phase:`):

```
  - dir: <ticket-dir>
    latest_eval_round: <int>
    latest_audit_round: <int>
    last_round_outcome: PASS | FAIL | PASS_WITH_CONCERNS | unknown
    in_progress_phase: impl-loop | impl-done | unknown
```

Parse them as an ordered list of maps; each map terminates when the next `  - dir: ` line appears or when the block ends. Do NOT use Bash for parsing — the allowed-tools of this skill do not include shell piping; `Read` and `Grep` are sufficient.

## Legacy (non-frontmatter) compact-state

**If the latest file does not start with `---`**, treat it as a legacy compact-state file and ignore the structured fields (still keep its existence as a flag for Step 2).

## Session-log fallback

**If no compact-state file is found** (or as a complement), check for the most recent session log at `.simple-workflow/docs/session-log/session-log-*.md`. If the file starts with a YAML frontmatter (`---`), parse the metadata (`date`, `branch`, `last_commit`, `changed_files`) and the `## Final Status` / `## Recent Commits` sections to recover the last-known working state. Skip files without YAML frontmatter (legacy format).
