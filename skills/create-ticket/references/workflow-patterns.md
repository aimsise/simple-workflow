# Claude Code Workflow Patterns

> Reference for selecting the appropriate workflow by category x size when creating tickets.
> See `.claude/skills/` and `.claude/agents/` for available skills and agents.

---

## Available Tools

| Tool | Type | Purpose |
|------|------|---------|
| `/investigate` | skill | Codebase research and structured report generation. Outputs to `.backlog/active/{ticket-dir}/investigation.md` for ticket work, or `.docs/research/` otherwise |
| `/plan2doc` | skill | Create implementation plans. Auto-selects model by ticket size (sonnet for S, opus for M/L/XL). Outputs to `.backlog/active/{ticket-dir}/plan.md` for ticket work, or `.docs/plans/` otherwise |
| `/scout` | skill | Chain codebase research + plan creation. Delegates to `/plan2doc` which handles model selection |
| `/impl` | skill | Implement latest plan with Generator-Evaluator loop (S→sonnet, M+→opus). Internally calls `/audit` for quality + security review |
| `/ship` | skill | Commit + create PR + optional squash-merge |
| `/refactor` | skill | Refactoring with safety checks |
| `/test` | skill | Create and run tests |
| `/audit` | skill | Multi-agent code quality + security audit. Always runs security-scanner; use `only_security_scan=true` for security-only mode |
| `/commit` | skill | Create conventional commit |
| `/catchup` | skill | Context recovery, phase detection, and next action guidance |
| `/ticket-move` | skill | Move tickets to a target backlog state (active/blocked/done) |
| planner | agent | Implementation plan design (opus for M/L/XL, sonnet for S) |
| researcher | agent | Code research and analysis |
| ticket-evaluator | agent | Ticket quality evaluation with 5 quality gates (sonnet) |
| implementer | agent | Code implementation (opus for M/L/XL, sonnet for S) |
| ac-evaluator | agent | AC compliance verification (sonnet) |

---

## Category Patterns

### Security

Security-critical changes. Wrap with security-only audits before and after.

| Size | Workflow |
|------|----------|
| **S** | `/investigate` -> `/audit only_security_scan=true` -> `/impl` -> `/test` -> `/audit` -> `/ship` |
| **M** | `/scout` -> `/audit only_security_scan=true` -> spec-first docs update -> `/impl` -> `/test` -> `/audit only_security_scan=true` -> `/audit` -> `/ship` |
| **L** | `/scout` -> `/audit only_security_scan=true` -> spec-first docs update -> incremental `/impl` -> `/test` -> `/audit only_security_scan=true` -> `/audit` -> `/ship` |
| **XL** | `/scout` -> `/audit only_security_scan=true` -> spec-first docs update -> multi-phase `/impl`(`/test` after each phase) -> `/audit only_security_scan=true` -> `/audit` -> `/ship` |

**Requirements**:
- Update relevant documentation first (spec-first)
- Run `/audit only_security_scan=true` before and after implementation
- Verify backward compatibility

### CodeQuality

Code quality improvements and refactoring.

| Size | Workflow |
|------|----------|
| **S** | `/scout` or `/investigate` -> `/impl` or `/refactor` -> `/audit` -> `/ship` |
| **M** | `/scout` -> `/impl` or `/refactor` -> `/test` -> `/audit` -> `/ship` |
| **L** | `/scout` -> incremental `/impl`(`/refactor` per function) -> `/test` -> `/audit` -> `/ship` |
| **XL** | `/scout` -> multi-phase `/impl` -> `/test` -> `/audit` -> `/ship` |

**Requirements**:
- No behavior changes (all tests must pass)
- L+ should split implementation by function or module

### Doc

Documentation creation and updates.

| Size | Workflow |
|------|----------|
| **S** | `/impl` with doc-focused plan -> `/audit` -> `/ship` |
| **M** | `/scout` -> `/impl` with doc-focused plan -> `/audit` -> `/ship` |
| **L** | `/scout` -> incremental `/impl` with doc-focused plan -> `/audit` -> `/ship` |

**Requirements**:
- Maintain consistency with existing documentation

### DevOps

CI/CD and infrastructure configuration.

| Size | Workflow |
|------|----------|
| **S** | `/investigate` -> `/impl` -> `/audit` -> `/ship` |
| **M** | `/scout` -> `/impl` -> `/audit` -> `/ship` |
| **L** | `/scout` -> incremental `/impl` -> `/audit` -> `/ship` |

**Special case**: Repository settings changes (Branch Protection, etc.) do not require file commits. Use `gh api` directly.

### Community

Community standards and templates.

| Size | Workflow |
|------|----------|
| **S** | `/impl` -> `/audit`(optional) -> `/ship` |
| **M** | `/impl` with doc-focused plan -> `/audit` -> `/ship` |

**Requirements**:
- Follow industry standards (Contributor Covenant, Keep a Changelog, etc.)

---

## Common Rules by Size

| Size | `/scout` | `/plan` | `/investigate` | `/impl` | `/test` | `/audit` |
|------|----------|---------|----------------|---------|---------|----------|
| **S** | Recommended (optional) | Optional | As needed | Recommended | Recommended | Recommended |
| **M** | Recommended | Recommended (included in /scout) | Required (included in /scout) | Required | Required | Required |
| **L** | Required | Required (included in /scout) | Required (included in /scout) | Required | Required | Required |
| **XL** | Required | Required (included in /scout) | Required (included in /scout) | Required | Required (each phase) | Required |

Note: `/impl` already invokes `/audit` internally as part of its Generator-Evaluator loop, so a separate `/audit` step before `/ship` is mainly for the final review gate.

---

## Workflow Selection Flowchart

```
1. Identify category -> Security / CodeQuality / Doc / DevOps / Community
2. Identify size -> S / M / L / XL
3. Select base pattern from the matrix above
4. Check special conditions:
   - Format changes -> spec-first (update docs first)
   - Security impact -> add `/audit only_security_scan=true` before and after
   - Performance impact -> add benchmarks
   - No file changes -> no commit needed, use gh api etc.
5. Research + planning phase: use /scout for M+ (auto-chains /investigate + /plan2doc)
6. Implementation phase: use /impl (automated lint/test loop, includes /audit)
7. Finalization phase: use /ship (commit + PR in one step)
8. Write final workflow to `### Claude Code Workflow` section in the ticket
```
