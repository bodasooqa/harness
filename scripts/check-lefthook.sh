#!/usr/bin/env bash
# Git-хуки проекта на живом git: тесты knowledge/, коммит и пуш через
# установленный lefthook, `lefthook run pre-push` на ветке без upstream и с ним.
#
# Ради Windows (CI гоняет его на windows-latest в Git Bash): там lefthook
# исполняет `files:` без оболочки, а `run:` — через `sh -c` в двойных кавычках,
# и пути временных каталогов вида `C:/…`. На Linux и macOS проходит так же.
#
# Раскладка — rust-crate: без фронта, чтобы не ставить зависимости; git-хуки
# и knowledge/ во всех раскладках одни. Проверяется не только код выхода:
# джоб, который тихо пропущен, так же плох, как упавший.
#
# Использование:
#   scripts/check-lefthook.sh
#
# Нужны в PATH: rootstock (или переменная ROOTSTOCK), lefthook, git, perl.

# Идиома проверок `условие && ok || bad`: ok не падает.
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
  printf '  ПРОВАЛ %s\n     ожидалось: %s\n     получено:\n%s\n' "$1" "$2" "$(printf '%s\n' "${3:-<пусто>}" | sed 's/^/       /')"
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

echo "окончания строк"
# Как у Git for Windows по умолчанию: без .gitattributes выкладка дала бы CRLF.
git config core.autocrlf true
rm -rf .harness knowledge
git checkout -- .harness knowledge
crlf=$(git ls-files --eol .harness knowledge | awk '$2 ~ /crlf/ { print $4 }')
[ -z "$crlf" ] && ok "выкладка при core.autocrlf=true — без CRLF" || bad "выкладка при core.autocrlf=true — без CRLF" "пусто" "$crlf"

echo "тесты knowledge/"
for t in knowledge/tests/*.sh; do
  out=$("./$t" 2>&1) && ok "$t" || bad "$t" "код 0" "$out"
done

lefthook install >/dev/null
# Ветка без upstream, как новая ветка задачи.
git switch -q -c feat --no-track

echo "pre-commit"
printf '# Урок\n\nТекст.\n' >knowledge/lessons/2026-11-12-lesson.md
git add knowledge/lessons/2026-11-12-lesson.md
out=$(git commit -m lesson 2>&1) && code=0 || code=$?
rest=$(git status --porcelain)
{ [ "$code" -eq 0 ] && [ -z "$rest" ]; } \
  && ok "коммит через lefthook, дерево чистое" \
  || bad "коммит через lefthook, дерево чистое" "код 0, пустой git status" "код $code, остаток: $rest
$out"
committed=$(git show --name-only --format= HEAD | sort | tr '\n' ' ')
[ "$committed" = "knowledge/lessons/2026-11-12-lesson.md knowledge/lessons/README.md " ] \
  && ok "оглавление уехало тем же коммитом" \
  || bad "оглавление уехало тем же коммитом" "урок и README" "$committed"

# Только джоб knowledge-tests: остальные зависят от раскладки, а этот
# выбирается глобом по списку файлов пуша.
push_job() { lefthook run pre-push --job knowledge-tests --no-tty --colors off </dev/null 2>&1; }
ran() {  # <имя проверки> <вывод> <код>
  { [ "$3" -eq 0 ] && [[ "$2" == *knowledge-tests* ]] && [[ "$2" != *"knowledge-tests (skip)"* ]]; } \
    && ok "$1" || bad "$1" "код 0, knowledge-tests не пропущен" "код $3: $2"
}
# Код не смотрим: lefthook новее 2.1 на пропуске выбранного `--job` отвечает
# ошибкой «no job matching».
skipped() {
  [[ "$2" == *"knowledge-tests (skip)"* ]] \
    && ok "$1" || bad "$1" "knowledge-tests (skip)" "код $3: $2"
}

echo "pre-push без upstream"
out=$(push_job) && code=0 || code=$?
ran "свой файл knowledge/ будит knowledge-tests" "$out" "$code"

# Падающий тест обязан уронить пуш: иначе зелёный вывод выше ничего не значит.
printf '#!/usr/bin/env bash\necho канарейка >&2\nexit 1\n' >knowledge/tests/zz-canary.sh
chmod +x knowledge/tests/zz-canary.sh
git add knowledge/tests/zz-canary.sh
git commit -q --no-verify -m canary
out=$(push_job) && code=0 || code=$?
{ [ "$code" -ne 0 ] && [[ "$out" == *канарейка* ]]; } \
  && ok "падающий тест knowledge/ роняет pre-push" \
  || bad "падающий тест knowledge/ роняет pre-push" "ненулевой код и «канарейка»" "код $code: $out"
git reset -q --hard HEAD~1

out=$(git push -u origin feat 2>&1) && code=0 || code=$?
[ "$code" -eq 0 ] && ok "git push новой ветки через хук" || bad "git push новой ветки через хук" "код 0" "код $code: $out"

echo "pre-push с upstream"
printf 'заметка\n' >notes.txt
git add notes.txt
git commit -q --no-verify -m notes
out=$(push_job) && code=0 || code=$?
skipped "пуш без knowledge/ knowledge-tests не будит" "$out" "$code"

printf '# Второй урок\n' >knowledge/lessons/2026-11-12-second.md
git add knowledge/lessons/2026-11-12-second.md
git commit -q -m second >/dev/null 2>&1
out=$(push_job) && code=0 || code=$?
ran "свой файл knowledge/ будит knowledge-tests" "$out" "$code"

out=$(git push 2>&1) && code=0 || code=$?
[ "$code" -eq 0 ] && ok "git push с upstream через хук" || bad "git push с upstream через хук" "код 0" "код $code: $out"

echo
if ((failed)); then
  echo "итого: есть провалы"
else
  echo "итого: всё прошло"
fi
exit "$failed"
