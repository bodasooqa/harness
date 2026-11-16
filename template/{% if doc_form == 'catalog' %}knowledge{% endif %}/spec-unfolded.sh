#!/usr/bin/env bash
# Spec revisions not yet folded into the sections.
#
# The revision journal is a directory, one file per revision (`NNNN-1.N.md`),
# each with `folded: false|true` in its frontmatter. The list of unfolded ones
# is built from here, not kept by hand: a hand-kept list drifts from the
# journal within the first week.
#
# Modes:
#   spec-unfolded.sh           prints unfolded revisions, one line per revision
#   spec-unfolded.sh --write   rewrites the block between the markers
#                              `<!-- unfolded revisions -->` and
#                              `<!-- /unfolded revisions -->` in the spec README
#
# Paths to the spec and the journal come from `.rootstock.toml` at the project
# root (`spec_path`, `revisions_path`) and are not hardcoded in the script.
set -euo pipefail

root=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
answers="$root/.rootstock.toml"

mode=${1:-}
case "$mode" in
  "" | --write) ;;
  --help | -h)
    sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    printf 'spec-unfolded.sh: unknown argument %s. Expected --write or nothing.\n' "$mode" >&2
    exit 2
    ;;
esac

# Value of a key from the `[answers]` table of the template record:
# `key = "value"`, quotes stripped. Escapes are not expanded: paths have none.
answer() {
  local key=$1 value
  value=$(awk -v key="$key" -v q="'" '
    /^[ \t]*\[/ { inside = ($0 ~ /^[ \t]*\[answers\][ \t]*$/); next }
    inside && $0 ~ ("^" key "[ \t]*=") {
      v = substr($0, index($0, "=") + 1)
      sub(/^[ \t]+/, "", v)
      sub(/[ \t]+$/, "", v)
      f = substr(v, 1, 1)
      if (length(v) >= 2 && (f == "\"" || f == q) && substr(v, length(v), 1) == f)
        v = substr(v, 2, length(v) - 2)
      print v
      exit
    }
  ' "$answers")
  if [[ -z "$value" ]]; then
    printf 'spec-unfolded.sh: %s has no key %s\n' "$answers" "$key" >&2
    exit 1
  fi
  # Path from the project root: no leading `./` and no trailing `/`.
  value=${value#./}
  value=${value%/}
  printf '%s\n' "$value"
}

# Path `to` relative to directory `from`; both from the project root.
relative_path() {
  local from=$1 to=$2 up=""
  while [[ -n "$from" && "$to" != "$from/"* ]]; do
    if [[ "$from" == */* ]]; then
      from=${from%/*}
    else
      from=""
    fi
    up="../$up"
  done
  if [[ -n "$from" ]]; then
    to=${to#"$from"/}
  fi
  printf '%s%s\n' "$up" "$to"
}

if [[ ! -f "$answers" ]]; then
  printf 'spec-unfolded.sh: no template answers file %s\n' "$answers" >&2
  exit 1
fi

spec_path=$(answer spec_path)
revisions_path=$(answer revisions_path)
spec_readme="$root/$spec_path/README.md"
revisions_dir="$root/$revisions_path"

# List lines: `- [1.N](path) — YYYY-MM-DD — title`, path relative to the spec README.
lines=""
if [[ -d "$revisions_dir" ]]; then
  for file in "$revisions_dir"/[0-9][0-9][0-9][0-9]-*.md; do
    [[ -e "$file" ]] || continue
    # version, date, folded from the frontmatter and the first `# ` heading after it.
    # The field separator is \037: a whitespace IFS would merge empty fields.
    fields=$(awk -v q="'" '
      NR == 1 { if ($0 != "---") exit; in_front = 1; next }
      in_front && $0 == "---" { in_front = 0; next }
      in_front {
        i = index($0, ":")
        if (i == 0) next
        k = substr($0, 1, i - 1)
        v = substr($0, i + 1)
        sub(/^[ \t]+/, "", v)
        sub(/[ \t]+$/, "", v)
        f = substr(v, 1, 1)
        if (length(v) >= 2 && (f == "\"" || f == q) && substr(v, length(v), 1) == f)
          v = substr(v, 2, length(v) - 2)
        meta[k] = v
        next
      }
      !in_front && title == "" && /^# / { title = substr($0, 3) }
      END { printf "%s\037%s\037%s\037%s\n", meta["version"], meta["date"], meta["folded"], title }
    ' "$file")
    IFS=$'\037' read -r version date folded title <<<"$fields"
    name=${file##*/}
    case "$folded" in
      true) continue ;;
      false) ;;
      *)
        printf 'spec-unfolded.sh: %s has no folded: true|false in its frontmatter (found "%s")\n' \
          "$revisions_path/$name" "$folded" >&2
        exit 1
        ;;
    esac
    link=$(relative_path "$spec_path" "$revisions_path/$name")
    line="- [${version:-$name}]($link)"
    [[ -n "$date" ]] && line="$line — $date"
    [[ -n "$title" ]] && line="$line — $title"
    lines="$lines$line"$'\n'
  done
fi

if [[ -z "$mode" ]]; then
  printf '%s' "$lines"
  exit 0
fi

if [[ ! -f "$spec_readme" ]]; then
  printf 'spec-unfolded.sh: no spec README %s\n' "$spec_readme" >&2
  exit 1
fi

start='<!-- unfolded revisions -->'
end='<!-- /unfolded revisions -->'
if ! grep -qxF "$start" "$spec_readme" || ! grep -qxF "$end" "$spec_readme"; then
  printf 'spec-unfolded.sh: %s has no markers %s and %s\n' "$spec_path/README.md" "$start" "$end" >&2
  exit 1
fi

block=$(mktemp)
out=$(mktemp)
trap 'rm -f "$block" "$out"' EXIT
if [[ -n "$lines" ]]; then
  printf '%s' "$lines" >"$block"
else
  printf 'No unfolded revisions.\n' >"$block"
fi

awk -v start="$start" -v end="$end" -v block="$block" '
  $0 == start {
    print
    while ((getline line < block) > 0) print line
    skip = 1
    next
  }
  $0 == end { skip = 0 }
  !skip { print }
' "$spec_readme" >"$out"
cat "$out" >"$spec_readme"
