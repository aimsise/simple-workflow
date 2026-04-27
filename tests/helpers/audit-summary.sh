#!/usr/bin/env bash
# audit-summary.sh — Parse an audit-round-N.md file and emit the canonical
# `Audit Summary:` line that /ship embeds into commit message and PR body.
#
# Usage:
#   tests/helpers/audit-summary.sh <audit-round-file>
#   tests/helpers/audit-summary.sh --dir <ticket-dir>
#   tests/helpers/audit-summary.sh --warning-titles <audit-round-file>
#
# When given a single file, prints the canonical line:
#   Audit Summary: <Status> (Critical=<N>, Warnings=<N>, Suggestions=<N>)
# When given --dir <ticket-dir>, selects the numerically-latest
# audit-round-N.md (audit-round-10.md beats audit-round-2.md) and parses it.
# When given --warning-titles, prints each `### Warning: <title>` heading
# verbatim (one per line), preserving any backticks in the title.
#
# Parsing rules (mirrored by the /ship documentation contract in
# skills/ship/SKILL.md):
#   - Lines inside triple-backtick fenced code blocks are ignored.
#   - Lines inside `<!-- ... -->` HTML comments are ignored.
#   - Optional `**` markdown bold markers around field names are tolerated
#     (`**Status**: PASS` and `Status: PASS` parse identically).
#   - Field names are matched case-sensitively as `Status`, `Critical`,
#     `Warnings`, `Suggestions`.
#
# Error contracts (exit non-zero, message on stderr):
#   - Missing Status line:
#       audit-summary: missing Status line in audit-round-<N>.md
#   - Warnings count mismatch (declared count != actual `### Warning:`
#     heading count):
#       audit-summary: count-mismatch (Warnings declared=<X>, headings=<Y>)
#
# This helper exists so the contract is mechanically verifiable from tests
# without requiring a real /ship invocation. /ship itself implements the
# same contract at prompt-time (see skills/ship/SKILL.md "Audit Summary
# embedding" section).

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
usage:
  audit-summary.sh <audit-round-file>
  audit-summary.sh --dir <ticket-dir>
  audit-summary.sh --warning-titles <audit-round-file>
  audit-summary.sh --warning-titles --dir <ticket-dir>
USAGE
  exit 2
}

MODE="summary"
DIR_MODE=0
DIR_ARG=""
FILE_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --warning-titles) MODE="warnings"; shift ;;
    --dir) DIR_MODE=1; DIR_ARG="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    --*) echo "audit-summary: unknown flag: $1" >&2; exit 2 ;;
    *) FILE_ARG="$1"; shift ;;
  esac
done

resolve_file() {
  if [[ "$DIR_MODE" -eq 1 ]]; then
    if [[ -z "$DIR_ARG" || ! -d "$DIR_ARG" ]]; then
      echo "audit-summary: directory not found: $DIR_ARG" >&2
      exit 2
    fi
    # Numeric ordering: audit-round-10.md beats audit-round-2.md.
    # Extract the integer N from the basename and sort numerically descending.
    local latest
    latest=$(
      find "$DIR_ARG" -maxdepth 1 -type f -name 'audit-round-*.md' 2>/dev/null \
        | while read -r f; do
            n=$(basename "$f" .md | sed -E 's/^audit-round-//')
            # Skip files whose suffix is not a pure non-negative integer.
            if [[ "$n" =~ ^[0-9]+$ ]]; then
              printf '%s\t%s\n' "$n" "$f"
            fi
          done \
        | sort -k1,1 -n -r \
        | head -1 \
        | cut -f2-
    )
    if [[ -z "$latest" ]]; then
      echo "audit-summary: no audit-round-N.md under $DIR_ARG" >&2
      exit 3
    fi
    FILE_ARG="$latest"
  fi

  if [[ -z "$FILE_ARG" || ! -f "$FILE_ARG" ]]; then
    echo "audit-summary: file not found: $FILE_ARG" >&2
    exit 2
  fi
}

