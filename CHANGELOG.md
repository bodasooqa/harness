# Changelog

Versions are semver `vX.Y.Z`; tags are set by `release.yml` after green CI of a commit merged into main; the bump kind is the PR label (`release:minor`, `release:patch` or no label — patch, `release:none` — no tag). Each release's description is assembled automatically from PRs.

When a note is written here:

- **Major version — always.** A path renamed, a template question changed, projects need a migration. A PR labeled `release:major` gets no automatic tag: after the merge the tag is set manually, and in the same release this file gets a version section with the migration steps the project takes before or after the update.
- **Minor and patch — optional.** The automatic release description is enough; a note is needed only if the change deserves a wider explanation than the PR titles.

New entries go on top.

## Executor checks on exit (minor)

An executor (a `*-developer` agent: `rust-developer`, `frontend-developer`, and project agents of the same kind) no longer hands in work with red fast checks. The new shared hook `agent-checks.sh` takes the worktree changes relative to HEAD plus untracked files, maps them to crates and packages, and runs `rustfmt --check`, clippy per crate, and `tsc --noEmit` per package — according to the project's modules. Red means a single refusal, with the error output in the reason; the executor fixes it or returns a question.

- Claude Code: slots `subagent-stop` (`SubagentStop`, `matcher` on `-developer$`) and `pre-handback` (`PreToolUse` on `SubagentHandback` — in auto mode the report goes out through this tool before the stop). Timeout — 600 s.
- Pi: slot `subagent-stop` on `agent_before_settle` of the `pi-subagents` child — one continuation of the run. Pi has no `pre-handback`.
- The template doesn't wire `Stop` of the main session; for an executor run as a separate session `claude --agent <executor>`, the project can wire `Stop` → `dispatch.sh subagent-stop` itself (hooks README, "Executor checks").
- Resolving the crate and package path and the check commands moved from `rust-clippy.sh` and `js-typecheck.sh` into `lib/rust-crate.sh` and `lib/js-package.sh`; clippy now runs from the crate directory, so an edit in a neighboring worktree is checked in its own worktree.

No migration: the wiring is in the managed `.claude/settings.json` and `.pi/extensions/harness.ts`. A project puts its own hook for the end of executor work in `.harness/local/hooks/subagent-stop/`.

## AGENTS.md — project rules for all agents

Project rules move from `CLAUDE.md` to `AGENTS.md`: it is read by Pi, Codex, and other agents, while the `@file` import that `CLAUDE.md` used to pull in `.harness/process.md` is understood only by Claude Code. Now, in a new project:

- `AGENTS.md` (starter) — project rules; instead of an import line it tells the agent to read `.harness/process.md` in full before starting work;
- `CLAUDE.md` (starter) — only `@AGENTS.md` and `@.harness/process.md`, so Claude Code gets both;
- in frontend monorepo packages (`apps/web`, `packages/uikit`) — the same: `AGENTS.md` with the rules, `CLAUDE.md` made of `@AGENTS.md`.

Managed texts (`.harness/process.md`, skills, agents, hooks README) name `AGENTS.md` as the place of project rules. The Pi shim takes `AGENTS.md` as the main file, `CLAUDE.md` without it, and then brings in `.harness/process.md`. It doesn't add a `CLAUDE.md` next to `AGENTS.md` while it holds only imports; with its own rules, it does.

**What the update does in a connected project.** Starter files the project didn't have yet are created by the update: `AGENTS.md` stubs appear at the root and, in a frontend monorepo, in `apps/web/` and `packages/uikit/`. The update doesn't touch `CLAUDE.md` — the rules stay there. Without the migration Claude Code works as before, Pi gets both the stub and the `CLAUDE.md` with project rules, but Codex sees only the stub, and managed texts point to `AGENTS.md`. So it's better not to postpone the migration.

**Migration** — as a separate PR after the update is merged (your own commit on the update branch disables automerge):

