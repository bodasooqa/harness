#!/usr/bin/env bash
# Проверка пяти раскладок шаблона.
#
# Для каждой раскладки `copier copy` из текущего рабочего каталога репозитория
# (с незакоммиченными правками) во временный каталог, затем в нём проверки
# стека: Rust — fmt, clippy, тесты; фронт — install, typecheck, lint, тесты,
# сборка; обвязка — шаг harness-files: набор агентов Claude Code и Pi и скиллов,
# нет остатков Jinja, доменных слов и `_partials`; хуки и git-хуки — тесты хуков
# `.harness/hooks/tests/run.sh`, прослойки Pi `pi.test.ts`, `knowledge/tests/`,
# `lefthook validate`, actionlint (если установлен) и shellcheck по скриптам
# `.harness/` и `knowledge/`; обновление харнесса — тесты `.harness/update/tests/`
# и нет маркеров конфликта в сгенерированном проекте.
#
# Шестой прогон, monolith, — полная раскладка с формой документов monolith,
# путями старой формы и модулем Linear: copier, harness-files и проверки хуков
# (стек тот же, что у full, его не собираем; bun install — только ради biome и
# tsc в тестах хуков), плюс проверка, что тексты ссылаются на файлы-журналы,
# а не на каталоги.
#
# lefthook берётся `bunx lefthook@2.1.12` через обёртку в PATH: в раскладках
# без фронта его в node_modules нет.
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
  sed -n '2,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
  local common="+.harness/hooks/dispatch.sh +.harness/hooks/tests/run.sh +.harness/local/README.md"
  common="$common +.claude/settings.json +lefthook.yml +.harness/lefthook.yml"
  common="$common +.github/workflows/ci.yml +.github/workflows/harness.yml +knowledge/due.sh"
  common="$common +.pi/settings.json +.pi/extensions/harness.ts +.harness/hooks/tests/pi.test.ts"
  common="$common +.github/workflows/harness-update.yml +.github/workflows/harness-automerge.yml"
  common="$common +.harness/update/next-version.sh +.harness/update/conflict-markers.sh"
  case "$1" in
    full) echo "$common +crates/app/Cargo.toml +apps/web/package.json +packages/uikit/package.json +turbo.json -src +.harness/biome.json +.harness/hooks/rust-clippy.sh +.harness/hooks/js-typecheck.sh +knowledge/index.sh" ;;
    rust-workspace) echo "$common +crates/app/Cargo.toml -package.json -src -apps -.harness/biome.json -.harness/hooks/js-fmt.sh" ;;
    rust-crate) echo "$common +src/main.rs -crates -package.json -.harness/biome.json -.harness/hooks/js-typecheck.sh" ;;
    web-monorepo) echo "$common +apps/web/package.json +packages/uikit/package.json -Cargo.toml -src +.harness/biome.json -.harness/hooks/rust-fmt.sh" ;;
    web-app) echo "$common +src/main.tsx +src/components/ui/.gitkeep +components.json -apps -packages -turbo.json -Cargo.toml -.harness/hooks/rust-clippy.sh" ;;
    monolith) echo "$common +crates/app/Cargo.toml +apps/web/package.json -docs/spec -knowledge/decisions -knowledge/spec-unfolded.sh -knowledge/index.sh" ;;
  esac
}

