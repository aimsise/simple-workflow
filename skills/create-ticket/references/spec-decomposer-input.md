# Spec: `decomposer` agent input

Canonical schema for the two input forms the `decomposer` agent (`agents/decomposer.md`) accepts when invoked from `/create-ticket`. The agent file documents the same forms; this reference file is the tracked source of truth that downstream readers (skills, tests, future agents) cite by relative path.

## Two input forms

The caller selects exactly one form per spawn. The form is identified by the literal header line **`Input form: <form-name>`** at the top of the spawn prompt body.

| Form | Used by | Authoritative work-unit source | `parent_slug` source |
|---|---|---|---|
| `findings_doc` | `/create-ticket findings=<path>` | `## Required Work Units` headings | findings frontmatter (`slug_hint` → `title`) |
| `scope_context` | `/create-ticket` bare-description and brief modes | derived from `## Investigation Summary` + `## Context` (+ `## Socratic Answers`) | caller-supplied via `Parent slug:` header |

## Form A — `findings_doc`

Spawn prompt body shape:

```markdown
Input form: findings_doc

<full findings document content, including frontmatter and body>

<optional Socratic Refinement answers, prefixed by `## Socratic Answers`>
```

Body sections expected inside the findings document body (per `.simple-workflow/docs/fix_structure/spec-findings-fixture.md`):

- `## Context` (required)
- `## Investigation Summary` (required)
- `## Required Work Units` with `### N. <Title>` entries (required, N ≥ 1) — **authoritative** for partition
- `## Dependencies` (optional)

Frontmatter required keys: `title`, `findings_version: 1`, optional `slug_hint`.

The decomposer derives `parent_slug` from `slug_hint` (verbatim) or from `title` (kebab-cased, lowercase ASCII, whitespace → hyphen, non-`[a-z0-9-]` stripped, truncated at 40 chars).

## Form B — `scope_context`

Spawn prompt body shape:

```markdown
Input form: scope_context
Parent slug: <kebab-case-slug>

## Context

<bare-description text verbatim, OR brief.md `## Vision` + `## Business Context` sections>

## Investigation Summary

<full content of the researcher-produced investigation.md>

## Socratic Answers

<optional Phase 2 user responses, one bullet per answer; omit the section entirely when no Socratic round ran>
```

There is no frontmatter and no `## Required Work Units` section. The decomposer enumerates Work Units itself, grounded in `## Investigation Summary` and `## Context` (and `## Socratic Answers` when present). Hard Constraint #2 in the agent file binds this grounding requirement.

The caller (`/create-ticket` orchestrator) is responsible for:
- Deriving `parent_slug` before the spawn (from the bare description's kebab-cased slug, or from the brief frontmatter `slug` key).
- Inlining the full content of `investigation.md` (no external file references — the agent has read-only tools and the spawn prompt is the only context source).
- Passing Socratic answers verbatim (omit the section if Phase 2 was skipped via `interview_complete: true` or non-interactive fallback).

## Output (both forms)

Both forms produce the same `## Result` block (status / parent slug / tickets / topological order / rationale) bounded by the agent's Context Conservation Protocol (< 500 tokens). Cycle detection, the 8-ticket cap, and the `Status: partial` overflow path apply identically across forms.

## Failure modes

- Missing `Input form:` header → return `Status: failed` with rationale `missing input form header`.
- `Input form: scope_context` without a `Parent slug:` header → return `Status: failed` with rationale `scope_context missing parent slug header`.
- `Input form: findings_doc` whose body lacks `## Required Work Units` → return `Status: failed` with rationale `findings_doc missing required work units section`.
- Cycle in inferred or explicit dependencies → return `Status: failed` with cycle members named in the rationale (per Decomposition principle #5).

## Why two forms

Findings mode (`findings_doc`) consumes a human-authored or `/investigate`-authored findings document where Work Units are already enumerated; the decomposer's job is partition + dependency-graph synthesis only.

Bare-description and brief modes (`scope_context`) feed the decomposer raw scope intent plus researcher findings. The decomposer enumerates Work Units AND partitions them. This unifies all three `/create-ticket` modes on a single decomposer-led partition path, eliminating the previous `planner.Split Judgment` cohesion bias (where a draft-first agent decided post-hoc whether to split its own draft).
