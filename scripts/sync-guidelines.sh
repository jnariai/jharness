#!/usr/bin/env bash
#
# sync-guidelines.sh — bring a project's stack convention layer
# (docs/agents/coding_guidelines.md) in line with a jharness source tree.
#
# The project file is composed from the harness's guidelines/*.md for the
# detected stack (joined by a `---` rule, harness-meta blocks stripped):
#   laravel           laravel.md
#   laravel-react     laravel.md + inertia.md + react.md  (package.json: @inertiajs/react)
#   laravel-vue       laravel.md + inertia.md + vue.md    (package.json: @inertiajs/vue3)
#   laravel-livewire  laravel.md + livewire.md            (composer.json: livewire/livewire)
# Inertia wins over Livewire when a project somehow requires both. The Inertia
# layers cover Inertia 2 and 3 only: any other adapter version (1, or one that
# cannot be read) composes laravel.md alone, with a warning on stderr.
#
# The source is normally a fresh clone of the harness from GitHub (see
# commands/update.md). When the source is a git repository, every past revision
# of the guidelines is known — including the old single-file
# guidelines/laravel-livewire.md layout, and the laravel.md-only composition an
# Inertia project received before inertia.md existed, and the Livewire layouts
# a project requiring both Livewire and Inertia received before Inertia took
# precedence — so a local copy that
# byte-matches ANY of them is provably unedited and safe to refresh. A copy that matches none was
# edited by hand and is never overwritten without --force.
#
# Usage:
#   scripts/sync-guidelines.sh --source <harness-dir> [--check] [--force] [target]
#   scripts/sync-guidelines.sh --source <harness-dir> --print-upstream [target]
#
# Output, one record per line:
#   STACK laravel|laravel-react|laravel-vue|laravel-livewire|none
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
    -h|--help) sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# lock_version <lockfile> <package> — packages["node_modules/<package>"].version
# (lockfile v2/v3, falling back to v1's dependencies[<package>].version), read
# as JSON so formatting and key order never matter. Uses node, else php; prints
# nothing when neither exists or the file does not parse.
lock_version() {
  if command -v node >/dev/null 2>&1; then
    node -e 'try {
      const l = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
      const p = process.argv[2];
      const v = ((l.packages || {})["node_modules/" + p] || {}).version ?? ((l.dependencies || {})[p] || {}).version;
      if (typeof v === "string") process.stdout.write(v);
    } catch (e) {}' "$1" "$2" 2>/dev/null
  elif command -v php >/dev/null 2>&1; then
    php -r '$l = json_decode((string) @file_get_contents($argv[1]), true);
      $v = $l["packages"]["node_modules/".$argv[2]]["version"] ?? $l["dependencies"][$argv[2]]["version"] ?? null;
      if (is_string($v)) echo $v;' "$1" "$2" 2>/dev/null
  fi
}

# inertia_major <package> — the adapter's major version: the installed one from
# package-lock.json when present, else the first number of the package.json
# constraint (^2.3.0 -> 2, ~3.1 -> 3, 3.x -> 3). Empty when it cannot be read.
inertia_major() {
  local pkg="$1" lock="$TARGET/package-lock.json" v=""
  [ -f "$lock" ] && v=$(lock_version "$lock" "$pkg")
  if [ -z "$v" ]; then
    v=$(grep -m1 -oE "\"$pkg\": *\"[^\"]*\"" "$TARGET/package.json" | sed 's/.*: *"\([^"]*\)"$/\1/')
  fi
  grep -m1 -oE '^[^0-9]*[0-9]+' <<< "$v" | grep -oE '[0-9]+$'
}

# inertia_stack <stack> <package> — the stack when the adapter is Inertia 2 or 3,
# else laravel (laravel.md alone) and a warning.
inertia_stack() {
  local major; major=$(inertia_major "$2")
  case "$major" in
    2|3) echo "$1" ;;
    *)
      echo "sync-guidelines: $2 ${major:-version unreadable} is not supported by the Inertia layer (2 or 3) — composing laravel.md only" >&2
      echo laravel
      ;;
  esac
}

detect_stack() {
  local c="$TARGET/composer.json" p="$TARGET/package.json"
  if [ -f "$c" ] && grep -q '"laravel/framework"' "$c"; then
    if [ -f "$p" ] && grep -q '"@inertiajs/react"' "$p"; then inertia_stack laravel-react @inertiajs/react
    elif [ -f "$p" ] && grep -q '"@inertiajs/vue3"' "$p"; then inertia_stack laravel-vue @inertiajs/vue3
    elif grep -q '"livewire/livewire"' "$c"; then echo laravel-livewire
    else echo laravel
    fi
    return
  fi
  echo none
}

STACK=$(detect_stack)

# Files composed for the stack, in order, plus the older compositions history
# may still hold for it (each a space-separated file list, tried in order).
FILES=()
ALTS=()
case "$STACK" in
  laravel) FILES=(guidelines/laravel.md) ;;
  laravel-react)
    FILES=(guidelines/laravel.md guidelines/inertia.md guidelines/react.md)
    ALTS=("guidelines/laravel.md")
    ;;
  laravel-vue)
    FILES=(guidelines/laravel.md guidelines/inertia.md guidelines/vue.md)
    ALTS=("guidelines/laravel.md")
    ;;
  laravel-livewire)
    FILES=(guidelines/laravel.md guidelines/livewire.md)
    ALTS=("guidelines/laravel-livewire.md")
    ;;
esac

# A project that also requires Livewire was composed as a Livewire project
# before Inertia took precedence (or before the Inertia version gate): those
# copies are unedited too.
if [ "$STACK" != laravel-livewire ] && [ "$STACK" != none ] \
  && grep -q '"livewire/livewire"' "$TARGET/composer.json" 2>/dev/null; then
  ALTS+=("guidelines/laravel.md guidelines/livewire.md" "guidelines/laravel-livewire.md")
fi

# compose — the stack's files from the source working tree
compose() {
  local f first=1
  for f in "${FILES[@]}"; do
    [ "$first" -eq 1 ] || printf '\n---\n\n'
    first=0
    strip "$SRC/$f"
  done
}

# compose_files_at <commit> <file>... — those files as they stood at that
# commit, composed; fails when the commit lacks any of them.
compose_files_at() {
  local c="$1" f first=1
  shift
  for f in "$@"; do
    git -C "$SRC" cat-file -e "$c:$f" 2>/dev/null || return 1
  done
  for f in "$@"; do
    [ "$first" -eq 1 ] || printf '\n---\n\n'
    first=0
    git -C "$SRC" show "$c:$f" | strip
  done
}

# matches_at <commit> — true when the local copy byte-matches the stack's
# composition, or any older composition, as it stood at that commit.
matches_at() {
  local c="$1" alt
  if compose_files_at "$c" "${FILES[@]}" > "$OLD" && cmp -s "$OLD" "$LOCAL"; then
    return 0
  fi
  for alt in ${ALTS[@]+"${ALTS[@]}"}; do
    # shellcheck disable=SC2086
    if compose_files_at "$c" $alt > "$OLD" && cmp -s "$OLD" "$LOCAL"; then
      return 0
    fi
  done
  return 1
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
      if matches_at "$h"; then
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
