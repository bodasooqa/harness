#!/usr/bin/env bash
# Слоты subagent-stop (SubagentStop) и pre-handback (PreToolUse/SubagentHandback):
# исполнитель не сдаёт работу, пока по затронутым им пакетам красные быстрые
# проверки — rustfmt и clippy по крейту (модуль rust), tsc по пакету (модуль
# frontend).
#
# Зачем. Правки субагента асинхронные проверки не будят (`rust-clippy.sh`,
# `js-typecheck.sh`): исполнитель идёт по TDD, и красное между его правками —
# рабочий ход. Но отчёт с красным fmt, clippy или tsc ловил только полный
# прогон главной сессии, и исполнителя приходилось перезапускать. Здесь
# проверка стоит на выходе: красное — остановка удерживается один раз,
# с выводом ошибок в причине.
#
# Исполнитель — агент с именем `*-developer` (`rust-developer`,
# `frontend-developer` и проектные исполнители того же вида): соглашение
# об именах агентов шаблона, второго списка, который отстал бы от агентов, нет.
# Ревьюеры, встроенные агенты и главная сессия хуку не интересны.
#
# Что проверяется: файлы, изменённые в рабочем дереве относительно HEAD,
# и неотслеживаемые (без игнорируемых), сведённые к крейтам и пакетам. Ничего
# не изменено — хук молчит. Изменения главной сессии до запуска исполнителя
# тоже попадают в набор: git не знает, чья правка.
#
# Один раз, не в цикл:
#   - SubagentStop с `stop_hook_active` — агент уже продолжает работу по отказу
#     этого же хука; не исправил — пусть вернёт вопрос в отчёте, а не крутится.
#   - SubagentHandback (auto mode Claude Code): отчёт уходит этим инструментом
#     ДО остановки, и держать надо его, а не остановку — иначе красный отчёт
#     уже у главной сессии. Отказ — один раз на агента; дальше отчёт проходит,
#     а остановка того же агента проверку не повторяет. Метка — в каталоге git
#     дерева (`harness/agent-checks/<agent_id>`), как состояние `rust-clippy.sh`.
#
# Подмена для тестов — та же, что у асинхронных хуков: `HARNESS_CLIPPY`,
# `HARNESS_TSC`.
set -uo pipefail

here=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
# shellcheck source=lib/same-repo.sh
. "$here/lib/same-repo.sh"
have_rust=0
have_js=0
# Выходы `rust_crate` и `js_package`: библиотеки есть не в каждой раскладке.
crate_pkg=""
crate_dir=""
pkg_dir=""
if [ -f "$here/lib/rust-crate.sh" ]; then
  # shellcheck source=/dev/null
  . "$here/lib/rust-crate.sh"
  have_rust=1
fi
if [ -f "$here/lib/js-package.sh" ]; then
  # shellcheck source=/dev/null
  . "$here/lib/js-package.sh"
  have_js=1
fi

# Сколько строк вывода одной проверки и всей причины уходит агенту: ему нужна
# первая ошибка и её место, а не простыня в контекст.
per_check_lines=30
reason_lines=90

input=$(cat)
field() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

case "$(field '.agent_type // empty')" in
  *-developer) ;;
  *) exit 0 ;;
esac
event=$(field '.hook_event_name // empty')
case "$event" in
  # Stop — исполнитель отдельной сессией `claude --agent <исполнитель>`: шаблон
  # его не проводит, проект может (README рядом, «Проверки исполнителя»).
  SubagentStop | Stop) [ "$(field '.stop_hook_active // false')" = true ] && exit 0 ;;
  PreToolUse) [ "$(field '.tool_name // empty')" = SubagentHandback ] || exit 0 ;;
  *) exit 0 ;;
esac

cwd=$(field '.cwd // empty')
[ -n "$cwd" ] || cwd=$PWD
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
# Проверки исполняют код дерева (build.rs, node_modules) — только своего.
same_repo "$top" || exit 0
cd "$top" || exit 0

