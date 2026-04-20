#!/usr/bin/env bash
# count-tokens.sh — Count tokens (not bytes) in a file.
# Prefers `tiktoken` (cl100k_base); falls back to chars/4 if unavailable.
# Future compression ACs should target token counts, not bytes — byte caps
# invite proxy over-optimization (see Remedy B post-mortem).

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $(basename "$0") <file>" >&2
  exit 2
fi

FILE="$1"

if [[ ! -f "$FILE" ]]; then
  echo "error: file not found: $FILE" >&2
  exit 1
fi

# Escape hatch: SWF_FORCE_FALLBACK=1 skips the tiktoken path deterministically.
FORCE_FALLBACK="${SWF_FORCE_FALLBACK:-0}"

TIKTOKEN_OUT=""
if [[ "$FORCE_FALLBACK" != "1" ]]; then
  TIKTOKEN_OUT="$(python3 - "$FILE" <<'PY' 2>/dev/null || true
import sys
try:
    import tiktoken
except Exception:
    sys.exit(1)
try:
    enc = tiktoken.get_encoding("cl100k_base")
    with open(sys.argv[1], "rb") as f:
        data = f.read()
    text = data.decode("utf-8", errors="replace")
    print(len(enc.encode(text)))
except Exception:
    sys.exit(1)
PY
)"
fi

if [[ -n "$TIKTOKEN_OUT" ]]; then
  echo "[tiktoken]" >&2
  printf '%s\n' "$TIKTOKEN_OUT"
else
  echo "[fallback: chars/4]" >&2
  BYTES=$(wc -c < "$FILE" | tr -d ' ')
  # Integer division; guarantee at least 0 (non-negative integer).
  echo $(( BYTES / 4 ))
fi
