#!/usr/bin/env bash
# build-standalone-skill.sh — generate a self-contained, host-neutral Agent
# Skill (SKILL.md + references/) from this plugin's sources, named
# `create-ticket` by default or any valid skill name given with --name.
#
# The output needs no plugin, no hooks and no custom agent files, and
# names tools by role, never by a host's tool name: drop it into the skill
# root the host reads (.github/skills/, .claude/skills/ or .agents/skills/)
# and invoke it by name. The output is never committed; correctness is
# enforced by the exit audit below and by tests/test-standalone-skill-build.sh.
#
# Usage:
#   bash tools/build-standalone-skill.sh --out <dir> [--name <skill-name>] [--src <dir>] [--force]
#   bash tools/build-standalone-skill.sh --help
#
# Inputs (tools/standalone-skill/, see its README.md):
#   files.tsv            shipped file map (destination <TAB> source, or "-"
#                        for a file whose whole content is an append override)
#   drop-sections.txt    sections removed by exact heading (scoped)
#   overrides/*.md       replacement / inserted section bodies
#   drop-paragraphs.txt  paragraphs / list items / table rows removed by ERE
#   substitutions.tsv    sed -E substitutions, applied in file order
#   denylist.txt         exit-audit EREs (any hit fails the build)
#   tool-vocabulary.txt  host tool names (allow) and foreign tool names (deny)
#
# Transform layers, in this order, per shipped file:
#   1. section drop / override by heading
#   2. paragraph drops by anchor ERE
#   3. token substitutions
#   4. exit audit over the whole generated tree (including the variant
#      check: no other form of the canonical name that the check covers)
#   5. with --name: the canonical name `create-ticket` is replaced by the
#      chosen name in every generated file, then the name audit runs
# Every manifest entry must match at least once in its scope; a stale entry
# fails the build so the manifests never rot silently. The manifests always
# carry the canonical name: layers 1-4 build and audit the canonical text,
# and the chosen name is applied only to a tree whose exit audit is clean.
#
# The tree is built and audited in a staging directory outside <out>, and
# <out>/<name> is created or replaced only when every audit is clean, so a
# failed build leaves the previous skill as it was. --force replaces only a
# directory that holds a skill this generator wrote.
#
# Tooling: bash + sed/awk/grep only (BSD and GNU compatible, LC_ALL=C).

set -euo pipefail
export LC_ALL=C

print_help() {
  cat <<'EOF'
build-standalone-skill.sh — generate the standalone, host-neutral ticket-creation skill

Usage:
  bash tools/build-standalone-skill.sh --out <dir> [--name <skill-name>] [--src <dir>] [--force]
  bash tools/build-standalone-skill.sh --help

Options:
  --out <dir>          Output directory. The skill is written to <dir>/<skill-name>/.
                       It is built and audited in a staging directory under
                       $TMPDIR (or /tmp) first, and <dir>/<skill-name>/ is
                       created or replaced only when every audit is clean.
  --name <skill-name>  Name of the generated skill (default: create-ticket): its
                       directory name, its frontmatter name and every place the
                       skill names itself (invocation, skill-root paths, scratch
                       directory, ERROR: messages). 1 to 64 lowercase ASCII
                       letters, digits and hyphens, no hyphen first, last or
                       next to another (^[a-z0-9]+(-[a-z0-9]+)*$). Refused: the
                       names the skill's text uses for its roles (planner,
                       researcher, decomposer, ticket-evaluator, evaluator,
                       orchestrator), a name YAML reads as a number, boolean,
                       null or date (123, true, yes, 1e3, 2024-01-01,
                       2024-1-1), and a host tool name the exit audit rejects
                       in backticks (bash, view). Not refused: a name that
                       resembles a word of the source plugin, a command or
                       folder a host reserves, or a product (hooks, test-plan,
                       home); check the host's documentation first. The skill
                       prints the name as the subject of its own
                       "ERROR: <name> ..." lines and writes it as `<name>` and
                       /<name>, so a name that is also an ordinary word of its
                       text (source, destination, findings) or a command it
                       runs (git, grep) reads ambiguously there. Such names
                       are accepted; the choice is the user's.
  --src <dir>          Plugin source root to read (default: this repository's
                       root). Manifests are always read from tools/standalone-skill/
                       next to this script. Its short git commit is stamped into
                       the frontmatter as metadata.source-commit ("unknown"
                       outside git).
  --force              Replace a non-empty <dir>/<skill-name>/ that holds a skill
                       this generator wrote (the frontmatter of its SKILL.md
                       holds the line
                       "  source: generated skill; do not edit by hand"). Any
                       other non-empty directory, a directory that cannot be
                       read, and a file or link that is not a directory, is
                       refused with or without --force. A symbolic link to a
                       directory is replaced by a real directory; its target
                       is not touched. Nothing else under <dir> is ever
                       removed.
  --help               Print this message and exit 0.

Exit status:
  0  skill generated; the exit audit (and with --name, the name audit) is clean
  1  exit audit or name audit failed, or a manifest entry is stale (details
     on stderr); the failed tree is kept in the staging directory the message
     names, and <dir>/<skill-name>/ is left as it was
  2  usage error (an invalid or reserved --name included), missing source
     file, malformed manifest row (a substitution target glued to its
     replacement), refused overwrite, or an output or temporary directory
     that cannot be created or written; no skill directory and no staging
     directory is left behind (an --out directory the run created stays) and
     <dir>/<skill-name>/ is left as it was
EOF
}

err() {
  printf '[build-standalone-skill] %s\n' "$*" >&2
}

