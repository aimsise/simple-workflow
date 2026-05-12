# Common Write Path Templates

Canonical templates referenced by `skills/create-ticket/SKILL.md` Step W-6 (`phase-state.yaml` per-ticket pending template), Step W-7 (`split-plan.md` per-parent index), and Step W-10 (summary printing format). The full step list and pinned literals (`counter + N`, `.ticket-counter`, `[POLICY-PROPAGATION] skipped: brief mode=manual`, atomicity rules) live in SKILL.md; this file only holds the verbatim block templates so SKILL.md can stay within the BP body budget.

The schema authorities are:
- `skills/create-ticket/references/phase-state-schema.md` for `phase-state.yaml`.
- `.simple-workflow/docs/fix_structure/spec-split-plan-schema.md` for `split-plan.md`.

These two files MUST agree with what is written below; if they diverge, the schema file wins and this template MUST be updated to match.

## Step W-6 — `phase-state.yaml` pending template (per ticket)

For each ticket `i`:

1. `now` = ISO-8601 UTC (`date -u +%Y-%m-%dT%H:%M:%SZ`).
2. `size_i` = Size from planner/decomposer (S/M/L/XL).
3. Write `{ticket_dir_path_i}/phase-state.yaml` with the pending template below. **Do NOT include a top-level `ticket_dir:` field** — the file path encodes location (per `phase-state-schema.md` §1). Canonical schema reference: `skills/create-ticket/references/phase-state-schema.md`.

```yaml
version: 1
size: {size_i}
created: {now}

current_phase: create_ticket
last_completed_phase: null
overall_status: in-progress

phases:
  create_ticket:
    status: in-progress
    started_at: {now}
    completed_at: null
    artifacts:
      ticket: null

  scout:
    status: pending
    started_at: null
    completed_at: null
    artifacts:
      investigation: null
      plan: null

  impl:
    status: pending
    started_at: null
    completed_at: null
    current_round: null
    max_rounds: null
    phase_sub: null
    last_ac_status: null
    last_audit_status: null
    last_audit_critical: 0
    last_round: null
    next_action: null
    feedback_files:
      eval: null
      quality: null

  ship:
    status: pending
    started_at: null
    completed_at: null
    artifacts:
      pr_url: null
```

4. **Immediately** transition `phases.create_ticket` to `completed` in the same invocation (before returning) via read-modify-write. The post-transition top-level fields MUST match:
   - `phases.create_ticket.status: completed`
   - `phases.create_ticket.completed_at: {now}` (recomputed immediately before write)
   - `phases.create_ticket.artifacts.ticket: {ticket_dir_path_i}/ticket.md`
   - `last_completed_phase: create_ticket`
   - `current_phase: scout`

5. Do NOT modify other `phases.*` sections. The `scout`, `impl`, `ship` sections remain in the pending template for their owning skills.

6. Do NOT emit a top-level `ticket_dir:` line.

**Atomicity**: On write failure, report the error but do NOT delete already-created `ticket.md` files — retry is idempotent on the state file.

## Step W-7 — `split-plan.md` template (per parent)

Write `.simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md` following `.simple-workflow/docs/fix_structure/spec-split-plan-schema.md`. For N=1, emit exactly one `### 1.` entry under `## Tickets`, with `depends_on: []`. `ticket_count: 1` in the frontmatter. Exact schema:

```markdown
---
parent_slug: {parent-slug}
findings_source: {findings-path-or-""}
ticket_count: {N}
created: {ISO-8601 UTC}
version: 1
---

# Split Plan: {parent-slug}

## Context

{1-3 sentence summary lifted from findings.md Context section, or brief.md Vision if brief mode.}

## Tickets

### 1. {parent-slug}-part-1: {Unit Title}

- ticket_dir: `.simple-workflow/backlog/product_backlog/{parent-slug}/{NNN-1}-{slug-1}`
- size: {S|M|L|XL}
- depends_on: []

{scope summary, 1-3 sentences}

### 2. {parent-slug}-part-2: {Unit Title}

- ticket_dir: `.simple-workflow/backlog/product_backlog/{parent-slug}/{NNN-2}-{slug-2}`
- size: {S|M|L|XL}
- depends_on: [{parent-slug}-part-1]

{scope summary}

### 3. {parent-slug}-part-3: {Unit Title}

- ticket_dir: `.simple-workflow/backlog/product_backlog/{parent-slug}/{NNN-3}-{slug-3}`
- size: {S|M|L|XL}
- depends_on: [{parent-slug}-part-1]

{scope summary}
```

Validation contract:
- Frontmatter `parent_slug` equals the parent directory basename.
- Frontmatter `ticket_count` equals the number of `### N.` entries in `## Tickets` (exactly N entries).
- Each entry's heading matches regex `^###[[:space:]]+[0-9]+\.[[:space:]]+{parent-slug}-part-[0-9]+:`.
- Every entry has a `- depends_on:` line.
- The `depends_on` graph is a DAG (topological sort returns N nodes).

On validation failure, print `ERROR: split-plan validation failed — <reason>` and exit non-zero. No directories or artifacts persist (they were created during Step W-4 and must be rolled back per the atomicity rule).

## Step W-10 — Summary printing format

After writing, print a summary.

**Non-split (N = 1)**:
- Ticket file path (e.g. `Ticket file path: .simple-workflow/backlog/product_backlog/{parent-slug}/{NNN}-{slug}/ticket.md`)
- Category, Size
- Number of ACs
- Quality evaluation result (PASS / FAIL + remaining issues)
- Recommended workflow: `/scout → /impl → /ship`

**Split (N > 1)**: Print a ticket list table followed by per-ticket details:

```
### Created Tickets (N tickets)

| # | Path | Category | Size | ACs | Quality |
|---|------|----------|------|-----|---------|
| T-005 | .simple-workflow/backlog/product_backlog/{parent-slug}/005-foo/ticket.md | CodeQuality | M | 3 | PASS |
| T-006 | .simple-workflow/backlog/product_backlog/{parent-slug}/006-bar/ticket.md | CodeQuality | S | 2 | PASS |
| ... | ... | ... | ... | ... | ... |

Split plan: .simple-workflow/backlog/product_backlog/{parent-slug}/split-plan.md
Recommended workflow per ticket: `/scout → /impl → /ship`
```
