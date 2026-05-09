# tests/fixtures/impl-checkpoint-guard/

Fixture-construction notes for `tests/test-impl-checkpoint-guard.sh`.

The test suite builds each fixture inline in a fresh `mktemp -d` directory
rather than committing per-case files here, so this directory is normally
empty. The README documents the canonical shapes so future readers can
audit the per-case state files in the test script against a single
specification.

## Per-fixture inputs

Each case constructs three independent inputs:

| Input                       | Location in tmpdir                                            |
| --------------------------- | ------------------------------------------------------------- |
| `phase-state.yaml`          | `<tmp>/.simple-workflow/backlog/active/<ticket-dir>/phase-state.yaml` |
| Transcript JSONL            | `<tmp>/transcript.jsonl`                                      |
| `autopilot-state.yaml` (viii only) | `<tmp>/.simple-workflow/backlog/briefs/active/<parent-slug>/autopilot-state.yaml` |
| Loop counter (v / viii)     | `/tmp/.impl-checkpoint-${SESSION_ID}` (preset to `3`)         |

The hook is invoked with `cwd=<tmp>` and stdin
`{"transcript_path": "<tmp>/transcript.jsonl", "session_id": "<sid>"}`.
`SESSION_ID` is unique per case (`impl-cp-<case>-$$`) so concurrent runs
do not collide on the counter file under `/tmp`.

## Canonical phase-state.yaml shapes

Three reusable shapes drive all eight cases:

- **`PHASE_STATE_NEEDS_AUDIT`** — `phases.impl.status: in-progress`,
  `phases.impl.next_action: start-audit`,
  `phases.scout.artifacts.plan: .simple-workflow/backlog/active/001-test/plan.md`.
  This is the failing state the hook is designed to catch; (i), (iv),
  (v), (vii), and (viii) reuse it.
- **`PHASE_STATE_NULL_NEXT_ACTION`** — `phases.impl.next_action: null`.
  Triggers the denylist short-circuit. Used by (ii).
- **`PHASE_STATE_COMPLETED`** — `phases.impl.status: completed`.
  Triggers the cheap status short-circuit before transcript scanning.
  Used by (iii).

## Canonical transcript shapes

Three reusable transcripts:

- **`TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT`** — `Skill(simple-workflow:impl)`
  invocation, then `Skill(simple-workflow:audit)` invocation, then a final
  assistant `text` block containing the literal `**Status**:` and
  `**Reports**:` lines (the audit structured block). NO `## [SW-CHECKPOINT]`.
  This is the failing transcript the hook must block.
- **`TRANSCRIPT_AUDIT_EMIT_WITH_CHECKPOINT`** — same as above, plus a
  trailing assistant `text` block emitting `## [SW-CHECKPOINT]`. The hook
  must exit 0 (state-update lag tolerance) and record `audit_handoff_via_prompt`.
- **`TRANSCRIPT_NO_IMPL`** — only `Skill(simple-workflow:audit)`, no /impl
  invocation. Exercises the cross-session staleness guard (5-AND condition
  (e)) — the hook must exit 0 even when (a) (b) (c) (d) all match.

## Counter-mtime invariant

For cases (v) and (viii) the counter file is preset to `3` and its mtime
is bumped *after* the state file's mtime so the hook's
`if [ "$STATE_FILE" -nt "$COUNTER_FILE" ]` reset branch does NOT fire.
This guarantees the release path is exercised deterministically.

## Replay corpus

`tests/replay/audit-emit-only.jsonl` is a longer, narratively-shaped
companion to `TRANSCRIPT_AUDIT_EMIT_NO_CHECKPOINT` for ad-hoc manual
replay against the hook (e.g. piping into `bash hooks/impl-checkpoint-guard.sh`
with a controlled cwd). Tests do not currently consume it — they use
inline transcripts above for hermeticity — but it serves as a
human-readable example of the failure-mode session shape.

## Boundary orthogonality (addendum §13.C-2)

The hook writes `boundary: session_end` entries to `runtime_metrics:` in
the same `phase-state.yaml` file used by `post-phase-checkpoint.sh`
(which writes `boundary: phase_complete | phase_failed | phase_skipped`).
Aggregations downstream MUST partition on `boundary` before computing
SLO ratios — see `hooks/lib/runtime-metrics.sh` header for the full
boundary × stop_reason taxonomy.
