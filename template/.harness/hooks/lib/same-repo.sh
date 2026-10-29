#!/usr/bin/env bash
# Чей файл правится: проверки, которые исполняют код дерева (`tsc` из его
# node_modules, `cargo` с его build.rs, макросами и rust-toolchain.toml), идут
# только по своему репозиторию — этому дереву или соседнему дереву того же
# репозитория. Правка файла в чужом клоне — не повод исполнять его код.
#
# Своё — корень дерева файла есть в `git worktree list` проекта. Сравнение
# общего каталога git (`--git-common-dir`) не годится: каталог с подложным
# файлом `.git`, указывающим на gitdir проекта, его проходит, а в список
# деревьев проекта он не попадает.

# same_repo <каталог> — успех, если каталог в зарегистрированном дереве проекта.
same_repo() {
  local project=${CLAUDE_PROJECT_DIR:-$PWD} top tree
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
  top=$(cd "$top" && pwd -P) || return 1
  while IFS= read -r tree; do
    [ "$(cd "$tree" 2>/dev/null && pwd -P)" = "$top" ] && return 0
  done < <(git -C "$project" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
  return 1
}
