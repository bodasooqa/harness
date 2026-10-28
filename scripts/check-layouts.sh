#!/usr/bin/env bash
# Проверка пяти раскладок шаблона.
#
# Для каждой раскладки `copier copy` из текущего рабочего каталога репозитория
# (с незакоммиченными правками) во временный каталог, затем в нём проверки
# стека: Rust — fmt, clippy, тесты; фронт — install, typecheck, lint, тесты,
# сборка; форма документов catalog — тест knowledge/tests/spec-unfolded.sh;
# обвязка — шаг harness-files: набор агентов и скиллов, нет остатков Jinja,
# доменных слов и каталога `_partials`.
#
# Шестой прогон, monolith, — полная раскладка с формой документов monolith,
# путями старой формы и модулем Linear: только copier и harness-files (стек тот
# же, что у full), плюс проверка, что тексты ссылаются на файлы-журналы, а не
# на каталоги.
#
# Использование:
#   scripts/check-layouts.sh               все пять раскладок и monolith
#   scripts/check-layouts.sh --only <имя>  один прогон
#
# Прогоны: full, rust-workspace, rust-crate, web-monorepo, web-app, monolith.
# Код выхода ненулевой, если хоть один прогон красный. Временные каталоги
# удаляются за собой.
set -euo pipefail

repo=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)

all_layouts="full rust-workspace rust-crate web-monorepo web-app monolith"

usage() {
  sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
    # Ответы проекта старой формы: ТЗ и журналы одним файлом, таблица этапов в
    # README, Linear с префиксом.
    monolith)
      echo "--data rust=true --data frontend=true --data doc_form=monolith" \
        "--data spec_path=docs/DENSITY_SCREENER_SPEC.md" \
        "--data revisions_path=docs/DENSITY_SCREENER_SPEC_REVISIONS.md" \
        "--data decisions_path=knowledge/decisions.md" \
        "--data lessons_path=knowledge/lessons.md" \
        "--data open_questions_path=knowledge/open-questions.md" \
        "--data stages_path=README.md" \
        "--data linear=true --data tracker_prefix=DEN"
      ;;
  esac
}

# Что обязано быть (+) и чего быть не должно (-) в раскладке.
# shellcheck disable=SC2329
layout_shape() {
  case "$1" in
    full) echo "+crates/app/Cargo.toml +apps/web/package.json +packages/uikit/package.json +turbo.json -src" ;;
    rust-workspace) echo "+crates/app/Cargo.toml -package.json -src -apps -.harness/biome.json" ;;
    rust-crate) echo "+src/main.rs -crates -package.json -.harness/biome.json" ;;
    web-monorepo) echo "+apps/web/package.json +packages/uikit/package.json -Cargo.toml -src" ;;
    web-app) echo "+src/main.tsx +src/components/ui/.gitkeep +components.json -apps -packages -turbo.json -Cargo.toml" ;;
    monolith) echo "+crates/app/Cargo.toml +apps/web/package.json -docs/spec -knowledge/decisions -knowledge/spec-unfolded.sh" ;;
  esac
}

# Значение ключа из файла ответов проекта (`ключ: значение`).
# shellcheck disable=SC2329
answer() {
  sed -n "s/^$1: //p" .copier-answers.yml | tr -d "'\""
}

# Файлы обвязки, которые рендерит шаблон: агенты, скиллы шаблона (без
# generated OpenSpec), правила процесса, стартовые CLAUDE.md и конфиг OpenSpec.
# shellcheck disable=SC2329
harness_text_files() {
  find .claude/agents .claude/skills -type f -name '*.md' -not -path '.claude/skills/openspec-*'
  printf '%s\n' CLAUDE.md .harness/process.md openspec/config.yaml
}

