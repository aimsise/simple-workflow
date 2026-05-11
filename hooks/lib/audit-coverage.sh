#!/usr/bin/env bash
# audit-coverage.sh — content-identity coverage block for /audit -> /ship gate.
#
# Sourced by:
#   - skills/audit/SKILL.md Step 4b (emit at audit time)
#   - skills/ship/SKILL.md Step 9 (check at ship time)
#
# Public contract (do not change without updating consumers above):
#
#   audit_coverage_emit <quality_round_path>
#     - Appends an HTML-comment-fenced YAML v1 block to <quality_round_path>
#       recording the base commit SHA, the working-state tree SHA, and the
#       per-file blob SHAs of every file in the audit's change set.
#     - Returns 0 on success or when the kill switch SW_AUDIT_COVERAGE=off
#       is set (in which case it is a NO-OP and writes nothing).
#     - Returns non-zero only on hard git failure.
#
#   audit_coverage_check <quality_round_path>
#     - Reads the v1 coverage block from <quality_round_path>, compares
#       recorded blob SHAs against the current HEAD content, and prints
#       one of:
#         "OK <N>"          (exit 0) — every commit-side change matches
#                                       the audit's coverage; N = entries
#         "STALE: <reason>" (exit 1) — at least one mismatch or uncovered
#                                       commit-side file
#         "LEGACY"          (exit 2) — block absent, or kill switch
#                                       SW_AUDIT_COVERAGE=off is set
#     - The caller (e.g. /ship Step 9) should treat LEGACY as a signal
#       to fall back to the legacy mtime heuristic, treat STALE as
#       gate-failure, and treat OK as gate-passed.
#
# Block format v1 (HTML-comment-fenced YAML inside the quality-round file):
#
#   <!-- audit-coverage v1
#   ---
#   base: <40-char SHA of HEAD at emit time>
#   tree: <40-char SHA of the working-state tree at emit time>
#   mode: pre-commit | post-commit
#   files:
#     - path: <relative path>
#       blob: <40-char blob SHA or __deleted__>
#       status: M | A | R | D
#   ---
#   -->
#
# The two `---` lines are YAML document separators that bracket the mapping,
# allowing the `<!--` and `-->` HTML fence lines to be parsed by `yq -p yaml`
# as standalone scalar documents (which are ignored by `.files | length`).
# `awk '/^<!-- audit-coverage v1/,/^-->$/'` extracts the full block including
# the fence lines so the result is directly pipeable to yq.
#
# Three-tier YAML parsing fallback (consistent with other hooks/lib helpers):
#   1. yq (mikefarah/yq v4) — preferred, schema-aware.
#   2. python3 + PyYAML — schema-aware fallback.
#   3. Pure-shell awk — extracts `path: <v>` / `blob: <v>` / `status: <v>` triples
#      from the comment-fenced block. Last resort under restricted PATH.
#
# Kill switch:
#   SW_AUDIT_COVERAGE=off  — emit becomes NO-OP returning 0; check returns
#                            "LEGACY" exit 2 without touching the file.
#                            Default behaviour is on.
#
# This file has no top-level side effects beyond function definitions, and
# does not set `set -euo pipefail` (caller's flags are respected, same
# convention as the other 5 helpers in hooks/lib/).