# Every directory is resolved with CDPATH cleared: with an exported CDPATH,
# cd would resolve a relative path through it and print the path it chose.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="$SCRIPT_DIR/standalone-skill"
SRC_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)"
OUT_DIR=""
FORCE=0
# The canonical name: every manifest, override and audit rule is written
# with it; --name replaces it in the generated tree after the exit audit.
CANON_NAME="create-ticket"
NAME="$CANON_NAME"

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) print_help; exit 0 ;;
    --out) [ $# -ge 2 ] || { err "--out requires a value"; exit 2; }; OUT_DIR="$2"; shift 2 ;;
    --name) [ $# -ge 2 ] || { err "--name requires a value"; exit 2; }; NAME="$2"; shift 2 ;;
    --src) [ $# -ge 2 ] || { err "--src requires a value"; exit 2; }; SRC_ROOT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    *) err "unknown argument: $1 (see --help)"; exit 2 ;;
  esac
done

# --- name validation (before any filesystem action) ----------------------------

NAME_RULE='a skill name is 1 to 64 lowercase ASCII letters, digits and hyphens, with no hyphen first, last or next to another (^[a-z0-9]+(-[a-z0-9]+)*$)'
# The name as printed in a message: control and non-ASCII bytes shown as '?'.
NAME_SHOWN="$(printf '%s' "$NAME" | tr -c '[:print:]' '?')"
case "$NAME" in
  ''|*[!a-z0-9-]*|-*|*-|*--*) err "invalid --name '$NAME_SHOWN': $NAME_RULE"; exit 2 ;;
esac
[ "${#NAME}" -le 64 ] || { err "invalid --name '$NAME_SHOWN' (${#NAME} characters): $NAME_RULE"; exit 2; }
# The frontmatter writes the name as a plain YAML scalar, so a name a YAML
# reader resolves to a number, a boolean, null or a date (YAML 1.1 or 1.2) is
# refused: the frontmatter name would not be the name.
# (A date with one-digit month or day is included: some YAML readers load
# 2024-1-1 as a date.)
if grep -qxE '(null|true|false|yes|no|on|off|y|n|[0-9]+|0x[0-9a-f]+|0o[0-7]+|0b[01]+|[0-9]+e-?[0-9]+|[0-9]{4}-[0-9]{1,2}-[0-9]{1,2})' <<<"$NAME"; then
  err "invalid --name '$NAME': a YAML reader takes it for a number, a boolean, null or a date, not a string, so the frontmatter name of SKILL.md would not be the name"
  exit 2
fi
case "$NAME" in
  planner|researcher|decomposer|ticket-evaluator|evaluator|orchestrator)
    err "reserved --name '$NAME': planner, researcher, decomposer, ticket-evaluator, evaluator and orchestrator are the names the skill's text uses for its roles (the orchestrator that runs it and the roles it spawns), so a skill of that name could not be told apart from the role"
    exit 2 ;;
esac

[ -n "$OUT_DIR" ] || { err "--out is required (see --help)"; exit 2; }
[ -d "$SRC_ROOT" ] || { err "--src is not a directory: $SRC_ROOT"; exit 2; }
SRC_ROOT="$(CDPATH='' cd -- "$SRC_ROOT" && pwd)"
[ -d "$MANIFEST_DIR" ] || { err "manifest directory missing: $MANIFEST_DIR"; exit 2; }

# Read a manifest, dropping comment and blank lines.
manifest_lines() {
  grep -vE '^[[:space:]]*(#|$)' "$1" || true
}

# Foreign tool names of the exit audit (tool-vocabulary.txt "deny <Name>").
DENY_TOOLS="$(manifest_lines "$MANIFEST_DIR/tool-vocabulary.txt" | awk '$1 == "deny" {printf "%s%s", sep, $2; sep = "|"}')"
# shellcheck disable=SC2016  # literal backticks, no expansion intended
DENY_TOOLS_RE='`('"$DENY_TOOLS"')(\([^`]*\))?`'

# A name that the exit audit's foreign-tool-name rule would reject: the probe
# holds the name in each context it takes in the generated tree, and a probe
# line the rule matches with the name, but not with the canonical name,
# refuses the name. The name audit after the rename is the backstop for a
# context the probe does not hold. The denylist is not run on the name: it
# finds vocabulary leaked from the plugin into the text, the canonical text
# has passed it, and a row that only the chosen name trips (hooks, test-plan,
# home) is a resemblance, not a leak.
name_probe() {
  printf '%s\n' "/$1" "\`$1\`" ".claude/skills/$1/" ".local/$1-scratch/run.XXXXXX" \
    "ERROR: $1 write failed" "the $1 skill" "# $1" "name: $1"
}
# probe_findings LABEL ERE — one line per probe line the ERE matches with the
# name and not with the canonical name.
probe_findings() {
  local hc hn ln
  hc=" $(name_probe "$CANON_NAME" | { grep -nE -- "$2" || true; } | cut -d: -f1 | tr '\n' ' ')"
  hn="$(name_probe "$NAME" | { grep -nE -- "$2" || true; } | cut -d: -f1)"
  for ln in $hn; do
    case "$hc" in *" $ln "*) continue ;; esac
    printf '%s matches "%s"\n' "$1" "$(name_probe "$NAME" | sed -n "${ln}p")"
  done
}
if [ "$NAME" != "$CANON_NAME" ] && [ -n "$DENY_TOOLS" ]; then
  PROBE_FAIL="$(probe_findings "foreign tool name rule (a deny row of tool-vocabulary.txt)" "$DENY_TOOLS_RE")"
  if [ -n "$PROBE_FAIL" ]; then
    err "invalid --name '$NAME': the generated text would fail the exit audit with this name:"
    printf '%s\n' "$PROBE_FAIL" | sed 's/^/  /' >&2
    exit 2
  fi
