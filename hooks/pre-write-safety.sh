#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_HOOKS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/hooks"
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Sensitive file patterns (aligned with pre-bash-safety.sh)
SENSITIVE='(\.(env|key|pem|p12|pfx|jks|keystore)\b|credentials\b|secret\b|id_rsa\b|id_ed25519\b|id_ecdsa\b|\.npmrc$|\.pypirc$)'

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
    source "$REPO_HOOKS_DIR/lib/state-authority.sh"
    NEW_STRING=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || true)
    OLD_STRING=""
    if [ -f "$FILE_PATH" ]; then
      OLD_STRING=$(cat "$FILE_PATH" 2>/dev/null || true)
    fi
    if state_field_change_blocked "$FILE_PATH" "$OLD_STRING" "$NEW_STRING"; then
      jq -nc '{decision:"block", reason:"hook_owned_field_violation"}'
      exit 0
    fi
    ;;
esac

exit 0
