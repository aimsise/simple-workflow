#!/usr/bin/env bash
# forbidden-rationale-patterns.sh — single source of truth for the rationales
# that MUST NOT appear as Manual Bash Fallback justifications.
#
# Sourced by:
#   - hooks/pre-bash-safety.sh (PreToolUse:Bash guard, PX-02a)
#   - hooks/pre-write-safety.sh (PostToolUse:Write guard for autopilot-state.yaml,
#     PX-02b / PX-04)
#   - tests/test-skill-contracts.sh (Phase B contract drift checks, PX-02b)
#
# Each element is a POSIX extended regular expression intended to be applied
# case-insensitively (e.g. `grep -iE "$pat"`). The patterns target common
# phrasings that justify "I bypassed a Skill invocation because the context
# window was full" — a class of rationale that the autopilot SKILL.md
# `## Context-Pressure Response Paths` section explicitly forbids.
#
# Adding to this list:
#   - Append to the array below.
#   - Update tests/test-hooks-lib.sh so the new pattern is covered.
#   - Do not introduce environment-variable escape hatches that bypass the
#     guard. The list is meant to be authoritative; if a pattern needs an
#     exception, edit the array.

# Bash 3.x compatibility: declare as a regular indexed array. `export -a` is
# not portable, so callers must `source` this file rather than expect the
# array to traverse a sub-shell boundary via `export`.
FORBIDDEN_RATIONALE_PATTERNS=(
  'context.*budget'
  'context.*pressure'
  'context.*exhaust(ed|ion)?'
  'context.*occupancy'
  'context.*window.*press'
  'token.*budget'
  'running out.*context'
  'release valve'
  'pressure relief'
  'pragmatic shortcut'
)

# Make the array visible to direct child shells when this file is sourced
# from a parent script. `export` of an indexed array is a no-op in some
# bash builds, so callers should source this file directly rather than rely
# on inheritance.
export FORBIDDEN_RATIONALE_PATTERNS
