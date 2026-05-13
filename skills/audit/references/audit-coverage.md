# audit-coverage block (Step 4b reference)

This file is the canonical user-facing description of the audit-coverage
block emitted by `audit_coverage_emit` in Step 4b of `skills/audit/SKILL.md`.
The block is the content-identity hand-off from `/audit` to `/ship` so
the review gate can verify that the bytes reviewed by `code-reviewer` and
`security-scanner` are the same bytes about to be committed and pushed.

The authoritative implementation lives in `hooks/lib/audit-coverage.sh`;
this reference summarises the schema, the kill switch, and the fail-open
behaviour for human readers of the audit skill.

## What `audit_coverage_emit` writes

`audit_coverage_emit` appends an HTML-comment-fenced YAML v1 block to the
`quality-round-{n}.md` artifact. The block records three identity fields:

- the **base commit SHA** of `HEAD` at audit emit time;
- the **working-state tree SHA** of the working tree at audit emit time;
- the **per-file blob SHAs** of every file in the audit's change set,
  together with their relative path and a `M | A | R | D` status marker
  (or the sentinel `__deleted__` for deletions).

A minimal block looks like:

```
<!-- audit-coverage v1
---
base: <40-char SHA of HEAD at emit time>
tree: <40-char SHA of the working-state tree at emit time>
mode: pre-commit | post-commit
files:
  - path: <relative path>
    blob: <40-char blob SHA or __deleted__>
    status: M | A | R | D
---
-->
```

The two `---` lines are YAML document separators that bracket the mapping,
so `yq -p yaml` can parse the block directly after `awk '/^<!-- audit-coverage v1/,/^-->$/'` extracts it.

## How `/ship` Step 9 consumes the block

`/ship` Phase 2 Step 9 sources the same helper and calls
`audit_coverage_check <quality_round_path>`. The helper prints one of
three verdicts and uses the exit code to drive the gate:

- `OK <N>` (exit 0) — every commit-side change matches the audit's
  coverage; the review gate passes and `/ship` continues.
- `STALE: <reason>` (exit 1) — at least one blob mismatch or an
  uncovered commit-side file; the gate fails and `/ship` blocks.
- `LEGACY` (exit 2) — the block is absent, or the kill switch is engaged;
  `/ship` falls back to the legacy mtime heuristic.

## Kill switch and fail-open behaviour

Setting `SW_AUDIT_COVERAGE=off` in the environment makes
`audit_coverage_emit` a no-op (it writes nothing and returns 0). On the
consumer side, `audit_coverage_check` returns `LEGACY` (exit 2) in the
same configuration, so `/ship` Step 9 falls back to the legacy mtime
heuristic. Use the kill switch only as an emergency escape hatch when the
content-identity gate is producing false positives; the default path is
the strict check.

If `audit_coverage_emit` returns non-zero for any other reason (a hard
git failure during blob enumeration, for example), `/audit` Step 4b
logs `warn: audit-coverage emit skipped (exit=<code>); /ship review-gate will fall back to legacy mtime heuristic` to stderr and continues. The
gate then degrades gracefully to the legacy heuristic rather than
blocking the audit run.

The block format and schema version (`v1`) are documented verbatim in the
header comments of `hooks/lib/audit-coverage.sh`; this file is the
human-readable companion.