# Тесты knowledge/ — каждый исполняемым файлом, как их зовут lefthook и CI.
# shellcheck disable=SC2329
run_knowledge_tests() {
  local t
  for t in knowledge/tests/*.sh; do
    echo "== $t"
    "./$t" || return 1
  done
}

# Тесты хуков — как их зовёт pre-push lefthook: с GIT_DIR и GIT_INDEX_FILE
# в окружении. Здесь они указывают на репозиторий-приманку — обычный, с рабочим
# деревом, как у проекта. Тест, который не очистил окружение для своего git,
# пишет в приманку, а не во временный репозиторий: заводит ссылки или меняет
# конфиг. Так `git init --bare` теста пометил настоящий клон screener как bare.
# Под настоящим хуком такой тест писал бы в репозиторий проекта.
# shellcheck disable=SC2329
under_git_hook() {
  local bait config refs
  bait=$(mktemp -d "$work/bait.XXXXXX")
  git init -q "$bait"
  config=$(git --git-dir="$bait/.git" config --local --list)
  GIT_DIR=$bait/.git GIT_INDEX_FILE=$bait/.git/index "$@" || return 1
  refs=$(git --git-dir="$bait/.git" for-each-ref)
  if [[ -n "$refs" ]]; then
    printf 'тесты писали в репозиторий из GIT_DIR:\n%s\n' "$refs"
    return 1
  fi
  if [[ "$(git --git-dir="$bait/.git" config --local --list)" != "$config" ]]; then
    printf 'тесты изменили конфиг репозитория из GIT_DIR:\n'
    diff <(printf '%s\n' "$config") <(git --git-dir="$bait/.git" config --local --list)
    return 1
  fi
}

# Тесты обновления харнесса — так же, как их зовёт джоба harness в CI проекта.
# shellcheck disable=SC2329
run_update_tests() {
  local t
  for t in .harness/update/tests/*.sh; do
    echo "== $t"
    "./$t" || return 1
  done
}

# Линт скриптов обвязки и knowledge/ (shellcheck) с уровня warning: замечания
# info и style — идиомы тестов (`проверка && ok || bad`) и source по пути от
# самого скрипта.
# shellcheck disable=SC2329
run_shellcheck() {
  local -a files=()
  local file
  while IFS= read -r file; do
    files+=("$file")
  done < <(find .harness knowledge -type f -name '*.sh' | sort)
  shellcheck -x -S warning "${files[@]}"
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
  find .claude/agents .claude/skills .pi/agents -type f -name '*.md' -not -path '.claude/skills/openspec-*'
  printf '%s\n' CLAUDE.md .harness/process.md openspec/config.yaml
}

# Обвязка раскладки: набор агентов и скиллов по ответам, нет остатков Jinja,
# доменных слов и `_partials`; в форме monolith — ссылки на файлы, а не на
# каталоги. Зовётся через step.
# shellcheck disable=SC2329
check_harness_files() {
  local agents skills expected found file path bad=0
  agents="spec-auditor"
  skills="change-finish contract-change harness-upstream knowledge-note stage-acceptance stage-grooming"
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
  for path in .claude/agents .pi/agents; do
    found=$(find "$path" -name '*.md' -exec basename {} .md \; | sort | tr '\n' ' ')
    if [[ "$found" != "$expected" ]]; then
      echo "агенты $path: ждали «${expected}», есть «${found}»"
      bad=1
    fi
  done
  # Агент Pi без модели молча берёт модель родителя: модель явная у каждого.
  for file in .pi/agents/*.md; do
    grep -qE '^model: [^ ]+/' "$file" || { echo "нет model: провайдер/модель в $file"; bad=1; }
  done
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
  # В `.pi/` generated OpenSpec пропущен выше целиком, файлы шаблона — здесь.
  if grep -rnE "$words" .pi/agents .pi/extensions .pi/settings.json; then
    echo "доменные слова в .pi/"
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
# Заданный в окружении (CI кладёт его в кеш) не перекрывается.
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$work/cargo-target}"
# lefthook для раскладок без фронта и для `lefthook validate`.
mkdir -p "$work/bin"
printf '#!/bin/sh\nexec bunx lefthook@2.1.12 "$@"\n' >"$work/bin/lefthook"
chmod +x "$work/bin/lefthook"
export PATH="$work/bin:$PATH"

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
  fi
  if ((copied)); then
    if [[ "$layout" == monolith ]]; then
      step "bun install" bun install
    fi
    # Проект — git-репозиторий, как у пользователя: actionlint ищет корень
    # по .git, хуки — общий каталог.
    step "git init" git init -q -b main
    step "hook tests" .harness/hooks/tests/run.sh
    step "pi tests" bun test ./.harness/hooks/tests/pi.test.ts
    step "hooks as hook" under_git_hook .harness/hooks/tests/run.sh
    step "pi as hook" under_git_hook bun test ./.harness/hooks/tests/pi.test.ts
    step "knowledge" run_knowledge_tests
    step "update tests" run_update_tests
    step "markers" .harness/update/conflict-markers.sh
    step "lefthook" lefthook validate
    if command -v actionlint >/dev/null 2>&1; then
      step "actionlint" actionlint
    fi
    step "shellcheck" run_shellcheck
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
