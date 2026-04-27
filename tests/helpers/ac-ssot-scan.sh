#!/usr/bin/env bash
# ac-ssot-scan.sh — AC SSoT (Single Source of Truth) scanner.
#
# Walks a brief tree (`.simple-workflow/backlog/{active,product_backlog,done}/<slug>/<ticket-id>/`)
# and verifies that every `plan.md` is a verbatim copy of its sibling `ticket.md`'s
# `## Acceptance Criteria` section, after stripping leading list markers
# `- `, `* `, or `[0-9]+. `.
#
# Stdout (success): the literal line `ac-ssot: synced`.
# Stderr (failure): one line per offending pair containing both the plan.md
#                   path AND the corresponding ticket.md path; one line per
#                   plan.md that lacks the `## Acceptance Criteria` heading
#                   entirely, containing the plan.md path.
# Exit:  0 on full sync (including empty trees with no pairs and empty-AC pairs);
#        non-zero when any drift is detected.
#
# Usage:  ac-ssot-scan.sh <root>
#         where <root> is the directory that contains
#         `backlog/{active,product_backlog,done}/<slug>/<ticket-id>/`.
#         Typically `<repo>/.simple-workflow`.

set -uo pipefail

ROOT="${1:-}"
if [ -z "$ROOT" ]; then
  echo "usage: ac-ssot-scan.sh <root>" >&2
  exit 2
fi

if [ ! -d "$ROOT" ]; then
  # An entirely missing tree counts as "no pairs" — synced by definition.
  echo "ac-ssot: synced"
  exit 0
fi

# Extract the body of the `## Acceptance Criteria` section, with leading list
# markers stripped, one normalized item per line.
extract_ac_items() {
  local file="$1"
  awk '
    BEGIN { in_ac = 0 }
    /^##[[:space:]]+Acceptance Criteria[[:space:]]*$/ {
      in_ac = 1
      next
    }
    in_ac && /^##[[:space:]]/ {
      in_ac = 0
    }
    in_ac { print }
  ' "$file" | awk '
    {
      line = $0
      # Strip CR if present (CRLF tolerance).
      sub(/\r$/, "", line)
      # Match a leading list marker: optional whitespace, then `-`, `*`, or
      # `<digits>.`, then at least one whitespace character.
      if (match(line, /^[[:space:]]*(-|\*|[0-9]+\.)[[:space:]]+/)) {
        body = substr(line, RSTART + RLENGTH)
        print body
      }
      # Lines that are not list items (blank lines, prose) are dropped.
    }
  '
}

# Returns 0 if the plan.md has the `## Acceptance Criteria` heading.
has_ac_heading() {
  local file="$1"
  grep -qE '^##[[:space:]]+Acceptance Criteria[[:space:]]*$' "$file"
}

EXIT_CODE=0

# Iterate over every plan.md under the three backlog buckets.
for bucket in active product_backlog done; do
  bucket_dir="$ROOT/backlog/$bucket"
  [ -d "$bucket_dir" ] || continue

  while IFS= read -r -d '' plan_md; do
    ticket_md="$(dirname "$plan_md")/ticket.md"

    # No ticket.md to compare against — out of scope for the SSoT guard.
    [ -f "$ticket_md" ] || continue

    if ! has_ac_heading "$plan_md"; then
      echo "ac-ssot: drift (missing-heading): plan=$plan_md ticket=$ticket_md" >&2
      EXIT_CODE=1
      continue
    fi

    plan_items_file=$(mktemp)
    ticket_items_file=$(mktemp)
    extract_ac_items "$plan_md" >"$plan_items_file"
    extract_ac_items "$ticket_md" >"$ticket_items_file"

    plan_count=$(wc -l <"$plan_items_file" | tr -d ' ')
    ticket_count=$(wc -l <"$ticket_items_file" | tr -d ' ')

    if [ "$plan_count" != "$ticket_count" ]; then
      echo "ac-ssot: drift (count-mismatch plan=$plan_count ticket=$ticket_count): plan=$plan_md ticket=$ticket_md" >&2
      EXIT_CODE=1
    elif ! cmp -s "$plan_items_file" "$ticket_items_file"; then
      echo "ac-ssot: drift (body-differs): plan=$plan_md ticket=$ticket_md" >&2
      EXIT_CODE=1
    fi

    rm -f "$plan_items_file" "$ticket_items_file"
  done < <(find "$bucket_dir" -mindepth 3 -maxdepth 3 -type f -name plan.md -print0 2>/dev/null)
done

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "ac-ssot: synced"
fi

exit "$EXIT_CODE"
