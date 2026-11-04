target: references/brief-template.md
heading: # brief.md Body Template
mode: before
---
# Brief Template

A brief is the input of `brief=<path>` mode: a hand-written Markdown file (any name, e.g. `brief.md`) with YAML frontmatter followed by the body below. This skill reads exactly these frontmatter keys and no others:

- `slug` (required): kebab-case; becomes `{brief_slug}`, which is also the `{parent-slug}` the tickets nest under (Steps B-2 and W-9).
- `interview_complete` (`true` | `false`): `true` skips Phase 2 (Socratic Refinement); `false` or absent runs the capped Socratic interview.
- `investigation_sha256` (optional): the SHA-256 of `{ticket-dir}/investigation.md`. When it matches, Phase 1 reuses that investigation instead of running the researcher (the content-hash freshness signal in `references/agent-spawn-prompts.md`).

```yaml
---
slug: <kebab-case-slug>
interview_complete: false
---
```

In the body, an optional sentence "This is part {N} of {total}" marks one brief of a split set; Step W-9 records it as the `Brief Part` row (key `brief_part`) of every ticket it creates.

The body uses the headings of the fenced template below. Step B-5 forwards `## Vision` + `## Business Context` verbatim as the decomposer's `## Context`. When Phase 2 runs, args-aware shrinkage also scans `## Vision`, `## Business Context`, `## Technical Requirements` and `## Scope`, so a question they already answer is not asked. `## Investigation Summary` may be left empty when Phase 1 will run the researcher.
