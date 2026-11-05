target: references/spec-decomposer-input.md
heading: ## Output (both forms)
mode: before
---
## `## Source dossier` (optional, both forms)

When the request carried `source=` tokens (SKILL.md `## Intake`), the caller appends one more body section as the LAST body section of either form (after `## Socratic Answers`, or after the last section the form has when no Socratic round ran), and in Form B one more header line after `Parent slug:`: `Dossier role: candidate` (bare or absent description: the dossier may hold the partition basis) or `Dossier role: context` (with a brief: the dossier is context only). Form A carries no such header.

```markdown
## Source dossier

<the full content of {scratch}/sources/dossier.md, verbatim: the index table, then every normalized source>
```

The dossier is defined in `references/sources.md`: each source `S<n>` starts with a six-line header block (`Source: S<n>` is its line 1) and a locator `S<n>:L<a>-L<b>` / `S<n>:L<a>` / `S<n>` names lines of that source.

What the section changes:

- **Grounding** extends to it: a work unit present (or directly entailed) in `## Source dossier` is grounded.
- **Partition basis.** Under `Dossier role: candidate`, the decomposer decides whether one source, or one part of it (a sheet, a section, a list), is partition-authoritative: it enumerates two or more discrete items that each state their own scope and outcome as work still to be done. Such a part is mapped to tickets one-to-one exactly as Form A maps `## Required Work Units` (merge, cap and overflow rules unchanged); otherwise the units are derived from the whole context. Form A keeps the findings units as the basis; Form B under `Dossier role: context` keeps the brief-derived units; a `## Source dossier` without a `Dossier role:` header is read as `context`. The decision rule in full is `## Source dossier handling` in `references/agents/decomposer.md`.
- **Output additions.** The `## Result` block carries `**Partition basis**: <locator> | derived | findings | brief` right after `**Rationale**:`, and every ticket carries a `source_refs: [<locator>, ...]` sub-line (`[]` when none). The caller extracts the lines those locators name into each planner spawn as `## Source excerpts` (`references/sources.md`, Locators and excerpts) and repeats the partition basis in the Final summary.
- **Caller duties.** Inline the dossier verbatim (the agent reads no file); keep it under the intake caps (`references/sources.md`), so the spawn prompt stays bounded; never pass the dossier to the ticket-evaluator.
