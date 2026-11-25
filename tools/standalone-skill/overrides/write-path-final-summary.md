target: references/write-path-templates.md
heading: ## Step W-10 — Summary printing format
mode: replace
---
## Final summary format (Step DL-5)

End the run with this block as its last output. The `### Final summary` block is printed in the stated format below, with its literal heading and its `Destination:` and `Scratch:` lines (each in the variants that carry it), and is never replaced by a free-form recap. `Destination` is the destination spec with its channel kind (`local:`, `mcp:`, `api:`, `browser:` or `cli:`), an `api:` or `browser:` URL printed without its query string and a `cli:` command template printed in full, in double-quoted token form. `Ticket` is the path of the `ticket.md` for a `local:` destination (relative to the working directory, or under `{dir}` exactly as typed when `{dir}` is absolute or `~`-prefixed, a `~` never expanded), and the identifier the create call returned (plus its URL without the query string, when one was returned) for an `mcp:`, `api:`, `browser:` or `cli:` destination. `Verdict` is `PASS`, `SELF-EVALUATED`, `FAIL (user-accepted)` or `FAIL (unresolved)` (either `FAIL` verdict with the remaining issues on a following line). Add the line `Phase 2 skipped (non-interactive mode)` when that fallback fired, repeat the implied-confirmation line `NOTE: this host has no ask-user tool; running as if confirm=yes was passed (a remote create is not confirmed first, and a ticket still graded FAIL is delivered as FAIL (unresolved)); pass confirm=no to stop instead` when it was printed, repeat every other `NOTE:` line of the run (no Python 3 for the HTML conversion or for the stored-text check, a stored text that could not be read back), and repeat every `WARNING:` line of the run (a decomposer overflow with its `findings=` re-run, a normalized slug, a spawn retry, a retry draft that dropped sections, an intake truncation or skip, a `dir:` file skipped beyond the 50-source cap, a `dir:` with directories below 5 levels, a failed follow-up read, follow-up reads stopped at the 50-source cap, an ignored `body_format=`, a stored text that differs slightly, a scratch directory that could not be removed).

**Body line** (a remote destination: `mcp:`, `api:`, `browser:` or `cli:`): `Body: <body_format>; stored text: complete (<k> of <N>)`, where `<body_format>` is the value the run used (`markdown`, `markdown-escaped` or `html`), `<N>` the number of items created and `<k>` the number whose **Stored text check** (`references/destinations.md`) was `complete`, followed by `, <m> with minor differences` and `, <u> not read back` when those counts are not zero; an item whose check was `incomplete` stopped the run with its `ERROR:` and counts in `<N>` only. On a host with no Python 3, where every check compares the heading titles only, the line reads `Body: <body_format>; stored text: complete, headings only (<k> of <N>)`, `<k>` counting `complete (headings only)`, with the same additions. A stored text that was not read back does not keep the scratch directory; an `incomplete` one is an `ERROR:` and already keeps it. The line follows the `Destination:` line and its `Derived from:` and `Parent:` lines, before `Sources:` and `Partition basis:`; in a failure block, which has no `Destination:` line, it follows the `Created before the failure:` line when at least one item was created. Do not recommend follow-up commands.

**N = 1**:

```
### Final summary

Destination: local:.local/tickets
Scratch: removed
Ticket: .local/tickets/{parent-slug}/005-foo/ticket.md
Category: CodeQuality | Size: M | ACs: 3 | Verdict: PASS
```

**N > 1** (rows in dependency order; `#` is the logical part number):

```
### Final summary

Destination: local:.local/tickets
Scratch: .local/create-ticket-scratch/run.k3Qz9a (kept: keep_scratch=yes)

| # | Ticket | Category | Size | ACs | Verdict |
|---|--------|----------|------|-----|---------|
| 1 | .local/tickets/{parent-slug}/005-foo/ticket.md | CodeQuality | M | 3 | PASS |
| 2 | .local/tickets/{parent-slug}/006-bar/ticket.md | CodeQuality | S | 2 | PASS |

Dependency order: {parent-slug}-part-1 (T-005) → {parent-slug}-part-2 (T-006)
Split plan: .local/tickets/{parent-slug}/split-plan.md
```

For an `mcp:`, `api:`, `browser:` or `cli:` destination the `Ticket` column holds identifiers, the dependency order names them, there is no `Split plan:` line, and the **Body line** follows the `Destination:` line:

```
### Final summary

Destination: api:https://tracker.example.invalid/api/items
Body: html; stored text: complete (2 of 2)
Scratch: removed

| # | Ticket | Category | Size | ACs | Verdict |
|---|--------|----------|------|-----|---------|
| 1 | ITEM-41 https://tracker.example.invalid/items/41 | CodeQuality | M | 3 | PASS |
| 2 | ITEM-42 https://tracker.example.invalid/items/42 | CodeQuality | S | 2 | PASS |

Dependency order: {parent-slug}-part-1 (ITEM-41) → {parent-slug}-part-2 (ITEM-42)
```

When the destination was derived from a platform item URL (SKILL.md Argument Parsing, **Platform item URLs**), the line `Derived from: <item URL without query>` follows the `Destination:` line directly, before the `Parent:`, `Body:`, `Sources:` and `Partition basis:` lines (in the failure block, which has no `Destination:` line, it follows the `Created:` line, before those lines).

**Failure**:

```
### Final summary

Created: none
ERROR: <the ERROR: line>
Scratch: <the {scratch} path> (kept: error)
```

After a remote failure, `Created: none` becomes `Created before the failure: <id>, <id>`, followed by the **Body line** (for example `Body: markdown; stored text: complete (1 of 2)` after a second item whose stored text was incomplete); after a `local:` write failure, or a `local:` refusal of the **Heading check** (`references/destinations.md`), the `ERROR:` line names the quarantine path. The `Scratch:` line appears once in every variant, success and failure: in a success block right before the ticket line or rows (after the `Destination:`, `Derived from:`, `Parent:`, `Body:`, `Sources:` and `Partition basis:` lines when those are present), in the failure block after the `ERROR:` line. It says what became of the scratch directory under the removal rule of SKILL.md `## Delivery` Step DL-5: `Scratch: removed` when it was removed (a clean run without `keep_scratch=yes`), or `Scratch: <{scratch} path> (kept: <reason>)` when it was kept, `<reason>` being the first that applies of `keep_scratch=yes`, `error`, `a ticket was delivered with a FAIL verdict` and `overflow findings` (a failure block reads `(kept: error)` unless `keep_scratch=yes` was passed), so the user can find the drafts, evaluator reports and API responses of that run; after a removal that left the directory in place it reads `Scratch: <{scratch} path> (kept: removal failed)`, next to the repeated `WARNING: could not remove the scratch directory <{scratch}> (<reason>)`; it is omitted when the `ERROR:` was raised before the scratch directory was created (an argument, input-file, preflight or scratch-creation error, unless a derived destination had already created it right after the `Resolved:` and `Derived:` lines, SKILL.md Argument Parsing **Platform item URLs**: then every later error of that run, its `needs a sign-in` and preflight errors included, keeps the line); a `{scratch}` path it names is relative to the working directory, and a `brief=` / `findings=` path in the `ERROR:` line is echoed exactly as the user typed it (with backslashes read as `/`; SKILL.md Host notes, **`~` paths**).
