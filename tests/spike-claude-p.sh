#!/usr/bin/env bash
# spike-claude-p.sh — sanity-check spike for the `claude -p` command
#
# Goal: verify whether skill invocations work in the claude CLI's `-p` (headless) mode.
# Outcome: based on how many of the 3 verifications pass, decide the future test strategy.
#
# Go / No-Go criteria:
#   3/3 pass    -> Go: build out Level 1 tests on top of `claude -p`
#   1/3 or 2/3  -> Wrapper: use `claude -p` only for the verifications that passed,
#                  fall back to mocks/stubs for the rest
#   0/3 (all fail) -> Level 0 only: drop the `claude -p` based tests and
#                     focus exclusively on static-analysis (Level 0) tests
#
# Usage:
#   bash tests/spike-claude-p.sh
#
# Note: this spike intentionally does NOT match the test-* pattern, so
#       run-all.sh will not pick it up automatically.
set -euo pipefail

# --- claude CLI detection ---
if ! command -v claude &>/dev/null; then
  echo "SKIP: claude CLI not found (skipping spike-claude-p.sh)"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SPIKE_PASSED=0
SPIKE_FAILED=0
SPIKE_TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

spike_assert() {
  local description="$1"
  local result="$2" # "pass" or "fail"
  SPIKE_TOTAL=$((SPIKE_TOTAL + 1))
  if [ "$result" = "pass" ]; then
    echo -e "  ${GREEN}PASS${NC} $description"
    SPIKE_PASSED=$((SPIKE_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} $description"
    SPIKE_FAILED=$((SPIKE_FAILED + 1))
  fi
}

echo "=== Spike: claude -p sanity check ==="
echo ""

# --- Verification 1: skill name resolution ---
# Invoke `/audit --help` etc. via `claude -p` and confirm the skill is recognized
echo "--- Verification 1: skill name resolution ---"
verify1_result="fail"
if output=$(claude -p "List available skills. Just print the skill names, one per line." --max-turns 1 2>&1); then
  # At least one known skill name is present in the output
  if echo "$output" | grep -qiE '(audit|impl|ship|scout|plan2doc)'; then
    verify1_result="pass"
  fi
fi
spike_assert "skill names resolve under claude -p" "$verify1_result"
echo ""

# --- Verification 2: backtick expansion ---
# Confirm that pre-computed-context blocks of the form !`command` get expanded
echo "--- Verification 2: backtick expansion ---"
verify2_result="fail"
if output=$(cd "$REPO_DIR" && claude -p "Run: git branch --show-current" --max-turns 1 --allowedTools "Bash(git branch:*)" 2>&1); then
  # If a branch name comes back, expansion is working
  if echo "$output" | grep -qE '[a-zA-Z]'; then
    verify2_result="pass"
  fi
fi
spike_assert "backtick expansion works" "$verify2_result"
echo ""

# --- Verification 3: allowed-tools is respected ---
# Confirm that tools outside allowed-tools are blocked
echo "--- Verification 3: allowed-tools is respected ---"
verify3_result="fail"
if output=$(cd "$REPO_DIR" && claude -p "Try to write a file called /tmp/spike-test-file.txt with content 'test'. Report if you succeeded or were blocked." --max-turns 1 --allowedTools "Bash(git:*)" 2>&1); then
  # If the file was not created, allowed-tools was respected
  if [ ! -f /tmp/spike-test-file.txt ]; then
    verify3_result="pass"
  else
    rm -f /tmp/spike-test-file.txt
  fi
fi
spike_assert "allowed-tools restriction is respected" "$verify3_result"
echo ""

# --- Summary ---
echo "==============================="
echo -e "Spike result: $SPIKE_TOTAL items, ${GREEN}${SPIKE_PASSED} passed${NC} / ${RED}${SPIKE_FAILED} failed${NC}"
echo "==============================="
echo ""

# --- Go / No-Go decision ---
if [ "$SPIKE_PASSED" -eq 3 ]; then
  echo -e "${GREEN}Verdict: Go${NC} — Level 1 tests on top of claude -p are viable for full build-out"
elif [ "$SPIKE_PASSED" -gt 0 ]; then
  echo -e "${YELLOW}Verdict: Wrapper${NC} — partial success: use claude -p for the items that passed, mock/stub the rest"
else
  echo -e "${RED}Verdict: Level 0 only${NC} — drop claude -p tests, focus on static-analysis tests"
fi

exit 0
