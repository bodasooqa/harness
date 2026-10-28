#!/usr/bin/env bash
# Проверка пяти раскладок шаблона.
#
# Для каждой раскладки `copier copy` из текущего рабочего каталога репозитория
# (с незакоммиченными правками) во временный каталог, затем в нём проверки
# стека: Rust — fmt, clippy, тесты; фронт — install, typecheck, lint, тесты,
# сборка; форма документов catalog — тест knowledge/tests/spec-unfolded.sh.
#
# Использование:
#   scripts/check-layouts.sh               все пять раскладок
#   scripts/check-layouts.sh --only <имя>  одна раскладка
#
# Раскладки: full, rust-workspace, rust-crate, web-monorepo, web-app.
# Код выхода ненулевой, если хоть одна раскладка красная. Временные каталоги
# удаляются за собой.
set -euo pipefail

repo=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)

all_layouts="full rust-workspace rust-crate web-monorepo web-app"

usage() {
  sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

layouts=$all_layouts
case "${1:-}" in
  "") ;;
  --only)
    if [[ -z "${2:-}" ]] || [[ " $all_layouts " != *" $2 "* ]]; then
      printf 'check-layouts.sh: --only ждёт одно из: %s\n' "$all_layouts" >&2
      exit 2
    fi
    layouts=$2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    printf 'check-layouts.sh: непонятный аргумент %s\n' "$1" >&2
    exit 2
    ;;
esac

# Ответы шаблона на раскладку: rust, frontend, monorepo. Для Rust с фронтом
# monorepo не передаётся — вопрос не задаётся, значение вычисляет шаблон.
layout_data() {
  case "$1" in
    full) echo "--data rust=true --data frontend=true" ;;
    rust-workspace) echo "--data rust=true --data frontend=false --data monorepo=true" ;;
    rust-crate) echo "--data rust=true --data frontend=false --data monorepo=false" ;;
    web-monorepo) echo "--data rust=false --data frontend=true --data monorepo=true" ;;
    web-app) echo "--data rust=false --data frontend=true --data monorepo=false" ;;
  esac
}

# Что обязано быть (+) и чего быть не должно (-) в раскладке.
# shellcheck disable=SC2329
layout_shape() {
  case "$1" in
    full) echo "+crates/app/Cargo.toml +apps/web/package.json +packages/uikit/package.json +turbo.json -src" ;;
    rust-workspace) echo "+crates/app/Cargo.toml -package.json -src -apps -.harness" ;;
    rust-crate) echo "+src/main.rs -crates -package.json -.harness" ;;
    web-monorepo) echo "+apps/web/package.json +packages/uikit/package.json -Cargo.toml -src" ;;
    web-app) echo "+src/main.tsx +src/components/ui/.gitkeep +components.json -apps -packages -turbo.json -Cargo.toml" ;;
  esac
}

# Проверка формы раскладки по layout_shape; зовётся через step.
# shellcheck disable=SC2329
check_shape() {
  local item path
  for item in $(layout_shape "$layout"); do
    path=${item#?}
    case "$item" in
      +*) [[ -e "$path" ]] || { echo "нет $path"; return 1; } ;;
      -*) [[ ! -e "$path" ]] || { echo "лишний $path"; return 1; } ;;
    esac
  done
}

work=$(mktemp -d "${TMPDIR:-/tmp}/check-layouts.XXXXXX")
trap 'rm -rf "$work"' EXIT
# Общий каталог сборки Rust на все раскладки: зависимости собираются один раз.
export CARGO_TARGET_DIR="$work/cargo-target"

summary=""
failed=0

# Шаг проверки: имя и команда. Вывод — в журнал раскладки; на провале хвост
# журнала печатается сразу.
step() {
  local name=$1
  shift
  printf '  %-12s' "$name"
  if (cd "$dst" && "$@") >>"$log" 2>&1; then
    printf 'ok\n'
  else
    printf 'FAIL\n'
    printf '    --- хвост журнала %s ---\n' "$name"
    tail -n 30 "$log" | sed 's/^/    /'
    layout_ok=0
  fi
}

for layout in $layouts; do
  printf '== %s\n' "$layout"
  dst="$work/$layout"
  log="$work/$layout.log"
  layout_ok=1

  # shellcheck disable=SC2046 # ответы раскладки — отдельные слова намеренно
  if ! copier copy --quiet --defaults --trust --vcs-ref=HEAD \
    --data project_name=demo $(layout_data "$layout") \
    "$repo" "$dst" >>"$log" 2>&1; then
    printf '  %-12sFAIL\n' "copier"
    tail -n 30 "$log" | sed 's/^/    /'
    layout_ok=0
  else
    printf '  %-12sok\n' "copier"
    step "shape" check_shape
    if [[ -f "$dst/Cargo.toml" ]]; then
      step "cargo fmt" cargo fmt --check
      step "clippy" cargo clippy --all-targets -- -D warnings
      step "cargo test" cargo test
    fi
    if [[ -f "$dst/package.json" ]]; then
      step "bun install" bun install
      step "typecheck" bun run typecheck
      step "lint" bun run lint
      step "bun test" bun run test
      step "build" bun run build
    fi
    if [[ -f "$dst/knowledge/tests/spec-unfolded.sh" ]]; then
      step "catalog" bash knowledge/tests/spec-unfolded.sh
    fi
  fi

  if ((layout_ok)); then
    summary="$summary$(printf '%-16s ok' "$layout")"$'\n'
  else
    summary="$summary$(printf '%-16s FAIL' "$layout")"$'\n'
    failed=1
  fi
done

printf '\nИтог:\n%s' "$summary"
exit "$failed"
