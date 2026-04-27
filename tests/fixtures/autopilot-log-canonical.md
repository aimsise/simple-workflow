---
parent_slug: example-brief
started: 2026-04-27T00:00:00Z
completed: 2026-04-27T00:42:00Z
final_status: completed
ticket_count: 1
tickets_completed: 1
tickets_failed: 0
tickets_skipped: 0
---

# Autopilot Log: example-brief

## Pipeline Execution

### Ticket: example-brief-part-1 → 001-example (completed)
- scout: completed
- impl: completed (1 round)
- ship: completed → PR: https://example.invalid/pr/1

## Human Overrides

No human overrides detected.

## KB Overrides

No KB overrides detected.

## Decisions Made

| gate | action | reason | notes |
|------|--------|--------|-------|
| scout | allow | evaluated | autopilot-policy.yaml present |
| plan | allow | evaluated | scout completed, plan.md produced |
| build | deny | evaluated | ac_eval_fail action=stop |
| verify | skip | dependency_skipped | upstream build emitted action=deny |
| retro | skip | condition_unmet | retro requires build action=allow |
| ship_ci_pending | skip | not_reached | run terminated before ship_ci_pending was considered |

<!-- Documentation example: an illustrative snippet such as reason=foo here is NOT a contract event. -->

The following fenced block is illustrative only and reason values inside fences are NOT validated:

```text
| example | skip | reason=foo | illustration only |
[AUTOPILOT-POLICY] gate=demo action=skip reason=foo
```
