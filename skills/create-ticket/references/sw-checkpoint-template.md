# `[SW-CHECKPOINT]` block — canonical template

Phase-terminating skills MUST emit this block as the final section of
their output. It is the single source of truth; individual SKILL.md
files reference this document rather than repeating the template body.

## Format

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
- `next_recommended:` is the plausible next command (e.g. `/scout {dir}`,
  `/impl {plan-path}`, `/ship`); use empty string `""` when there is no
  sensible next step (ticket complete, or the skill stopped without
  producing a shippable state).
- `/audit` does NOT emit a CHECKPOINT — it is a review delegate, not a
  phase terminator. `/plan2doc` is a delegate of `/scout` and also does
  NOT emit a CHECKPOINT; `/scout`'s block covers the plan2doc work.
