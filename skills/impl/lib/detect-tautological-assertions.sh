#!/usr/bin/env bash
# Detect tautological assertions (R1 / R2 / R3) in a single test file.
#
# Canonical rules: skills/impl/references/tautological-assertion-rules.md
#
# Usage:
#   detect-tautological-assertions.sh <file>
#
# Exit codes:
#   0  — file is clean (no rule fires, OR an R1 hint comment exempts the file)
#   1  — file contains at least one rule violation
#   2  — invalid invocation (missing argument or unreadable file)
#
# Stdout (only on violation):
#   one line per finding, in the form
#     R<N>: <file>:<line> — <line content>
#
# This detector is intentionally grep-based and language/framework-agnostic
# at the regex level. See the rules file's `## Limitations` section for the
# documented out-of-scope cases (variable resolution, type inference,
# cross-file analysis, AST-level algebraic simplification).
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $(basename "$0") <file>" >&2
  exit 2
fi

FILE="$1"
if [ ! -r "$FILE" ]; then
  echo "detect-tautological-assertions: cannot read $FILE" >&2
  exit 2
fi

# Hint exemption (R1 only). Matches anywhere in the file.
HINT_RE='intentional reference (equality|identity) test|reference-equality: intentional'
HINT_HIT=0
if grep -qE "$HINT_RE" "$FILE"; then
  HINT_HIT=1
fi

VIOLATIONS=0
emit() {
  local rule="$1" lineno="$2" content="$3"
  printf '%s: %s:%s — %s\n' "$rule" "$FILE" "$lineno" "$content"
  VIOLATIONS=1
}

# Iterate the file once, applying R1/R2/R3 to each line.
# Skip the entire file for R1 if a hint is present, but still apply R2/R3.
lineno=0
while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))

  # Skip blank or comment-only lines for performance and to avoid matching
  # patterns inside narrative comments. We accept that this skips comments
  # that contain assertion-shaped strings; that is acceptable since the
  # detector targets executable test code.
  trimmed="${line#"${line%%[![:space:]]*}"}"
  case "$trimmed" in
    ''|//*|'#'*|'*'*) continue ;;
  esac

  # ---- R1: same identifier on both sides of toEqual / toBe ----
  # The identifier must NOT be a boolean / null literal — those are R3
  # territory (constant truthiness) and should be reported as R3 only.
  if [ "$HINT_HIT" -eq 0 ]; then
    if printf '%s' "$line" \
        | grep -vE 'expect\([[:space:]]*(true|false|null|undefined)[[:space:]]*\)' \
        | grep -qE 'expect\([[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\)\.(toEqual|toBe|toStrictEqual)\([[:space:]]*\1[[:space:]]*\)'; then
      emit "R1" "$lineno" "$line"
    fi
  fi

  # ---- R2: vacuous numeric boundary against a literal extremum ----
  # Right-hand side is one of: 0, -0, Number.MAX_VALUE, Number.MIN_VALUE,
  # Number.MAX_SAFE_INTEGER, Number.MIN_SAFE_INTEGER, Infinity, -Infinity.
  if printf '%s' "$line" | grep -qE 'expect\([^)]*\)\.(toBeGreaterThanOrEqual|toBeGreaterThan|toBeLessThanOrEqual|toBeLessThan)\([[:space:]]*(-?0|-?Infinity|Number\.(MAX_VALUE|MIN_VALUE|MAX_SAFE_INTEGER|MIN_SAFE_INTEGER))[[:space:]]*\)'; then
    emit "R2" "$lineno" "$line"
  fi

  # ---- R3: constant boolean assertions ----
  # 3a) expect(<bool literal>).(toBe|toEqual|toStrictEqual)(<bool literal>)
  if printf '%s' "$line" | grep -qE 'expect\([[:space:]]*(true|false)[[:space:]]*\)\.(toBe|toEqual|toStrictEqual)\([[:space:]]*(true|false)[[:space:]]*\)'; then
    emit "R3" "$lineno" "$line"
    continue
  fi
  # 3b) truthiness/falsy assertions wrapping a bare boolean literal
  if printf '%s' "$line" | grep -qE 'expect\([[:space:]]*(true|false)[[:space:]]*\)\.(toBeTruthy|toBeFalsy)\(\)'; then
    emit "R3" "$lineno" "$line"
    continue
  fi
  # 3c) short-circuit constants: `|| true)` or `&& false)` inside expect(...)
  if printf '%s' "$line" | grep -qE 'expect\([^)]*(\|\|[[:space:]]*true|&&[[:space:]]*false)[[:space:]]*\)\.(toBe|toEqual|toStrictEqual|toBeTruthy|toBeFalsy)'; then
    emit "R3" "$lineno" "$line"
  fi
done < "$FILE"

if [ "$VIOLATIONS" -ne 0 ]; then
  exit 1
fi
exit 0
