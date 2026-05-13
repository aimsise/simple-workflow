# Skeptical Third-Pass triggers and prompt template

This file is the canonical source for the Skeptical Third-Pass triggers
and the verbatim prompt template that Step 3.5 of `/audit` passes to the
`general-purpose` reviewer agent. The orchestration semantics (when the
third-pass fires, where the response is saved, the at-most-once rule, the
`only_security_scan=true` short circuit, and the agent-failure handling)
remain in `skills/audit/SKILL.md` Step 3.5; this reference contains only
the trigger definitions and the prompt body.

## Triggers

Any single trigger fires Step 3.5:

- **T-A** The PR introduces or modifies a `hooks/lib/` shared library file. These files are leverage points — a defect in a shared library propagates to every hook that sources it.
- **T-B** The PR introduces or modifies a sanitization or escaping function. Heuristic: diff hunks contain at least one of `printf %q`, `escape`, `sanitize`, `quote`, or ERE-escape patterns. Standard rubric-bound reviewers check syntactic patterns, not enumerative coverage of caller-controlled inputs.
- **T-C** The PR adds or modifies a `tools:` permission entry in any `agents/*.md` file. Agent permission changes have orchestration consequences outside the categorical security rubric.
- **T-D** The prior `ac-evaluator` round returned `PASS-WITH-CAVEATS` due to missing tooling. Heuristic: any `eval-round-{n}.md` file in `{ticket-dir}` contains both `PASS-WITH-CAVEATS` and `skipped` within the same AC entry. This indicates the evaluator accepted code inspection as evidence when a live execution tier was unavailable.
- **T-E** The PR diff touches more than 3 files in total, with at least one file in each of `hooks/`, `agents/`, and `skills/` simultaneously. Cross-cutting changes are by definition outside any single rubric. A PR that only touches `tests/` does NOT fire T-E, regardless of file count.

## Prompt Template

When Step 3.5 fires, use the following prompt verbatim, substituting
`{changed_files}`, `{rubric_ids}`, and `{trigger_list}` from context:

```
You are a general-purpose reviewer acting as a skeptical third-pass auditor.

The following files were changed in this PR:
{changed_files}

The standard rubric-bound reviewers have already evaluated this change:
- code-reviewer (rubric IDs: {rubric_ids[code-reviewer]})
- security-scanner (rubric IDs: {rubric_ids[security-scanner]})

Triggers that fired for this review: {trigger_list}

Note: if T-4 (Pre-existing Failure Attribution) is documented in agents/ac-evaluator.md, do NOT duplicate that check — focus on issues outside T-4's scope.

Your task: identify any substantive ship-blockers that the standard rubric-bound reviewers would miss because they operate within categorical rubrics (code quality, security vulnerability patterns) and do not verify:
- End-to-end behavioural correctness (e.g., live execution of a claimed production path)
- Enumerative coverage of all caller-controlled inputs to a sanitization function
- Cross-system orchestration consequences of permission changes
- Any other substantive concern outside the standard rubrics

Classify findings by severity matching the ac-evaluator scale:
- **CRITICAL**: would cause data loss, security breach, or correctness failure in production
- **HIGH**: would cause incorrect behaviour detectable in normal use
- **MEDIUM**: potential concern that needs investigation before the next release

Output format:
**Verdict**: SHIP | DO_NOT_SHIP
**Findings**: (list findings with severity; "None" if SHIP)
**Reasoning**: (1-3 sentences on why the verdict was reached)
```
