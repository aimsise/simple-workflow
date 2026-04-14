#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERALL_FAILED=0

echo "=========================================="
echo "  simple-workflow Test Suite"
echo "=========================================="
echo ""

for test_file in "$SCRIPT_DIR"/test-*.sh; do
  if [ -f "$test_file" ]; then
    # Skip test-helper.sh (it's a library, not a test suite)
    if [ "$(basename "$test_file")" = "test-helper.sh" ]; then
      continue
    fi
    # Skip test-integration.sh here; it runs separately below
    if [ "$(basename "$test_file")" = "test-integration.sh" ]; then
      continue
    fi
    echo "Running $(basename "$test_file")..."
    echo ""
    if ! bash "$test_file"; then
      OVERALL_FAILED=1
    fi
    echo ""
  fi
done

# Integration tests (auto-skipped when claude CLI is not available)
if [ -f "$SCRIPT_DIR/test-integration.sh" ]; then
  echo "Running test-integration.sh (integration)..."
  echo ""
  if ! bash "$SCRIPT_DIR/test-integration.sh"; then
    OVERALL_FAILED=1
  fi
  echo ""
fi

echo "=========================================="
if [ "$OVERALL_FAILED" -eq 0 ]; then
  echo "  ALL TEST SUITES PASSED"
else
  echo "  SOME TEST SUITES FAILED"
fi
echo "=========================================="

exit $OVERALL_FAILED