# Обвязка раскладки: набор агентов и скиллов по ответам, нет остатков Jinja,
# доменных слов и `_partials`; в форме monolith — ссылки на файлы, а не на
# каталоги. Зовётся через step.
# shellcheck disable=SC2329
check_harness_files() {
  local agents skills expected found file path bad=0
  agents="spec-auditor"
  skills="change-finish contract-change knowledge-note stage-acceptance stage-grooming"
  if [[ $(answer rust) == true ]]; then
    agents="$agents rust-developer rust-reviewer"
  fi
  if [[ $(answer frontend) == true ]]; then
    agents="$agents frontend-developer frontend-reviewer"
    skills="$skills uikit-component"
  fi
  [[ $(answer linear) == true ]] && skills="$skills linear-triage"
  [[ $(answer telegram) == true ]] && skills="$skills telegram-bot"

  expected=$(tr ' ' '\n' <<<"$agents" | sort | tr '\n' ' ')
  found=$(find .claude/agents -name '*.md' -exec basename {} .md \; | sort | tr '\n' ' ')
  if [[ "$found" != "$expected" ]]; then
    echo "агенты: ждали «${expected}», есть «${found}»"
    bad=1
  fi
  expected=$(tr ' ' '\n' <<<"$skills" | sort | tr '\n' ' ')
  found=$(find .claude/skills -mindepth 1 -maxdepth 1 -type d -not -name 'openspec-*' -exec basename {} \; | sort | tr '\n' ' ')
  if [[ "$found" != "$expected" ]]; then
    echo "скиллы: ждали «${expected}», есть «${found}»"
    bad=1
  fi

  local -a files=()
  while IFS= read -r file; do
    files+=("$file")
  done < <(harness_text_files)

  for file in "${files[@]}"; do
    [[ -f "$file" ]] || { echo "нет $file"; bad=1; continue; }
    if grep -n '{{\|{%\|%}\|}}' "$file"; then
      echo "остаток Jinja в $file"
      bad=1
    fi
  done

  if [[ -n $(find . -name _partials -not -path './node_modules/*') ]]; then
    echo "в проекте есть _partials"
    bad=1
  fi

  # Доменные слова — по всему проекту, кроме зависимостей, сборки, generated
  # OpenSpec и файла ответов (в нём путь к шаблону). В monolith пути и префикс
  # задач берутся из ответов старой формы, поэтому там ищутся только слова домена.
  local words='плотност|Плотност|трейдер|Трейдер'
  [[ "$layout" == monolith ]] || words="$words|[Ss]creener|SCREENER|DEN-"
  if grep -rnE "$words" . \
    --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=target \
    --exclude-dir=.pi --exclude-dir=opsx --exclude-dir='openspec-*' \
    --exclude-dir=dist --exclude-dir=.turbo \
    --exclude=.copier-answers.yml --exclude=bun.lock; then
    echo "доменные слова в проекте"
    bad=1
  fi

  if [[ "$layout" == monolith ]]; then
    for path in spec_path revisions_path decisions_path lessons_path; do
      path=$(answer "$path")
      if grep -nF "$path/" "${files[@]}"; then
        echo "ссылка на каталог $path/ в форме monolith"
        bad=1
      fi
    done
    for file in .claude/skills/knowledge-note/SKILL.md .claude/skills/change-finish/SKILL.md; do
      grep -qF "$(answer decisions_path)" "$file" || { echo "в $file нет $(answer decisions_path)"; bad=1; }
    done
    if grep -n 'spec-unfolded' "${files[@]}"; then
      echo "ссылка на скрипт формы catalog в форме monolith"
      bad=1
    fi
    grep -qF 'DEN-N' .claude/skills/change-finish/SKILL.md || { echo "в change-finish нет DEN-N"; bad=1; }
  fi
  return "$bad"
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
  printf '  %-14s' "$name"
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
  copied=0

  # shellcheck disable=SC2046 # ответы раскладки — отдельные слова намеренно
  if ! copier copy --quiet --defaults --trust --vcs-ref=HEAD \
    --data project_name=demo $(layout_data "$layout") \
    "$repo" "$dst" >>"$log" 2>&1; then
    printf '  %-14sFAIL\n' "copier"
    tail -n 30 "$log" | sed 's/^/    /'
    layout_ok=0
  else
    printf '  %-14sok\n' "copier"
    copied=1
    step "shape" check_shape
    step "harness-files" check_harness_files
  fi
  # Стек monolith тот же, что у full: собирать его второй раз незачем.
  if ((copied)) && [[ "$layout" != monolith ]]; then
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
