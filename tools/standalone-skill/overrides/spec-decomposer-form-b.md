target: references/spec-decomposer-input.md
heading: ## Form B — `scope_context`
mode: replace
---
## Form B — `scope_context`

Spawn prompt body shape (header lines first, in this order: `Input form:`, `Parent slug:`, the optional `Dossier role:`, present only when a `## Source dossier` body section follows (its own section below), and `Max tickets:`, the last header line):

```markdown
Input form: scope_context
Parent slug: <kebab-case-slug>
Dossier role: <candidate | context; only with a source dossier>
Max tickets: <N>

## Context

<bare-description text verbatim, OR brief.md `## Vision`, `## Business Context`, `## Technical Requirements`, `## Scope` (In / Out of Scope, Edge Cases) and `## Constraints` sections>

## Investigation Summary

<full content of the researcher-produced investigation.md>

## Socratic Answers

<optional Phase 2 user responses, one bullet per answer; omit the section entirely when no Socratic round ran>
```

There is no frontmatter and no `## Required Work Units` section. The decomposer enumerates Work Units itself, grounded in `## Investigation Summary` and `## Context` (and `## Socratic Answers` when present). Hard Constraint #2 in the agent file binds this grounding requirement.

The caller (`/create-ticket` orchestrator) is responsible for:
- Deriving `parent_slug` before the spawn (from the bare description's kebab-cased slug, or from the brief frontmatter `slug` key).
- Inlining the full content of `investigation.md` (no external file references — the agent must not write anything but its return envelope, and the spawn prompt is the only context source).
- Passing Socratic answers verbatim (omit the section if Phase 2 was skipped via `interview_complete: true` or non-interactive fallback).
