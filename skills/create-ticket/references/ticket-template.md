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

#### Failure-Class Coverage (Gate 9)

(One matrix per Scope-touched external boundary — public / exported function, CLI subcommand, endpoint, exported API symbol, file-format / wire-format, or parser. Each row resolves to >=1 AC ID OR a one-line `n/a` justification — never a blank. Omit this section entirely when the ticket touches no external boundary, e.g. an internal-helper-only refactor.)

**Boundary: `<surface name>`**

| Failure class | AC(s) or n/a justification |
|------|------|
| R1 FULL-DOMAIN INVARIANT (whole valid domain incl. min/max/empty/singleton/max-length/just-inside-each-boundary) | AC-... \| n/a: ... |
| R2 HOSTILE + BOUNDED TERMINATION + RESOURCE-CAP (malformed/oversized/empty/out-of-domain -> bounded error in bounded time/space; no hang, no non-error success; when this unit is a member of a cross-ticket `shared_input_boundary` family it owes this row even if it DELEGATES to a shared parser — 'delegates to the shared parser' is not an acceptable n/a) | AC-... \| n/a: ... |
| R3 DESCRIPTION-MATCHES-BEHAVIOR (runtime matches the unit's own docstring/declared invariant) | AC-... \| n/a: ... |
| R4 DOC/INTERFACE TRUTHFULNESS (each advertised example reproduces on a real build; advertised boundary == enforced boundary) | AC-... \| n/a: ... |

#### Peer-Set Uniformity (Gate 10)

(Only when the ticket's Scope creates a `>=2`-peer set — a family of analogous sibling units in one category, e.g. several MCP tools / endpoints / subcommands / exported functions sharing an output surface. Resolve the single row to >=1 AC ID (a UNIFIED-convention AC over the set, mechanically grep/AST-verifiable across every peer) OR a one-line `n/a` justification — never a blank. Omit this section entirely when the Scope creates fewer than 2 peers.)

| Failure class | AC(s) or n/a justification |
|------|------|
| D PEER-SET UNIFORMITY (one error convention / one success-envelope shape / one vocabulary per concept / one wrapper for repeated boilerplate, asserted across every peer in the set) | AC-... \| n/a: ... |

### Implementation Notes

- ...

### Capabilities

| Name | Type | Purpose | Used by | Bound AC(s) |
|------|------|---------|---------|-------------|
| ... | skill \| agent \| MCP server \| test runner | ... | ... | AC-... |

### Advisory Capabilities

| Name | Type | Purpose | Used by |
|------|------|---------|---------|
| ... | skill \| MCP server | implementation reference / library docs / design guidance | implementer \| researcher \| test-writer |

#### Capability Gaps

- (Optional) List runtime/visual ACs that lack a binding and the reason (e.g. no suitable skill available).

#### Capability Skip Rationale

- **<name>**: <one-line reason this probe-visible capability is neither Bound nor Advisory for this ticket>

### Claude Code Workflow

| Phase | Skill / Agent | Purpose |
|-------|--------------|---------|
| 1. ... | ... | ... |

**Example execution**:
```
[Command flow]
```
```
