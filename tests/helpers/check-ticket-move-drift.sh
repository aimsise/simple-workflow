#!/usr/bin/env bash
# tests/helpers/check-ticket-move-drift.sh
#
# Scans a fixture tree for residual OLD-source-path strings on the three
# surfaces touched by /ship's post-move path-rewrite contract:
#
#   1. .simple-workflow/backlog/done/<slug>/<ticket-id>/audit-round-*.md
#   2. <briefs-done-root>/<slug>/autopilot-state.yaml
#   3. .simple-workflow/backlog/done/<slug>/<ticket-id>/autopilot-log.md
#
# Occurrences inside fenced code blocks (triple-backtick) and inside HTML
# comments (<!-- ... -->) are NOT counted as drift — they are documentation,
# regex examples, or historical narrative that the rewrite contract
# intentionally leaves alone.
#
# Cross-ticket references (paths that mention a different slug or a different
# ticket-id) are NOT counted as drift either; this scanner is scoped to the
# moved ticket only.
#
# Usage:
#   check-ticket-move-drift.sh <fixture-root> <slug> <ticket-id>
#
# Exit codes:
#   0 — clean (no in-prose residuals on any of the three surfaces)
#   1 — drift detected; one or more `drift:` lines emitted on stderr
#   2 — usage error
#
# Stderr drift line format:
#   drift: <relative-file> :<line> :<old-path-substring>

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $(basename "$0") <fixture-root> <slug> <ticket-id>" >&2
  exit 2
fi

FIXTURE_ROOT="$1"
SLUG="$2"
TICKET_ID="$3"

if [ ! -d "$FIXTURE_ROOT" ]; then
  echo "error: fixture-root '$FIXTURE_ROOT' does not exist" >&2
  exit 2
fi

OLD_ACTIVE=".simple-workflow/backlog/active/${SLUG}/${TICKET_ID}/"
OLD_PRODUCT=".simple-workflow/backlog/product_backlog/${SLUG}/${TICKET_ID}/"

DRIFT_COUNT=0

