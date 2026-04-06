# Claude Code Workflow Patterns

> Reference for selecting the appropriate workflow by category x size when creating tickets.
> See `.claude/skills/` and `.claude/agents/` for available skills and agents.

---

## Available Tools

| Tool | Type | Purpose |
|------|------|---------|
| `/investigate` | skill | Codebase research and structured report generation. Outputs to `.backlog/active/{slug}/investigation.md` for ticket work, or `.docs/research/` otherwise |
| `/plan2doc` | skill | Create implementation plans. Outputs to `.backlog/active/{slug}/plan.md` for ticket work, or `.docs/plans/` otherwise |
| `/plan2doc-light` | skill | Lightweight plan creation for S-size tickets (sonnet planner) |
| `/scout` | skill | Chain codebase research + plan creation. Auto-routes S->plan2doc-light, M+->plan2doc |
| `/impl` | skill | Implement latest plan with automated lint/test loop |
| `/ship` | skill | Commit + create PR + optional squash-merge |
| `/refactor` | skill | Refactoring with safety checks |
| `/test` | skill | Create and run tests |
| `/review-diff` | skill | Multi-agent change review |
| `/commit` | skill | Create conventional commit |
| `/security-scan` | skill | Security audit |
| `/catchup` | skill | Branch state analysis and context recovery |
| `/phase-clear` | skill | Work phase switching and context preservation |
| `/ticket-done` | skill | Move completed tickets to .backlog/done/ |
| `/ticket-blocked` | skill | Move blocked tickets to .backlog/blocked/ |
| `/ticket-active` | skill | Resume tickets by moving to .backlog/active/ |
| doc-writer | agent | Documentation generation |
| planner | agent | Implementation plan design (opus) |
| planner-light | agent | Lightweight planner for S-size tickets (sonnet) |
| researcher | agent | Code research and analysis |

---

## Category Patterns

### Security

Security-critical changes. Wrap with security scans before and after.

| Size | Workflow |
|------|----------|
| **S** | `/investigate` -> `/security-scan` -> `/impl` -> `/test` -> `/review-diff` -> `/ship` |
| **M** | `/scout` -> `/security-scan` -> spec-first docs update -> `/impl` -> `/test` -> `/security-scan` -> `/review-diff` -> `/ship` |
| **L** | `/scout` -> `/security-scan` -> spec-first docs update -> incremental `/impl` -> `/test` -> `/security-scan` -> `/review-diff` -> `/ship` |
| **XL** | `/scout` -> `/security-scan` -> spec-first docs update -> multi-phase `/impl`(`/test` after each phase) -> `/security-scan` -> `/review-diff` -> `/ship` |

**Requirements**:
- Update relevant documentation first (spec-first)
- Run `/security-scan` before and after implementation
- Verify backward compatibility

### CodeQuality

Code quality improvements and refactoring.

| Size | Workflow |
|------|----------|
| **S** | `/scout` or `/investigate` -> `/impl` or `/refactor` -> `/review-diff` -> `/ship` |
| **M** | `/scout` -> `/impl` or `/refactor` -> `/test` -> `/review-diff` -> `/ship` |
| **L** | `/scout` -> incremental `/impl`(`/refactor` per function) -> `/test` -> `/review-diff` -> `/ship` |
| **XL** | `/scout` -> multi-phase `/impl` -> `/test` -> `/review-diff` -> `/ship` |

**Requirements**:
- No behavior changes (all tests must pass)
- L+ should split implementation by function or module

### Doc

Documentation creation and updates.

| Size | Workflow |
|------|----------|
| **S** | doc-writer agent -> `/review-diff` -> `/ship` |
| **M** | `/scout` -> doc-writer agent + `/impl` -> `/review-diff` -> `/ship` |
| **L** | `/scout` -> doc-writer agent + incremental `/impl` -> `/review-diff` -> `/ship` |

**Requirements**:
- Maintain consistency with existing documentation

### DevOps

CI/CD and infrastructure configuration.

| Size | Workflow |
|------|----------|
| **S** | `/investigate` -> `/impl` -> `/review-diff` -> `/ship` |
| **M** | `/scout` -> `/impl` -> `/review-diff` -> `/ship` |
| **L** | `/scout` -> incremental `/impl` -> `/review-diff` -> `/ship` |

**Special case**: Repository settings changes (Branch Protection, etc.) do not require file commits. Use `gh api` directly.

### Community

Community standards and templates.

| Size | Workflow |
|------|----------|
| **S** | `/impl` -> `/review-diff`(optional) -> `/ship` |
| **M** | doc-writer agent -> `/review-diff` -> `/ship` |

**Requirements**:
- Follow industry standards (Contributor Covenant, Keep a Changelog, etc.)

---

## Common Rules by Size

| Size | `/scout` | `/plan` | `/investigate` | `/impl` | `/test` | `/review-diff` |
|------|----------|---------|----------------|---------|---------|-----------------|
| **S** | Recommended (optional) | Optional | As needed | Recommended | Recommended | Recommended |
| **M** | Recommended | Recommended (included in /scout) | Required (included in /scout) | Required | Required | Required |
| **L** | Required | Required (included in /scout) | Required (included in /scout) | Required | Required | Required |
| **XL** | Required | Required (included in /scout) | Required (included in /scout) | Required | Required (each phase) | Required |

---

## Workflow Selection Flowchart

```
1. Identify category -> Security / CodeQuality / Doc / DevOps / Community
2. Identify size -> S / M / L / XL
3. Select base pattern from the matrix above
4. Check special conditions:
   - Format changes -> spec-first (update docs first)
   - Security impact -> add /security-scan before and after
   - Performance impact -> add benchmarks
   - No file changes -> no commit needed, use gh api etc.
5. Research + planning phase: use /scout for M+ (auto-chains /investigate + /plan2doc)
6. Implementation phase: use /impl (automated lint/test loop)
7. Finalization phase: use /ship (commit + PR in one step)
8. Write final workflow to `### Claude Code Workflow` section in the ticket
```
