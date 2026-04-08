---
name: security-scan
description: >-
  Run security audit on security-sensitive modules against known
  vulnerability patterns. Use when reviewing or auditing security-critical code changes.
allowed-tools:
  - Agent
  - Read
  - Glob
  - Grep
  - Write
argument-hint: "[target module or file (optional, defaults to all)]"
---

Run security audit. Target: $ARGUMENTS

## Instructions

0. Determine output destination:
   - Parse `$ARGUMENTS` for `(ticket-dir: <path>)`.
   - If `ticket-dir` is specified: set output path to `{ticket-dir}/security-scan.md`
   - If `ticket-dir` is not specified: search `.backlog/product_backlog/` and `.backlog/active/` using Glob for directories matching `$ARGUMENTS` keywords. If a match is found in `product_backlog`, move it to `active` (`mv .backlog/product_backlog/{slug} .backlog/active/{slug}`) and use `.backlog/active/{slug}/security-scan.md`. If already in `active`, use `.backlog/active/{slug}/security-scan.md`.
   - If no ticket-dir and no matching ticket found: use `.docs/reviews/security-{topic}.md`
1. Spawn the **security-scanner** agent on the target, specifying the output path determined in step 0
   - If no target specified, identify and audit all security-sensitive modules in the project (e.g., authentication, cryptography, network, input parsing, file handling)
2. The scanner will reference project security documentation (e.g., THREAT_MODEL.md) if available
3. Report findings by severity: Critical > High > Medium > Low
4. If critical issues found, recommend immediate remediation
