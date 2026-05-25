#!/usr/bin/env bash
# migrate-state-schema.sh — non-destructive v7 -> v8 migrator for
# `autopilot-state.yaml`. Idempotent on already-v8 input.
#
# Schema reference: docs/state-schema.md
#
# Usage:
#   bash tools/migrate-state-schema.sh --in <path> --out <path>
#   bash tools/migrate-state-schema.sh --help
#
# Steps performed (see docs/state-schema.md "Migration guidance"):
#   1. Drop legacy total_tickets, completed_tickets, failed_tickets,
#      skipped_tickets, boundary.
#   2. Add processing_order from tickets[].logical_id in document order
#      when missing.
#   3. Add human_overrides: [], kb_overrides: [], decisions_made: [],
#      manual_bash_fallbacks: [] when missing.
#   4. Add pr_url: null and failure_reason: null to every tickets[]
#      entry that does not already carry those keys.
#   5. Rewrite each ticket_mapping value that is a basename (no '/')
#      into the matching tickets[].ticket_dir fullpath.
#
# Dependency fallback (project convention): yq (mikefarah v4) preferred,
# python3 + PyYAML second, then fail-with-warning.

set -euo pipefail

print_help() {
  cat <<'EOF'
migrate-state-schema.sh — non-destructive v7 -> v8 migrator for autopilot-state.yaml

Usage:
  bash tools/migrate-state-schema.sh --in <path> --out <path>
  bash tools/migrate-state-schema.sh --help

Options:
  --in   <path>   Input autopilot-state.yaml (v7 or already-v8).
  --out  <path>   Output path (canonical v8). Required; in-place edits are
                  not supported by design.
  --help          Print this message and exit 0.

Behaviour:
  - Drops legacy fields (total_tickets, completed_tickets, failed_tickets,
    skipped_tickets, boundary) if present.
  - Adds processing_order from tickets[].logical_id when missing.
  - Defaults human_overrides, kb_overrides, decisions_made,
    manual_bash_fallbacks to empty arrays when missing.
  - Defaults tickets[].pr_url and tickets[].failure_reason to null when
    missing.
  - Rewrites basename ticket_mapping values into tickets[].ticket_dir
    fullpaths.
  - Idempotent: running this on an already-v8 file produces no diff.
EOF
}

err() {
  printf '[migrate-state-schema] %s\n' "$*" >&2
}

have() {
  command -v "$1" >/dev/null 2>&1
}

IN_PATH=""
OUT_PATH=""

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      print_help
      exit 0
      ;;
    --in)
      IN_PATH="${2:-}"
      shift 2 || { err "--in requires a value"; exit 2; }
      ;;
    --out)
      OUT_PATH="${2:-}"
      shift 2 || { err "--out requires a value"; exit 2; }
      ;;
    *)
      err "unknown argument: $1"
      print_help >&2
      exit 2
      ;;
  esac
done

if [ -z "$IN_PATH" ] || [ -z "$OUT_PATH" ]; then
  err "both --in and --out are required"
  print_help >&2
  exit 2
fi
if [ ! -f "$IN_PATH" ]; then
  err "input file not found: $IN_PATH"
  exit 1
fi

