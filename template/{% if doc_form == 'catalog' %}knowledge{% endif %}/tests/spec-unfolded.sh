#!/usr/bin/env bash
# Тест spec-unfolded.sh на временном проекте: две ревизии, одна сведена —
# в списке и в блоке README ТЗ остаётся одна. Пути ТЗ и журнала в тесте
# нестандартные, чтобы проверить, что скрипт берёт их из файла ответов.
set -euo pipefail

script="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)/spec-unfolded.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$tmp/knowledge" "$tmp/specs/main" "$tmp/specs/log"
cp "$script" "$tmp/knowledge/spec-unfolded.sh"

cat >"$tmp/.copier-answers.yml" <<'EOF'
# Файл ведёт Copier
_src_path: gh:bodasooqa/harness
doc_form: catalog
revisions_path: specs/log/
spec_path: "specs/main"
EOF

cat >"$tmp/specs/main/README.md" <<'EOF'
# ТЗ

Текст до блока.

<!-- несведённые ревизии -->
Несведённых ревизий нет.
<!-- /несведённые ревизии -->

Текст после блока.
EOF

cat >"$tmp/specs/log/0001-1.1.md" <<'EOF'
---
version: "1.1"
date: 2026-10-01
folded: true
---

# Первая ревизия
EOF

cat >"$tmp/specs/log/0002-1.2.md" <<'EOF'
---
version: "1.2"
date: 2026-10-02
folded: false
---

# Вторая ревизия
EOF

# Печать списка.
listed=$(bash "$tmp/knowledge/spec-unfolded.sh")
expected='- [1.2](../log/0002-1.2.md) — 2026-10-02 — Вторая ревизия'
[[ "$listed" == "$expected" ]] || fail "список: ожидалось «$expected», получено «$listed»"

# Запись блока; повторная запись ничего не меняет.
bash "$tmp/knowledge/spec-unfolded.sh" --write
first=$(cat "$tmp/specs/main/README.md")
bash "$tmp/knowledge/spec-unfolded.sh" --write
[[ "$(cat "$tmp/specs/main/README.md")" == "$first" ]] || fail "повторная запись изменила README"

block=$(awk '/^<!-- несведённые ревизии -->$/ { on = 1; next } /^<!-- \/несведённые ревизии -->$/ { on = 0 } on' \
  "$tmp/specs/main/README.md")
[[ "$block" == "$expected" ]] || fail "блок: ожидалось «$expected», получено «$block»"
grep -qxF 'Текст до блока.' "$tmp/specs/main/README.md" || fail "пропал текст до блока"
grep -qxF 'Текст после блока.' "$tmp/specs/main/README.md" || fail "пропал текст после блока"

# Все сведены — блок говорит, что несведённых нет, список пуст.
sed 's/^folded: false$/folded: true/' "$tmp/specs/log/0002-1.2.md" >"$tmp/rev" && mv "$tmp/rev" "$tmp/specs/log/0002-1.2.md"
[[ -z "$(bash "$tmp/knowledge/spec-unfolded.sh")" ]] || fail "список не пуст, когда всё сведено"
bash "$tmp/knowledge/spec-unfolded.sh" --write
grep -qxF 'Несведённых ревизий нет.' "$tmp/specs/main/README.md" || fail "нет строки о пустом списке"

# Ревизия без folded — ошибка, а не тихий пропуск.
printf -- '---\nversion: "1.3"\ndate: 2026-10-03\n---\n' >"$tmp/specs/log/0003-1.3.md"
if bash "$tmp/knowledge/spec-unfolded.sh" >/dev/null 2>&1; then
  fail "ревизия без folded прошла молча"
fi

printf 'spec-unfolded.sh: ok\n'
