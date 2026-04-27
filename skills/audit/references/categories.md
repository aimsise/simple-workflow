# Audit category checklists

This file is the canonical source for the per-Category checklist body that
`/audit` propagates to the `code-reviewer` and `security-scanner` agents.

`/audit` reads the ticket's `| Category |` row and selects the matching
`## Category: <name>` section verbatim. The whole body of the matching
section (between the matching header and the next `## Category:` header,
or end-of-file) is passed through to each spawned agent as the checklist
the agent MUST evaluate against. Each agent's report is required to cite
the items it evaluated using the format
`- [ ] <item> (Category: <CategoryName>)` (or `- [x]` once the item is
addressed).

When the ticket's Category does not match any header below (e.g. lowercase
`accessibility`, or any value outside the canonical six), the value is
still passed through verbatim to the dispatch log but no checklist body
is selected; the agents fall back to their default review heuristics and
no `(Category: ...)` lines are required in the report.

Adding a seventh `## Category: <name>` section here is allowed and does
NOT break the contract — extra categories are not flagged as drift by
`tests/test-skill-contracts.sh`. The six required headers below MUST be
present and each MUST have at least three checklist items in
`- [ ] <Capitalized item>` form.

## Category: CodeQuality

- [ ] Naming is consistent with surrounding code and project conventions
- [ ] Functions stay focused; long functions are split or justified
- [ ] Duplicate logic is extracted or de-duplicated
- [ ] Dead code, unreachable branches, and unused symbols are removed
- [ ] Comments explain intent, not the obvious mechanics

## Category: Security

- [ ] No hardcoded secrets, tokens, API keys, or credentials are introduced
- [ ] User input is validated and properly escaped before use in queries / shell / HTML
- [ ] Authentication and authorization checks gate every privileged operation
- [ ] Logged data does not leak PII, secrets, or session tokens
- [ ] Cryptographic primitives use vetted libraries, not hand-rolled implementations

## Category: Performance

- [ ] Hot paths avoid quadratic or worse complexity unless justified
- [ ] Database / network calls are batched or cached where the access pattern allows
- [ ] Allocations inside loops are minimized
- [ ] Pagination, streaming, or backpressure is applied to large data sets
- [ ] Resource handles (files, sockets, locks) are released on every exit path

## Category: Reliability

- [ ] Error paths return actionable diagnostics, not silent failures
- [ ] Retries use bounded backoff and surface terminal failures
- [ ] Timeouts and cancellation propagate through the call chain
- [ ] State mutations are atomic or idempotent
- [ ] External-service contracts are validated at the boundary

## Category: Documentation

- [ ] Public APIs document inputs, outputs, and error conditions
- [ ] CHANGELOG entries describe user-visible behavior, not internal refactors
- [ ] README / quickstart instructions stay runnable on a fresh checkout
- [ ] Inline comments are kept in sync with code changes
- [ ] Migration notes are written for breaking behavior shifts

## Category: Testing

- [ ] New behavior is covered by at least one automated test
- [ ] Bug fixes include a regression test that fails without the fix
- [ ] Tests assert on observable behavior, not on implementation details
- [ ] Flaky or skipped tests are tracked and time-bounded
- [ ] Test fixtures are minimal and explain the scenario they encode
