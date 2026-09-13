#!/usr/bin/env bash
#
# sync-guidelines.sh — bring a project's stack convention layer
# (docs/agents/coding_guidelines.md) in line with a jharness source tree.
#
# The project file is composed from the harness's guidelines/*.md for the
# detected stack: laravel.md, plus livewire.md when the project uses Livewire
# (joined by a `---` rule, harness-meta blocks stripped).
#
# The source is normally a fresh clone of the harness from GitHub (see
# commands/update.md). When the source is a git repository, every past revision
# of the guidelines is known — including the old single-file
# guidelines/laravel-livewire.md layout — so a local copy that byte-matches ANY
# of them is provably unedited and safe to refresh. A copy that matches none was
# edited by hand and is never overwritten without --force.
#
# Usage:
#   scripts/sync-guidelines.sh --source <harness-dir> [--check] [--force] [target]
#   scripts/sync-guidelines.sh --source <harness-dir> --print-upstream [target]
#
# Output, one record per line:
#   STACK laravel|laravel-livewire|none
#   UPSTREAM <sha12>|-
#   GUIDELINES <status> <path>
#
# Status, apply mode: seeded | current | updated | kept-modified | forced | none
# Status, --check:    absent | current | outdated | modified | none
#
# Exit: 0 = ran (a kept-modified file is not an error); 2 = usage/precondition.

set -uo pipefail

SRC=""
CHECK=0
FORCE=0
PRINT=0
TARGET=""

die() { echo "sync-guidelines: $1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --source) [ $# -ge 2 ] || die "--source needs a path"; SRC="$2"; shift 2 ;;
    --check) CHECK=1; shift ;;
    --force) FORCE=1; shift ;;
    --print-upstream) PRINT=1; shift ;;
    -h|--help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) [ -z "$TARGET" ] || die "only one target allowed"; TARGET="$1"; shift ;;
  esac
done

[ -n "$SRC" ] || die "--source <harness-dir> is required"
[ -d "$SRC/guidelines" ] || die "$SRC has no guidelines/ directory — not a jharness tree"
TARGET="${TARGET:-$PWD}"
[ -d "$TARGET" ] || die "target $TARGET is not a directory"

REL="docs/agents/coding_guidelines.md"
LOCAL="$TARGET/$REL"

# Same strip as commands/ai-context.md: drop the harness-meta block and the
# blank line after it. Reads stdin when called without a file.
strip() {
  awk '/^<!-- harness-meta:start -->$/{skip=1;next} /^<!-- harness-meta:end -->$/{skip=0;drop=1;next} skip{next} drop&&/^$/{drop=0;next} {drop=0;print}' "$@"
}

detect_stack() {
  local c="$TARGET/composer.json"
  if [ -f "$c" ] && grep -q '"laravel/framework"' "$c"; then
    if grep -q '"livewire/livewire"' "$c"; then echo laravel-livewire; else echo laravel; fi
    return
  fi
  echo none
}

STACK=$(detect_stack)

# Files composed for the stack, in order, and the pre-split single file that
# history may still hold for it.
FILES=()
LEGACY=""
case "$STACK" in
  laravel) FILES=(guidelines/laravel.md) ;;
  laravel-livewire)
    FILES=(guidelines/laravel.md guidelines/livewire.md)
    LEGACY=guidelines/laravel-livewire.md
    ;;
esac

# compose — the stack's files from the source working tree
compose() {
  local f first=1
  for f in "${FILES[@]}"; do
    [ "$first" -eq 1 ] || printf '\n---\n\n'
    first=0
    strip "$SRC/$f"
  done
}

# compose_at <commit> — the same composition as it stood at that commit;
# fails when the commit holds neither the split files nor the legacy file.
compose_at() {
  local c="$1" f first=1
  for f in "${FILES[@]}"; do
    git -C "$SRC" cat-file -e "$c:$f" 2>/dev/null || { first=-1; break; }
  done
  if [ "$first" -eq 1 ]; then
    for f in "${FILES[@]}"; do
      [ "$first" -eq 1 ] || printf '\n---\n\n'
      first=0
      git -C "$SRC" show "$c:$f" | strip
    done
  elif [ -n "$LEGACY" ] && git -C "$SRC" cat-file -e "$c:$LEGACY" 2>/dev/null; then
    git -C "$SRC" show "$c:$LEGACY" | strip
  else
    return 1
  fi
}

if [ "$STACK" != none ]; then
  for f in "${FILES[@]}"; do
    [ -f "$SRC/$f" ] || die "source is missing $f"
  done
fi

if [ "$PRINT" -eq 1 ]; then
  [ "$STACK" != none ] || die "no harness guidelines for this stack"
  compose
  exit 0
fi

echo "STACK $STACK"

IS_GIT=0
UPSTREAM="-"
if git -C "$SRC" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  IS_GIT=1
  UPSTREAM=$(git -C "$SRC" rev-parse --short=12 HEAD 2>/dev/null || echo -)
fi
echo "UPSTREAM $UPSTREAM"

if [ "$STACK" = none ]; then
  echo "GUIDELINES none -"
  exit 0
fi

TMP=$(mktemp)
OLD=$(mktemp)
trap 'rm -f "$TMP" "$OLD"' EXIT
compose > "$TMP"

# absent | current | outdated | modified
classify() {
  [ -f "$LOCAL" ] || { echo absent; return; }
  cmp -s "$TMP" "$LOCAL" && { echo current; return; }
  if [ "$IS_GIT" -eq 1 ]; then
    local h
    while read -r h; do
      if compose_at "$h" > "$OLD" && cmp -s "$OLD" "$LOCAL"; then
        echo outdated
        return
      fi
    done < <(git -C "$SRC" log --format=%H -- guidelines/)
  fi
  echo modified
}

STATE=$(classify)

if [ "$CHECK" -eq 1 ]; then
  echo "GUIDELINES $STATE $REL"
  exit 0
fi

write_upstream() {
  mkdir -p "$(dirname "$LOCAL")"
  cp "$TMP" "$LOCAL.tmp.$$" && mv "$LOCAL.tmp.$$" "$LOCAL"
}

case "$STATE" in
  absent)   write_upstream; echo "GUIDELINES seeded $REL" ;;
  current)  echo "GUIDELINES current $REL" ;;
  outdated) write_upstream; echo "GUIDELINES updated $REL" ;;
  modified)
    if [ "$FORCE" -eq 1 ]; then
      write_upstream; echo "GUIDELINES forced $REL"
    else
      echo "GUIDELINES kept-modified $REL"
    fi
    ;;
esac
exit 0
