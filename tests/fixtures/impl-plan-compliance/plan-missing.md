# Plan: fixture-missing

## Summary

A fixture plan where the Affected files table declares 3 files but only 2 of
them appear in the diff. The Plan-Compliance Pre-Check must emit a
`[PLAN-COMPLIANCE-WARN]` line for the unbuilt file.

## Acceptance Criteria

1. AC-1: stub.

## Affected files

| File | Lines | Change |
|---|---|---|
| `src/foo.ts` | +12/-3 | new export |
| `src/bar.ts` | +1/-0 | bugfix |
| `tests/foo.test.ts` | +20/-0 | new test (NOT MODIFIED in fixture diff) |

## Implementation Strategy

Stub.
