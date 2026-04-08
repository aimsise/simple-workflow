# Test Strategy

## Hook Tests (Automated)

All hooks in `hooks/` have corresponding test files in `tests/`:

| Hook | Test File | Coverage |
|------|-----------|----------|
| pre-bash-safety.sh | test-pre-bash-safety.sh | Destructive commands, pipes, chains, prefixes, subshells, sensitive files, bulk staging, edge cases |
| pre-write-safety.sh | test-pre-write-safety.sh | Sensitive file blocking, allowed files |
| pre-edit-safety.sh | test-pre-edit-safety.sh | Sensitive file blocking, allowed files |
| session-start.sh | test-session-start.sh | JSON output, context injection, branch detection, plan detection, log cleanup |
| session-stop-log.sh | test-session-stop-log.sh | Log creation and content |
| pre-compact-save.sh | test-pre-compact-save.sh | State file creation, content verification |

### Running Tests

```bash
# Run all tests
bash tests/run-all.sh

# Run a single test file
bash tests/test-pre-bash-safety.sh
```

### CI

Tests run automatically on push and PR via `.github/workflows/ci.yml` (ShellCheck + test suite).

## Skill/Agent Testing (Manual, Future Automation)

Skills and agents are currently tested through manual invocation in real development scenarios.

### Future Improvements

- **Pressure test scenarios** per skill (following obra/superpowers RED/GREEN/REFACTOR methodology for documentation)
- **Headless integration tests** using `claude -p` to verify skill invocation, subagent dispatch, and file creation
- **A/B comparison testing** for skill prompt revisions using comparator agents
- **Regression detection** to identify when model improvements make a skill redundant
