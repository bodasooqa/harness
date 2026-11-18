#!/usr/bin/env bash
# Check of the template's five layouts.
#
# For each layout, `rootstock new --version HEAD` from the repository's working
# directory (with uncommitted edits) into a temporary directory, then stack
# checks: Rust — fmt, clippy, tests; frontend — install, typecheck, lint, tests,
# build; harness — the harness-files step: the set of Claude Code and Pi agents
# and skills, no Jinja leftovers, domain words, or `_partials`; hooks and git
# hooks — hook tests `.harness/hooks/tests/run.sh`, Pi shim `pi.test.ts`,
# `knowledge/tests/`, `lefthook validate`, actionlint (if installed), and
# a shellcheck pass over `.harness/` and `knowledge/` scripts; harness update — tests
# `.harness/update/tests/` and no conflict markers in the generated project.
#
# The sixth run, monolith, is the full layout with the monolith document form,
# old-form paths, and the Linear module: rootstock, harness-files, and hook
# checks (the stack is the same as full, so it isn't built; bun install is only
# for biome and tsc in hook tests), plus a check that texts point to journal
# files, not directories.
#
# lefthook comes from `bunx lefthook@2.1.12` via a wrapper in PATH: layouts
# without frontend don't have it in node_modules. rootstock — from PATH or ROOTSTOCK.
#
# Usage:
#   scripts/check-layouts.sh               all five layouts and monolith
#   scripts/check-layouts.sh --only <name> a single run
#
# Runs: full, rust-workspace, rust-crate, web-monorepo, web-app, monolith.
# The exit code is non-zero if any run is red. Temporary directories are
# cleaned up.
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
      printf 'check-layouts.sh: --only expects one of: %s\n' "$all_layouts" >&2
      exit 2
    fi
    layouts=$2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    printf 'check-layouts.sh: unknown argument %s\n' "$1" >&2
    exit 2
    ;;
esac

# Template answers per layout: rust, frontend, monorepo. For Rust with frontend
# monorepo isn't passed — the question isn't asked, the template computes it.
layout_data() {
  case "$1" in
    full) echo "--data rust=true --data frontend=true" ;;
    rust-workspace) echo "--data rust=true --data frontend=false --data monorepo=true" ;;
    rust-crate) echo "--data rust=true --data frontend=false --data monorepo=false" ;;
    web-monorepo) echo "--data rust=false --data frontend=true --data monorepo=true" ;;
    web-app) echo "--data rust=false --data frontend=true --data monorepo=false" ;;
    # Answers of an old-form project: the spec and journals as single files, the
    # stage table in README, Linear with a prefix.
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

# What must be (+) and must not be (-) in the layout.
# shellcheck disable=SC2329
layout_shape() {
  local common="+.harness/hooks/dispatch.sh +.harness/hooks/tests/run.sh +.harness/local/README.md"
  common="$common +.claude/settings.json +lefthook.yml +.harness/lefthook.yml"
  common="$common +.github/workflows/ci.yml +.github/workflows/harness.yml +knowledge/due.sh"
  common="$common +.pi/settings.json +.pi/extensions/harness.ts +.harness/hooks/tests/pi.test.ts"
  common="$common +.codex/hooks.json +.harness/hooks/codex.sh +.harness/hooks/tests/codex.test.sh"
  common="$common +.github/workflows/harness-update.yml +.github/workflows/harness-automerge.yml"
  common="$common +.harness/update/next-version.sh +.harness/update/conflict-markers.sh +.gitattributes"
  common="$common +AGENTS.md +CLAUDE.md"
  local packages="+apps/web/AGENTS.md +apps/web/CLAUDE.md +packages/uikit/AGENTS.md +packages/uikit/CLAUDE.md"
  case "$1" in
    full) echo "$common $packages +crates/app/Cargo.toml +apps/web/package.json +packages/uikit/package.json +turbo.json -src +.harness/biome.json +.harness/hooks/rust-clippy.sh +.harness/hooks/js-typecheck.sh +knowledge/index.sh" ;;
    rust-workspace) echo "$common +crates/app/Cargo.toml -package.json -src -apps -.harness/biome.json -.harness/hooks/js-fmt.sh" ;;
    rust-crate) echo "$common +src/main.rs -crates -package.json -.harness/biome.json -.harness/hooks/js-typecheck.sh" ;;
    web-monorepo) echo "$common $packages +apps/web/package.json +packages/uikit/package.json -Cargo.toml -src +.harness/biome.json -.harness/hooks/rust-fmt.sh" ;;
    web-app) echo "$common +src/main.tsx +src/components/ui/.gitkeep +components.json -apps -packages -turbo.json -Cargo.toml -.harness/hooks/rust-clippy.sh" ;;
    monolith) echo "$common $packages +crates/app/Cargo.toml +apps/web/package.json -docs/spec -knowledge/decisions -knowledge/spec-unfolded.sh -knowledge/index.sh" ;;
  esac
}