audit_coverage_emit() {
  local qr_path="$1"

  # Kill switch: NO-OP.
  if [ "${SW_AUDIT_COVERAGE:-on}" = "off" ]; then
    return 0
  fi

  if [ -z "$qr_path" ]; then
    return 1
  fi

  # Resolve current HEAD. If git fails or no commits, bail without writing.
  local base
  base=$(git rev-parse HEAD 2>/dev/null) || return 1
  if [ -z "$base" ]; then
    return 1
  fi

  # Detect pre-commit vs post-commit mode.
  local mode tree range porcelain
  porcelain=$(git status --porcelain 2>/dev/null) || porcelain=""

  if [ -n "$porcelain" ]; then
    # Pre-commit: working tree has staged or unstaged changes.
    tree=$(git stash create 2>/dev/null) || tree=""
    if [ -n "$tree" ]; then
      mode="pre-commit"
      range="HEAD"
    else
      # stash create returned empty (e.g. only untracked files) -- fall
      # through to post-commit semantics.
      mode="post-commit"
      tree=$(git rev-parse "HEAD^{tree}" 2>/dev/null) || tree=""
      range="HEAD~..HEAD"
    fi
  else
    # Post-commit: working tree clean. Use HEAD tree, change set = HEAD~..HEAD.
    mode="post-commit"
    tree=$(git rev-parse "HEAD^{tree}" 2>/dev/null) || tree=""
    range="HEAD~..HEAD"
  fi

  if [ -z "$tree" ]; then
    return 1
  fi

  # Enumerate change set. For post-commit mode with no HEAD~, fall back to
  # diffing against an empty tree (all files in HEAD become A).
  local diff_out
  if [ "$mode" = "post-commit" ] && ! git rev-parse "HEAD~" >/dev/null 2>&1; then
    # First commit: list every file as added.
    diff_out=$(git ls-tree -r --name-only HEAD 2>/dev/null \
      | awk '{print "A\t"$0}')
  else
    diff_out=$(git diff --name-status -M "$range" 2>/dev/null) || diff_out=""
  fi

  # Buffer the entries (TSV: status<TAB>path) and resolve each blob via the
  # captured tree, NOT against working tree files (so the recorded SHA is the
  # one that will be committed, not the on-disk file contents).
  local entries=""
  local count=0
  local line raw_status path_new path_old status_letter blob
  # Use a process substitution to avoid the subshell trap of `| while`.
  while IFS=$'\t' read -r raw_status path_new path_old; do
    [ -z "$raw_status" ] && continue
    # Renames arrive as `R<score>\t<old>\t<new>`; awk-style split gives us
    # path_new in $2 and path_old in $3 with the new path stored as the
    # "primary" we record.
    status_letter="${raw_status:0:1}"
    local recorded_path="$path_new"
    if [ "$status_letter" = "R" ] && [ -n "$path_old" ]; then
      # Rename: the *new* path is the second column, but git emits it as
      # `R<score>\t<old>\t<new>` so path_new is the OLD path with our
      # read pattern. Re-parse: with 3-field read, $2 is old, $3 is new.
      recorded_path="$path_old"
    fi

    if [ "$status_letter" = "D" ]; then
      blob="__deleted__"
    else
      blob=$(git ls-tree -r "$tree" -- "$recorded_path" 2>/dev/null | awk '{print $3; exit}')
      if [ -z "$blob" ]; then
        # Path not in tree (defensive); skip with __deleted__ marker.
        blob="__deleted__"
      fi
    fi

    entries+="  - path: ${recorded_path}"$'\n'
    entries+="    blob: ${blob}"$'\n'
    entries+="    status: ${status_letter}"$'\n'
    count=$((count + 1))
  done <<< "$diff_out"

  # Append the comment-fenced block to the quality-round file. The `---`
  # document separators bracket the inner mapping so the bare `<!--` and
  # `-->` HTML fence lines become standalone YAML scalar documents that
  # `yq -p yaml '.files | length'` ignores.
  {
    printf '\n'
    printf '<!-- audit-coverage v1\n'
    printf -- '---\n'
    printf 'base: %s\n' "$base"
    printf 'tree: %s\n' "$tree"
    printf 'mode: %s\n' "$mode"
    printf 'files:\n'
    if [ "$count" -gt 0 ]; then
      printf '%s' "$entries"
    fi
    printf -- '---\n'
    printf -- '-->\n'
  } >> "$qr_path"

  return 0
}

