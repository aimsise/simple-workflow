# Test Strategy

## Hook Tests (Automated)

All hooks in `hooks/` have corresponding test files in `tests/`:

| Hook | Test File | Coverage |
|------|-----------|----------|
| pre-bash-safety.sh | test-pre-bash-safety.sh | Destructive commands, pipes, chains, prefixes, subshells, sensitive files, bulk staging, edge cases |
| pre-write-safety.sh | test-pre-write-safety.sh | Sensitive file blocking, allowed files |
| pre-edit-safety.sh | test-pre-edit-safety.sh | Sensitive file blocking, allowed files |
| session-start.sh | test-session-start.sh | JSON output, context injection, branch detection, log cleanup |
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

## Skill Tests

Skill contract and structural integrity tests verify cross-skill/agent/hook consistency without requiring `claude` CLI.

### Test Levels

- **Level 0** (static analysis): `test-skill-contracts.sh` -- no external dependencies, runs in CI
- **Level 1** (integration): `test-skill-commit-l1.sh` -- requires `claude` CLI + `RUN_LEVEL1_TESTS=true`

### Running Tests

```bash
# Level 0 のみ（CI と同等）
bash tests/run-all.sh

# Level 1 を含める（claude CLI 必須）
RUN_LEVEL1_TESTS=true bash tests/run-all.sh

# スパイク検証（claude -p の動作確認）
bash tests/spike-claude-p.sh
```

### 13 Skill x Verification Category Matrix

| Skill | A: dmi | B: AskUQ | C: Skill委譲 | D: Agent委譲 | E: args | F: fork | G: Status | H: hook | I: KB |
|-------|--------|----------|-------------|-------------|---------|---------|-----------|---------|-------|
| commit | x | | | | x | | | | |
| ticket-move | x | | | | x | | | | |
| investigate | x | | | x | x | x | | | |
| test | x | | | x | x | x | | | |
| scout | x | | x | | x | | | | |
| plan2doc | x | | | x | x | | | | |
| audit | x | | | x | x | | x | | |
| catchup | x | | | x | x | | | x | |
| create-ticket | x | x | | x | x | | | | |
| refactor | x | x | | x | x | | | | |
| impl | x | x | x | x | x | | x | | |
| ship | x | | x | | x | | | | |
| tune | x | | | x | x | | | | x |

Legend: `x` = skill is tested in that category

### Categories

- **A**: `disable-model-invocation` contract (dmi=true implies Agent/Skill delegation or exception)
- **B**: `AskUserQuestion` non-interactive fallback (Non-interactive documentation)
- **C**: Skill delegation graph integrity (`/skill-name` references resolve to existing SKILL.md)
- **D**: Agent delegation integrity (agent field and body references resolve to existing agents)
- **E**: `argument-hint` and `$ARGUMENTS` consistency
- **F**: `context:fork` and `agent:` co-occurrence contract
- **G**: `/audit` -> `/impl` Status contract type alignment (PASS/PASS_WITH_CONCERNS/FAIL)
- **H**: hook -> skill data flow integrity (pre-compact-save fields consumed by catchup)
- **I**: `/tune` knowledge base contract (KB directory structure, pattern file format, impl injection)

## Skill/Agent Integration Testing (Level 1)

Level 1 tests use `claude -p` to invoke skills in headless mode within temporary git repositories.

### Future Improvements

- **Pressure test scenarios** per skill (following obra/superpowers RED/GREEN/REFACTOR methodology for documentation)
- **Headless integration tests** using `claude -p` to verify skill invocation, subagent dispatch, and file creation
- **A/B comparison testing** for skill prompt revisions using comparator agents
- **Regression detection** to identify when model improvements make a skill redundant
