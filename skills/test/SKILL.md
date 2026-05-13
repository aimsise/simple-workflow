---
name: test
description: >-
  Creates and runs tests for a specified file or feature by spawning the
  test-writer subagent in a forked context, then returns a structured
  summary with test file paths and pass/fail counts. Use when (1) the
  user runs `/test FILE` directly to add tests for a specific module,
  (2) the user runs `/test FEATURE` to design and execute test cases
  for a feature outside any ticket workflow, or (3) `/catchup` detects
  Rule 4 (source diff exists but no matching test changes) and suggests
  `/test` against the changed files to close coverage. The test-writer
  subagent reads existing tests first and follows project conventions
  (happy path, edge cases, boundary values, error cases), runs the
  configured test command, and returns a structured result under 500
  tokens per the Context Conservation Protocol. Triggers on "/test",
  "write tests", "add tests", "test the feature", "test coverage",
  "missing tests", "test cases", "cover the changes".
context: fork
agent: test-writer
model: sonnet
argument-hint: "<file path or feature name to test>"
allowed-tools:
  - Agent
  - Read
  - Glob
  - Grep
  - "Bash(git:*)"
  - "Bash(ls:*)"
---

Create and run tests for: $ARGUMENTS

Current changes:
!`git diff --stat`

Existing test directories:
!`ls -d tests/ test/ __tests__/ spec/ 2>/dev/null || echo "(no top-level test directory found)"`

## Instructions

1. Parse `$ARGUMENTS` to identify the file path(s) or feature name to be tested. The spawned test-writer subagent owns the fork — the orchestrator does NOT run direct Read/Grep/Edit loops at this level; delegation happens via `context: fork` + `agent: test-writer` declared in the frontmatter.
2. The test-writer subagent examines existing tests to understand patterns and conventions (test runner, helper imports, fixture style, naming).
3. The test-writer subagent designs test cases covering: happy path, edge cases, boundary values, error cases.
4. The test-writer subagent writes tests following the existing patterns and project conventions (test framework, file naming, directory layout — as defined in CLAUDE.md or project conventions).
5. The test-writer subagent runs the project's test command (as defined in CLAUDE.md or project conventions) to verify.
6. The test-writer subagent fixes any failing tests it introduced before returning. If the iteration limit (`maxTurns: 25` in `agents/test-writer.md`) is hit with tests still failing, the agent returns a `partial` or `failed` status.
7. **Return contract**: the test-writer agent returns the structured envelope declared in `agents/test-writer.md` Context Conservation Protocol — under 500 tokens, with the four fields **Status**: `success | partial | failed`, **Output**: `[test file path(s) created/modified]`, **Summary**: `[test count, pass/fail results]`, **Next Steps**: `[recommended actions]`. The orchestrator surfaces these fields to the user verbatim.

## Error Handling

- **Empty arguments**: If `$ARGUMENTS` is empty, print `Usage: /test <file path or feature name to test>` and stop without spawning the subagent.
- **test-writer agent failure** (no return value, or `**Status**: failed`): Report the failure reason and any files modified up to the failure point. Do not silently swallow the error.
- **Persistent test failures after fix loop**: When the test-writer returns `**Status**: partial` with remaining failures, surface the test command output and the list of still-failing tests to the user. Do not mark the task as success.
