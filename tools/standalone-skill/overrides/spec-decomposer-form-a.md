target: references/spec-decomposer-input.md
heading: ## Form A — `findings_doc`
mode: replace
---
## Form A — `findings_doc`

Spawn prompt body shape (header lines first: `Input form:`, then `Max tickets:`, its last header line):

```markdown
Input form: findings_doc
Max tickets: <N>

<full findings document content, including frontmatter and body>

<optional Socratic Refinement answers, prefixed by `## Socratic Answers`>
```

Body sections expected inside the findings document body (per `references/findings-schema.md`):

- `## Context` (required)
- `## Investigation Summary` (required)
- `## Required Work Units` with `### N. <Title>` entries (required, N ≥ 1) — **authoritative** for partition
- `## Dependencies` (optional)

Frontmatter required keys: `title`, `findings_version: 1`, optional `slug_hint`.

The decomposer derives `parent_slug` from `slug_hint` (verbatim when it is kebab-case; the orchestrator normalizes it otherwise, Step F-2) or from `title` (kebab-cased, lowercase ASCII, whitespace → hyphen, non-`[a-z0-9-]` stripped, leading hyphens dropped, truncated at 40 chars).