# ---------------------------------------------------------------------------
# Tier 2 helper: python3 + PyYAML. We always prefer this when available because
# YAML structural edits are clearer in Python than in yq's expression syntax,
# and the resulting normalised emission is deterministic regardless of the
# host yq version.
# ---------------------------------------------------------------------------
migrate_with_python3() {
  python3 - "$IN_PATH" "$OUT_PATH" <<'PY'
import sys
import yaml


def main(in_path: str, out_path: str) -> int:
    with open(in_path, "r", encoding="utf-8") as fh:
        doc = yaml.safe_load(fh) or {}

    if not isinstance(doc, dict):
        print(
            "[migrate-state-schema] root document is not a mapping; refusing to migrate",
            file=sys.stderr,
        )
        return 1

    # Step 1: drop legacy aggregates and boundary.
    for legacy in (
        "total_tickets",
        "completed_tickets",
        "failed_tickets",
        "skipped_tickets",
        "boundary",
    ):
        doc.pop(legacy, None)

    # Normalise tickets[] into a list, preserving order. The parser library
    # tolerates the map form for read; the migrator emits the canonical
    # list form.
    tickets = doc.get("tickets")
    if isinstance(tickets, dict):
        tickets_list = []
        for key, entry in tickets.items():
            if not isinstance(entry, dict):
                entry = {}
            entry.setdefault("logical_id", key)
            tickets_list.append(entry)
        tickets = tickets_list
    elif not isinstance(tickets, list):
        tickets = []
    doc["tickets"] = tickets

    # Step 2: add processing_order from tickets[].logical_id when missing.
    if "processing_order" not in doc or not isinstance(doc.get("processing_order"), list) or not doc.get("processing_order"):
        order = []
        for entry in tickets:
            if isinstance(entry, dict):
                lid = entry.get("logical_id")
                if isinstance(lid, str) and lid:
                    order.append(lid)
        if order or "processing_order" not in doc:
            doc["processing_order"] = order

    # Step 3: default empty arrays.
    for key in ("human_overrides", "kb_overrides", "decisions_made", "manual_bash_fallbacks"):
        if key not in doc or doc.get(key) is None:
            doc[key] = []

    # Step 4: default null pr_url / failure_reason on tickets[].
    for entry in tickets:
        if not isinstance(entry, dict):
            continue
        if "pr_url" not in entry:
            entry["pr_url"] = None
        if "failure_reason" not in entry:
            entry["failure_reason"] = None

    # Step 5: rewrite basename ticket_mapping values into fullpaths.
    mapping = doc.get("ticket_mapping")
    if isinstance(mapping, dict):
        # Build a logical_id -> fullpath lookup from tickets[].
        lookup = {}
        for entry in tickets:
            if not isinstance(entry, dict):
                continue
            lid = entry.get("logical_id")
            tdir = entry.get("ticket_dir")
            if isinstance(lid, str) and isinstance(tdir, str) and tdir:
                lookup[lid] = tdir
        for lid, value in list(mapping.items()):
            if not isinstance(value, str):
                continue
            if "/" in value:
                continue  # already a fullpath
            replacement = lookup.get(lid)
            if replacement:
                mapping[lid] = replacement
            else:
                print(
                    "[migrate-state-schema] WARN: could not resolve fullpath for "
                    f"ticket_mapping[{lid}] = {value}",
                    file=sys.stderr,
                )

    with open(out_path, "w", encoding="utf-8") as fh:
        yaml.safe_dump(doc, fh, sort_keys=False, allow_unicode=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
PY
}

# ---------------------------------------------------------------------------
# Tier 1: prefer python3 + PyYAML when present (clearer YAML edits, stable
# output). Fall back to yq when python3+PyYAML is unavailable. Final tier
# is a hard error so silent corruption cannot occur.
# ---------------------------------------------------------------------------
if have python3 && python3 -c 'import yaml' >/dev/null 2>&1; then
  migrate_with_python3
  exit 0
fi

if have yq; then
  # yq tier: do the same structural edits with yq -P normalisation. Less
  # surgical than the python tier but adequate for environments without
  # PyYAML.
  TMP="$(mktemp)"
  trap 'rm -f "$TMP"' EXIT

  # Step 1: drop legacy fields.
  yq -P 'del(.total_tickets, .completed_tickets, .failed_tickets, .skipped_tickets, .boundary)' "$IN_PATH" > "$TMP"

  # Step 2: add processing_order from tickets[].logical_id when missing or empty.
  # yq's `// []` does not detect existing empty arrays as missing, so we
  # branch explicitly.
  yq -P '
    .tickets = (.tickets // []) |
    .processing_order = (
      if (.processing_order // null) == null or (.processing_order | length) == 0
      then [.tickets[] | .logical_id]
      else .processing_order
      end
    )
  ' "$TMP" > "$TMP.po" && mv "$TMP.po" "$TMP"

  # Step 3: default empty arrays.
  yq -P '
    .human_overrides = (.human_overrides // []) |
    .kb_overrides = (.kb_overrides // []) |
    .decisions_made = (.decisions_made // []) |
    .manual_bash_fallbacks = (.manual_bash_fallbacks // [])
  ' "$TMP" > "$TMP.def" && mv "$TMP.def" "$TMP"

  # Step 4: default null pr_url / failure_reason on tickets[].
  yq -P '
    .tickets = [.tickets[] |
      .pr_url = (.pr_url // null) |
      .failure_reason = (.failure_reason // null)
    ]
  ' "$TMP" > "$TMP.tk" && mv "$TMP.tk" "$TMP"

  # Step 5: rewrite basename ticket_mapping values. yq cannot easily express
  # a per-key lookup, so we shell out to a small inline awk replacement that
  # uses the tickets list as a lookup. Read the lookup first.
  if yq -e '.ticket_mapping | type == "!!map"' "$TMP" >/dev/null 2>&1; then
    # Collect logical_id -> ticket_dir pairs.
    while IFS=$'\t' read -r lid tdir; do
      [ -n "$lid" ] || continue
      [ -n "$tdir" ] || continue
      cur="$(yq -r ".ticket_mapping.\"${lid}\" // \"\"" "$TMP")"
      case "$cur" in
        */*) ;;  # already a fullpath
        "") ;;
        *)
          yq -i -P ".ticket_mapping.\"${lid}\" = \"${tdir}\"" "$TMP"
          ;;
      esac
    done < <(yq -r '.tickets[] | [.logical_id, .ticket_dir] | @tsv' "$TMP" 2>/dev/null)
  fi

  mv "$TMP" "$OUT_PATH"
  trap - EXIT
  exit 0
fi

err "neither python3+PyYAML nor yq is available; cannot migrate"
exit 1