fi

PLUGIN_JSON="$SRC_ROOT/.claude-plugin/plugin.json"
[ -f "$PLUGIN_JSON" ] || { err "missing $PLUGIN_JSON"; exit 2; }
SOURCE_VERSION="$(sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$PLUGIN_JSON" | head -n 1)"
[ -n "$SOURCE_VERSION" ] || { err "cannot read version from $PLUGIN_JSON"; exit 2; }
# Short commit of the source tree; "unknown" when --src is not a git
# repository or git is not on PATH.
SOURCE_COMMIT=""
if command -v git >/dev/null 2>&1; then
  SOURCE_COMMIT="$(git -C "$SRC_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
fi
printf '%s\n' "$SOURCE_COMMIT" | grep -qxE '[0-9a-f]{7,40}' || SOURCE_COMMIT="unknown"

mkdir -p -- "$OUT_DIR" || { err "cannot create --out $OUT_DIR"; exit 2; }
OUT_ABS="$(CDPATH='' cd -- "$OUT_DIR" && pwd)" || { err "cannot enter --out $OUT_DIR"; exit 2; }
OUT_DIR="$OUT_ABS"
# FINAL is checked before the build and changed only after a clean audit.
FINAL="$OUT_DIR/$NAME"
# Every tree this generator wrote holds this line in the frontmatter of its
# SKILL.md; --force replaces only such a tree.
GEN_MARK='  source: generated skill; do not edit by hand'
if { [ -e "$FINAL" ] || [ -L "$FINAL" ]; } && [ ! -d "$FINAL" ]; then
  err "refusing to overwrite $FINAL: it exists and is not a directory"
  exit 2
fi
# The listing ends in "." so that an entry whose name is only line breaks
# still counts; a directory that cannot be listed is refused, not taken for
# empty.
FINAL_LIST="."
if [ -d "$FINAL" ]; then
  FINAL_LIST="$(ls -A "$FINAL" && echo .)" || { err "refusing to overwrite $FINAL: it cannot be read"; exit 2; }
