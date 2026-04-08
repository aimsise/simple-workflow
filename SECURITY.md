# Security Policy

## Supported Versions

Only the latest version on the `main` branch is supported with security updates.

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |

## Reporting a Vulnerability

**Please do NOT open a public issue for security vulnerabilities.**

Instead, report vulnerabilities by emailing **helix2066@gmail.com** directly.

Please include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

You will receive an acknowledgment within **72 hours** of your report.

## Scope

The following are considered security issues for this project:

- Bypass of `pre-bash-safety.sh` destructive command blocking
- Bypass of `pre-write-safety.sh` or `pre-edit-safety.sh` sensitive file protection
- Path traversal in hook scripts
- Unintended command execution through hook inputs

## Out of Scope

- Issues in Claude Code itself — please report to [Anthropic](https://github.com/anthropics/claude-code/issues)
- Issues in user-configured CLAUDE.md or custom settings