audit_coverage_check() {
  local qr_path="$1"

  # Kill switch: report LEGACY without inspecting the file.
  if [ "${SW_AUDIT_COVERAGE:-on}" = "off" ]; then
    printf 'LEGACY\n'
    return 2
  fi

  if [ -z "$qr_path" ] || [ ! -f "$qr_path" ]; then
    printf 'LEGACY\n'
    return 2
  fi

  # Extract the coverage block. awk emits the block including the opening
  # `<!-- audit-coverage v1` line and the closing `-->` line.
  local block
  block=$(awk '/^<!-- audit-coverage v1/,/^-->$/' "$qr_path")
  if [ -z "$block" ]; then
    printf 'LEGACY\n'
    return 2
  fi

  # Strip the comment fences and the YAML document separators (`---`) so the
  # interior mapping can be parsed by yq / python3+PyYAML / awk as a single
  # YAML document. The fence pattern is:
  #   <!-- audit-coverage v1   (line 1 — stripped)
  #   ---                       (YAML doc separator — stripped)
  #   <mapping body>
  #   ---                       (YAML doc separator — stripped)
  #   -->                       (closing fence — terminates awk)
  local yaml_body
  yaml_body=$(printf '%s\n' "$block" \
    | awk 'NR==1{next} /^-->$/{exit} /^---[[:space:]]*$/{next} {print}')

  # Parse into three parallel arrays: paths[], blobs[], statuses[], plus base.
  local base="" mode=""
  local -a cov_paths=() cov_blobs=() cov_statuses=()
  local parsed=0

  # Tier 1: yq (mikefarah v4).
  if [ "$parsed" -eq 0 ] && command -v yq >/dev/null 2>&1; then
    local yq_json
    yq_json=$(printf '%s\n' "$yaml_body" | yq -p yaml -o json 2>/dev/null) || yq_json=""
    if [ -n "$yq_json" ] && command -v jq >/dev/null 2>&1; then
      base=$(printf '%s' "$yq_json" | jq -r '.base // ""' 2>/dev/null) || base=""
      mode=$(printf '%s' "$yq_json" | jq -r '.mode // ""' 2>/dev/null) || mode=""
      local files_n p b s i
      files_n=$(printf '%s' "$yq_json" | jq -r '.files | length' 2>/dev/null) || files_n=0
      if [ -n "$files_n" ] && [ "$files_n" != "null" ] && [ "$files_n" -ge 0 ] 2>/dev/null; then
        i=0
        while [ "$i" -lt "$files_n" ]; do
          p=$(printf '%s' "$yq_json" | jq -r ".files[$i].path // \"\"" 2>/dev/null)
          b=$(printf '%s' "$yq_json" | jq -r ".files[$i].blob // \"\"" 2>/dev/null)
          s=$(printf '%s' "$yq_json" | jq -r ".files[$i].status // \"\"" 2>/dev/null)
          cov_paths+=("$p")
          cov_blobs+=("$b")
          cov_statuses+=("$s")
          i=$((i + 1))
        done
        parsed=1
      fi
    fi
  fi

  # Tier 2: python3 + PyYAML.
  if [ "$parsed" -eq 0 ] && command -v python3 >/dev/null 2>&1 \
      && python3 -c 'import yaml' >/dev/null 2>&1; then
    local py_out
    py_out=$(YAML_BODY="$yaml_body" python3 - <<'PYEOF'
import os, sys
try:
    import yaml
except ImportError:
    sys.exit(1)
body = os.environ.get('YAML_BODY', '')
try:
    data = yaml.safe_load(body) or {}
except Exception:
    sys.exit(1)
if not isinstance(data, dict):
    sys.exit(1)
print('BASE\t' + str(data.get('base', '')))
print('MODE\t' + str(data.get('mode', '')))
files = data.get('files') or []
if isinstance(files, list):
    for f in files:
        if isinstance(f, dict):
            print('FILE\t{0}\t{1}\t{2}'.format(
                str(f.get('path', '')),
                str(f.get('blob', '')),
                str(f.get('status', '')),
            ))
PYEOF
) || py_out=""
    if [ -n "$py_out" ]; then
      local py_line py_kind py_a py_b py_c
      while IFS=$'\t' read -r py_kind py_a py_b py_c; do
        case "$py_kind" in
          BASE) base="$py_a" ;;
          MODE) mode="$py_a" ;;
          FILE)
            cov_paths+=("$py_a")
            cov_blobs+=("$py_b")
            cov_statuses+=("$py_c")
            ;;
        esac
      done <<< "$py_out"
      parsed=1
    fi
  fi

  # Tier 3: pure-shell awk. Extracts `base:`, `mode:`, and each
  # `- path: ... blob: ... status: ...` triple from the YAML body.
  if [ "$parsed" -eq 0 ]; then
    local awk_out
    awk_out=$(printf '%s\n' "$yaml_body" | awk '
      BEGIN { in_files = 0; have_path = 0 }
      /^base:[[:space:]]/ {
        v = $0; sub(/^base:[[:space:]]+/, "", v); print "BASE\t" v; next
      }
      /^mode:[[:space:]]/ {
        v = $0; sub(/^mode:[[:space:]]+/, "", v); print "MODE\t" v; next
      }
      /^files:/ { in_files = 1; next }
      in_files == 1 && /^[[:space:]]*-[[:space:]]+path:[[:space:]]/ {
        if (have_path == 1) {
          print "FILE\t" cur_path "\t" cur_blob "\t" cur_status
        }
        cur_path = $0
        sub(/^[[:space:]]*-[[:space:]]+path:[[:space:]]+/, "", cur_path)
        cur_blob = ""; cur_status = ""
        have_path = 1
        next
      }
      in_files == 1 && /^[[:space:]]+blob:[[:space:]]/ {
        cur_blob = $0
        sub(/^[[:space:]]+blob:[[:space:]]+/, "", cur_blob)
        next
      }
      in_files == 1 && /^[[:space:]]+status:[[:space:]]/ {
        cur_status = $0
        sub(/^[[:space:]]+status:[[:space:]]+/, "", cur_status)
        next
      }
      END {
        if (have_path == 1) {
          print "FILE\t" cur_path "\t" cur_blob "\t" cur_status
        }
      }
    ')
    local aw_kind aw_a aw_b aw_c
    while IFS=$'\t' read -r aw_kind aw_a aw_b aw_c; do
      case "$aw_kind" in
        BASE) base="$aw_a" ;;
        MODE) mode="$aw_a" ;;
        FILE)
          cov_paths+=("$aw_a")
          cov_blobs+=("$aw_b")
          cov_statuses+=("$aw_c")
          ;;
      esac
    done <<< "$awk_out"
  fi

  if [ -z "$base" ]; then
    # Couldn't parse base SHA -- treat as LEGACY rather than misleading STALE.
    printf 'LEGACY\n'
    return 2
  fi

  # Build the commit-side change set: every file changed between base..HEAD.
  local commit_changes
  commit_changes=$(git diff --name-only -M "${base}..HEAD" 2>/dev/null) || commit_changes=""

  # If the base equals HEAD (audit ran post-commit with no further commits),
  # there will be no diff. Compare against the recorded entries directly.
  local total_cov=${#cov_paths[@]}

  # Index coverage entries by path for lookup.
  local cov_blob_for cov_status_for
  local idx=0
  declare -A cov_idx=()
  while [ "$idx" -lt "$total_cov" ]; do
    cov_idx["${cov_paths[$idx]}"]=$idx
    idx=$((idx + 1))
  done

  # 1. For each commit-side file: must be covered AND blob must match.
  local commit_file head_blob audit_blob audit_status reason
  local short_audit short_head
  if [ -n "$commit_changes" ]; then
    while IFS= read -r commit_file; do
      [ -z "$commit_file" ] && continue
      head_blob=$(git rev-parse "HEAD:$commit_file" 2>/dev/null) || head_blob="__deleted__"
      if [ -z "${cov_idx[$commit_file]+x}" ]; then
        printf 'STALE: uncovered %s\n' "$commit_file"
        return 1
      fi
      audit_blob="${cov_blobs[${cov_idx[$commit_file]}]}"
      if [ "$audit_blob" != "$head_blob" ]; then
        short_audit="${audit_blob:0:12}"
        short_head="${head_blob:0:12}"
        printf 'STALE: %s audit=%s head=%s\n' "$commit_file" "$short_audit" "$short_head"
        return 1
      fi
    done <<< "$commit_changes"
  fi

  # 2. For each coverage entry: validate that the recorded state still holds.
  #    This catches deleted-file-handling sub-case (b) where the coverage
  #    block recorded `__deleted__` but the commit resurrected the file
  #    (the file is then NOT in the base..HEAD diff because the audit base
  #    already had it, but the audit captured an intent-to-delete that the
  #    commit did not honour).
  idx=0
  while [ "$idx" -lt "$total_cov" ]; do
    audit_blob="${cov_blobs[$idx]}"
    audit_status="${cov_statuses[$idx]}"
    local cov_path="${cov_paths[$idx]}"
    head_blob=$(git rev-parse "HEAD:$cov_path" 2>/dev/null) || head_blob="__deleted__"
    if [ "$audit_blob" != "$head_blob" ]; then
      short_audit="${audit_blob:0:12}"
      short_head="${head_blob:0:12}"
      if [ "$audit_blob" = "__deleted__" ]; then
        printf 'STALE: %s audit=__deleted__ head=%s\n' "$cov_path" "$short_head"
      else
        printf 'STALE: %s audit=%s head=%s\n' "$cov_path" "$short_audit" "$short_head"
      fi
      return 1
    fi
    idx=$((idx + 1))
  done

  printf 'OK %d\n' "$total_cov"
  return 0
}

export -f audit_coverage_emit
export -f audit_coverage_check
