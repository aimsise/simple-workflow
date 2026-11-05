target: SKILL.md
heading: ## Common Write Path
mode: replace
---
## Delivery

All three modes converge here, and only once every ticket of the run has a verdict. Exactly three verdicts exist: `PASS` (Phase 4); `SELF-EVALUATED` (only on a host with no subagent tool at all, per the degraded branch above); `FAIL (user-accepted)` (the user chose "proceed" at the exhausted-retry question). A subagent spawn that was attempted and failed, for any mandatory role, fails the run instead: nothing is delivered. Producing the tickets (Phases 1-4) never depends on the destination; Delivery is the only part of the run that writes outside `{scratch}`, apart from the one-line `.gitignore` append of Argument Parsing. The destination is `destination=<spec>` from Argument Parsing (`local:.docs/tickets` when absent), already checked by its preflight; each kind's adapter (`local:`, `mcp:`, `api:`) is defined in [references/destinations.md](references/destinations.md). Ticket content follows [references/ticket-template.md](references/ticket-template.md); the summary format is in [references/write-path-templates.md](references/write-path-templates.md).

### Step DL-1: Dependency graph validation (N>1 only)

Re-verify the `depends_on` graph: every `depends_on` references another ticket's logical id (`{parent-slug}-part-{M}` for `1 ≤ M ≤ N`); acyclic (topological sort returns N nodes). Violation → `ERROR: split-plan validation failed — <reason>` or `ERROR: circular dependency detected among tickets: <cycle members>`. The topological order computed here is the delivery order of every later step, so a ticket's dependencies are always delivered before it.

### Step DL-2: Final ticket text

For each ticket, starting from its last evaluated draft:

- Remove every `Change rationale:` comment line the retry planner added (a line that starts with `Change rationale:`, or an HTML comment that contains it); the rest of the text is delivered unchanged.
- Add `| Quality | <verdict> |` to its field table, with the verdict exactly as named above.
- If `brief=<path>` provided: read brief `slug` → `{brief_slug}`; extract `{brief_part}` from any "This is part {N} of {total}" indicator (from split briefs). Add `| Brief Slug | {brief_slug} |` (key `brief_slug`) and (if extracted) `| Brief Part | {brief_part} |` (key `brief_part`).

### Step DL-3: Deliver each ticket

Run the adapter of the destination kind over the tickets in topological order, exactly as [references/destinations.md](references/destinations.md) specifies:

- **Identity is destination-assigned.** A ticket's heading becomes `## {id}: {Title}`. A `local:` destination allocates `{id}` = `T-{NNN}` from its counter before it writes anything; an `mcp:` or `api:` destination submits the body with the heading `## {Title}` and records the `{id}` its create call returns.
- **Dependencies** are written as destination identifiers: the ticket's `Dependencies` cell lists the `{id}` of each ticket it depends on (`--` when none). A `local:` destination knows every `T-{NNN}` before writing; an `mcp:` or `api:` destination knows them because each dependency was created earlier in topological order, and it also states them as the destination's own link field or a `Depends on:` line.
- **`local:`** writes `{dir}/{parent-slug}/{NNN}-{slug}/ticket.md` per ticket, plus `{dir}/{parent-slug}/split-plan.md` when N > 1 ([references/split-plan-schema.md](references/split-plan-schema.md)), then writes the counter `{dir}/.ticket-counter` once, after every other file is written.
- **`mcp:` and `api:`** ask once for confirmation before the first create (skipped only by `confirm=yes`; a denied, erroring or unavailable ask-user tool stops the run with nothing created), then issue one create call per ticket. Before a ticket is sent, every logical id (`{parent-slug}-part-N`) of an already-created ticket in its text is replaced by that ticket's destination id. The returned identifiers are the whole record of the run: no split-plan file and no counter.

### Step DL-4: Delivery failure

- **`local:`**: a write failure is quarantined, never deleted, under `{dir}/.rollback/{parent-slug}-{ts}/` by the write-failure rule of [references/destinations.md](references/destinations.md); the counter stays untouched, so a re-run with the same inputs is safe. If only the final counter write fails, the tickets stay in place and the run prints `ERROR: create-ticket counter write failed — set {dir}/.ticket-counter to <counter + N> (<reason>)` and stops.
- **`mcp:` / `api:`**: remote creates are not transactional. On a failure after `k` successful creates, print the `k` identifiers already created (in creation order), then the `ERROR:` line, and stop. Never delete or modify a remote item and never retry on your own: a re-run with the same input creates every ticket again, so the user decides how to finish.

### Step DL-5: Final summary

End the run with a `### Final summary` block as the last output, in the format of [references/write-path-templates.md](references/write-path-templates.md): per ticket, the path of its `ticket.md` relative to the working directory (`local:`) or its identifier (`mcp:` / `api:`), plus category, size, AC count and verdict; N>1 adds the dependency order (and, for `local:`, the `split-plan.md` path). Repeat any `WARNING:` line of the run (e.g. the decomposer overflow). In every variant, the `Scratch:` line names the `{scratch}` path so the user can find the drafts, evaluator reports and API responses of the run; it is omitted when the run stopped before the scratch directory was created. On failure, list what was created (`Created: none`, or the `k` identifiers) followed by the `ERROR:` line and the quarantine path when a `local:` write failed. Do not recommend follow-up commands.