fi
if [ "$FINAL_LIST" != "." ]; then
  if [ "$FORCE" -ne 1 ]; then
    err "refusing to overwrite non-empty $FINAL (pass --force)"
    exit 2
  fi
  # The line counts only inside the leading frontmatter block: a SKILL.md
  # written by hand may quote it in its text. A carriage return at a line
  # end is ignored, so a generated tree checked out with CR LF line ends is
  # still a generated tree.
  if ! { [ -f "$FINAL/SKILL.md" ] && awk -v m="$GEN_MARK" '
      { sub(/\r$/, "") }
      NR == 1 { if ($0 != "---") exit; next }
      $0 == "---" { exit }
      $0 == m { found = 1; exit }
      END { exit !found }' "$FINAL/SKILL.md"; }; then
    err "refusing to replace $FINAL: it is not a skill this generator wrote (no SKILL.md whose frontmatter holds the line \"$GEN_MARK\"), and --force does not remove it; remove it by hand if that is really intended"
    exit 2
  fi
fi

# The tree is built and audited in a staging directory outside <out>, so
# nothing under FINAL changes until every audit is clean. The staging tree is
# kept for inspection when an audit fails and removed on every other exit.
WORK=""
STAGE=""
KEEP_STAGE=0
INCOMING=""
cleanup() {
  trap '' INT TERM HUP
  [ -z "$WORK" ] || rm -rf "$WORK"
  [ -z "$INCOMING" ] || rm -rf "$INCOMING"
  [ -z "$STAGE" ] || [ "$KEEP_STAGE" -eq 1 ] || rm -rf "$STAGE"
}
trap cleanup EXIT
WORK="$(mktemp -d "${TMPDIR:-/tmp}/build-standalone-skill.XXXXXX")" || { err "cannot create a working directory under ${TMPDIR:-/tmp}"; exit 2; }
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/build-standalone-skill-out.XXXXXX")" || { err "cannot create a staging directory under ${TMPDIR:-/tmp}"; exit 2; }
STAGE="$(CDPATH='' cd -- "$STAGE" && pwd)"
# The basename of TARGET is the name, as the name audit expects.
TARGET="$STAGE/$NAME"
mkdir -p "$TARGET"
STALE="$WORK/stale.txt"
: >"$STALE"

DELIM="$(printf '\001')"

# scope_match DEST GLOB — bash pattern match ('*' matches across '/').
scope_match() {
  # shellcheck disable=SC2053
  [[ $1 == $2 ]]
}

# Glued-target guard: a two-field row whose replacement ends in a generated
# file path (SKILL.md, README.md or references/<path>.md) directly preceded
# by sentence punctuation lost the TAB before its target file. Such a row
# would apply to every file and glue the file name onto the output text, so
# it fails the build. A replacement that is itself a path (\1SKILL.md) is
# preceded by a backreference or a space and passes.
GLUED_RE='[].)!?:;,*`'"'\""'](SKILL\.md|README\.md|references/[A-Za-z0-9_./-]+\.md)$'
GLUED="$(RE="$GLUED_RE" awk -F'\t' '
  /^[[:space:]]*(#|$)/ { next }
  NF == 2 && match($2, ENVIRON["RE"]) {
    printf "substitutions.tsv line %d: the replacement ends in \"%s\" glued to the text before it; a TAB is missing before the target file\n", NR, substr($2, RSTART + 1)
  }' "$MANIFEST_DIR/substitutions.tsv")"
if [ -n "$GLUED" ]; then
  printf '%s\n' "$GLUED" | while IFS= read -r g; do err "$g"; done
  exit 2
fi

# --- Layer 0: copy sources ------------------------------------------------

# Source "-" marks a file with no plugin source: it starts empty and an
# "append" override supplies its whole content.
DESTS=()
PURE=()
while IFS=$'\t' read -r dest src; do
  [ -n "$dest" ] || continue
  if [ "$src" = "-" ]; then
    mkdir -p "$(dirname "$TARGET/$dest")"
    : >"$TARGET/$dest"
    DESTS+=("$dest")
    PURE+=("$dest")
    continue
  fi
  if [ ! -f "$SRC_ROOT/$src" ]; then
    err "source file missing: $src"
    exit 2
  fi
  mkdir -p "$(dirname "$TARGET/$dest")"
  case "$dest" in
    references/agents/*)
      # Agent bodies become task prompts: strip the frontmatter block.
      awk 'NR==1 && $0=="---" {fm=1; next}
           fm && $0=="---" {fm=0; skip=1; next}
           fm {next}
           skip && $0=="" {skip=0; next}
           {skip=0; print}' "$SRC_ROOT/$src" >"$TARGET/$dest"
      ;;
    *) cat "$SRC_ROOT/$src" >"$TARGET/$dest" ;;
  esac
  DESTS+=("$dest")
done < <(manifest_lines "$MANIFEST_DIR/files.tsv")

# --- Layer 1: sections ----------------------------------------------------

# section_op FILE HEADING OP CONTENT_FILE — OP is drop|replace|before|after.
# A section runs from its heading to the next heading of the same or a
# higher level at the same fence depth, so a heading inside a fenced
# template block never swallows the fence that closes it.
# HEADING "(frontmatter)" addresses the leading YAML frontmatter block.
section_op() {
  local file="$1" heading="$2" op="$3" content="$4"
  local rc=0
  H="$heading" OP="$op" CF="$content" awk '
    function lvl(s) { match(s, /^#+/); return RLENGTH }
    function isfence(s) { return s ~ /^ ? ? ?(```|~~~)/ }
    BEGIN {
      H = ENVIRON["H"]; OP = ENVIRON["OP"]; CF = ENVIRON["CF"]
      body = ""
      if (CF != "") {
        while ((getline l < CF) > 0) { body = body l "\n"; last = l }
        if (last != "") body = body "\n"
      }
      fs = 0; found = 0; inside = 0
    }
    {
      line = $0
      if (H == "(frontmatter)") {
        if (NR == 1 && line == "---") { found = 1; inside = 1; next }
        if (inside) { if (line == "---") { inside = 0; printf "%s", body } ; next }
        print line; next
      }
      if (inside) {
        if (fs == hfs && line ~ /^#+ / && lvl(line) <= hl) {
          inside = 0
          if (OP == "after") printf "%s", body
        } else {
          if (isfence(line)) fs = !fs
          if (OP == "before" || OP == "after") print line
          next
        }
      }
      if (!found && line == H) {
        found = 1; inside = 1; hl = lvl(H); hfs = fs
        if (OP == "replace") printf "%s", body
        else if (OP == "before") { printf "%s", body; print line }
        else if (OP == "after") print line
        next
      }
      if (isfence(line)) fs = !fs
      print line
    }
    END {
      if (inside && OP == "after") printf "%s", body
      if (!found) exit 3
    }' "$file" >"$file.tmp" || rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$file.tmp"
    return "$rc"
  fi
  mv "$file.tmp" "$file"
}

append_content() {
  local file="$1" content="$2"
  { printf '\n'; cat "$content"; } >>"$file"
}

# Drop sections: "<dest-glob><TAB><exact heading line>".
while IFS=$'\t' read -r glob heading; do
  [ -n "$glob" ] || continue
  hit=0
  for dest in "${DESTS[@]}"; do
    scope_match "$dest" "$glob" || continue
    if section_op "$TARGET/$dest" "$heading" drop ""; then hit=1; fi
  done
  [ "$hit" -eq 1 ] || printf 'drop-sections.txt: heading not found in %s: %s\n' "$glob" "$heading" >>"$STALE"
done < <(manifest_lines "$MANIFEST_DIR/drop-sections.txt")

# Overrides: header lines "target:", "heading:", "mode:", then a "---" line,
# then the content. target may list several destinations (space-separated).
for ovr in "$MANIFEST_DIR"/overrides/*.md; do
  [ -f "$ovr" ] || continue
  o_target="$(sed -n 's/^target:[[:space:]]*//p' "$ovr" | head -n 1)"
  o_heading="$(sed -n 's/^heading:[[:space:]]*//p' "$ovr" | head -n 1)"
  o_mode="$(sed -n 's/^mode:[[:space:]]*//p' "$ovr" | head -n 1)"
  content="$WORK/$(basename "$ovr").content"
  awk 'done {print; next} $0 == "---" {done = 1}' "$ovr" >"$content"
  case "$o_mode" in
    replace|before|after|append) ;;
    *) err "override $(basename "$ovr"): invalid mode '$o_mode'"; exit 2 ;;
  esac
  for dest in $o_target; do
    if [ ! -f "$TARGET/$dest" ]; then
      printf 'overrides/%s: target not shipped: %s\n' "$(basename "$ovr")" "$dest" >>"$STALE"
      continue
    fi
    if [ "$o_mode" = "append" ]; then
      append_content "$TARGET/$dest" "$content"
    elif ! section_op "$TARGET/$dest" "$o_heading" "$o_mode" "$content"; then
      printf 'overrides/%s: heading not found in %s: %s\n' "$(basename "$ovr")" "$dest" "$o_heading" >>"$STALE"
    fi
  done
