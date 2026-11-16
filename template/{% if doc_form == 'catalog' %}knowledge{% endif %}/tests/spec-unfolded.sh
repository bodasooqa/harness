#!/usr/bin/env bash
# Test of spec-unfolded.sh on a temporary project: two revisions, one folded —
# one stays in the list and in the spec README block. The spec and journal
# paths in the test are non-standard, to check that the script takes them from
# the answers file.
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

# Keys with the same names outside `[answers]` do not count.
cat >"$tmp/.rootstock.toml" <<'EOF'
schema = 1
source = "gh:bodasooqa/harness"
spec_path = "wrong"

[answers]
doc_form = "catalog"
revisions_path = 'specs/log/'
spec_path = "specs/main"

[answers.pi_models]
revisions_path = "wrong"
EOF

cat >"$tmp/specs/main/README.md" <<'EOF'
# Spec

Text before the block.

<!-- unfolded revisions -->
No unfolded revisions.
<!-- /unfolded revisions -->

Text after the block.
EOF

cat >"$tmp/specs/log/0001-1.1.md" <<'EOF'
---
version: "1.1"
date: 2026-10-01
folded: true
---

# First revision
EOF

cat >"$tmp/specs/log/0002-1.2.md" <<'EOF'
---
version: "1.2"
date: 2026-10-02
folded: false
---

# Second revision
EOF

# Printing the list.
listed=$(bash "$tmp/knowledge/spec-unfolded.sh")
expected='- [1.2](../log/0002-1.2.md) — 2026-10-02 — Second revision'
[[ "$listed" == "$expected" ]] || fail "list: expected \"$expected\", got \"$listed\""

# Writing the block; a second write changes nothing.
bash "$tmp/knowledge/spec-unfolded.sh" --write
first=$(cat "$tmp/specs/main/README.md")
bash "$tmp/knowledge/spec-unfolded.sh" --write
[[ "$(cat "$tmp/specs/main/README.md")" == "$first" ]] || fail "a second write changed the README"

block=$(awk '/^<!-- unfolded revisions -->$/ { on = 1; next } /^<!-- \/unfolded revisions -->$/ { on = 0 } on' \
  "$tmp/specs/main/README.md")
[[ "$block" == "$expected" ]] || fail "block: expected \"$expected\", got \"$block\""
grep -qxF 'Text before the block.' "$tmp/specs/main/README.md" || fail "text before the block is gone"
grep -qxF 'Text after the block.' "$tmp/specs/main/README.md" || fail "text after the block is gone"

# All folded — the block says there are none, the list is empty.
sed 's/^folded: false$/folded: true/' "$tmp/specs/log/0002-1.2.md" >"$tmp/rev" && mv "$tmp/rev" "$tmp/specs/log/0002-1.2.md"
[[ -z "$(bash "$tmp/knowledge/spec-unfolded.sh")" ]] || fail "the list is not empty when everything is folded"
bash "$tmp/knowledge/spec-unfolded.sh" --write
grep -qxF 'No unfolded revisions.' "$tmp/specs/main/README.md" || fail "no line about the empty list"

# A revision without folded is an error, not a silent skip.
printf -- '---\nversion: "1.3"\ndate: 2026-10-03\n---\n' >"$tmp/specs/log/0003-1.3.md"
if bash "$tmp/knowledge/spec-unfolded.sh" >/dev/null 2>&1; then
  fail "a revision without folded passed silently"
fi

printf 'spec-unfolded.sh: ok\n'
