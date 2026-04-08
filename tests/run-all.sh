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
    echo "Running $(basename "$test_file")..."
    echo ""
    if ! bash "$test_file"; then
      OVERALL_FAILED=1
    fi
    echo ""
  fi
done

echo "=========================================="
if [ "$OVERALL_FAILED" -eq 0 ]; then
  echo "  ALL TEST SUITES PASSED"
else
  echo "  SOME TEST SUITES FAILED"
fi
echo "=========================================="

exit $OVERALL_FAILED
