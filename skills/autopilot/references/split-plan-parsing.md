# Split-Plan Parsing Reference

Detailed parsing, edge-case, and topological-sort contract for
`.simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md`
when consumed by `/autopilot`. The SKILL.md `## Error Handling` section
keeps the verbatim error literals for the empty-tickets and cyclic-
`depends_on` edges; this file holds the parser detail, algorithmic
discipline, AND the verbatim error literals for the invalid-frontmatter
and `parent_slug` mismatch edges (see Edge cases below).

## Source-of-truth path

The single source of truth for the ticket list is
`.simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md`
(Plan 4). The legacy `briefs/active/{parent-slug}/split-plan.md` path
is NOT read.

## Frontmatter parse

Per `.simple-workflow/docs/fix_structure/spec-split-plan-schema.md`,
the file MUST carry frontmatter with three keys:

- `parent_slug` — MUST equal the `/autopilot` argument; mismatch is an
  error.
- `ticket_count` — integer `N >= 0`.
- `version` — schema version integer.

Any missing key is an error. Frontmatter `parent_slug` mismatch is also
an error. The exact ERROR literals (load-bearing for downstream
tooling) are:

- **Invalid frontmatter** (missing `parent_slug`, `ticket_count`, or
  `version` key): print exactly `ERROR: split-plan.md at .simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md has invalid frontmatter` and exit non-zero.
- **`parent_slug` mismatch**: print exactly `ERROR: split-plan.md parent_slug mismatch (file=<frontmatter-value>, argument=<parent-slug>)` and exit non-zero.

## Ticket entries

Each ticket appears under `## Tickets` as

```markdown
### N. {parent-slug}-part-N: <Title>
- ticket_dir: `.simple-workflow/backlog/product_backlog/{parent-slug}/{NNN}-{slug}`
- size: ...
- depends_on: [...]
```

Field summary:

- `N` — 1-based index, monotone.
- `{parent-slug}-part-N` — the logical id used in `ticket_mapping`.
- `ticket_dir` — absolute-from-repo-root path; basename is
  `{NNN}-{slug}`.
- `size` — informational only for `/autopilot`.
- `depends_on` — list of logical ids that MUST be `completed` before
  this ticket runs.

## Edge: zero ticket entries

Zero `### N.` entries (equivalently `ticket_count: 0`) is an error.
The SKILL.md Error Handling section carries the verbatim ERROR literal
including the load-bearing word `empty`. `/autopilot` MUST exit non-zero
and MUST NOT create or modify any file under
`.simple-workflow/backlog/active/`.

## Edge: cyclic `depends_on` graph

Build a directed graph over ticket logical ids and run Kahn's algorithm
to detect cycles. If detected, `/autopilot` emits the verbatim ERROR
literal (see SKILL.md Error Handling) including the load-bearing word
`circular` (or `cycle`) and the cycle members, and exits non-zero
**before any ticket work begins**. Do NOT create
`.simple-workflow/backlog/active/{parent-slug}/` subdirectories.

## Topological sort with lexicographic tiebreak

Run Kahn's algorithm with a FIFO queue ordered by ascending
lexicographic `ticket_dir`:

1. Compute in-degree per node.
2. Seed the ready queue with all nodes whose `depends_on: []` (roots).
3. Pop the smallest ready node into the processing order.
4. Decrement each dependent's in-degree; re-insert in lex order when
   in-degree hits 0.
5. Repeat until the ready queue is empty.

If the processing order's length is less than `total_tickets`, the
graph had a cycle (use the same ERROR path as the cycle edge).

Emit one `Processing order: {NNN-slug}` line per ticket at the top of
Phase 2 (`{NNN-slug}` is the basename of `ticket_dir`, e.g.
`005-add-user-auth`).

## Wave layering (level-synchronous Kahn) — `PARALLEL_MODE != off` only

When `PARALLEL_MODE != off`, `/autopilot` ALSO groups the tickets into
**topological waves** so non-blocked tickets can be executed together
(Phase 2 parallelism; emit/test-only at Phase 1 concurrency 1). A wave is
one level of the dependency DAG: wave 0 is every root, wave k+1 is every
ticket whose `depends_on` are all in waves ≤ k.

Level-synchronous Kahn — the same in-degree + lexicographic-tiebreak
machinery as the linear sort above, but peel a whole in-degree-0 LEVEL
per round instead of one node:

1. Compute in-degree per node.
2. **Wave 0** = all nodes with in-degree 0 (roots), listed in ascending
   lexicographic `ticket_dir` order.
3. Remove the current wave's nodes; decrement each dependent's in-degree.
4. **Wave k+1** = all nodes whose in-degree has now reached 0 and were
   not placed in any earlier wave, again in lexicographic order.
5. Repeat until every node is placed. If some node never reaches
   in-degree 0 the graph had a cycle — use the same ERROR path as the
   cycle edge (already detected by the linear sort above, which runs
   first).

Emit one line per wave, AFTER the existing `Processing order:` block:

```
Wave 0: {NNN-slug}, {NNN-slug}
Wave 1: {NNN-slug}
```

`{NNN-slug}` is the basename of `ticket_dir`; entries within a wave are
listed lexicographically.

**Relationship to `Processing order:`.** The linear `Processing order:`
(per-node Kahn, authoritative for serial / concurrency-1 execution) is
**unchanged** — wave layering is purely additive, and both honour every
`depends_on` edge. For the common layout where a dependent ticket is
numbered (hence sorts) after the tickets it depends on, reading the waves
in order and each wave lexicographically reproduces `Processing order:`
exactly. The two diverge only when a dependent sorts lexicographically
*before* an unrelated independent ticket; in that case `Processing
order:` stays authoritative for serial execution and the wave grouping is
authoritative for Phase 2 parallel execution (a ticket is spawned only
once all its `depends_on` sit in completed waves). At Phase 1 concurrency
1, execution follows `Processing order:` and the wave lines are
emit/test-only.

## Mapping table

If `resume_mode`, use `ticket_mapping` from `autopilot-state.yaml`.
Otherwise seed empty and add each ticket from the split-plan as
`{parent-slug}-part-{N}` → `{ticket-dir}` immediately on first parse.