# strip_fenced_and_comments <file>
#
# Reads <file> and emits a per-line stream where every line that lies inside a
# triple-backtick fenced block or an HTML comment block is replaced with an
# empty placeholder. Line numbers are preserved (one output line per input
# line) so that subsequent grep -n reports the original line number.
strip_fenced_and_comments() {
  local file="$1"
  awk '
    BEGIN { in_fence = 0; in_html = 0 }
    {
      line = $0
      out  = line

      # Toggle fence state on lines that match ^```... (start or end of fence).
      # We process the toggle BEFORE deciding whether to blank the line so the
      # fence-delimiter line itself is also blanked (prevents the literal
      # backtick line from being scanned).
      if (line ~ /^[[:space:]]*```/) {
        in_fence = 1 - in_fence
        print ""
        next
      }

      if (in_fence) {
        print ""
        next
      }

      # HTML comment handling: a single line may open AND close (<!-- ... -->),
      # open without closing, or close a previously-opened block. Loop until
      # the line is fully classified.
      result = ""
      i = 1
      n = length(line)
      while (i <= n) {
        if (in_html) {
          # Scan for "-->"
          end = index(substr(line, i), "-->")
          if (end == 0) {
            # Comment continues past end of line
            i = n + 1
          } else {
            # Comment ends; consume "-->" (3 chars)
            i = i + end + 2
            in_html = 0
          }
        } else {
          # Scan for "<!--"
          start = index(substr(line, i), "<!--")
          if (start == 0) {
            # No comment opener on the rest of this line; keep the rest verbatim
            result = result substr(line, i)
            i = n + 1
          } else {
            # Keep up to the opener; enter comment mode
            if (start > 1) {
              result = result substr(line, i, start - 1)
            }
            i = i + start + 3
            in_html = 1
          }
        }
      }
      print result
    }
  ' "$file"
}

# emit_drift <relative-file> <line-number> <substring>
emit_drift() {
  echo "drift: $1:$2:$3" >&2
  DRIFT_COUNT=$((DRIFT_COUNT + 1))
}

# scan_file <absolute-path> <relative-label>
#
# Strips fenced/HTML zones, then greps for OLD_ACTIVE / OLD_PRODUCT. Emits a
# `drift:` line per residual match.
scan_file() {
  local abspath="$1"
  local label="$2"

  if [ ! -f "$abspath" ]; then
    return 0
  fi

  local stripped
  stripped=$(strip_fenced_and_comments "$abspath")

  # Search OLD_ACTIVE and OLD_PRODUCT in the stripped stream.
  local pattern
  pattern=$(printf '%s\n%s\n' "$OLD_ACTIVE" "$OLD_PRODUCT")

  while IFS= read -r match_line; do
    [ -z "$match_line" ] && continue
    local lineno="${match_line%%:*}"
    local content="${match_line#*:}"
    if echo "$content" | grep -qF "$OLD_ACTIVE"; then
      emit_drift "$label" "$lineno" "$OLD_ACTIVE"
    fi
    if echo "$content" | grep -qF "$OLD_PRODUCT"; then
      emit_drift "$label" "$lineno" "$OLD_PRODUCT"
    fi
  done < <(echo "$stripped" | grep -nF -e "$OLD_ACTIVE" -e "$OLD_PRODUCT" || true)

  # Suppress unused-variable warning for $pattern — kept for future extension.
  : "$pattern"
}

# --- Surface 1: audit reports under done/<slug>/<ticket-id>/audit-round-*.md
DONE_TICKET_DIR="$FIXTURE_ROOT/.simple-workflow/backlog/done/${SLUG}/${TICKET_ID}"
if [ -d "$DONE_TICKET_DIR" ]; then
  while IFS= read -r -d '' audit_file; do
    rel=".simple-workflow/backlog/done/${SLUG}/${TICKET_ID}/$(basename "$audit_file")"
    scan_file "$audit_file" "$rel"
  done < <(find "$DONE_TICKET_DIR" -maxdepth 1 -type f -name 'audit-round-*.md' -print0 2>/dev/null)
fi

# --- Surface 2: brief-side autopilot-state.yaml under briefs/done/<slug>/
# Per autopilot Split Brief Lifecycle, the brief-side autopilot-state.yaml is
# moved to briefs/done/<slug>/autopilot-state.yaml at the end of the run.
# For the moved ticket, the corresponding `tickets[].ticket_dir` value MUST
# NOT carry the OLD path. Other tickets' entries are out of scope.
BRIEF_STATE_FILE="$FIXTURE_ROOT/.simple-workflow/backlog/briefs/done/${SLUG}/autopilot-state.yaml"
if [ -f "$BRIEF_STATE_FILE" ]; then
  rel=".simple-workflow/backlog/briefs/done/${SLUG}/autopilot-state.yaml"
  # YAML never has triple-backtick fences in normal use, but the scan_file
  # helper handles it gracefully if present. We additionally constrain the
  # match to lines whose `ticket_dir:` value names THIS ticket — i.e. the
  # OLD-path substring scoped to <slug>/<ticket-id>/. Cross-ticket entries
  # (different slug or different ticket-id) are not flagged.
  while IFS= read -r match_line; do
    [ -z "$match_line" ] && continue
    lineno="${match_line%%:*}"
    content="${match_line#*:}"
    if echo "$content" | grep -qF "$OLD_ACTIVE"; then
      emit_drift "$rel" "$lineno" "$OLD_ACTIVE"
    fi
    if echo "$content" | grep -qF "$OLD_PRODUCT"; then
      emit_drift "$rel" "$lineno" "$OLD_PRODUCT"
    fi
  done < <(grep -nF -e "$OLD_ACTIVE" -e "$OLD_PRODUCT" "$BRIEF_STATE_FILE" || true)
fi

# --- Surface 3: autopilot-log.md under done/<slug>/<ticket-id>/
LOG_FILE="$DONE_TICKET_DIR/autopilot-log.md"
if [ -f "$LOG_FILE" ]; then
  rel=".simple-workflow/backlog/done/${SLUG}/${TICKET_ID}/autopilot-log.md"
  scan_file "$LOG_FILE" "$rel"
fi

if [ "$DRIFT_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
