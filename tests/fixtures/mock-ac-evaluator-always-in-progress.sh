#!/usr/bin/env bash
# mock-ac-evaluator-always-in-progress.sh — Fixture for CT-MODE-SINGLESHOT-7 (AC-7).
#
# Simulates an ac-evaluator that ALWAYS exhausts its turn budget:
#   - Writes ## Status: IN_PROGRESS to EVAL_REPORT_PATH on every invocation.
#   - Increments the call counter in COUNTER_FILE by 1 each call.
#   - Exits 0 with EMPTY stdout (mirrors T-1 Persistence-First Protocol: agent
#     writes skeleton first, then returns empty Output envelope).
#
# Inputs (environment variables):
#   EVAL_REPORT_PATH — absolute path where the IN_PROGRESS report is written.
#   COUNTER_FILE     — absolute path to a plain-text file holding the current
#                      call count (one integer per line; created as "0" on
#                      first use if the file does not exist).
set -euo pipefail

: "${EVAL_REPORT_PATH:?EVAL_REPORT_PATH must be set}"
: "${COUNTER_FILE:?COUNTER_FILE must be set}"

# Read current count (default 0 if file absent or empty).
current=0
if [ -f "$COUNTER_FILE" ]; then
  current=$(cat "$COUNTER_FILE")
  current=${current:-0}
fi

# Increment counter.
printf '%s\n' "$((current + 1))" > "$COUNTER_FILE"

# Write IN_PROGRESS skeleton to the report path.
printf '## Status: IN_PROGRESS\n- [ ] AC-1\n- [ ] AC-2\n- [ ] AC-3\n' > "$EVAL_REPORT_PATH"

# Exit 0 with EMPTY stdout (no Output envelope).
exit 0
