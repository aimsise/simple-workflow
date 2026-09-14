#!/usr/bin/env bash
# test-eval-panel-merge.sh — bash wrapper so tests/run-all.sh (which globs
# test-*.sh only) and CI exercise the Workflow merge unit test + the
# product-script contract (top-level `return`, parses as a Workflow body).
# Skips cleanly when node is not installed (the merge test is plain Node).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

echo "=== eval-panel merge + product-script contract (node) ==="
if ! command -v node >/dev/null 2>&1; then
  echo "  (skip) node not on PATH — tests/test-eval-panel-merge.mjs not run"
  echo "==============================="
  echo "Total: 0 | Passed: 0 | Failed: 0 (skipped)"
  echo "==============================="
  exit 0
fi

if node "$SCRIPT_DIR/test-eval-panel-merge.mjs"; then
  echo -e "  ${GREEN}PASS${NC} node tests/test-eval-panel-merge.mjs"
  echo "==============================="
  echo -e "Total: 1 | ${GREEN}Passed: 1${NC} | ${RED}Failed: 0${NC}"
  echo "==============================="
  exit 0
else
  echo -e "  ${RED}FAIL${NC} node tests/test-eval-panel-merge.mjs"
  echo "==============================="
  echo -e "Total: 1 | ${GREEN}Passed: 0${NC} | ${RED}Failed: 1${NC}"
  echo "==============================="
  exit 1
fi
