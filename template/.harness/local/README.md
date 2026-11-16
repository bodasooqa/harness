# Project harness extensions

`.harness/` belongs entirely to the template and is updated by `rootstock update`, except this directory: `.harness/local/` is created once and then belongs to the project. A template update leaves it alone.

The rule: the project doesn't edit a managed file but puts its own into an extension point. Then an update almost never conflicts.

## Extension points

| What | Your own — here | How it is wired |
|---|---|---|
| Project rules | `AGENTS.md` at the root and in packages | a starter file, read by all agents. `CLAUDE.md` next to it is an import of `@AGENTS.md` (at the root also `@.harness/process.md`) for Claude Code; no rules are written into it. Pi picks up `AGENTS.md` by itself, `.harness/process.md` is delivered by the shim |
| Agent hooks | `.harness/local/hooks/<slot>/<name>.sh` | the dispatcher `.harness/hooks/dispatch.sh` runs them after the slot's shared hooks, alphabetically; it is called by both Claude Code and the Pi shim. Slots and the contract — `.harness/hooks/README.md` |
| Agent addenda | `.harness/local/agents/<name>.md` | the agent reads the file if it exists — both in `.claude/agents/` and in `.pi/agents/` |
| Skill addenda | `.harness/local/skills/<skill>.md` | a template skill reads the file as its first step if it exists; a skill's text is shared by Claude Code and Pi (Pi takes skills from `.claude/skills/`). On conflict the addendum wins over the shared text. A whole skill of your own — next to the template skills in `.claude/skills/<name>/`, under its own name |
| Pi extensions | `.pi/extensions/<name>.ts` | Pi loads every extension in the directory; `harness.ts` there is managed |
| Git hooks | `lefthook.yml` at the root | includes the shared `.harness/lefthook.yml` via `extends`; your own jobs go in it too |
| Document tables of contents (monolith form) | `knowledge/index.sh` | the shared `knowledge` job in pre-commit calls it with `--stage` after archiving closed questions (with `--stage` the script stages what it rewrote itself), CI — without an argument and goes red if the tree changed after it. No file — the step is skipped. In the catalog form this file is shared |
| CI | `.github/workflows/ci.yml` | calls the shared `.github/workflows/harness.yml`; your own jobs go next to it |
| biome | `biome.json` at the root | `extends` on `.harness/biome.json` |
| Claude Code permissions | `.claude/settings.json` | the file is managed, but the project adds its own lines to `permissions.allow` and `permissions.deny` right in it: `rootstock update` merges edits with a three-way merge and keeps them |
| Pi settings | `.pi/settings.json` | likewise: the file is managed, the project adds its own keys right in it, the merge keeps them |

## Harness updates

New template versions arrive as a PR by themselves. Three managed files:

- `.github/workflows/harness-update.yml` — once a day (and manually, Actions → harness-update → Run workflow, with an optional version) compares the template tags with `version` in `.rootstock.toml`. If there is a newer one — `rootstock update` to it ([rootstock](https://github.com/bodasooqa/rootstock)), conflicts as markers in files, a PR "Update harness to vX.Y.Z" from the branch `harness/update-vX.Y.Z`. A major version gets the `harness:major` label, a conflict — `harness:conflict`. The logic — `.harness/update/update.sh`.
- `.github/workflows/harness-automerge.yml` — when CI completes (the `CI` workflow from `ci.yml`; rename it and automerge stops firing) squash-merges the update PR if CI is green, there are no `harness:major` and `harness:conflict` labels, the PR head is the checked commit, the head was pushed by the token owner (per GitHub's push log, not the commit signature — that can't be forged), and all PR commits were made by the update itself. It leaves PRs from forks and PRs by another author alone.
- The `markers` job in `.github/workflows/harness.yml` — CI is red while files contain conflict markers.

A conflict is handled like a regular task: resolve the markers in the PR branch, commit, and after green CI merge the PR by hand — automerge deliberately skips a commit not made by the update. A major version is merged by hand after the migration steps from the template's `CHANGELOG.md`.

Setup (Settings → Secrets and variables → Actions):

| What | Kind | Why |
|---|---|---|
| `HARNESS_UPDATE_TOKEN` | secret, required | the owner's fine-grained PAT for this repository: Contents — read and write, Pull requests — read and write, Issues — read and write (labels `harness:major`, `harness:conflict`), Workflows — read and write, Metadata — read. The stock `GITHUB_TOKEN` won't do: its PR doesn't trigger CI, and it may not push edits to `.github/workflows/`. Without the secret both workflows fail with a hint. The author of the update PR is the token owner; automerge leaves PRs by another author alone |
| `HARNESS_RUNNER` | variable, optional | the runner for both workflows: a label as a string (`self-hosted`) or a JSON array of labels (`["self-hosted", "ci"]`); default `ubuntu-latest`. A self-hosted runner needs `git`, `jq` and `curl`; `gh`, if missing, is installed by the workflow itself at a pinned version into the job directory — on Linux x86_64 and arm64. rootstock is always installed by the workflow itself, at a pinned version with a checksum check — on Linux and macOS, x86_64 and arm64 |
| `HARNESS_TEMPLATE_URL` | variable, optional | where to take template tags from; default `https://github.com/bodasooqa/harness`. Must match `source` in `.rootstock.toml` (the `gh:owner/repository` form also works), otherwise the update stops with an error |

## Project hook

Example: forbidding a command that wipes project data.

```bash
#!/usr/bin/env bash
# .harness/local/hooks/pre-bash/guard-data.sh
set -uo pipefail
. "${BASH_SOURCE[0]%/*}/../../../hooks/lib/bash-scan.sh"

scan=$(bash_scan) || exit 0
if printf '%s' "$scan" | grep -Eq 'docker[[:space:]]+volume[[:space:]]+rm'; then
  deny "The volume holds data that cannot be restored. Ask the user to remove it themselves."
fi
exit 0
```

The file must be executable (`chmod +x`): the dispatcher skips a hook without the execute bit — so it can be disabled without deleting it. Tests for your own hooks also go here, for example `.harness/local/hooks/tests/`.
