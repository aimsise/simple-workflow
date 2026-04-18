#!/usr/bin/env bash
# PR F Task 13: [SW-CHECKPOINT] template consolidation tests.
#
# Asserts:
#   AC 13.1 — sw-checkpoint-template.md exists and contains the canonical
#             block + the literal context_advice sentence.
#   AC 13.2 — the literal "Intermediate tool outputs from this phase"
#             appears exactly once in the skills/ tree (in the template).
#   AC 13.3 — each of the 4 emitting skills (/create-ticket, /scout,
#             /impl, /ship) references the template file by relative path.
#   AC 13.4 — /audit and /plan2doc do NOT reference SW-CHECKPOINT (they
#             are review / plan delegates, not phase terminators).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=./test-helper.sh
source "$SCRIPT_DIR/test-helper.sh"

echo "=== [SW-CHECKPOINT] template consolidation tests (PR F Task 13) ==="
echo ""

TEMPLATE="$REPO_DIR/skills/create-ticket/references/sw-checkpoint-template.md"

# --- AC 13.1: template exists and carries canonical content ---
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$TEMPLATE" ]; then
  echo -e "  ${GREEN}PASS${NC} AC 13.1: sw-checkpoint-template.md exists"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC 13.1: sw-checkpoint-template.md is missing at $TEMPLATE"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$TEMPLATE" ] && grep -qF '## [SW-CHECKPOINT]' "$TEMPLATE"; then
  echo -e "  ${GREEN}PASS${NC} AC 13.1: template has canonical '## [SW-CHECKPOINT]' block"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC 13.1: template missing '## [SW-CHECKPOINT]' block"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [ -f "$TEMPLATE" ] && grep -qF 'Intermediate tool outputs from this phase remain in the main session context' "$TEMPLATE"; then
  echo -e "  ${GREEN}PASS${NC} AC 13.1: template has literal context_advice sentence"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC 13.1: template missing literal context_advice sentence"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- AC 13.2: "Intermediate tool outputs" appears exactly once in skills/ ---
# The literal sentence MUST live in exactly one file — the template.
TESTS_TOTAL=$((TESTS_TOTAL + 1))
INTERMEDIATE_HITS=$(grep -rl "Intermediate tool outputs" "$REPO_DIR/skills/" 2>/dev/null | wc -l | tr -d ' ')
if [ "$INTERMEDIATE_HITS" = "1" ]; then
  echo -e "  ${GREEN}PASS${NC} AC 13.2: 'Intermediate tool outputs' appears in exactly 1 file in skills/"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo -e "  ${RED}FAIL${NC} AC 13.2: 'Intermediate tool outputs' appears in $INTERMEDIATE_HITS files (expected 1)"
  grep -rl "Intermediate tool outputs" "$REPO_DIR/skills/" 2>/dev/null | sed 's/^/       /'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# --- AC 13.3: each of the 4 emitting skills references the template path ---
# Reference is by relative path "skills/create-ticket/references/sw-checkpoint-template.md".
for skill in create-ticket scout impl ship; do
  skill_file="$REPO_DIR/skills/$skill/SKILL.md"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ -f "$skill_file" ] && grep -qF 'sw-checkpoint-template.md' "$skill_file"; then
    echo -e "  ${GREEN}PASS${NC} AC 13.3: /$skill references sw-checkpoint-template.md"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} AC 13.3: /$skill does NOT reference sw-checkpoint-template.md"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

# --- AC 13.4 + AC 14.2: /audit and /plan2doc do NOT emit a SW-CHECKPOINT ---
# They reference the template doc to document "we do not emit", but must
# not have an inline SW-CHECKPOINT block. The concrete grep AC 14.2 uses
# is "no SW-CHECKPOINT string at all" in /plan2doc, and by extension the
# same is expected of /audit (pre-existing invariant).
for skill in audit plan2doc; do
  skill_file="$REPO_DIR/skills/$skill/SKILL.md"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [ -f "$skill_file" ] && ! grep -q 'SW-CHECKPOINT' "$skill_file"; then
    echo -e "  ${GREEN}PASS${NC} AC 13.4 / AC 14.2: /$skill does NOT reference SW-CHECKPOINT"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "  ${RED}FAIL${NC} AC 13.4 / AC 14.2: /$skill unexpectedly references SW-CHECKPOINT"
    grep -n 'SW-CHECKPOINT' "$skill_file" | sed 's/^/       /'
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

echo ""
print_summary
