#!/usr/bin/env bash
# Проверка `copier update`: правки проекта переживают обновление шаблона.
#
# Шаблон — снимок рабочего каталога (с незакоммиченными правками) двумя
# версиями во временном репозитории: v1.0.0 как есть, v1.0.1 с правкой
# управляемого `harness.yml`. Проект создаётся из v1.0.0 полной раскладкой и
# правится так, как правят настоящие проекты: свои строки в управляемом
# `.claude/settings.json`, своя строка в стартовом документе, удалён стартовый
# крейт, добавлен свой. После обновления до v1.0.1 всё это на месте, а правка
# шаблона доехала.
#
# Плюс сверка: стартовые файлы `_skip_if_exists` и исключения обновления
# в `_exclude` в copier.yml — один и тот же список.
set -euo pipefail

repo=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

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

# Список стартовых файлов — из `_skip_if_exists`, исключения обновления — из
# `_exclude` без обёртки `{% if _copier_operation == 'update' ... %}`.
skip_list() {
  awk '/^_skip_if_exists:/ { on = 1; next } on && /^[^ #]/ { exit } on && /^  - / { sub(/^  - /, ""); print }' "$repo/copier.yml" |
    sed -E 's/^"\{% if [a-z_]+ %\}(.*)\{% endif %\}"$/\1/'
}
exclude_list() {
  awk '/^_exclude:/ { on = 1; next } on && /^[^ #]/ { exit } on && /^  - / { sub(/^  - /, ""); print }' "$repo/copier.yml" |
    sed -nE "s/^\"\{% if _copier_operation == 'update'( and [a-z_]+)? %\}(.*)\{% endif %\}\"$/\2/p"
}
check "стартовые файлы и исключения обновления совпадают" \
  diff <(skip_list | sort) <(exclude_list | sort)

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

# Проект из v1.0.0.
mkdir "$tmp/p"
cd "$tmp/p"
git init -q
copier copy --quiet --trust --defaults --skip-tasks --vcs-ref v1.0.0 \
  --data project_name=demo --data rust=true --data frontend=true \
  "$tmp/tpl" . >/dev/null
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

copier update --quiet --trust --defaults --skip-tasks --vcs-ref v1.0.1 --conflict inline >/dev/null

check "правка шаблона доехала" grep -q '^# check-update: правка шаблона' .github/workflows/harness.yml
check "своя строка в управляемом .claude/settings.json цела" \
  test "$(jq '.permissions.allow | index("Bash(cargo run -p demo *)") != null' .claude/settings.json)" = true
check "стартовый документ не тронут" \
  test "$(grep -c '^Строка проекта\.$' docs/spec/01-purpose.md)" = 1
check "удалённый стартовый крейт не вернулся" test ! -e crates/app
check "свой крейт цел" test -f crates/core/src/lib.rs
check "нет отвергнутых кусков .rej" test -z "$(find . -name '*.rej' -not -path './.git/*')"
check "нет маркеров конфликта" ./.harness/update/conflict-markers.sh

exit "$fail"
