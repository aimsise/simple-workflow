#!/usr/bin/env bash
# audit-block-pattern.sh — single source of truth for the /audit Step 4
# structured-block grep pattern.
#
# Sourced by:
#   - hooks/impl-checkpoint-guard.sh (Stop hook 5-AND condition (a))
#   - tests/test-skill-contracts.sh (literal match assertion against
#     skills/audit/SKILL.md Step 4 example)
#
# Public contract:
#
#   Two environment variables exported on source:
#     AUDIT_BLOCK_PATTERN_STATUS   — ERE pattern that matches the literal
#                                    `**Status**:` line emitted by Step 4.
#     AUDIT_BLOCK_PATTERN_REPORTS  — ERE pattern that matches the literal
#                                    `**Reports**:` line emitted by Step 4.
#
# Patterns are HARDCODED LITERALS, NOT runtime-parsed from SKILL.md. The
# skill-contract test asserts these literals appear in audit/SKILL.md Step 4,
# so a documentation drift fails CI at the contract layer instead of the
# runtime hook silently ceasing to fire.
#
# Why no SUMMARY: only Status + Reports drive the Stop-hook 5-AND condition (a).
# Adding an unused export bloats the surface; if a future caller needs it,
# add it then.
#
# `set -euo pipefail` is intentionally NOT set here. This file is sourced by
# hook scripts and tests that already declare their own shell flags; setting
# them again would override the caller's configuration.

export AUDIT_BLOCK_PATTERN_STATUS='\*\*Status\*\*:'
export AUDIT_BLOCK_PATTERN_REPORTS='\*\*Reports\*\*:'
