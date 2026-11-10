target: references/write-path-templates.md
heading: ## Step W-10 — Summary printing format
mode: replace
---
## Final summary format (Step DL-5)

End the run with this block as its last output. `Destination` is the destination spec, with an `api:` URL printed without its query string. `Ticket` is the path of the `ticket.md` relative to the working directory for a `local:` destination, and the identifier the create call returned (plus its URL without the query string, when one was returned) for an `mcp:` or `api:` destination. `Verdict` is `PASS`, `SELF-EVALUATED` or `FAIL (user-accepted)` (with the remaining issues on a following line). Add the line `Phase 2 skipped (non-interactive mode)` when that fallback fired, and repeat every `WARNING:` line of the run. Do not recommend follow-up commands.

**N = 1**:

```
### Final summary

Destination: local:.docs/tickets
Scratch: .create-ticket-scratch/run.k3Qz9a
Ticket: .docs/tickets/{parent-slug}/005-foo/ticket.md
Category: CodeQuality | Size: M | ACs: 3 | Verdict: PASS
```

**N > 1** (rows in dependency order; `#` is the logical part number):

```
### Final summary

Destination: local:.docs/tickets
Scratch: .create-ticket-scratch/run.k3Qz9a

| # | Ticket | Category | Size | ACs | Verdict |
|---|--------|----------|------|-----|---------|
| 1 | .docs/tickets/{parent-slug}/005-foo/ticket.md | CodeQuality | M | 3 | PASS |
| 2 | .docs/tickets/{parent-slug}/006-bar/ticket.md | CodeQuality | S | 2 | PASS |

Dependency order: {parent-slug}-part-1 (T-005) → {parent-slug}-part-2 (T-006)
Split plan: .docs/tickets/{parent-slug}/split-plan.md
```

For an `mcp:` or `api:` destination the `Ticket` column holds identifiers, the dependency order names them, and there is no `Split plan:` line.

**Failure**:

```
### Final summary

Created: none
ERROR: <the ERROR: line>
Scratch: <the {scratch} path>
```

After a remote failure, `Created: none` becomes `Created before the failure: <id>, <id>`; after a `local:` write failure, the `ERROR:` line names the quarantine path. The `Scratch:` line appears once in every variant, success and failure: in a success block right before the ticket line or rows (after the `Destination:`, `Parent:`, `Sources:` and `Partition basis:` lines when those are present), in the failure block after the `ERROR:` line, so the user can find the drafts, evaluator reports and API responses of that run; it is omitted when the `ERROR:` was raised before the scratch directory was created (an argument, input-file, preflight or scratch-creation error); its `{scratch}` path is relative to the working directory, and a `brief=` / `findings=` path in the `ERROR:` line is echoed exactly as the user typed it (SKILL.md Host notes).
