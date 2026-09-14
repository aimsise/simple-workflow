# Test Strategy

## Hook Tests (Automated)

All hooks in `hooks/` have corresponding test files in `tests/`:

| Hook | Test File | Coverage |
|------|-----------|----------|
| pre-bash-safety.sh | test-pre-bash-safety.sh | Destructive commands, pipes, chains, prefixes, subshells, sensitive files, bulk staging, edge cases |
| pre-write-safety.sh | test-pre-write-safety.sh | Sensitive file blocking, allowed files, hook-owned state fields |
| pre-edit-safety.sh | test-pre-edit-safety.sh | Sensitive file blocking, allowed files, hook-owned state fields |
| pre-bash-contract-guard.sh | test-pre-bash-contract-guard.sh | Forbidden fallback rationales, inline `git commit` nonce gate, review-agent firewall, Bash state mutation |
| pre-skill-contract-guard.sh | test-pre-skill-contract-guard.sh | Review-agent pipeline-skill deny |
| pre-askuserquestion-guard.sh | test-ask-guard.sh | 3-tier `risk_tolerance` header matrix |
| pre-state-transition.sh | test-state-transition-guard.sh | Skip / advancement transition authority |
| pre-next-scout-auto-compact.sh | test-pre-next-scout-auto-compact.sh | Ticket-boundary `/compact` injection, loop guard, sentinels |
| post-ship-state-auto-compact.sh | test-post-ship-state-auto-compact.sh | State-write safety-net `/compact` injection, integrity self-heal |
| post-phase-checkpoint.sh | test-per-phase-metrics.sh | Per-phase `runtime_metrics` emission |
| post-skill-cleanup.sh | test-post-skill-cleanup.sh | Stale `auto-kick.yaml` removal |
| accept-set-verify.sh | test-accept-set-verify.sh | Accept-set sweep conformance predicates |
| autopilot-continue.sh | test-autopilot-continue.sh, test-autopilot-runtime-metrics.sh | Stop-hook continuation, loop guards, policy-gate-stop honour, wave-aware continuation, `runtime_metrics` writes |
| impl-checkpoint-guard.sh | test-impl-checkpoint-guard.sh | Post-`/audit` handoff guard (Stop + SubagentStop) |
| scout-checkpoint-guard.sh | test-scout-checkpoint-guard.sh | Post-`/plan2doc` handoff guard (Stop + SubagentStop) |
| session-start.sh | test-session-start.sh, test-session-start-hook.sh, test-session-start-next-compact.sh | JSON output, context injection, branch detection, log cleanup, post-compact resume kick, `.next-compact-pending` replay |
| session-stop-log.sh | test-session-stop-log.sh | Log creation and content |
| pre-level1-guard.sh | (none) | Dev-repository-only guard registered in the tracked `.claude/settings.json` (not in `hooks/hooks.json`); exercised manually |
| pre-compact-save.sh | test-pre-compact-save.sh, test-precompact-end-to-end.sh | State file creation, content verification, end-to-end compact round-trip |
| hooks/lib/*.sh | test-hooks-lib.sh, test-state-parsers.sh, test-detect-policy-gate-stop.sh, test-inject-keys.sh | Shared helpers: state parsers, policy-gate-stop detector, keystroke injection |

The committed Workflow script (`skills/impl/workflows/eval-panel.mjs`) is covered by `node tests/test-eval-panel-merge.mjs` (the merge pure-function plus the product-script contract: top-level `return`, parses as a Workflow body).

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

### Running Tests

```bash
# Level 0 only (equivalent to CI)
bash tests/run-all.sh

# Spike verification (sanity check for the claude -p subprocess)
bash tests/spike-claude-p.sh
```

### 13 Skill x Verification Category Matrix

| Skill | A: dmi | B: AskUQ | C: Skill delegation | D: Agent delegation | E: args | F: fork | G: Status | H: hook | I: KB | J: Policy | K: kb-suggested | L: v2.2.0 | M: WF separation | N: safety |
|-------|--------|----------|-------------|-------------|---------|---------|-----------|---------|-------|-----------|-----------------|-----------|-----------|-----------|
| investigate | x | | | x | x | x | | | | | | | | |
| test | x | | | x | x | x | | | | | | | | |
| scout | x | | x | | x | | | | | | | | | |
| plan2doc | x | | | x | x | | | | | | | | | |
| audit | x | | | x | x | | x | | | | | | | |
| catchup | x | | | x | x | | | x | | | | | | |
| create-ticket | x | x | | x | x | | | | | x | | x | x | |
| refactor | x | x | | x | x | | | | | | | | | |
| impl | x | x | x | x | x | | x | | | x | | | x | x |
| ship | x | x | x | | x | | | | | x | | | | x |
| tune | x | | | x | x | | | | x | | | | | |
| brief | x | x | x | x | x | | | | | x | x | | | |
| autopilot | x | | x | | x | | | | | x | x | x | x | |

Legend: `x` = skill is tested in that category

### Categories

- **A**: `disable-model-invocation` contract (dmi=true implies Agent/Skill delegation; dmi=false or unset skills validated for correct delegation tools)
- **B**: `AskUserQuestion` non-interactive fallback (Non-interactive documentation)
- **C**: Skill delegation graph integrity (`/skill-name` references resolve to existing SKILL.md)
- **D**: Agent delegation integrity (agent field and body references resolve to existing agents)
- **E**: `argument-hint` and `$ARGUMENTS` consistency
- **F**: `context:fork` and `agent:` co-occurrence contract
- **G**: `/audit` -> `/impl` Status contract type alignment (PASS/PASS_WITH_CONCERNS/FAIL)
- **H**: hook -> skill data flow integrity (pre-compact-save fields consumed by catchup)
- **I**: `/tune` knowledge base contract (KB directory structure, pattern file format, impl injection, decision pattern extraction I-16 through I-20)
- **J**: Autopilot-policy structural integrity (policy YAML schema, gate resolution, decision logging, human override tracking — J-1 through J-19)
- **K**: kb-suggested / kb_override contract — verifies KB-driven policy comments and override type distinction (K-1 through K-7)
- **L**: autopilot/brief/create-ticket v2.2.0 contract — ticket_mapping, ticket_dir, brief_slug metadata, split criteria, ticket-counter, and stale ticket-slug absence (L-1 through L-5, L-7 through L-9)
- **M**: Workflow isolation contract — bidirectional isolation between manual `/impl` and `/autopilot` workflows: autopilot-policy.yaml exclusion, FIFO ordering, Policy guard, explicit plan path, shared `.ticket-counter` mechanism (M-1 through M-9)
- **N**: impl safety contracts — `/impl` stash exclusion pathspecs for plugin artifact directories, `/ship` ticket completion ordering (done before Phase 2) (N-1 through N-2)

## Skill/Agent Integration Testing (Level 1)

Level 1 tests use `claude -p` to invoke skills in headless mode within temporary git repositories.

### Future Improvements

- **Pressure test scenarios** per skill (following obra/superpowers RED/GREEN/REFACTOR methodology for documentation)
- **Headless integration tests** using `claude -p` to verify skill invocation, subagent dispatch, and file creation
- **A/B comparison testing** for skill prompt revisions using comparator agents
- **Regression detection** to identify when model improvements make a skill redundant
