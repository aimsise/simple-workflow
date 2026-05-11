#!/usr/bin/env bash
# mock-ac-evaluator-second-call-terminal.sh — Fixture for CT-MODE-SINGLESHOT-6 (AC-6).
#
# Simulates an ac-evaluator that exhausts its turn budget on the first call
# (writes IN_PROGRESS, empty stdout) but succeeds on the second call (writes
# terminal PASS, non-empty stdout summary).
#
#   Call 1 (count == 0 before increment):
#     - Writes ## Status: IN_PROGRESS skeleton to EVAL_REPORT_PATH.
#     - Increments COUNTER_FILE to 1.
#     - Exits 0 with EMPTY stdout.
#
#   Call 2 (count == 1 before increment):
#     - Writes ## Status: PASS with all [x] ACs to EVAL_REPORT_PATH.
#     - Increments COUNTER_FILE to 2.
#     - Prints a non-empty stdout summary line ("AC evaluation complete: PASS").
#     - Exits 0.
#
# Inputs (environment variables):
#   EVAL_REPORT_PATH — absolute path where the report is written.
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

if [ "$current" -eq 0 ]; then
  # First call: simulate turn-budget exhaustion — write IN_PROGRESS, empty stdout.
  printf '## Status: IN_PROGRESS\n- [ ] AC-1\n- [ ] AC-2\n- [ ] AC-3\n' > "$EVAL_REPORT_PATH"
  # Empty stdout.
  exit 0
else
  # Second call: recovery succeeded — write terminal PASS report, non-empty stdout.
  printf '## Status: PASS\n- [x] AC-1\n- [x] AC-2\n- [x] AC-3\n' > "$EVAL_REPORT_PATH"
  printf 'AC evaluation complete: PASS\n'
  exit 0
fi
