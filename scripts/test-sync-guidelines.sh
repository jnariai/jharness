#!/usr/bin/env bash
#
# test-sync-guidelines.sh — suite red/green do scripts/sync-guidelines.sh.
#
# Zero rede: um repo git fake faz o papel do upstream, com o historico real do
# layout — arquivo unico laravel-livewire.md (v1 sem harness-meta, v2 com), depois
# o split em laravel.md + livewire.md, depois uma revisao do laravel.md — e
# projetos fake fazem o papel do alvo.
#
# Uso: scripts/test-sync-guidelines.sh [nome-do-caso]   (exit 0 = tudo verde)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="${SYNC_BIN:-$ROOT/scripts/sync-guidelines.sh}"
ONLY="${1:-}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

ok()  { PASS=$((PASS + 1)); echo -e "  ${GREEN}ok${NC}   $1"; }
bad() { FAIL=$((FAIL + 1)); echo -e "  ${RED}FAIL${NC} $1"; }

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$expected" = "$actual" ]; then ok "$msg"; else bad "$msg (esperado '$expected', veio '$actual')"; fi
}

assert_same_file() {
  if cmp -s "$1" "$2"; then ok "$3"; else bad "$3 ($1 != $2)"; fi
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

EXP="$TMP/expected"
SEP=$'\n---\n\n'

meta() { printf '<!-- harness-meta:start -->\nmeta only for the harness\n<!-- harness-meta:end -->\n\n'; }

commit() { git -C "$TMP/upstream" add -A && git -C "$TMP/upstream" commit -qm "$1"; }

make_upstream() {
  local up="$TMP/upstream"
  mkdir -p "$up/guidelines" "$EXP"
  git -C "$up" init -q
  git -C "$up" config user.email t@t
  git -C "$up" config user.name t

  # c1/c2 — layout antigo, arquivo unico
  printf '# LL\n\nlegacy v1\n' > "$up/guidelines/laravel-livewire.md"
  commit legacy-v1
  { printf '# LL\n\n'; meta; printf 'legacy v2\n'; } > "$up/guidelines/laravel-livewire.md"
  commit legacy-v2

  # c3 — split
  git -C "$up" rm -q guidelines/laravel-livewire.md
  mkdir -p "$up/guidelines"   # git rm removes the emptied directory
  { printf '# Laravel\n\n'; meta; printf 'laravel v1\n'; } > "$up/guidelines/laravel.md"
  { printf '# Livewire\n\n'; meta; printf 'livewire v1\n'; } > "$up/guidelines/livewire.md"
  commit split

  # c4 — revisao do laravel.md
  { printf '# Laravel\n\n'; meta; printf 'laravel v2\n'; } > "$up/guidelines/laravel.md"
  commit laravel-v2

  printf '# LL\n\nlegacy v1\n' > "$EXP/legacy_v1"
  printf '# LL\n\nlegacy v2\n' > "$EXP/legacy_v2"
  printf '# Laravel\n\nlaravel v1\n' > "$EXP/laravel_v1"
  printf '# Laravel\n\nlaravel v2\n' > "$EXP/laravel_v2"
  { cat "$EXP/laravel_v1"; printf '%s' "$SEP"; printf '# Livewire\n\nlivewire v1\n'; } > "$EXP/composed_v1"
  { cat "$EXP/laravel_v2"; printf '%s' "$SEP"; printf '# Livewire\n\nlivewire v1\n'; } > "$EXP/composed_v2"
}

# make_project <name> <composer-require-json>
make_project() {
  local p="$TMP/$1"
  mkdir -p "$p"
  printf '{"require": {%s}}\n' "$2" > "$p/composer.json"
  echo "$p"
}

# make_project_with <name> <composer-require-json> <local-guidelines-file>
make_project_with() {
  local p; p=$(make_project "$1" "$2")
  mkdir -p "$p/docs/agents"
  cp "$3" "$p/docs/agents/coding_guidelines.md"
  echo "$p"
}

LARAVEL='"laravel/framework": "^12.0"'
LIVEWIRE='"laravel/framework": "^12.0", "livewire/livewire": "^4.0"'

field() { awk -v k="$1" '$1==k{print $2}' "$2"; }

run() { # run <out> <args...>
  local out="$1"; shift
  "$SYNC" --source "$TMP/upstream" "$@" > "$out" 2> "$out.err"
  echo $? > "$out.rc"
}

# ---------------------------------------------------------------------------
# Casos
# ---------------------------------------------------------------------------

case_non_laravel() {
  local p; p=$(make_project plain '"symfony/console": "^7.0"')
  run "$TMP/o" "$p"
  assert_eq none "$(field STACK "$TMP/o")" "stack nao reconhecida -> none"
  assert_eq none "$(field GUIDELINES "$TMP/o")" "status none"
  assert_eq 0 "$(cat "$TMP/o.rc")" "exit 0"
  [ ! -e "$p/docs" ] && ok "nada escrito" || bad "escreveu docs/ num alvo sem stack"
}

case_laravel_only() {
  local p; p=$(make_project lara "$LARAVEL")
  run "$TMP/o" "$p"
  assert_eq laravel "$(field STACK "$TMP/o")" "laravel sem livewire -> stack laravel"
  assert_eq seeded "$(field GUIDELINES "$TMP/o")" "apply: seeded"
  assert_same_file "$EXP/laravel_v2" "$p/docs/agents/coding_guidelines.md" "so laravel.md, sem livewire.md"
}

case_laravel_outdated() {
  local p; p=$(make_project_with laraold "$LARAVEL" "$EXP/laravel_v1")
  run "$TMP/o" --check "$p"
  assert_eq outdated "$(field GUIDELINES "$TMP/o")" "laravel.md v1 intacto -> outdated"
  run "$TMP/o" "$p"
  assert_same_file "$EXP/laravel_v2" "$p/docs/agents/coding_guidelines.md" "atualizado para laravel.md v2"
}

case_seed() {
  local p; p=$(make_project seed "$LIVEWIRE")
  run "$TMP/o" --check "$p"
  assert_eq absent "$(field GUIDELINES "$TMP/o")" "--check: absent"
  [ ! -e "$p/docs" ] && ok "--check nao escreve" || bad "--check escreveu"
  run "$TMP/o" "$p"
  assert_eq laravel-livewire "$(field STACK "$TMP/o")" "stack laravel-livewire"
  assert_eq seeded "$(field GUIDELINES "$TMP/o")" "apply: seeded"
  assert_same_file "$EXP/composed_v2" "$p/docs/agents/coding_guidelines.md" "laravel.md + --- + livewire.md, sem harness-meta"
  run "$TMP/o" "$p"
  assert_eq current "$(field GUIDELINES "$TMP/o")" "re-run: current"
}

case_outdated_legacy() {
  local v p
  for v in legacy_v1 legacy_v2; do
    p=$(make_project_with "old_$v" "$LIVEWIRE" "$EXP/$v")
    run "$TMP/o" --check "$p"
    assert_eq outdated "$(field GUIDELINES "$TMP/o")" "copia intacta do arquivo unico ($v) -> outdated"
    assert_same_file "$EXP/$v" "$p/docs/agents/coding_guidelines.md" "--check nao escreve ($v)"
    run "$TMP/o" "$p"
    assert_eq updated "$(field GUIDELINES "$TMP/o")" "apply: updated ($v)"
    assert_same_file "$EXP/composed_v2" "$p/docs/agents/coding_guidelines.md" "conteudo agora = composicao atual ($v)"
  done
}

case_outdated_split() {
  local p; p=$(make_project_with oldsplit "$LIVEWIRE" "$EXP/composed_v1")
  run "$TMP/o" --check "$p"
  assert_eq outdated "$(field GUIDELINES "$TMP/o")" "composicao antiga intacta -> outdated"
}

case_modified() {
  local p
  printf '# mine\n\nhand-written rule\n' > "$TMP/mine"
  p=$(make_project_with mod "$LIVEWIRE" "$TMP/mine")
  run "$TMP/o" --check "$p"
  assert_eq modified "$(field GUIDELINES "$TMP/o")" "--check: modified"
  run "$TMP/o" "$p"
  assert_eq kept-modified "$(field GUIDELINES "$TMP/o")" "apply sem --force: kept-modified"
  assert_same_file "$TMP/mine" "$p/docs/agents/coding_guidelines.md" "edicao manual preservada"
  run "$TMP/o" --force "$p"
  assert_eq forced "$(field GUIDELINES "$TMP/o")" "--force: forced"
  assert_same_file "$EXP/composed_v2" "$p/docs/agents/coding_guidelines.md" "--force sobrescreve com a composicao atual"
}

case_non_git_source() {
  # Sem historico nao ha prova de copia intacta: versao antiga vira modified.
  local src="$TMP/plainsrc" p
  mkdir -p "$src/guidelines"
  cp "$TMP/upstream/guidelines/"*.md "$src/guidelines/"
  p=$(make_project_with nogit "$LIVEWIRE" "$EXP/composed_v1")
  "$SYNC" --source "$src" --check "$p" > "$TMP/o"
  assert_eq - "$(field UPSTREAM "$TMP/o")" "fonte sem git -> UPSTREAM -"
  assert_eq modified "$(field GUIDELINES "$TMP/o")" "fonte sem git: versao antiga -> modified"
}

case_print_upstream() {
  local p; p=$(make_project print "$LIVEWIRE")
  "$SYNC" --source "$TMP/upstream" --print-upstream "$p" > "$TMP/printed"
  assert_same_file "$EXP/composed_v2" "$TMP/printed" "--print-upstream = composicao atual"
  [ ! -e "$p/docs" ] && ok "--print-upstream nao escreve" || bad "--print-upstream escreveu"
}

case_usage() {
  "$SYNC" > /dev/null 2>&1
  assert_eq 2 "$?" "sem --source -> exit 2"
  "$SYNC" --source "$TMP" > /dev/null 2>&1
  assert_eq 2 "$?" "fonte sem guidelines/ -> exit 2"
}

# ---------------------------------------------------------------------------

make_upstream

CASES=(non_laravel laravel_only laravel_outdated seed outdated_legacy outdated_split modified non_git_source print_upstream usage)
for c in "${CASES[@]}"; do
  [ -n "$ONLY" ] && [ "$ONLY" != "$c" ] && continue
  echo "== $c"
  "case_$c"
done

echo
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
