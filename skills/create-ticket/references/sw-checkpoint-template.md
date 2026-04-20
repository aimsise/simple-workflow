# `[SW-CHECKPOINT]` block — canonical template

Phase-terminating skills MUST emit this block as the final section of
their output. It is the single source of truth; individual SKILL.md
files reference this document rather than repeating the template body.

## Format (single-recommendation mode — N = 1 or non-ticket flows)

```
## [SW-CHECKPOINT]
phase: <skill canonical name>
ticket: <ticket-dir or "none">
artifacts:
  - <relative path>
  - <relative path>
next_recommended: <next command>
context_advice: "Intermediate tool outputs from this phase remain in the main session context. If you plan to run the next phase manually, run `/clear` first and then `/catchup` to recover position with minimal token spend."
```

## Format (dual-recommendation mode — gated on N > 1)

When `/create-ticket` writes the final CHECKPOINT for an N>1 run (multi-ticket
findings mode or brief-with-split), the block emits TWO recommendation lines
instead of one — `next_recommended_auto` and `next_recommended_manual`. The
legacy single `next_recommended:` line MUST NOT appear alongside these two
in the same block.

```
## [SW-CHECKPOINT]
phase: create_ticket
ticket: <first-created-ticket-dir>
artifacts:
  - <relative path to each ticket.md>
  - <relative path to split-plan.md>
next_recommended_auto: /autopilot <parent-slug>
next_recommended_manual: /scout <first-unblocked-ticket-dir>
context_advice: "Intermediate tool outputs from this phase remain in the main session context. If you plan to run the next phase manually, run `/clear` first and then `/catchup` to recover position with minimal token spend."
```

## Rules

- The block MUST be the last section of the skill's output. No summary,
  notice, or prose may follow it.
- `context_advice:` is the literal English sentence shown above, verbatim.
  Never translate, never paraphrase, never omit — include it even on
  failure paths.
- `phase:` uses the underscore-form canonical name of the emitting skill:
  one of `create_ticket`, `scout`, `impl`, `ship`.
- `ticket:` is the full repo-relative ticket directory path (e.g.
  `.backlog/active/001-foo`) when a ticket is in scope; otherwise the
  bare string `none` (no quotes) for non-ticket flows.
- `artifacts:` is a non-empty list of repo-relative paths on success;
  emit `artifacts: []` on a single line on failure paths (no files
  produced).
- **Recommendation mode selection (per-run)**:
  - **N = 1 success** → emit a single `next_recommended:` line whose value
    is the plausible next command (e.g. `/scout {dir}`, `/impl {plan-path}`,
    `/ship`). Do NOT emit `next_recommended_auto:` / `next_recommended_manual:`.
  - **N > 1 success** (dual-recommendation mode — only `/create-ticket`
    emits this) → emit BOTH `next_recommended_auto: /autopilot <parent-slug>`
    AND `next_recommended_manual: /scout <first-unblocked-ticket-dir>`. Do
    NOT emit a plain `next_recommended:` line. The `<first-unblocked-ticket-dir>`
    is chosen by selecting all tickets with `depends_on: []` and taking the
    lexicographically smallest `ticket_dir` (per
    `spec-split-plan-schema.md` § first-unblocked rule).
  - **Failure path (any N)** → emit a single `next_recommended:` line with
    value `""` (empty string). Do NOT emit `next_recommended_auto:` /
    `next_recommended_manual:`, even for N > 1 runs, because no ticket
    dirs exist and no downstream command is sensible.
- Exactly one of `next_recommended:`, or the pair `next_recommended_auto:`
  + `next_recommended_manual:`, appears per block. A single block that
  contains all three (or neither shape) is a contract violation.
- `/audit` does NOT emit a CHECKPOINT — it is a review delegate, not a
  phase terminator. `/plan2doc` is a delegate of `/scout` and also does
  NOT emit a CHECKPOINT; `/scout`'s block covers the plan2doc work.

## Why the dual-recommendation for N>1

A successful N > 1 `/create-ticket` run leaves the user at a fork:

1. Delegate the whole multi-ticket execution to `/autopilot <parent-slug>`
   (the `_auto` path), which consumes the `split-plan.md` this run just
   wrote and drives `/scout → /impl → /ship` per ticket in topological
   order.
2. Drive the pipeline manually, starting with the first-unblocked ticket
   (the `_manual` path): `/scout <first-unblocked-ticket-dir>`.

Both paths are valid; the CHECKPOINT surfaces both so neither is buried.
The `_manual` recommendation is deterministic (lexicographic tiebreak on
`ticket_dir`) so automation keying off the block's regex can assume a
stable value for the same set of tickets.

For N = 1 there is no fork — there is one ticket, and the next step is
always `/scout <that-ticket-dir>` — so the single `next_recommended:`
line remains.