# Метка отчёта агента: `blocked` — отчёт уже держали, `checked` — проверен
# зелёным. Имя — agent_id без символов, которым не место в имени файла.
id=$(field '.agent_id // empty' | LC_ALL=C tr -c 'A-Za-z0-9_.-' '_')
state=$(git rev-parse --path-format=absolute --git-path harness/agent-checks 2>/dev/null)
mark=""
[ -n "$id" ] && [ -n "$state" ] && mark="$state/$id"
# Отказ отчёту без метки повторялся бы на каждой попытке, и после третьей
# Claude Code завершает агента вовсе без отчёта. Лучше пропустить.
[ "$event" = PreToolUse ] && [ -z "$mark" ] && exit 0

if [ -n "$mark" ] && [ -f "$mark" ]; then
  # Отчёт этого агента уже проверен (или уже держался): остановка следом
  # не гоняет проверки второй раз, и метка уходит — продолженный потом агент
  # проверяется заново.
  [ "$event" = SubagentStop ] && rm -f "$mark"
  exit 0
fi

remember() {  # <blocked|checked> — только для отчёта: у остановки своя защита
  [ "$event" = PreToolUse ] && [ -n "$mark" ] || return 0
  mkdir -p "$state" 2>/dev/null && printf '%s\n' "$1" > "$mark"
}

changed=$({
  git diff --name-only HEAD -- 2>/dev/null
  git ls-files --others --exclude-standard 2>/dev/null
} | LC_ALL=C sort -u)
[ -n "$changed" ] || exit 0

# Крейты и пакеты — по строке «пакет<TAB>каталог» и «каталог», без повторов.
crates=""
packages=""
rs_files=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  f="$top/$p"
  case "$p" in
    *.rs | Cargo.toml | */Cargo.toml)
      [ "$have_rust" -eq 1 ] || continue
      rust_crate "$f" || continue
      crates="$crates$crate_pkg"$'\t'"$crate_dir"$'\n'
      case "$p" in *.rs) [ -f "$f" ] && rs_files+=("$f") ;; esac
      ;;
    *.ts | *.tsx | tsconfig.json | */tsconfig.json)
      [ "$have_js" -eq 1 ] || continue
      js_package "$f" || continue
      packages="$packages$pkg_dir"$'\n'
      ;;
  esac
done <<EOF
$changed
EOF

report=""
add_report() {  # <заголовок> <вывод>
  local body
  body=$(printf '%s\n' "$2" | head -n "$per_check_lines")
  [ "$(printf '%s\n' "$2" | wc -l)" -gt "$per_check_lines" ] && body="$body"$'\n'"…"
  report="$report$1"$'\n'"$body"$'\n\n'
}

if [ "${#rs_files[@]}" -gt 0 ]; then
  out=$(rust_fmt_check "${rs_files[@]}") || add_report "rustfmt --check: файлы отформатированы не так (cargo fmt)" "$out"
fi
while IFS=$'\t' read -r pkg dir; do
  [ -n "$pkg" ] || continue
  out=$(rust_clippy "$pkg" "$dir") || add_report "clippy: $pkg не проходит -D warnings" "$out"
done <<EOF
$(printf '%s' "$crates" | LC_ALL=C sort -u)
EOF
while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  out=$(js_tsc "$dir") || add_report "tsc: ${dir#"$top"/} не проходит проверку типов" "$out"
done <<EOF
$(printf '%s' "$packages" | LC_ALL=C sort -u)
EOF

if [ -z "$report" ]; then
  remember checked
  exit 0
fi
remember blocked

reason=$(printf '%s\n\n%s' \
  "Работа не сдана: по затронутым пакетам красные быстрые проверки. Исправь их в пределах задачи и проверь снова. Если исправление — решение вне задачи, верни вопрос и перечисли красное в отчёте: второй раз этот хук не остановит." \
  "$report" | head -n "$reason_lines")

if [ "$event" = PreToolUse ]; then
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
else
  jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
fi
exit 0
