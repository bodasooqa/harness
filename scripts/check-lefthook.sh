#!/usr/bin/env bash
# The project's git hooks on live git: knowledge/ tests, a commit and a push
# through the installed lefthook, `lefthook run pre-push` on a branch without
# an upstream and with one.
#
# For Windows (CI runs it on windows-latest in Git Bash): there lefthook runs
# `files:` without a shell and `run:` via `sh -c` in double quotes, and
# temporary directory paths look like `C:/…`. Passes the same on Linux and macOS.
#
# Layout — rust-crate: no frontend, so no dependencies to install; git hooks
# and knowledge/ are the same in all layouts. Not only the exit code is checked:
# a job that is silently skipped is as bad as a failed one.
#
# Usage:
#   scripts/check-lefthook.sh
#
# Required in PATH: rootstock (or the ROOTSTOCK variable), lefthook, git, perl.

# Check idiom `condition && ok || bad`: ok doesn't fail.
# shellcheck disable=SC2015
set -euo pipefail

repo=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
rootstock=${ROOTSTOCK:-rootstock}

work=$(mktemp -d "${TMPDIR:-/tmp}/check-lefthook.XXXXXX")
trap 'rm -rf "$work"' EXIT

failed=0
ok() { printf '  ok   %s\n' "$1"; }
bad() {
  failed=1
  printf '  FAIL %s\n     expected: %s\n     got:\n%s\n' "$1" "$2" "$(printf '%s\n' "${3:-<empty>}" | sed 's/^/       /')"
}

p=$work/p
"$rootstock" new --version HEAD --defaults --trust --data project_name=demo \
  --data rust=true --data frontend=false --data monorepo=false \
  "$repo" "$p" >"$work/rootstock.log" 2>&1 || {
  cat "$work/rootstock.log"
  exit 1
}
cd "$p"

git init -q -b main
git config user.email t@t
git config user.name t
git add -A
git commit -q --no-verify -m base
git init -q --bare "$work/origin.git"
git remote add origin "$work/origin.git"
git push -q --no-verify origin main 2>/dev/null

echo "line endings"
# As in Git for Windows by default: without .gitattributes checkout would give CRLF.
git config core.autocrlf true
rm -rf .harness knowledge
git checkout -- .harness knowledge
crlf=$(git ls-files --eol .harness knowledge | awk '$2 ~ /crlf/ { print $4 }')
[ -z "$crlf" ] && ok "checkout with core.autocrlf=true — no CRLF" || bad "checkout with core.autocrlf=true — no CRLF" "empty" "$crlf"

echo "knowledge/ tests"
for t in knowledge/tests/*.sh; do
  out=$("./$t" 2>&1) && ok "$t" || bad "$t" "exit 0" "$out"
done

lefthook install >/dev/null
# A branch without an upstream, like a new task branch.
git switch -q -c feat --no-track

echo "pre-commit"
printf '# Lesson\n\nText.\n' >knowledge/lessons/2026-11-12-lesson.md
git add knowledge/lessons/2026-11-12-lesson.md
out=$(git commit -m lesson 2>&1) && code=0 || code=$?
rest=$(git status --porcelain)
{ [ "$code" -eq 0 ] && [ -z "$rest" ]; } \
  && ok "commit through lefthook, tree clean" \
  || bad "commit through lefthook, tree clean" "exit 0, empty git status" "exit $code, leftover: $rest
$out"
committed=$(git show --name-only --format= HEAD | sort | tr '\n' ' ')
[ "$committed" = "knowledge/lessons/2026-11-12-lesson.md knowledge/lessons/README.md " ] \
  && ok "table of contents went in the same commit" \
  || bad "table of contents went in the same commit" "lesson and README" "$committed"

# Only the knowledge-tests job: the others depend on the layout, and this one
# is selected by a glob over the push's file list.
push_job() { lefthook run pre-push --job knowledge-tests --no-tty --colors off </dev/null 2>&1; }
ran() {  # <check name> <output> <code>
  { [ "$3" -eq 0 ] && [[ "$2" == *knowledge-tests* ]] && [[ "$2" != *"knowledge-tests (skip)"* ]]; } \
    && ok "$1" || bad "$1" "exit 0, knowledge-tests not skipped" "exit $3: $2"
}
# The code is ignored: lefthook newer than 2.1 answers a skip of the selected
# `--job` with a "no job matching" error.
skipped() {
  [[ "$2" == *"knowledge-tests (skip)"* ]] \
    && ok "$1" || bad "$1" "knowledge-tests (skip)" "exit $3: $2"
}

echo "pre-push without upstream"
out=$(push_job) && code=0 || code=$?
ran "own knowledge/ file triggers knowledge-tests" "$out" "$code"

# A failing test must fail the push: otherwise the green output above means nothing.
printf '#!/usr/bin/env bash\necho canary >&2\nexit 1\n' >knowledge/tests/zz-canary.sh
chmod +x knowledge/tests/zz-canary.sh
git add knowledge/tests/zz-canary.sh
git commit -q --no-verify -m canary
out=$(push_job) && code=0 || code=$?
{ [ "$code" -ne 0 ] && [[ "$out" == *canary* ]]; } \
  && ok "failing knowledge/ test fails pre-push" \
  || bad "failing knowledge/ test fails pre-push" "non-zero exit and 'canary'" "exit $code: $out"
git reset -q --hard HEAD~1

out=$(git push -u origin feat 2>&1) && code=0 || code=$?
[ "$code" -eq 0 ] && ok "git push of a new branch through the hook" || bad "git push of a new branch through the hook" "exit 0" "exit $code: $out"

echo "pre-push with upstream"
printf 'note\n' >notes.txt
git add notes.txt
git commit -q --no-verify -m notes
out=$(push_job) && code=0 || code=$?
skipped "push without knowledge/ doesn't trigger knowledge-tests" "$out" "$code"

printf '# Second lesson\n' >knowledge/lessons/2026-11-12-second.md
git add knowledge/lessons/2026-11-12-second.md
git commit -q -m second >/dev/null 2>&1
out=$(push_job) && code=0 || code=$?
ran "own knowledge/ file triggers knowledge-tests" "$out" "$code"

out=$(git push 2>&1) && code=0 || code=$?
[ "$code" -eq 0 ] && ok "git push with upstream through the hook" || bad "git push with upstream through the hook" "exit 0" "exit $code: $out"

echo
if ((failed)); then
  echo "summary: there are failures"
else
  echo "summary: all passed"
fi
exit "$failed"
