#!/usr/bin/env bash
# Fixture: legacy-no-block
# qr.md contains review text only, no coverage block. Expected: LEGACY, exit 2.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
HELPER="$REPO_ROOT/hooks/lib/audit-coverage.sh"

WORKDIR=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$WORKDIR'" EXIT

cd "$WORKDIR" || { echo "FAIL: cannot cd to workdir"; exit 1; }

QR="$WORKDIR/qr.md"
{
  echo "# Quality Round 1"
  echo ""
  echo "**Status**: PASS"
  echo "**Summary**: legacy file without coverage block"
} > "$QR"

# shellcheck disable=SC1090
source "$HELPER"

set +e
OUT=$(audit_coverage_check "$QR")
RC=$?
set -e

if [ "$RC" -eq 2 ] && [ "$OUT" = "LEGACY" ]; then
  echo "PASS"
  exit 0
fi

echo "FAIL: rc=$RC out='$OUT' (expected LEGACY exit 2)"
exit 1
