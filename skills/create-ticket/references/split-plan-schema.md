# Schema: `split-plan.md`

Normative schema for the per-parent ticket index that `/create-ticket` writes to `.simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md` on every successful run (N >= 1; for N = 1 the file carries exactly one `### 1.` entry with `ticket_count: 1` and `depends_on: []`). This file is the single source of truth for the field set, the entry grammar, the validation rules, and the first-unblocked tiebreak. The verbatim block template that the writer emits lives in `skills/create-ticket/references/write-path-templates.md` Step W-7 and is NOT repeated here; if the two ever disagree, this schema wins and the template MUST be updated to match.

Producer: `skills/create-ticket/SKILL.md` Step W-7 (writer) and Step W-11 (first-unblocked rule). Consumer: `skills/autopilot/references/split-plan-parsing.md` (parser, topological sort, wave layering).

## Frontmatter

| Key | Required by writer | Value |
|---|---|---|
| `parent_slug` | yes | Identical to the parent directory basename, i.e. the `{parent-slug}` in `.simple-workflow/backlog/product_backlog/{parent-slug}/`. |
| `findings_source` | yes | Path of the input findings file (audit trail). The empty string `""` in brief and bare-description modes, matching the `{findings-path-or-""}` placeholder in the W-7 template. |
| `ticket_count` | yes | Integer equal to the number of `### N.` entries under `## Tickets`. |
| `created` | yes | ISO-8601 UTC timestamp, e.g. `2026-04-21T00:14:18Z` (`date -u +%Y-%m-%dT%H:%M:%SZ`). |
| `version` | yes | Schema version; currently `1`. |

The writer emits all five keys. The `/autopilot` parser requires only `parent_slug`, `ticket_count` and `version` (a missing one of those three is its invalid-frontmatter error) and treats `findings_source` and `created` as informational.

## Body layout

```markdown
# Split Plan: {parent-slug}

## Context

{1-3 sentence summary: findings `## Context` in findings mode, brief `## Vision` in brief mode, the description in bare mode}

## Tickets

### 1. {parent-slug}-part-1: {Unit Title}

- ticket_dir: `.simple-workflow/backlog/product_backlog/{parent-slug}/{NNN}-{slug}`
- size: S | M | L | XL
- depends_on: []

{scope summary, 1-3 sentences}
```

## `## Tickets` entry grammar

Each entry heading is `### N. {parent-slug}-part-N: {Title}` and MUST match the regex

```
^###[[:space:]]+[0-9]+\.[[:space:]]+{parent-slug}-part-[0-9]+:
```

`N` is the 1-based index, monotone across entries. `{parent-slug}-part-N` is the ticket's **logical id**: it is the token used in `depends_on` lists and in `/autopilot`'s `ticket_mapping`.

Directly under each heading come three meta lines, in **this order**:

```
- ticket_dir: `.simple-workflow/backlog/product_backlog/{parent-slug}/{NNN}-{slug}`
- size: S | M | L | XL
- depends_on: [{logical-id-1}, {logical-id-2}, ...]
```

- `ticket_dir` is the physical directory path, repo-relative. `{NNN}` is the zero-padded three-digit ticket number allocated in Step W-2; the basename is `{NNN}-{slug}`.
- `size` is the granularity the planner / decomposer assigned. Informational for `/autopilot`.
- `depends_on` is a list of **logical ids** (`{parent-slug}-part-N`), never physical paths. No dependency is the literal `[]`.

Dependency examples (illustrative only):

```
- depends_on: []                                   # no deps
- depends_on: [{parent-slug}-part-1]               # one dep
- depends_on: [{parent-slug}-part-1, {parent-slug}-part-2]  # several deps
```

## Validation (writer side, Step W-7)

All of the following MUST hold before the writer returns success:

1. Frontmatter `parent_slug` equals the parent directory basename.
2. Frontmatter `ticket_count` equals the number of `### N.` entries under `## Tickets`.
3. Every entry heading matches the regex above.
4. Every entry carries a `- depends_on:` line.
5. Every `depends_on` element resolves to a logical id declared in the same file. An unresolvable id is reported as `ERROR: split-plan validation failed — unknown depends_on id <id>`.
6. The `depends_on` graph is a DAG: a topological sort returns all N nodes. A cycle is reported as `ERROR: circular dependency detected among tickets: <cycle members>` (the literal `circular` MUST appear).
7. Every `ticket_dir` exists on disk at write time (the per-ticket directories are created in Step W-4 before `split-plan.md` is written).

Any other violation is reported as `ERROR: split-plan validation failed — <reason>` with a non-zero exit. The failure handling (quarantine of the partial parent directory, counter untouched, re-run safety) is defined once in `skills/create-ticket/SKILL.md` Step W-4 and Step W-7.

## First-unblocked rule (Step W-11, N > 1)

`next_recommended_manual: /scout {first-unblocked-ticket-dir}` is resolved as:

1. Collect every entry whose `depends_on` is `[]`.
2. When more than one candidate exists, pick the entry whose `ticket_dir` is lexicographically smallest (the deterministic tiebreak).
3. Emit that physical `ticket_dir`.

The same lexicographic ordering of `ticket_dir` is the tiebreak `/autopilot` uses inside Kahn's algorithm, so the manual recommendation and the automated processing order start at the same ticket.

## Consumer note (`/autopilot`)

- `/autopilot` reads exactly one path: `.simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md`.
- The legacy `.simple-workflow/backlog/briefs/active/{parent-slug}/split-plan.md` location is NEVER read and is NOT a fallback, even when a file exists there.
- Parsing, the `parent_slug` mismatch and invalid-frontmatter error literals, the zero-entry and cycle edges, the topological sort and the wave layering are specified in `skills/autopilot/references/split-plan-parsing.md`.
