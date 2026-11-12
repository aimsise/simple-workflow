target: references/write-path-templates.md
heading: ## Step W-10 — Summary printing format
mode: replace
---
## Final summary format (Step DL-5)

End the run with this block as its last output. The `### Final summary` block is printed in the stated format below, with its literal heading and its `Destination:` and `Scratch:` lines (each in the variants that carry it), and is never replaced by a free-form recap. `Destination` is the destination spec with its channel kind (`local:`, `mcp:`, `api:`, `browser:` or `cli:`), an `api:` or `browser:` URL printed without its query string and a `cli:` command template printed in full, in double-quoted token form. `Ticket` is the path of the `ticket.md` for a `local:` destination (relative to the working directory, or under `{dir}` exactly as typed when `{dir}` is absolute or `~`-prefixed, a `~` never expanded), and the identifier the create call returned (plus its URL without the query string, when one was returned) for an `mcp:`, `api:`, `browser:` or `cli:` destination. `Verdict` is `PASS`, `SELF-EVALUATED`, `FAIL (user-accepted)` or `FAIL (unresolved)` (either `FAIL` verdict with the remaining issues on a following line). Add the line `Phase 2 skipped (non-interactive mode)` when that fallback fired, repeat the implied-confirmation line `NOTE: this host has no ask-user tool; running as if confirm=yes was passed (a remote create is not confirmed first, and a ticket still graded FAIL is delivered as FAIL (unresolved)); pass confirm=no to stop instead` when it was printed, and repeat every `WARNING:` line of the run (a decomposer overflow with its `findings=` re-run, a normalized slug, a spawn retry, an intake truncation or skip, a `dir:` file skipped beyond the 50-source cap, a `dir:` with directories below 5 levels, a failed follow-up read, follow-up reads stopped at the 50-source cap, a scratch directory that could not be removed). Do not recommend follow-up commands.

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

For an `mcp:`, `api:`, `browser:` or `cli:` destination the `Ticket` column holds identifiers, the dependency order names them, and there is no `Split plan:` line. When the destination was derived from a platform item URL (SKILL.md Argument Parsing, **Platform item URLs**), the line `Derived from: <item URL without query>` follows the `Destination:` line directly, before the `Parent:`, `Sources:` and `Partition basis:` lines (in the failure block, which has no `Destination:` line, it follows the `Created:` line, before those lines).

**Failure**:

```
### Final summary

Created: none
ERROR: <the ERROR: line>
Scratch: <the {scratch} path> (kept: error)
```

After a remote failure, `Created: none` becomes `Created before the failure: <id>, <id>`; after a `local:` write failure, the `ERROR:` line names the quarantine path. The `Scratch:` line appears once in every variant, success and failure: in a success block right before the ticket line or rows (after the `Destination:`, `Derived from:`, `Parent:`, `Sources:` and `Partition basis:` lines when those are present), in the failure block after the `ERROR:` line. It says what became of the scratch directory under the removal rule of SKILL.md `## Delivery` Step DL-5: `Scratch: removed` when it was removed (a clean run without `keep_scratch=yes`), or `Scratch: <{scratch} path> (kept: <reason>)` when it was kept, `<reason>` being the first that applies of `keep_scratch=yes`, `error`, `a ticket was delivered with a FAIL verdict` and `overflow findings` (a failure block reads `(kept: error)` unless `keep_scratch=yes` was passed), so the user can find the drafts, evaluator reports and API responses of that run; after a failed `rm -r` it reads `Scratch: <{scratch} path> (kept: removal failed)`, next to the repeated `WARNING: could not remove the scratch directory <{scratch}> (<reason>)`; it is omitted when the `ERROR:` was raised before the scratch directory was created (an argument, input-file, preflight or scratch-creation error, unless a derived destination had already created it right after the `Resolved:` and `Derived:` lines, SKILL.md Argument Parsing **Platform item URLs**: then every later error of that run, its `needs a sign-in` and preflight errors included, keeps the line); a `{scratch}` path it names is relative to the working directory, and a `brief=` / `findings=` path in the `ERROR:` line is echoed exactly as the user typed it (with backslashes read as `/`; SKILL.md Host notes, **`~` paths**).
