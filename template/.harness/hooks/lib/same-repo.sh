#!/usr/bin/env bash
# Чей файл правится: проверки, которые исполняют код дерева (`tsc` из его
# node_modules, `cargo` с его build.rs, макросами и rust-toolchain.toml), идут
# только по своему репозиторию — этому дереву или соседнему дереву того же
# репозитория. Правка файла в чужом клоне — не повод исполнять его код.
#
# Своё — каталог физически лежит в дереве из `git worktree list` проекта,
# и корень по git у него — это самое дерево. Порядок важен:
#   - сначала путь: ответу git из чужого каталога верить нельзя — его
#     `core.worktree` или подложный `.git` назовут корнем дерево проекта,
#     а запуск пойдёт в чужом каталоге. Git в каталоге вне деревьев проекта
#     не запускается вовсе;
#   - потом git: клон, вложенный в дерево проекта, лежит в нём физически,
#     но корень у него свой;
#   - и последнее: игнорируемое (`tmp/`, `node_modules/`, распакованный
#     чужой пакет) проекту не принадлежит, хоть и лежит в дереве.
# Неотслеживаемый, но не игнорируемый каталог считается своим: новый пакет
# до первого коммита — такой же.

# same_repo <каталог> — успех, если каталог в зарегистрированном дереве проекта.
same_repo() {
  local project=${CLAUDE_PROJECT_DIR:-$PWD} dir tree top=""
  dir=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  while IFS= read -r tree; do
    tree=$(cd "$tree" 2>/dev/null && pwd -P) || continue
    case "$dir/" in
      "$tree"/*) ;;
      *) continue ;;
    esac
    # Деревья бывают вложены одно в другое: корень по git сверяется с каждым
    # подходящим, а считается один раз.
    if [ -z "$top" ]; then
      top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 1
      top=$(cd "$top" 2>/dev/null && pwd -P) || return 1
    fi
    if [ "$top" = "$tree" ]; then
      git -C "$tree" check-ignore -q -- "$dir" 2>/dev/null && return 1
      return 0
    fi
  done < <(git -C "$project" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
  return 1
}
