#!/usr/bin/env bash
# Check of `rootstock update`: project edits survive a template update.
#
# The template is a snapshot of the working directory (with uncommitted edits)
# as two versions in a temporary repository: an older layout without Codex,
# and the current layout with an edit to the managed `harness.yml`. A project
# is created from the older version in the full
# layout and edited the way real projects edit it: own lines in the managed
# `.claude/settings.json`, an own line in a starter document, an own skill
# addendum in `.harness/local/skills/`, the starter crate deleted, an own crate added. After updating to v1.0.1 all of it is in place, the
# template edit has arrived, the project record is consistent (`rootstock check`),
# and the `knowledge/` scripts read paths from it.
#
# rootstock — from PATH or the ROOTSTOCK variable.
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

# Template: snapshot the working tree and simulate the layout before Codex.
git -C "$repo" ls-files -z -co --exclude-standard |
  (cd "$repo" && xargs -0 tar -cf -) | (mkdir "$tmp/tpl" && cd "$tmp/tpl" && tar -xf -)
git -C "$tmp/tpl" init -q
mv "$tmp/tpl/template/.codex" "$tmp/tpl/template/.agents" "$tmp/"
mv "$tmp/tpl/template/.harness/hooks/codex.sh" "$tmp/"
cp "$tmp/tpl/rootstock.toml" "$tmp/rootstock.toml"
sed 's/--tools claude,pi,codex/--tools claude,pi/g' "$tmp/rootstock.toml" >"$tmp/tpl/rootstock.toml"
git -C "$tmp/tpl" add -A
git -C "$tmp/tpl" commit -qm v1.0.0
git -C "$tmp/tpl" tag v1.0.0
mv "$tmp/.codex" "$tmp/.agents" "$tmp/tpl/template/"
mv "$tmp/codex.sh" "$tmp/tpl/template/.harness/hooks/"
cp "$tmp/rootstock.toml" "$tmp/tpl/rootstock.toml"
printf '# check-update: template edit\n' >>"$tmp/tpl/template/.github/workflows/harness.yml.jinja"
git -C "$tmp/tpl" add -A
git -C "$tmp/tpl" commit -qm v1.0.1
git -C "$tmp/tpl" tag v1.0.1

# Project from v1.0.0. The template hook (`openspec init`) runs if openspec is present.
"$rootstock" new --version v1.0.0 --defaults --trust --git \
  --data project_name=demo --data rust=true --data frontend=true \
  "$tmp/tpl" "$tmp/p" >/dev/null
cd "$tmp/p"
git add -A
git commit -qm init

# Project edits.
jq '.permissions.allow += ["Bash(cargo run -p demo *)"]' .claude/settings.json >settings.tmp
mv settings.tmp .claude/settings.json
printf '\nProject line.\n' >>docs/spec/01-purpose.md
printf '\n<!-- Project rules -->\n' >>AGENTS.md
printf '\n# Project OpenSpec configuration\n' >>openspec/config.yaml
cp openspec/config.yaml "$tmp/openspec-config.yaml"
if command -v openspec >/dev/null; then
  openspec new change keep-me >/dev/null
fi
mkdir -p .harness/local/skills
printf 'Project addendum.\n' >.harness/local/skills/change-finish.md
git rm -rq crates/app
mkdir -p crates/core/src
printf 'pub fn f() {}\n' >crates/core/src/lib.rs
git add -A
git commit -qm edit

code=0
"$rootstock" update --to v1.0.1 --defaults --trust >"$tmp/conflicts" || code=$?

check "rootstock update without conflicts (exit 0)" test "$code" = 0
check "no conflicts printed" test ! -s "$tmp/conflicts"
check "record at v1.0.1" grep -q '^version = "v1.0.1"$' .rootstock.toml
check "record consistent (rootstock check)" "$rootstock" check
check "template edit arrived" grep -q '^# check-update: template edit' .github/workflows/harness.yml
check "own line in managed .claude/settings.json intact" \
  test "$(jq '.permissions.allow | index("Bash(cargo run -p demo *)") != null' .claude/settings.json)" = true
check "starter document untouched" \
  test "$(grep -c '^Project line\.$' docs/spec/01-purpose.md)" = 1
check "root AGENTS.md keeps project rules" grep -q '^<!-- Project rules -->$' AGENTS.md
check "Codex hooks arrived" test -f .codex/hooks.json
check "Codex shared skill arrived" test -f .agents/skills/change-finish/SKILL.md
if command -v openspec >/dev/null; then
  check "old project needs Codex OpenSpec initialization" test ! -e .agents/skills/openspec-propose
  check "initialize OpenSpec for all three clients" openspec init --tools claude,pi,codex --no-animation
  check "project OpenSpec config unchanged" cmp -s "$tmp/openspec-config.yaml" openspec/config.yaml
  check "project OpenSpec change retained" test -d openspec/changes/keep-me
  check "OpenSpec generated its Codex skill" test -f .agents/skills/openspec-propose/SKILL.md
fi
check "skill addendum untouched" \
  test "$(cat .harness/local/skills/change-finish.md)" = 'Project addendum.'
check "deleted starter crate not restored" test ! -e crates/app
check "own crate intact" test -f crates/core/src/lib.rs
check "no conflict markers" ./.harness/update/conflict-markers.sh
check "knowledge/due.sh reads paths from the record" ./knowledge/due.sh --overdue

exit "$fail"
