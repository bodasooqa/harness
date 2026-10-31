#!/usr/bin/env bash
# Ревизии ТЗ, ещё не сведённые в разделы.
#
# Журнал ревизий — каталог, файл на ревизию (`NNNN-1.N.md`), во frontmatter
# каждой — `folded: false|true`. Список несведённых собирается отсюда, а не
# ведётся руками: рукописный список расходится с журналом в первую же неделю.
#
# Режимы:
#   spec-unfolded.sh           печатает несведённые ревизии, по строке на ревизию
#   spec-unfolded.sh --write   переписывает блок между метками
#                              `<!-- несведённые ревизии -->` и
#                              `<!-- /несведённые ревизии -->` в README ТЗ
#
# Пути к ТЗ и журналу берутся из `.rootstock.toml` в корне проекта
# (`spec_path`, `revisions_path`), а не зашиты в скрипт.
set -euo pipefail

root=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
answers="$root/.rootstock.toml"

mode=${1:-}
case "$mode" in
  "" | --write) ;;
  --help | -h)
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    printf 'spec-unfolded.sh: непонятный аргумент %s. Ожидается --write или ничего.\n' "$mode" >&2
    exit 2
    ;;
esac

# Значение ключа из таблицы `[answers]` записи шаблона: `ключ = "значение"`,
# кавычки снимаются. Экранирование в строке не раскрывается: в путях его нет.
answer() {
  local key=$1 value
  value=$(awk -v key="$key" -v q="'" '
    /^[ \t]*\[/ { inside = ($0 ~ /^[ \t]*\[answers\][ \t]*$/); next }
    inside && $0 ~ ("^" key "[ \t]*=") {
      v = substr($0, index($0, "=") + 1)
      sub(/^[ \t]+/, "", v)
      sub(/[ \t]+$/, "", v)
      f = substr(v, 1, 1)
      if (length(v) >= 2 && (f == "\"" || f == q) && substr(v, length(v), 1) == f)
        v = substr(v, 2, length(v) - 2)
      print v
      exit
    }
  ' "$answers")
  if [[ -z "$value" ]]; then
    printf 'spec-unfolded.sh: в %s нет ключа %s\n' "$answers" "$key" >&2
    exit 1
  fi
  # Путь от корня проекта: без ведущего `./` и завершающего `/`.
  value=${value#./}
  value=${value%/}
  printf '%s\n' "$value"
}

# Путь `to` относительно каталога `from`; оба — от корня проекта.
relative_path() {
  local from=$1 to=$2 up=""
  while [[ -n "$from" && "$to" != "$from/"* ]]; do
    if [[ "$from" == */* ]]; then
      from=${from%/*}
    else
      from=""
    fi
    up="../$up"
  done
  if [[ -n "$from" ]]; then
    to=${to#"$from"/}
  fi
  printf '%s%s\n' "$up" "$to"
}

if [[ ! -f "$answers" ]]; then
  printf 'spec-unfolded.sh: нет файла ответов шаблона %s\n' "$answers" >&2
  exit 1
fi

spec_path=$(answer spec_path)
revisions_path=$(answer revisions_path)
spec_readme="$root/$spec_path/README.md"
revisions_dir="$root/$revisions_path"

# Строки списка: `- [1.N](путь) — ГГГГ-ММ-ДД — заголовок`, путь — от README ТЗ.
lines=""
if [[ -d "$revisions_dir" ]]; then
  for file in "$revisions_dir"/[0-9][0-9][0-9][0-9]-*.md; do
    [[ -e "$file" ]] || continue
    # version, date, folded из frontmatter и первый заголовок `# ` после него.
    # Разделитель полей — \037: пробельный IFS склеил бы пустые поля.
    fields=$(awk -v q="'" '
      NR == 1 { if ($0 != "---") exit; in_front = 1; next }
      in_front && $0 == "---" { in_front = 0; next }
      in_front {
        i = index($0, ":")
        if (i == 0) next
        k = substr($0, 1, i - 1)
        v = substr($0, i + 1)
        sub(/^[ \t]+/, "", v)
        sub(/[ \t]+$/, "", v)
        f = substr(v, 1, 1)
        if (length(v) >= 2 && (f == "\"" || f == q) && substr(v, length(v), 1) == f)
          v = substr(v, 2, length(v) - 2)
        meta[k] = v
        next
      }
      !in_front && title == "" && /^# / { title = substr($0, 3) }
      END { printf "%s\037%s\037%s\037%s\n", meta["version"], meta["date"], meta["folded"], title }
    ' "$file")
    IFS=$'\037' read -r version date folded title <<<"$fields"
    name=${file##*/}
    case "$folded" in
      true) continue ;;
      false) ;;
      *)
        printf 'spec-unfolded.sh: у %s во frontmatter нет folded: true|false (найдено «%s»)\n' \
          "$revisions_path/$name" "$folded" >&2
        exit 1
        ;;
    esac
    link=$(relative_path "$spec_path" "$revisions_path/$name")
    line="- [${version:-$name}]($link)"
    [[ -n "$date" ]] && line="$line — $date"
    [[ -n "$title" ]] && line="$line — $title"
    lines="$lines$line"$'\n'
  done
fi

if [[ -z "$mode" ]]; then
  printf '%s' "$lines"
  exit 0
fi

if [[ ! -f "$spec_readme" ]]; then
  printf 'spec-unfolded.sh: нет README ТЗ %s\n' "$spec_readme" >&2
  exit 1
fi

start='<!-- несведённые ревизии -->'
end='<!-- /несведённые ревизии -->'
if ! grep -qxF "$start" "$spec_readme" || ! grep -qxF "$end" "$spec_readme"; then
  printf 'spec-unfolded.sh: в %s нет меток %s и %s\n' "$spec_path/README.md" "$start" "$end" >&2
  exit 1
fi

block=$(mktemp)
out=$(mktemp)
trap 'rm -f "$block" "$out"' EXIT
if [[ -n "$lines" ]]; then
  printf '%s' "$lines" >"$block"
else
  printf 'Несведённых ревизий нет.\n' >"$block"
fi

awk -v start="$start" -v end="$end" -v block="$block" '
  $0 == start {
    print
    while ((getline line < block) > 0) print line
    skip = 1
    next
  }
  $0 == end { skip = 0 }
  !skip { print }
' "$spec_readme" >"$out"
cat "$out" >"$spec_readme"