done

# A file with no plugin source must have received its content from an override.
for dest in ${PURE[@]+"${PURE[@]}"}; do
  grep -q '[^[:space:]]' "$TARGET/$dest" || printf 'files.tsv: %s has no source and no override filled it\n' "$dest" >>"$STALE"
done

# --- Layer 2: paragraph drops ---------------------------------------------

# drop_paragraphs FILE ERE — exit 3 when the ERE matches nothing.
# A hit on a list item drops that item (plus its indented continuation), a
# hit on a table row or on a line inside a fenced block drops that line
# only, and any other hit drops its whole paragraph (up to blank lines,
# headings and fences).
drop_paragraphs() {
  local file="$1" ere="$2"
  local rc=0
  RE="$ere" awk '
    function isfence(s) { return s ~ /^ ? ? ?(```|~~~)/ }
    function isitem(s) { return s ~ /^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]/ }
    function stop(s) { return s == "" || s ~ /^#+ / || isfence(s) }
    BEGIN { RE = ENVIRON["RE"] }
    { line[NR] = $0 }
    END {
      fs = 0
      for (i = 1; i <= NR; i++) {
        if (isfence(line[i])) { infence[i] = 0; fs = !fs } else infence[i] = fs
      }
      hits = 0
      for (i = 1; i <= NR; i++) {
        if (drop[i] || line[i] !~ RE) continue
        hits++
        if (infence[i] || line[i] ~ /^[[:space:]]*\|/) { drop[i] = 1; continue }
        if (isitem(line[i])) {
          drop[i] = 1
          for (j = i + 1; j <= NR && !stop(line[j]) && !isitem(line[j]) && line[j] ~ /^[[:space:]]/; j++) drop[j] = 1
          continue
        }
        s = i; while (s > 1 && !stop(line[s - 1]) && !infence[s - 1]) s--
        e = i; while (e < NR && !stop(line[e + 1]) && !infence[e + 1]) e++
        for (j = s; j <= e; j++) drop[j] = 1
      }
      for (i = 1; i <= NR; i++) if (!drop[i]) print line[i]
      if (hits == 0) exit 3
    }' "$file" >"$file.tmp" || rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$file.tmp"
    return "$rc"
  fi
  mv "$file.tmp" "$file"
}

while IFS=$'\t' read -r glob ere; do
  [ -n "$glob" ] || continue
  hit=0
  for dest in "${DESTS[@]}"; do
    scope_match "$dest" "$glob" || continue
    if drop_paragraphs "$TARGET/$dest" "$ere"; then hit=1; fi
  done
  [ "$hit" -eq 1 ] || printf 'drop-paragraphs.txt: no match in %s: %s\n' "$glob" "$ere" >>"$STALE"
done < <(manifest_lines "$MANIFEST_DIR/drop-paragraphs.txt")

# --- Layer 3: substitutions -----------------------------------------------

# "<ERE><TAB><replacement>[<TAB><dest-glob>]"; sed -E replacement syntax
# (& is the whole match, \1..\9 are groups, \& is a literal ampersand).
# Fields are split by hand: `read` would collapse an empty replacement.
TAB=$'\t'
while IFS= read -r row; do
  pat="${row%%"$TAB"*}"
  rep=""; glob=""
  if [ "$pat" != "$row" ]; then
    rest="${row#*"$TAB"}"
    rep="${rest%%"$TAB"*}"
    [ "$rep" = "$rest" ] || glob="${rest#*"$TAB"}"
  fi
  [ -n "$pat" ] || continue
  glob="${glob:-*}"
  case "$pat$rep" in *"$DELIM"*) err "substitution contains the delimiter: $pat"; exit 2 ;; esac
  hit=0
  for dest in "${DESTS[@]}"; do
    scope_match "$dest" "$glob" || continue
    f="$TARGET/$dest"
    if grep -qE -- "$pat" "$f"; then
      sed -E "s${DELIM}${pat}${DELIM}${rep}${DELIM}g" "$f" >"$f.tmp"
      mv "$f.tmp" "$f"
      hit=1
    fi
  done
  [ "$hit" -eq 1 ] || printf 'substitutions.tsv: no match in %s: %s\n' "$glob" "$pat" >>"$STALE"
done < <(manifest_lines "$MANIFEST_DIR/substitutions.tsv")

# Normalise: collapse blank-line runs, strip leading/trailing blank lines.
for dest in "${DESTS[@]}"; do
  f="$TARGET/$dest"
  awk 'NF == 0 { blank = 1; next }
       { if (blank && printed) print ""; blank = 0; printed = 1; print }' "$f" >"$f.tmp"
  mv "$f.tmp" "$f"
done

# Frontmatter placeholders: the version from plugin.json and the source commit.
sed -E -e "s${DELIM}@SOURCE_VERSION@${DELIM}${SOURCE_VERSION}${DELIM}g" \
  -e "s${DELIM}@SOURCE_COMMIT@${DELIM}${SOURCE_COMMIT}${DELIM}g" "$TARGET/SKILL.md" >"$TARGET/SKILL.md.tmp"
mv "$TARGET/SKILL.md.tmp" "$TARGET/SKILL.md"

# --- Layer 4: exit audit --------------------------------------------------

FAIL="$WORK/audit.txt"
: >"$FAIL"

# prefix TEXT — prepend TEXT verbatim (no escape processing) to each line.
prefix() {
  P="$1" awk '{ print ENVIRON["P"] $0 }'
}
cat "$STALE" >>"$FAIL"

GEN_FILES=()
while IFS= read -r f; do GEN_FILES+=("$f"); done < <(cd "$TARGET" && find . -type f | sed 's#^\./##' | sort)

# Checks (b) and (e) run again in the name audit (Layer 5); LABEL prefixes
# each finding ("" in the exit audit). The denylist (a) does not run again:
# it finds plugin vocabulary leaked into the text, the canonical text passed
# it, and a row that only the chosen name trips is a resemblance, not a leak.

# (a) denylist
while IFS= read -r pat; do
  for f in "${GEN_FILES[@]}"; do
    (cd "$TARGET" && grep -nE -- "$pat" "$f" || true) | prefix "denylist [$pat] $f:" | cut -c1-240
  done
done < <(manifest_lines "$MANIFEST_DIR/denylist.txt") >>"$FAIL"

# (b) foreign tool names in backticks (tool-vocabulary.txt "deny <Name>",
#     read into DENY_TOOLS before the build)
audit_tool_names() {
  [ -n "$DENY_TOOLS" ] || return 0
  for f in "${GEN_FILES[@]}"; do
    (cd "$TARGET" && grep -nE -- "$DENY_TOOLS_RE" "$f" || true) | prefix "${1}foreign tool name $f:" | cut -c1-240
  done
}
audit_tool_names "" >>"$FAIL"

# (c) English only: no CJK / Hangul / fullwidth lead bytes (U+3000..U+D7FF).
CJK="$(printf '[\343-\355]')"
for f in "${GEN_FILES[@]}"; do
  (cd "$TARGET" && grep -nE -- "$CJK" "$f" || true) | prefix "non-English text $f:" | cut -c1-120 >>"$FAIL"
done

# (d) relative links and backticked references/ paths resolve in the tree
for f in "${GEN_FILES[@]}"; do
  case "$f" in *.md) ;; *) continue ;; esac
  fdir="$(dirname "$f")"
  { grep -noE '\]\([^)[:space:]]+\)' "$TARGET/$f" || true; } | while IFS= read -r m; do
    ln="${m%%:*}"; link="${m#*:](}"; link="${link%)}"; link="${link%%#*}"
    case "$link" in ''|http://*|https://*|mailto:*) continue ;; esac
    [ -f "$TARGET/$fdir/$link" ] || printf 'broken link %s:%s: %s\n' "$f" "$ln" "$link" >>"$FAIL"
  done
  # shellcheck disable=SC2016  # literal backticks, no expansion intended
  { grep -noE '`references/[A-Za-z0-9_./-]+`' "$TARGET/$f" || true; } | while IFS= read -r m; do
    ln="${m%%:*}"; p="${m#*:\`}"; p="${p%\`}"
    [ -e "$TARGET/$p" ] || printf 'unresolved path %s:%s: %s\n' "$f" "$ln" "$p" >>"$FAIL"
  done
done

# (e) inline code spans stay balanced outside fences (catches a substitution
#     that nests a backticked token inside a backticked phrase)
audit_backticks() {
  for f in "${GEN_FILES[@]}"; do
    awk -v F="$f" -v L="$1" '/^ ? ? ?(```|~~~)/ { fz = !fz; next }
      !fz { n = gsub(/`/, "`"); if (n % 2) printf "%sunbalanced backticks %s:%d\n", L, F, NR }' "$TARGET/$f"
  done
}
audit_backticks "" >>"$FAIL"

# (f) frontmatter
FM="$(awk 'NR == 1 && $0 == "---" {fm = 1; next} fm && $0 == "---" {exit} fm {print}' "$TARGET/SKILL.md")"
printf '%s\n' "$FM" | grep -qx 'name: create-ticket' || printf 'frontmatter: name is not create-ticket\n' >>"$FAIL"
if printf '%s\n' "$FM" | grep -q '^allowed-tools:'; then printf 'frontmatter: allowed-tools must be omitted\n' >>"$FAIL"; fi
DESC_LEN="$(printf '%s\n' "$FM" | awk '/^description:/ {d = 1; next} d && /^[a-z-]+:/ {d = 0} d {sub(/^ +/, ""); s = s (s == "" ? "" : " ") $0} END {printf "%d", length(s)}')"
{ [ "$DESC_LEN" -gt 0 ] && [ "$DESC_LEN" -le 1024 ]; } || printf 'frontmatter: description length %s not in 1..1024\n' "$DESC_LEN" >>"$FAIL"
printf '%s\n' "$FM" | grep -qE '^  source-commit: "([0-9a-f]{7,40}|unknown)"$' || printf 'frontmatter: metadata.source-commit missing or malformed\n' >>"$FAIL"

# (g) rubric parity (zero-loss: renaming only)
SRC_RUBRIC="$SRC_ROOT/skills/create-ticket/references/ac-quality-criteria.md"
GEN_RUBRIC="$TARGET/references/ac-quality-criteria.md"
gates() { grep -E '^#{2,3} Gate ' "$1" || true; }
terms() { awk '/^## Terminology/ {t = 1; next} t && /^## / {t = 0} t && /^- \*\*/ {n++} END {printf "%d", n}' "$1"; }
if [ "$(gates "$SRC_RUBRIC")" != "$(gates "$GEN_RUBRIC")" ]; then
  printf 'rubric parity: Gate heading set differs from the source\n' >>"$FAIL"
fi
[ "$(terms "$SRC_RUBRIC")" = "$(terms "$GEN_RUBRIC")" ] || printf 'rubric parity: Terminology entry count differs\n' >>"$FAIL"
SRC_WC="$(wc -w <"$SRC_RUBRIC" | tr -d ' ')"
GEN_WC="$(wc -w <"$GEN_RUBRIC" | tr -d ' ')"
DELTA=$((GEN_WC - SRC_WC)); [ "$DELTA" -ge 0 ] || DELTA=$((-DELTA))
[ $((DELTA * 100)) -le $((SRC_WC * 5)) ] || printf 'rubric parity: word count %s vs source %s (> 5%%)\n' "$GEN_WC" "$SRC_WC" >>"$FAIL"

# (h) the name has one spelling: the rename of Layer 5, its occurrence count
#     and its left-over check all use the exact token create-ticket, so the
#     canonical text may hold none of these forms of it: another letter
#     case, an underscore or no separator (Create-Ticket, create_ticket,
#     createTicket); create-ticket glued to an ASCII letter, digit, hyphen or
#     underscore (the scratch directory create-ticket-scratch is the one
#     compound, and it may not be glued either); the name wrapped over a line
#     end (create- at the end of a line, trailing blanks aside, and ticket
#     first on the next one, leading punctuation aside); a file named after
#     it (the rename does not rename files). An upstream path
#     skills/create-ticket is reported too, unless it is a host skill root
#     (.<word>/skills/create-ticket, the dot first in its path segment).
#     Out of reach of this check: a form that differs by markup, a character
#     entity, a non-ASCII hyphen or an invisible character, and the two
#     words with a space between them (the text holds the prose "Create
#     tickets from").
for f in "${GEN_FILES[@]}"; do
  awk -v F="$f" '
    {
      l = $0
      m = l; gsub(/create-ticket/, "\001", m)
      if (tolower(m) ~ /create[-_]?ticket/) printf "name variant (another spelling of the name) %s:%d: %s\n", F, NR, l
      g = l; gsub(/create-ticket-scratch/, "\001", g)
      if (g ~ /[A-Za-z0-9_-]create-ticket/ || g ~ /create-ticket[A-Za-z0-9_-]/ || g ~ ("[A-Za-z0-9_-]" "\001") || g ~ ("\001" "[A-Za-z0-9_-]")) printf "name variant (glued to another word) %s:%d: %s\n", F, NR, l
      n = l; sub(/^[^A-Za-z0-9]+/, "", n)
      if ((wrap && tolower(n) ~ /^ticket/) || (wrap2 && tolower(l) ~ /^[ \t]*-ticket/)) { t = l; sub(/^[ \t]+/, "", t); printf "name variant (wrapped over a line end) %s:%d: %s %s\n", F, NR - 1, prev, t }
      p = l; sub(/[ \t\r]+$/, "", p)
      wrap = (tolower(p) ~ /create-$/); wrap2 = (tolower(p) ~ /create$/); prev = p
      u = l; gsub(/\.[A-Za-z0-9_-]+\/skills\/create-ticket/, "\001", u)
      if (u ~ /skills\/create-ticket([^A-Za-z0-9_-]|$)/ || l ~ /[A-Za-z0-9_.-]\.[A-Za-z0-9_-]+\/skills\/create-ticket([^A-Za-z0-9_-]|$)/) printf "upstream path of the skill %s:%d: %s\n", F, NR, l
    }' "$TARGET/$f" | cut -c1-240
done >>"$FAIL"
printf '%s\n' "${GEN_FILES[@]}" | { grep -iE 'create[^A-Za-z0-9]*ticket' || true; } |
  prefix 'name in a file name (the rename does not rename files): ' >>"$FAIL"

if [ -s "$FAIL" ]; then
  CANON_NOTE=""
  [ "$NAME" = "$CANON_NAME" ] || CANON_NOTE=" (still the canonical text: --name is applied only after a clean exit audit)"
  KEEP_STAGE=1
  err "exit audit FAILED ($(wc -l <"$FAIL" | tr -d ' ') finding(s)); output left at $TARGET for inspection$CANON_NOTE; $FINAL is unchanged:"
  sed 's/^/  /' "$FAIL" >&2
  exit 1
fi

# publish — replace FINAL by the audited staging tree. FINAL was checked
# before the build: absent, empty, or a tree this generator wrote (--force).
# The tree is first moved next to FINAL (the step that can fail: another
# file system, a full disk, a directory that cannot be written). The swap is
# then two renames inside <out>, the previous tree aside and the new one in,
# with signals held off, so a run that fails or is interrupted leaves either
# the previous skill or the new one, never neither. The previous tree is
# removed last; what cannot be removed is named in a WARNING.
publish() {
  local old=""
  INCOMING="$OUT_DIR/.$NAME.incoming.$$"
  rm -rf "$INCOMING"
  mv "$TARGET" "$INCOMING" || { err "cannot write to $OUT_DIR; $FINAL is unchanged"; exit 2; }
  trap '' INT TERM HUP QUIT
  if [ -e "$FINAL" ] || [ -L "$FINAL" ]; then
    old="$OUT_DIR/.$NAME.replaced.$$"
    rm -rf "$old"
    mv "$FINAL" "$old" || { err "cannot move the previous $FINAL aside; $FINAL is unchanged"; exit 2; }
  fi
  if ! mv "$INCOMING" "$FINAL"; then
    if [ -n "$old" ] && ! mv "$old" "$FINAL"; then
      err "cannot move the new tree to $FINAL; the previous skill is at $old"
    else
      err "cannot move the new tree to $FINAL; $FINAL is unchanged"
    fi
    exit 2
  fi
  # A directory that another build of the same name put at FINAL between the
  # two renames received this tree as a subdirectory: that build's tree
  # stays whole and this one is dropped.
  if [ -e "$FINAL/.$NAME.incoming.$$" ]; then
    rm -rf "$FINAL/.$NAME.incoming.$$"
  fi
  INCOMING=""
  if [ -n "$old" ]; then
    rm -rf "$old" 2>/dev/null || err "WARNING: the previous tree could not be removed completely; what is left of it is at $old"
  fi
  trap - INT TERM HUP QUIT
}

if [ "$NAME" = "$CANON_NAME" ]; then
  publish
  printf '[build-standalone-skill] wrote %s (%s files, source version %s, commit %s); exit audit clean\n' \
    "$FINAL" "${#GEN_FILES[@]}" "$SOURCE_VERSION" "$SOURCE_COMMIT"
  exit 0
fi

# --- Layer 5: the chosen name and the name audit ----------------------------

# The generated tree names the skill by the exact token create-ticket (the
# exit audit's check (h) fails the build on a case, underscore, glued or
# line-wrapped variant and on a file named after it), so one sed pass per
# file renames it; the validated name needs no escaping in sed. The name audit
# then proves the pass per file: the occurrences of the name, minus those the
# canonical text already held (counted with every create-ticket masked),
# equal the create-ticket occurrences counted before the pass, and no
# create-ticket is left outside an occurrence of the name. The checks that
# the name can change and that look for a defect, not for leaked plugin
# vocabulary, run again on the renamed tree; the canonical tree passed the
# exit audit, so any finding is caused by the name.
NFAIL="$WORK/name-audit.txt"
: >"$NFAIL"
NLABEL="name audit (caused by --name $NAME): "
MASK="$(printf '\002')"
# count_in WORD — occurrences (not lines) of WORD on standard input.
count_in() { { grep -oF -- "$1" || true; } | wc -l | tr -d ' '; }
RENAMED=0
for f in "${GEN_FILES[@]}"; do
  p="$TARGET/$f"
  c="$(count_in "$CANON_NAME" <"$p")"
  [ "$c" -gt 0 ] || continue
  base="$(sed "s/$CANON_NAME/$MASK/g" "$p" | count_in "$NAME")"
  sed "s/$CANON_NAME/$NAME/g" "$p" >"$p.tmp"
  mv "$p.tmp" "$p"
  after="$(count_in "$NAME" <"$p")"
  [ $((after - base)) -eq "$c" ] ||
    printf '%s%s: %s occurrence(s) of the name after the rename, expected %s (%s of create-ticket renamed, %s of the name already in the text)\n' \
      "$NLABEL" "$f" "$after" $((base + c)) "$c" "$base" >>"$NFAIL"
  RENAMED=$((RENAMED + c))
done
for f in "${GEN_FILES[@]}"; do
  case "$NAME" in
    *"$CANON_NAME"*) left="$(sed "s/$NAME/$MASK/g" "$TARGET/$f" | count_in "$CANON_NAME")" ;;
    *) left="$(count_in "$CANON_NAME" <"$TARGET/$f")" ;;
  esac
  [ "$left" -eq 0 ] || printf '%s%s: %s occurrence(s) of create-ticket left after the rename\n' "$NLABEL" "$f" "$left" >>"$NFAIL"
done

FM_N="$(awk 'NR == 1 && $0 == "---" {fm = 1; next} fm && $0 == "---" {exit} fm {print}' "$TARGET/SKILL.md")"
FM_N_NAME="$(printf '%s\n' "$FM_N" | sed -n 's/^name: //p')"
{ [ "$FM_N_NAME" = "$NAME" ] && [ "$FM_N_NAME" = "$(basename "$TARGET")" ]; } ||
  printf '%sfrontmatter: name is "%s", not the name and directory name %s\n' "$NLABEL" "$FM_N_NAME" "$NAME" >>"$NFAIL"
DESC_LEN_N="$(printf '%s\n' "$FM_N" | awk '/^description:/ {d = 1; next} d && /^[a-z-]+:/ {d = 0} d {sub(/^ +/, ""); s = s (s == "" ? "" : " ") $0} END {printf "%d", length(s)}')"
if [ "$DESC_LEN_N" -gt 1024 ]; then
  printf '%sfrontmatter: description length %s not in 1..1024: the name is too long for the description (%s characters with this %s-character name, %s with create-ticket)\n' \
    "$NLABEL" "$DESC_LEN_N" "$DESC_LEN_N" "${#NAME}" "$DESC_LEN" >>"$NFAIL"
elif [ "$DESC_LEN_N" -lt 1 ]; then
  printf '%sfrontmatter: description length %s not in 1..1024\n' "$NLABEL" "$DESC_LEN_N" >>"$NFAIL"
fi

{
  audit_tool_names "$NLABEL"
  audit_backticks "$NLABEL"
} >>"$NFAIL"

if [ -s "$NFAIL" ]; then
  KEEP_STAGE=1
  err "name audit FAILED ($(wc -l <"$NFAIL" | tr -d ' ') finding(s)); the name '$NAME' caused them, since the canonical text passed the exit audit; output left at $TARGET for inspection; $FINAL is unchanged:"
  sed 's/^/  /' "$NFAIL" >&2
  exit 1
fi

publish
printf '[build-standalone-skill] wrote %s (%s files, source version %s, commit %s); exit audit clean; name audit clean (%s occurrences of create-ticket renamed to %s)\n' \
  "$FINAL" "${#GEN_FILES[@]}" "$SOURCE_VERSION" "$SOURCE_COMMIT" "$RENAMED" "$NAME"
