# brief.md Body Template

This reference holds the Phase 3 `brief.md` body schema produced by `/brief`. The body follows the frontmatter contract documented in SKILL.md and uses the canonical section headings (`## Vision`, `## Business Context`, `## Technical Requirements`, `## Scope` with `### In Scope` / `### Out of Scope` / `### Edge Cases`, `## Constraints`, `## Quality Expectations`, `## Investigation Summary`). `/brief` Phase 3 links here for the load-bearing template.

```
## Vision
[Refined expression of the user's goal]

## Business Context
[Motivation, stakeholders, timeline — from interview or "Not specified"]

## Technical Requirements
[Specific technical requirements gathered from investigation + interview]

## Scope
### In Scope
- [items]
### Out of Scope
- [items, or "Not explicitly defined" — state behavioral ENDS that are excluded (a value domain, a use case, a guarantee NOT provided), NOT implementation MEANS (a data type, algorithm, library, or representation); a foreclosed MEANS under an advertised END is a Gate 4 violation downstream. If a representation truly IS the external contract (wire format, ABI, declared arithmetic guarantee), state it under `## Constraints`, not here.]
### Edge Cases
- [case]: [expected behavior]

## Constraints
[Technical constraints, compatibility requirements]

## Quality Expectations
[Test coverage expectations, review requirements]

## Investigation Summary
[Key findings from Phase 1 researcher]
```