1. Project rules go into `AGENTS.md` over the stub, with history: `git mv -f CLAUDE.md AGENTS.md`. In it, the heading `# CLAUDE.md — …` → `# AGENTS.md — …`; replace the `@.harness/process.md` line and the phrase about including it on the line below with an instruction to read `.harness/process.md` in full before starting work (the model is the paragraph in the template's `template/AGENTS.md.jinja`); "each package has its own `CLAUDE.md`" → `AGENTS.md`.
2. A new two-line `CLAUDE.md` — like the template's `template/CLAUDE.md.jinja`:

   ```
   @AGENTS.md
   @.harness/process.md
   ```

3. Packages — optional, the same way: `git mv -f <package>/CLAUDE.md <package>/AGENTS.md`, in it "the rules of the root `CLAUDE.md`" → `AGENTS.md`, next to it a `CLAUDE.md` with the line `@AGENTS.md`. Template agents look for package rules in `<package>/AGENTS.md`. If the packages aren't moved, delete the stubs `apps/web/AGENTS.md` and `packages/uikit/AGENTS.md`: the update doesn't bring back a deleted starter file.
4. The Pi shim from the release works both without the migration and after it — no separate step.
5. `.harness/local/README.md` is a starter file: copy the "Project rules" row of the extension point table from the template's `template/.harness/local/README.md` by hand, if needed.

## Project skill addenda

Template skills got an extension point, like agents: `.harness/local/skills/<skill>.md`. Every template skill reads this file as its first step, if it exists — both in Claude Code and in Pi (the skill text is shared); where they disagree, the addendum overrides the shared text. The directory belongs to the project: `.harness/local/**` is starter, `rootstock update` doesn't touch it.

**Optional for the project:**

- Move the skill rules the project kept in `CLAUDE.md` (who merges PRs, who is who in Linear, how to check a rollout) into `.harness/local/skills/<skill>.md`. Skills still look into `CLAUDE.md` too, so the move isn't mandatory.
- `.harness/local/README.md` is a starter file and isn't changed by the update: copy the "Skill addenda" row of the extension point table from the template's `template/.harness/local/README.md` by hand.

## Narrow Claude Code permissions (#21)

`permissions.allow` in `.claude/settings.json` no longer lets through without a prompt the forms that execute a command or write to an arbitrary path: removed `Bash(rg *)`, `Bash(git diff *)`, `Bash(git log *)`, `Bash(lefthook *)`, `Bash(bunx *)`; `bun`, `turbo`, `openspec` narrowed to specific subcommands; `deny` holds dangerous flags (`rg --pre`, `git diff|log|show --output|--ext-diff`, `cargo --config`, and report files of biome, turbo, `bun test`). Why so and what remains — `docs/design.md`, section "Claude Code permissions".

**What the project will notice:** some commands that used to run silently now ask for permission (`bunx <package>`, `bun run <own script>`, `lefthook run`, `openspec init|update`). Safe `git diff`, `git log` still run without a prompt — Claude Code itself allows them. A command the project needs — as its own line in `.claude/settings.json` (survives the update) or in `.claude/settings.local.json`; deny lines still apply.

`rootstock new` now installs git hooks (`lefthook install`) if the project already has a repository, and otherwise loudly reminds you: rootstock 0.1 runs `git init` after the template tasks, so with `--git` the hooks are installed by hand — `lefthook install` (in a frontend project, after `bun install` — `bunx lefthook install`).

## biome.json at the root of the template repository

Concerns only the template repository; projects get nothing. The root got a `biome.json` that extends the template's `template/.harness/biome.json`: the session hook formats `template/` files the same way the generated project formats them (two spaces, width 100), not with biome defaults (tabs). biome doesn't touch `.jinja` files — it doesn't know the extension; paths with `{% if %}` are ordinary directories to it. Template CI runs `biome check .` in the `lint` job with the same version as in the template's `package.json`. To edit `template/` files locally you need biome of this version (`bunx @biomejs/biome@2.5.12`): an older one won't understand the config keys.

## Git hooks on Windows (#26)

- **pre-push on Windows works without `LEFTHOOK=0`.** lefthook runs `files:` without a shell, and `.sh` didn't run on Windows. Now `files: sh ./.harness/lefthook/push-files.sh`, and the script itself is POSIX sh. `run:` has no double quotes: on Windows lefthook wraps the line in them without escaping.
- **Starter `.gitattributes`** with `* text=auto eol=lf`: without it git on Windows with `core.autocrlf=true` checks out CRLF, and harness scripts, biome, and tests fail. A project without `.gitattributes` gets it with the update; its own (like screener's) isn't touched. A project that has none of its own but where git has already checked out CRLF re-checks out the files after the update: `git rm -r --cached -q . && git reset --hard`.
- Template CI has a `windows` job (Git Bash): `scripts/check-lefthook.sh` runs a commit and a push through lefthook, pre-push without and with an upstream, `knowledge/` tests, and checkout with `core.autocrlf=true`.

## Tables of contents for monolith-form documents

In the monolith form, the shared lefthook job `knowledge`, after archiving closed questions, calls the project's `knowledge/index.sh --stage` if it exists; edits to the decision and lesson journals now trigger it too. The CI step "Tables of contents built" in this form also calls the script (without an argument) and turns red if the tree changed after it. No script — both steps are skipped; the catalog form doesn't change.

A project with its own TOC script that disabled the shared `knowledge` job (`skip: true`) in favor of its own can drop both of its jobs. The script must understand `--stage`: with it, stage what it rewrote (the closed questions archive is staged by `archive-questions.sh --stage`). Nothing breaks without dropping them: the shared job stays disabled, and CI starts checking the tables of contents.

## v1.0.0 — the template on rootstock

The template moves from [Copier](https://copier.readthedocs.io/) to [rootstock](https://github.com/bodasooqa/rootstock). The files a project gets are the same: rootstock renders all five layouts and monolith byte for byte like Copier.

**What changed:**

- Template config — `rootstock.toml` instead of `copier.yml`. New project: `rootstock new gh:bodasooqa/harness <directory> --git`.
- Project record — `.rootstock.toml` instead of `.copier-answers.yml`: source, version, answers (the `[answers]` table), file inventory. The `knowledge/` scripts (`due.sh`, `archive-questions.sh`, `index.sh`, `spec-unfolded.sh`) read paths from it.
- `harness-update.yml` updates only with `rootstock update`; the runner no longer needs pipx and uv. The workflow installs rootstock itself, at a pinned version with a checksum check.
- A starter file deleted by the project no longer comes back on update (Copier recreated it).

**Migration:**

1. **Project on v0.5.x (bridge release).** A project on an earlier version first updates to v0.5.x with a regular PR: the `harness-update` workflow (or `gh workflow run harness-update -f version=v0.5.0`), without the workflow — `copier update --vcs-ref v0.5.0`. The workflow before the bridge can't do rootstock: updating to v1.0.0 would break the project, and the `harness:major` label keeps such a PR from merging itself.
2. **The PR to v1.0.0 arrives by itself** with the `harness:major` label and two commits: «Перевод харнесса на rootstock» ("Move harness to rootstock"; `rootstock import-copier`: `.rootstock.toml` instead of `.copier-answers.yml` at the previous version, project files unchanged) and «Обновление харнесса до v1.0.0» ("Update harness to v1.0.0"; `rootstock update`). Review and merge manually after green CI.
3. **Without the workflow** — the same by hand, on a clean tree: `rootstock import-copier`, commit, `rootstock update --to v1.0.0`, commit.
4. **The project's own scripts** that read `.copier-answers.yml` (in `.harness/local/`, own CI jobs) switch to `.rootstock.toml`: answers are in the `[answers]` table, as lines `key = "value"`; version — `version`, source — top-level `source`.
   The update doesn't touch starter files, so the project's `.harness/local/README.md` and `README.md` still talk about Copier; fresh text is in the template's `template/`, copied by hand if desired.
5. **Locally**, manual updates need rootstock (`cargo install rootstock` or a release binary); copier is no longer needed.
