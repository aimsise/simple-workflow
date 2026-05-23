# Ticket Output Template

Generate the ticket in the following format:

```markdown
## T-{NNN}: [Title]

| Field | Value |
|-------|-------|
| Priority | **P?** |
| Category | [Category] |
| Size | [S/M/L/XL] |
| Dependencies | [Dependent tickets or --] |

### Background

[Problem description and rationale]

### Scope

| File | Lines | Change |
|------|-------|--------|
| ... | ... | ... |

### Acceptance Criteria

1. ...
2. ...

### Implementation Notes

- ...

### Capabilities

| Name | Type | Purpose | Used by | Bound AC(s) |
|------|------|---------|---------|-------------|
| ... | skill \| agent \| MCP server \| test runner | ... | ... | AC-... |

#### Capability Gaps

- (Optional) List runtime/visual ACs that lack a binding and the reason (e.g. no suitable skill available).

### Claude Code Workflow

| Phase | Skill / Agent | Purpose |
|-------|--------------|---------|
| 1. ... | ... | ... |

**Example execution**:
```
[Command flow]
```
```
