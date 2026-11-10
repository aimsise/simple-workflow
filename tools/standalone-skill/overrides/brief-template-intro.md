target: references/brief-template.md
heading: # brief.md Body Template
mode: before
---
# Brief Template

A brief is the input of `brief=<path>` mode: a hand-written Markdown file (any name, e.g. `brief.md`) with YAML frontmatter followed by the body below. This skill reads exactly these frontmatter keys and no others:

- `slug` (required): kebab-case; becomes `{brief_slug}`, which is also the `{parent-slug}` of the run (Steps B-2 and DL-2; a `local:` destination nests the tickets under it).
- `interview_complete` (`true` | `false`): `true` skips Phase 2 (Socratic Refinement); `false` or absent runs the capped Socratic interview.

```yaml
---
slug: <kebab-case-slug>
interview_complete: false
---
```

In the body, an optional sentence "This is part {N} of {total}" marks one brief of a split set; Step DL-2 records it as the `Brief Part` row (key `brief_part`) of every ticket it delivers.

The body uses the headings of the fenced template below. Step B-5 forwards `## Vision`, `## Business Context`, `## Technical Requirements`, `## Scope` and `## Constraints` verbatim as the decomposer's `## Context`. When Phase 2 runs, args-aware shrinkage also scans `## Vision`, `## Business Context`, `## Technical Requirements` and `## Scope`, so a question they already answer is not asked. `## Investigation Summary` may be left empty: Phase 1 always runs the researcher in brief mode.
