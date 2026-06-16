#!/usr/bin/env bash
set -euo pipefail

# jq is a documented hard dependency. When it is missing this guard cannot parse
# the tool payload; rather than dying with a silent `exit 127` (which Claude Code
# treats as a non-blocking error — a fail-OPEN), resolve the behaviour through
# SW_SAFETY_JQ_MISSING_MODE (UX-11):
#   on          -> fail CLOSED (exit 2) with an explicit message
#   metric-only -> (default) log the would-be fail-closed and ALLOW (exit 0)
#   off         -> silently allow (exit 0)
# A typo collapses to metric-only (the observe-only default). Default is
# metric-only so this hardening does not change the shipped fail-open behaviour
# until an operator opts in with `=on` (post-dogfood promote).
if ! command -v jq >/dev/null 2>&1; then
  case "${SW_SAFETY_JQ_MISSING_MODE:-metric-only}" in
    on)
      echo "[SAFETY-JQ-MISSING] pre-write-safety: jq not found on PATH — failing closed (exit 2). Install jq (e.g. 'brew install jq') to run this guard." >&2
      exit 2 ;;
    off)
      exit 0 ;;
    metric-only|*)
      echo "[SAFETY-JQ-MISSING] metric-only: pre-write-safety would fail closed (exit 2) — jq not found on PATH; allowing this call. Install jq, or set SW_SAFETY_JQ_MISSING_MODE=on to enforce." >&2
      exit 0 ;;
  esac
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Sensitive file patterns (aligned with pre-bash-safety.sh). F-HOOKS-03: the
# `credentials`/`secret` arms are anchored to secret-bearing EXTENSIONS so
# legitimate source/doc files (credentials.ts, secret.md) are NOT false-blocked,
# while secret-bearing config (credentials.json, app-secret.yaml) and key
# material (.env, *.key, id_rsa) still are. id_rsa* is basename-anchored so
# `id_rsa_test.pub` stays allowed.
SENSITIVE='(\.(env|key|pem|p12|pfx|jks|keystore)\b|\.npmrc$|\.pypirc$|(^|/)(id_rsa|id_ed25519|id_ecdsa)\b|(credentials|secret)[A-Za-z0-9._-]*\.(json|ya?ml|env|ini|cfg|conf|xml|properties|toml)\b)'

if echo "$FILE_PATH" | grep -qiE "$SENSITIVE"; then
  echo "Blocked: writing to sensitive file not allowed: $FILE_PATH" >&2
  exit 2
fi

# PII guard: reject absolute home paths ( /Users/<name>/... or /home/<name>/... )
# in the target file content. Triple-backtick fenced code blocks are skipped, and
# `.gitignore` is allowlisted (it legitimately stores absolute paths).
BASENAME=$(basename "$FILE_PATH")
if [ "$BASENAME" != ".gitignore" ]; then
  CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
  if [ -n "$CONTENT" ]; then
    if printf '%s' "$CONTENT" | awk '
      BEGIN {
        fenced = 0
        hit = 0
        re = "(/Users/[^/]+/|/home/[^/]+/)"
      }
      /^[[:space:]]*```/ { fenced = 1 - fenced; next }
      {
        if (!fenced && match($0, re)) {
          hit = 1
          exit
        }
      }
      END { exit (hit ? 0 : 1) }
    '; then
      echo "pii: absolute home path detected in $FILE_PATH" >&2
      exit 2
    fi
  fi
fi

# state-authority.sh sourced lazily inside case arm to preserve byte-identity for non-state-file payloads (T-002)
case "$FILE_PATH" in
  *"/autopilot-state.yaml"|*"/phase-state.yaml")
    # shellcheck source=lib/state-authority.sh
    source "$SCRIPT_DIR/lib/state-authority.sh"
    NEW_STRING=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || true)
    OLD_STRING=""
    if [ -f "$FILE_PATH" ]; then
      OLD_STRING=$(cat "$FILE_PATH" 2>/dev/null || true)
    fi
    # state_field_change_blocked echoes the violated registry key on stdout
    # and returns 0 when a hook-owned field would change. The DENY is gated by
    # SW_STATE_FIELD_GUARD_MODE (proposal 4 / ST-03): `on` blocks, `metric-only`
    # (default) logs + allows, `off` allows silently. Default is metric-only so
    # populating HOOK_OWNED_FIELDS does not change the shipped allow behaviour.
    if _SFG_FIELD=$(state_field_change_blocked "$FILE_PATH" "$OLD_STRING" "$NEW_STRING"); then
      case "${SW_STATE_FIELD_GUARD_MODE:-metric-only}" in
        on)
          jq -nc --arg f "$_SFG_FIELD" \
            '{decision:"block", reason:("hook_owned_field_violation: " + $f + " is a hook-owned, append-only field written exclusively by the autopilot Stop / PreCompact / checkpoint hooks. Do not Write it directly — let the hooks append. See docs/state-schema.md.")}'
          exit 0 ;;
        off) ;;
        metric-only|*)
          echo "[STATE-FIELD-GUARD] metric-only: would block hook_owned_field_violation: ${_SFG_FIELD} (Write to $FILE_PATH); set SW_STATE_FIELD_GUARD_MODE=on to enforce. See docs/state-schema.md." >&2 ;;
      esac
    fi
    ;;
esac

exit 0
