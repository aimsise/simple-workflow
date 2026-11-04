# Schema: findings document (`findings=<path>`)

Normative schema for the findings file that `/create-ticket findings=<path>` consumes (Findings mode, Steps F-1..F-3 in `skills/create-ticket/references/mode-dispatch-flows.md`) and forwards verbatim to the `decomposer` agent as `Input form: findings_doc` (`skills/create-ticket/references/spec-decomposer-input.md` Form A).

A findings document is the structured result of an investigation that has **already been carried out**: it enumerates every work unit needed to finish the job. Contrast with `brief.md` (the `/brief` output), which is the interview + investigation request written BEFORE any investigation.

## Required layout

```markdown
---
title: <project title>
findings_version: 1
slug_hint: <optional-kebab-case-hint>
---

# Findings: <title>

## Context
<project background, why this work matters, 1-3 paragraphs>

## Investigation Summary
<what was investigated, what was found, 2-5 paragraphs>

## Required Work Units
<each work unit is a `### N. <Unit Title>` heading>

### 1. <Unit Title A>
<scope, observable outcome, affected files, dependencies: free-form prose + bullets>

### 2. <Unit Title B>
...

## Dependencies (optional)
<inter-unit dependencies when they are not inferable from the Required Work Units bodies>

- Unit B depends on Unit A
```

## Frontmatter

| Key | Required | Value |
|---|---|---|
| `title` | yes | Title of the whole piece of work. The naming base of `parent_slug` when `slug_hint` is absent. |
| `findings_version` | yes | Schema version. MUST equal `1` for this skill version; any other value (or a missing key) is rejected. |
| `slug_hint` | no | Explicit `parent_slug`. When omitted, `parent_slug` is derived from `title`. |

## Body sections

- `## Context` (required): background. Material for each ticket's Background.
- `## Investigation Summary` (required): the facts the investigation established. Material for each ticket's Scope / affected files.
- `## Required Work Units` (required): one `### N. <Title>` heading per unit, N >= 1, matched by the regex `^###\s+[0-9]+\.\s+.+`. **Authoritative** for the partition: the decomposer maps these headings to tickets one-to-one (after its own merge / overflow rules).
- `## Dependencies` (optional): inter-unit dependencies. When omitted, the decomposer infers them from the unit bodies.

## `parent_slug` derivation

1. If frontmatter `slug_hint` is present, use it verbatim (after trimming surrounding whitespace).
2. Otherwise kebab-case `title`: lowercase ASCII, whitespace -> hyphen, strip every character outside `[a-z0-9-]`, truncate at 40 characters.

The decomposer applies the same rule; when `slug_hint` was absent and the two derivations disagree, the decomposer's value wins (Step F-5).

## N = 1 versus N > 1

The number of `### N.` headings is the ticket count N. Both paths use the uniform nesting `.simple-workflow/backlog/product_backlog/{parent-slug}/{NNN}-{slug}/` and both write `.simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md` (unconditional for N >= 1, Step W-7; schema in `skills/create-ticket/references/split-plan-schema.md`). The difference is the SW-CHECKPOINT recommendation shape (Step W-11): a single `next_recommended:` line for N = 1, the `next_recommended_auto:` / `next_recommended_manual:` pair for N > 1.

## Error cases

| Input | Behaviour (exit non-zero, no directories created, `.ticket-counter` untouched) |
|---|---|
| File does not exist at `<path>` | `ERROR: Findings file not found at <path>` (Step F-1; the literal path argument is substituted) |
| `findings_version` missing, or value other than `1` | `ERROR: findings_version missing or unsupported (expected 1)` (Step F-2) |
| `## Required Work Units` section missing, or zero `### N.` headings under it | `ERROR: findings file contains zero Required Work Units` (Step F-3) |
| Circular dependency among the units (A -> B -> A) | `ERROR: circular dependency detected among tickets: <cycle members>` (Step F-6; the literal `circular` MUST appear) |

## Examples

Two tracked fixtures are the reference instances of this schema (their subject matter is illustrative only):

- `tests/fixtures/findings-3tickets.md`: N = 3 with `slug_hint`, a `## Dependencies` section in which units 2 and 3 both depend on unit 1 and are independent of each other. The expected decomposer output is `{parent-slug}-part-1` with `depends_on: []` and parts 2 and 3 each with `depends_on: [{parent-slug}-part-1]`, so the topological order runs part-1 first and parts 2 and 3 may run in parallel.
- `tests/fixtures/findings-1ticket.md`: N = 1 without `slug_hint`, so `parent_slug` is derived from `title`.