# strip_masked: emit only lines that are NOT inside a triple-backtick fenced
# code block AND NOT inside an HTML comment (`<!-- ... -->`). Both can span
# multiple lines. We also drop any inline `<!-- ... -->` segment that opens
# and closes on the same line, leaving the surrounding text intact, in case
# a field assignment is hidden inline.
strip_masked() {
  local file="$1"
  awk '
    BEGIN { in_fence = 0; in_html = 0 }
    {
      line = $0
      # Toggle fenced code block on a line beginning with ``` (allow up to 3
      # leading spaces, per CommonMark). A fence line itself is masked.
      if (line ~ /^[[:space:]]{0,3}```/) {
        in_fence = 1 - in_fence
        next
      }
      if (in_fence) { next }

      # Strip inline `<!-- ... -->` comments contained on a single line.
      while (match(line, /<!--[^\n]*-->/)) {
        line = substr(line, 1, RSTART - 1) substr(line, RSTART + RLENGTH)
      }

      # Multi-line HTML comments: enter on `<!--` without a matching `-->`,
      # exit on the line containing the closing `-->`.
      if (in_html) {
        if (index(line, "-->") > 0) {
          in_html = 0
          # Drop content up to and including the closing marker.
          line = substr(line, index(line, "-->") + 3)
        } else {
          next
        }
      }
      if (index(line, "<!--") > 0 && index(line, "-->") == 0) {
        in_html = 1
        line = substr(line, 1, index(line, "<!--") - 1)
      }

      print line
    }
  ' "$file"
}

# Extract the value for a field name. Tolerates a leading `**` markdown bold
# marker around the field name (so `**Status**: PASS` and `Status: PASS`
# both match). Trims trailing whitespace.
extract_field() {
  local field="$1"
  local masked="$2"
  # First match wins; later duplicates are ignored.
  printf '%s\n' "$masked" \
    | grep -m1 -E "^(\*\*)?${field}(\*\*)?:[[:space:]]" \
    | sed -E "s/^(\*\*)?${field}(\*\*)?:[[:space:]]*//; s/[[:space:]]+$//" \
    || true
}

# Extract `### Warning:` headings. Inside the masked content (so fenced and
# HTML-commented warnings are dropped). Backticks in titles are preserved
# verbatim.
extract_warning_headings() {
  local masked="$1"
  printf '%s\n' "$masked" \
    | grep -E '^###[[:space:]]+Warning:[[:space:]]' \
    || true
}

main() {
  resolve_file
  local masked
  masked=$(strip_masked "$FILE_ARG")

  if [[ "$MODE" == "warnings" ]]; then
    extract_warning_headings "$masked"
    return 0
  fi

  local status critical warnings suggestions
  status=$(extract_field "Status" "$masked")
  critical=$(extract_field "Critical" "$masked")
  warnings=$(extract_field "Warnings" "$masked")
  suggestions=$(extract_field "Suggestions" "$masked")

  if [[ -z "$status" ]]; then
    echo "audit-summary: missing Status line in $(basename "$FILE_ARG")" >&2
    exit 4
  fi

  # Default missing counts to 0 to mirror /audit's "all counts at 0" no-op
  # default; the contract focuses on Status as the load-bearing field.
  : "${critical:=0}"
  : "${warnings:=0}"
  : "${suggestions:=0}"

  # Count mismatch: declared Warnings count vs actual `### Warning:` headings.
  local heading_count
  heading_count=$(extract_warning_headings "$masked" | grep -c . || true)
  # grep -c on empty input prints 0; ensure integer.
  heading_count="${heading_count:-0}"

  # Only enforce mismatch when both counts are pure non-negative integers;
  # an obviously malformed Warnings field falls through as-is so the user
  # sees the raw value in the canonical line and can debug.
  if [[ "$warnings" =~ ^[0-9]+$ ]] && [[ "$heading_count" =~ ^[0-9]+$ ]]; then
    if [[ "$warnings" -ne "$heading_count" ]]; then
      echo "audit-summary: count-mismatch (Warnings declared=$warnings, headings=$heading_count)" >&2
      exit 5
    fi
  fi

  printf 'Audit Summary: %s (Critical=%s, Warnings=%s, Suggestions=%s)\n' \
    "$status" "$critical" "$warnings" "$suggestions"
}

main "$@"