# knowledge/ tests — each as an executable, the way lefthook and CI call them.
# shellcheck disable=SC2329
run_knowledge_tests() {
  local t
  for t in knowledge/tests/*.sh; do
    echo "== $t"
    "./$t" || return 1
  done
}

# Hook tests — the way lefthook's pre-push calls them: with GIT_DIR and
# GIT_INDEX_FILE in the environment. Here they point to a bait repository — a
# regular one, with a working tree, like a project's. A test that didn't clear
# the environment for its git writes into the bait rather than its temporary
# repository: creates refs or changes the config. That's how a test's
# `git init --bare` marked the real screener clone as bare. Under a real hook
# such a test would write into the project's repository.
# shellcheck disable=SC2329
under_git_hook() {
  local bait config refs
  bait=$(mktemp -d "$work/bait.XXXXXX")
  git init -q "$bait"
  config=$(git --git-dir="$bait/.git" config --local --list)
  GIT_DIR=$bait/.git GIT_INDEX_FILE=$bait/.git/index "$@" || return 1
  refs=$(git --git-dir="$bait/.git" for-each-ref)
  if [[ -n "$refs" ]]; then
    printf 'tests wrote into the GIT_DIR repository:\n%s\n' "$refs"
    return 1
  fi
  if [[ "$(git --git-dir="$bait/.git" config --local --list)" != "$config" ]]; then
    printf 'tests changed the config of the GIT_DIR repository:\n'
    diff <(printf '%s\n' "$config") <(git --git-dir="$bait/.git" config --local --list)
    return 1
  fi
}

# Harness update tests — the same way the harness job in the project's CI calls them.
# shellcheck disable=SC2329
run_update_tests() {
  local t
  for t in .harness/update/tests/*.sh; do
    echo "== $t"
    "./$t" || return 1
  done
}

# Lint of harness and knowledge/ scripts (shellcheck) from the warning level:
# info and style remarks are test idioms (`check && ok || bad`) and source by a
# path relative to the script itself.
# shellcheck disable=SC2329
run_shellcheck() {
  local -a files=()
  local file
  while IFS= read -r file; do
    files+=("$file")
  done < <(find .harness knowledge -type f -name '*.sh' | sort)
  shellcheck -x -S warning "${files[@]}"
}

# Value of a key from the `[answers]` table of the project record (`key = "value"`).
# shellcheck disable=SC2329
answer() {
  awk -v key="$1" '
    /^[ \t]*\[/ { inside = ($0 ~ /^[ \t]*\[answers\][ \t]*$/); next }
    inside && $0 ~ ("^" key "[ \t]*=") { v = substr($0, index($0, "=") + 1); gsub(/^[ \t\047"]+|[ \t\047"]+$/, "", v); print v; exit }
  ' .rootstock.toml
}

# Harness files the template renders: agents, template skills (without the
# generated OpenSpec ones), process rules, starter AGENTS.md and CLAUDE.md, and
# the OpenSpec config.
# shellcheck disable=SC2329
harness_text_files() {
  find .claude/agents .claude/skills .pi/agents -type f -name '*.md' -not -path '.claude/skills/openspec-*'
  printf '%s\n' AGENTS.md CLAUDE.md .harness/process.md openspec/config.yaml
}

# The layout's harness: the set of agents and skills per the answers, no Jinja
# leftovers, domain words, or `_partials`; in the monolith form — links to files,
# not directories. Called via step.
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
      echo "agents $path: expected '${expected}', got '${found}'"
      bad=1
    fi
  done
  found=$(find .codex/agents -name '*.toml' -exec basename {} .toml \; | sort | tr '\n' ' ')
  if [[ "$found" != "$expected" ]]; then
    echo "Codex agents: expected '${expected}', got '${found}'"
    bad=1
  fi
  for file in .codex/agents/*.toml; do
    bun -e 'const profile = Bun.TOML.parse(await Bun.file(process.argv[1]).text());
      if (profile.name !== process.argv[2] || !profile.description || !profile.developer_instructions) process.exit(1);' \
      "$file" "$(basename "$file" .toml)" || { echo "invalid Codex profile $file"; bad=1; }
  done
  # A Pi agent without a model silently takes the parent's: every one has an explicit model.
  for file in .pi/agents/*.md; do
    grep -qE '^model: [^ ]+/' "$file" || { echo "no model: provider/model in $file"; bad=1; }
  done
  expected=$(tr ' ' '\n' <<<"$skills" | sort | tr '\n' ' ')
  found=$(find .claude/skills -mindepth 1 -maxdepth 1 -type d -not -name 'openspec-*' -exec basename {} \; | sort | tr '\n' ' ')
  if [[ "$found" != "$expected" ]]; then
    echo "skills: expected '${expected}', got '${found}'"
    bad=1
  fi

  # Skill extension point: every template skill reads its addendum.
  for path in $skills; do
    grep -qF ".harness/local/skills/$path.md" ".claude/skills/$path/SKILL.md" ||
      { echo "skill $path doesn't read .harness/local/skills/$path.md"; bad=1; }
    grep -qF ".claude/skills/$path/SKILL.md" ".agents/skills/$path/SKILL.md" ||
      { echo "Codex skill $path doesn't point at the shared skill"; bad=1; }
  done
  found=$(find .agents/skills -mindepth 1 -maxdepth 1 -type d -not -name 'openspec-*' -exec basename {} \; | sort | tr '\n' ' ')
  if [[ "$found" != "$expected" ]]; then
    echo "Codex skills: expected '${expected}', got '${found}'"
    bad=1
  fi
  if command -v openspec >/dev/null && [[ ! -f .agents/skills/openspec-propose/SKILL.md ]]; then
    echo "OpenSpec did not install its Codex skills"
    bad=1
  fi

  file=.github/workflows/harness.yml
  sed -n '/^            harness:$/,/^$/p' "$file" | grep -qxF '              - .codex/**' ||
    { echo "Codex changes do not trigger the harness job"; bad=1; }
  grep -qxF '        run: bash ./.harness/hooks/tests/codex.test.sh' "$file" ||
    { echo "the harness job does not run the Codex adapter tests"; bad=1; }

  # Project rules are in AGENTS.md; CLAUDE.md only includes them and the process
  # rules for Claude Code: an `@file` import is a whole line.
  for path in @AGENTS.md @.harness/process.md; do
    grep -qxF "$path" CLAUDE.md || { echo "CLAUDE.md doesn't import ${path#@}"; bad=1; }
  done
  grep -qF '.harness/process.md' AGENTS.md || { echo "AGENTS.md doesn't name .harness/process.md"; bad=1; }

  local -a files=()
  while IFS= read -r file; do
    files+=("$file")
  done < <(harness_text_files)

  for file in "${files[@]}"; do
    [[ -f "$file" ]] || { echo "missing $file"; bad=1; continue; }
    if grep -n '{{\|{%\|%}\|}}' "$file"; then
      echo "Jinja leftover in $file"
      bad=1
    fi
  done

  if [[ -n $(find . -name _partials -not -path './node_modules/*') ]]; then
    echo "the project has _partials"
    bad=1
  fi

  # Domain words — across the whole project except dependencies, build output,
  # generated OpenSpec, and the template record (it holds the template path). In
  # monolith the paths and task prefix come from old-form answers, so only domain
  # words are searched there. Both languages: texts were Russian before v2.0.0.
  local words='[Dd]ensit|[Tt]rader|плотност|Плотност|трейдер|Трейдер'
  [[ "$layout" == monolith ]] || words="$words|[Ss]creener|SCREENER|DEN-"
  if grep -rnE "$words" . \
    --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=target \
    --exclude-dir=.pi --exclude-dir=opsx --exclude-dir='openspec-*' \
    --exclude-dir=dist --exclude-dir=.turbo \
    --exclude=.rootstock.toml --exclude=bun.lock; then
    echo "domain words in the project"
    bad=1
  fi
  # In `.pi/` the generated OpenSpec is skipped above entirely; template files are checked here.
  if grep -rnE "$words" .pi/agents .pi/extensions .pi/settings.json; then
    echo "domain words in .pi/"
    bad=1
  fi

  if [[ "$layout" == monolith ]]; then
    for path in spec_path revisions_path decisions_path lessons_path; do
      path=$(answer "$path")
      if grep -nF "$path/" "${files[@]}"; then
        echo "link to directory $path/ in the monolith form"
        bad=1
      fi
    done
    for file in .claude/skills/knowledge-note/SKILL.md .claude/skills/change-finish/SKILL.md; do
      grep -qF "$(answer decisions_path)" "$file" || { echo "$file lacks $(answer decisions_path)"; bad=1; }
    done
    if grep -n 'spec-unfolded' "${files[@]}"; then
      echo "link to a catalog-form script in the monolith form"
      bad=1
    fi
    grep -qF 'DEN-N' .claude/skills/change-finish/SKILL.md || { echo "change-finish lacks DEN-N"; bad=1; }
  fi
  return "$bad"
}

# Check of the layout's shape per layout_shape; called via step.
# shellcheck disable=SC2329
check_shape() {
  local item path
  for item in $(layout_shape "$layout"); do
    path=${item#?}
    case "$item" in
      +*) [[ -e "$path" ]] || { echo "missing $path"; return 1; } ;;
      -*) [[ ! -e "$path" ]] || { echo "unexpected $path"; return 1; } ;;
    esac
  done
}

work=$(mktemp -d "${TMPDIR:-/tmp}/check-layouts.XXXXXX")
trap 'rm -rf "$work"' EXIT
# A shared Rust build directory for all layouts: dependencies are built once.
# One set in the environment (CI caches it) isn't overridden.
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$work/cargo-target}"
# lefthook for layouts without frontend and for `lefthook validate`.
mkdir -p "$work/bin"
printf '#!/bin/sh\nexec bunx lefthook@2.1.12 "$@"\n' >"$work/bin/lefthook"
chmod +x "$work/bin/lefthook"
export PATH="$work/bin:$PATH"
rootstock=${ROOTSTOCK:-rootstock}

summary=""
failed=0

# A check step: name and command. Output goes to the layout's log; on failure
# the log tail is printed right away.
step() {
  local name=$1
  shift
  printf '  %-14s' "$name"
  if (cd "$dst" && "$@") >>"$log" 2>&1; then
    printf 'ok\n'
  else
    printf 'FAIL\n'
    printf '    --- log tail %s ---\n' "$name"
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

  # shellcheck disable=SC2046 # layout answers are separate words on purpose
  if ! "$rootstock" new --version HEAD --defaults --trust \
    --data project_name=demo $(layout_data "$layout") \
    "$repo" "$dst" >>"$log" 2>&1; then
    printf '  %-14sFAIL\n' "rootstock"
    tail -n 30 "$log" | sed 's/^/    /'
    layout_ok=0
  else
    printf '  %-14sok\n' "rootstock"
    copied=1
    step "shape" check_shape
    step "harness-files" check_harness_files
  fi
  # The monolith stack is the same as full: no point building it twice.
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
    # The project is a git repository, as for the user: actionlint finds the
    # root by .git, hooks find the shared directory.
    step "git init" git init -q -b main
    step "hook tests" .harness/hooks/tests/run.sh
    step "pi tests" bun test ./.harness/hooks/tests/pi.test.ts
    step "codex tests" bash .harness/hooks/tests/codex.test.sh
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

printf '\nSummary:\n%s' "$summary"
exit "$failed"
