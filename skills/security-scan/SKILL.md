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

1. Spawn the **security-scanner** agent on the target
   - If no target specified, identify and audit all security-sensitive modules in the project (e.g., authentication, cryptography, network, input parsing, file handling)
2. The scanner will reference project security documentation (e.g., THREAT_MODEL.md) if available
3. Full report will be saved to `.docs/reviews/security-{topic}.md`
4. Report findings by severity: Critical > High > Medium > Low
5. If critical issues found, recommend immediate remediation
