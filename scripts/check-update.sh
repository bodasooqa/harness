#!/usr/bin/env bash
# Проверка `rootstock update`: правки проекта переживают обновление шаблона.
#
# Шаблон — снимок рабочего каталога (с незакоммиченными правками) двумя
# версиями во временном репозитории: v1.0.0 как есть, v1.0.1 с правкой
# управляемого `harness.yml`. Проект создаётся из v1.0.0 полной раскладкой и
# правится так, как правят настоящие проекты: свои строки в управляемом
# `.claude/settings.json`, своя строка в стартовом документе, удалён стартовый
# крейт, добавлен свой. После обновления до v1.0.1 всё это на месте, правка
# шаблона доехала, запись проекта согласована (`rootstock check`), а скрипты
# `knowledge/` читают пути из неё.
#
# rootstock — из PATH или переменной ROOTSTOCK.
set -euo pipefail

repo=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rootstock=${ROOTSTOCK:-rootstock}

export GIT_AUTHOR_NAME=check GIT_AUTHOR_EMAIL=check@example.invalid
export GIT_COMMITTER_NAME=check GIT_COMMITTER_EMAIL=check@example.invalid

fail=0
check() {
  local name=$1
  shift
  if "$@"; then
    printf 'ok    %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name" >&2
    fail=1
  fi
}

# Шаблон: две версии.
git -C "$repo" ls-files -z -co --exclude-standard |
  (cd "$repo" && xargs -0 tar -cf -) | (mkdir "$tmp/tpl" && cd "$tmp/tpl" && tar -xf -)
git -C "$tmp/tpl" init -q
git -C "$tmp/tpl" add -A
git -C "$tmp/tpl" commit -qm v1.0.0
git -C "$tmp/tpl" tag v1.0.0
printf '# check-update: правка шаблона\n' >>"$tmp/tpl/template/.github/workflows/harness.yml.jinja"
git -C "$tmp/tpl" commit -qam v1.0.1
git -C "$tmp/tpl" tag v1.0.1

# Проект из v1.0.0. Хук шаблона (`openspec init`) идёт, если openspec есть.
"$rootstock" new --version v1.0.0 --defaults --trust --git \
  --data project_name=demo --data rust=true --data frontend=true \
  "$tmp/tpl" "$tmp/p" >/dev/null
cd "$tmp/p"
git add -A
git commit -qm init

# Правки проекта.
jq '.permissions.allow += ["Bash(cargo run -p demo *)"]' .claude/settings.json >settings.tmp
mv settings.tmp .claude/settings.json
printf '\nСтрока проекта.\n' >>docs/spec/01-purpose.md
git rm -rq crates/app
mkdir -p crates/core/src
printf 'pub fn f() {}\n' >crates/core/src/lib.rs
git add -A
git commit -qm edit

code=0
"$rootstock" update --to v1.0.1 --defaults --trust >"$tmp/conflicts" || code=$?

check "rootstock update без конфликтов (код 0)" test "$code" = 0
check "конфликтов не напечатано" test ! -s "$tmp/conflicts"
check "запись на v1.0.1" grep -q '^version = "v1.0.1"$' .rootstock.toml
check "запись согласована (rootstock check)" "$rootstock" check
check "правка шаблона доехала" grep -q '^# check-update: правка шаблона' .github/workflows/harness.yml
check "своя строка в управляемом .claude/settings.json цела" \
  test "$(jq '.permissions.allow | index("Bash(cargo run -p demo *)") != null' .claude/settings.json)" = true
check "стартовый документ не тронут" \
  test "$(grep -c '^Строка проекта\.$' docs/spec/01-purpose.md)" = 1
check "удалённый стартовый крейт не вернулся" test ! -e crates/app
check "свой крейт цел" test -f crates/core/src/lib.rs
check "нет маркеров конфликта" ./.harness/update/conflict-markers.sh
check "knowledge/due.sh читает пути из записи" ./knowledge/due.sh --overdue

exit "$fail"
