target: references/findings-schema.md
heading: ## Error cases
mode: replace
---
## Error cases

| Input | Behaviour (stop, no directories created, `.ticket-counter` untouched) |
|---|---|
| File does not exist at `<path>` | `ERROR: Findings file not found at <path>` (Step F-1; the literal path argument is substituted) |
| Frontmatter without `title` | `ERROR: findings frontmatter is missing title` (Step F-2) |
| `findings_version` missing, or value other than `1` | `ERROR: findings_version missing or unsupported (expected 1)` (Step F-2) |
| `## Required Work Units` section missing, or zero `### N.` headings under it | `ERROR: findings file contains zero Required Work Units` (Step F-3) |
| Circular dependency among the units (A -> B -> A) | `ERROR: circular dependency detected among tickets: <cycle members>` (Step F-6; the literal `circular` MUST appear) |
