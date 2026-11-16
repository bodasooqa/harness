# Shared harness: design

Date: 2026-10-28. Author: Claude, from a conversation with the owner (bodasooqa). Here "the owner" means his words and decisions; "my decision" means something I decided and the owner may challenge.

## Why

Over two months on screener, a stack and harness took shape that the owner likes: Rust and React in one monorepo, bun, turbo, biome, lefthook, CI on own runners, the "spec → OpenSpec → stages → `knowledge/`" process, executors and reviewers, edit hooks, Orca for worktrees. The owner wants to move this into a separate repository and run both screener and future projects on it.

The point, in the owner's words: **harness improvements reach all projects**. This is not a one-off template but a living, versioned distribution. It must work in both Claude Code and Pi: the owner has already started using Pi.

## Goals

1. A new project is created with one command, choosing its parts: Rust (yes/no), frontend (yes/no), monorepo (yes/no). Any combination with at least Rust or frontend.
2. A harness improvement merged into shared automatically arrives as a PR in every project; a PR with no conflicts and green CI merges itself.
3. A session in any project can open a PR with an improvement to shared on its own.
4. The harness works in Claude Code and Pi from day one.
5. screener moves onto shared and becomes its first consumer.

## Non-goals

- **Not a code library.** The code skeleton and `uikit` are starter files: created once and owned by the project afterwards. The owner: "a new project starts from the uikit template from screener, and then each project has its own look"; he clarified: the template has only the package skeleton, zinc theme tokens and utilities, "components are each project's own".
- **Not an application skeleton.** The daemon, `proto` with TS type generation, Postgres are not in the template. The owner: "an empty application with basic tools configured, since projects will differ a lot from the screener".
- No agents other than Claude Code and Pi (Codex, Cursor and others are out of scope for now).
- No per-project choice of artifact language. Since v2.0.0 the harness and everything it generates are in English: skills, prompts, hook messages, documents, comments, the knowledge journal, commits. Agents talk to the owner in the chat language from the `chat_language` template answer (Russian by default). Markers that scripts parse are English too: `<!-- unfolded revisions -->`, `<!-- toc: built by knowledge/index.sh, do not edit -->` / `<!-- /toc -->`, stage states `in progress` / `closed`, `# Closed questions`.
- Not a hidden repository: shared is public for now (see below), so it holds no secrets and no domain knowledge of projects.

## Anti-goals

The owner said it directly: conflicts during updates and migrations are a normal workflow, not a failure. Failure is when an improvement made in one project does not reach the others, or when an update silently overwrites what a project changed for itself.

## Decided by the owner

| Question | Answer |
|---|---|
| Template or living distribution | Living: improvements reach all projects |
| Repository | New; public for now, shared CI on GitHub runners |
| Merging into shared | The main Claude session merges PRs into shared itself, after green CI (owner's permission of 28.10.2026: "I allow you to merge on your own"); a patch/minor tag is set automatically on merge; a major version only manually, with a migration note |
| Language | Everything in English; agents talk to the owner in the chat language (`chat_language`, Russian by default) |
| Telegram bots | A skill, not a separate subagent; an optional module |
| Linear in Pi | The owner will set up MCP in Pi himself later; Linear is optional altogether |
| Pi | From day one |
| Process | All of it: spec with a revision journal, OpenSpec, stages, `knowledge/`, Orca. Linear at the project's choice |
| Alternatives to the process (Spec Kit, Kiro, BMAD) | Not needed, the process works |
| screener | Moves onto shared |
| Update delivery | Automatic PR; merges itself if CI is green and there are no conflicts |
| `uikit` | Starter file: an empty package skeleton — shadcn neutral theme tokens (zinc) and `cn`, no primitives; components are each project's own (owner's clarification of 28.10.2026) |
| Skeleton | Empty workspaces with configured tools |
| Composition | Rust and frontend are optional; so is the monorepo |
| Orca | The main tool for now, but may change |
| Improvements to shared | A project session opens a PR to shared itself |

## Delivery mechanism — rootstock

Since v1.0.0 shared is a [rootstock](https://github.com/bodasooqa/rootstock) template: the `rootstock.toml` config at the root, template files in `template/`. `rootstock new` creates a project and writes the `.rootstock.toml` record (source, version, answers, inventory); `rootstock update` applies a new template version with a three-way merge and keeps the project's changes; a conflict is visible in the file. Starter files are the `starter` list: an update does not touch them, and one the project deleted does not come back. Template tasks on `new` are `openspec init --tools claude,pi` and `lefthook install`; a tool missing from PATH gives a warning, not silence. rootstock 0.1 runs `git init` after the tasks, so on `new --git` git hooks are usually installed by hand, and the task says so.

Before v1.0.0 the same role was played by [Copier](https://copier.readthedocs.io/en/latest/updating/) (`copier.yml`, `.copier-answers.yml`) — my decision; the owner saw the comparison and did not object. rootstock is its replacement in Rust, a separate project of the owner's started for this template: the same template format and the same three-way merge, without Python and without Copier's defects in rendering starter paths and recreating deleted starter files. Projects moved over via the bridge release v0.5.x, then v1.0.0 (item 4 "Delivery" below; steps are in `CHANGELOG.md`).

Rejected:

- **rulesync** — generates configs for many agents, but has no subagents for Pi, and from another repository it pulls only rules and skills. It knows nothing about the stack (Cargo, bun, biome, CI). May be useful later as a generator if a third agent appears.
- **Microsoft APM** — a harness package manager, but without Pi and pre-1.0.
- **Claude Code plugin + Pi package** — native and auto-updating, but covers only the agent part; project configs still need a template. Two mechanisms instead of one.
- **Renovate with the Copier manager** — does not keep the executable bit (and hooks are shell scripts) and does not go red on a merge conflict.

**The mechanism may change.** That is how Copier was replaced by rootstock. So that a replacement goes through without manual migration of projects, shared does not rely on anything hard to reproduce outside one tool: no Python Jinja extensions, template hooks as shell scripts. The project's link to the mechanism is only the template format (Jinja2 via minijinja) and the `.rootstock.toml` record; harness scripts read answers from it (the `[answers]` table) themselves, without the rootstock binary.

### Two kinds of files

- **Managed** — updated everywhere: skills, agents, hooks and their tests, the Pi shim, `knowledge/` scripts, the shared part of CI, lefthook, biome, the OpenSpec config.
- **Starter** — created once (the `starter` list in `rootstock.toml`: a starter file the project deleted does not come back); updates do not touch them: the code skeleton, `uikit`, project rules `AGENTS.md` and `CLAUDE.md` made of imports, the empty spec, `README.md`, project extensions. `.gitignore` and `.gitattributes` are starter too: the project adds its own entries to them (screener had its own `.gitattributes` before the template's, and the starter one does not touch it, while a project without one gets it created). The template `.gitattributes` keeps LF on any system: with CRLF from `core.autocrlf=true` on Windows, harness scripts fail.

### Extension points

Rule: a project does not edit a managed file, it adds its own content to a starter file that the managed one includes. Then updates almost never conflict. How each kind is included is my decision:

| What | Managed | Project |
|---|---|---|
| Agent instructions | common process rules as a separate managed file `.harness/process.md` | the project's `AGENTS.md` (starter): domain, invariants, definitions; tells the agent to read the common one. `CLAUDE.md` (starter) holds only the imports `@AGENTS.md` and `@.harness/process.md` for Claude Code. One rules file for all agents (Claude Code, Pi, Codex and others that read `AGENTS.md`); only Claude Code understands the `@file` import, so it lives in `CLAUDE.md`, not in `AGENTS.md`. Packages do the same: `AGENTS.md` with rules, `CLAUDE.md` made of `@AGENTS.md` |
| Hooks | dispatcher: Claude's `settings.json` and the Pi extension call one dispatcher script per event | `<harness dir>/local/hooks/<event>/*.sh` — the dispatcher runs them after the common ones |
| Agents | the common agent prompt | addendum `<harness dir>/local/agents/<name>.md`; the agent must read it if the file exists |
| Skills | common skills | the project's own skills alongside, under their own names; an addendum to a common skill is `<harness dir>/local/skills/<skill>.md`, the skill reads it as its first step if the file exists |
| CI | a managed workflow with common jobs | the project's starter `ci.yml`: its own jobs (screener has `spec-defaults`) |
| lefthook | a managed common config | a starter `lefthook.yml` with `extends` to the common one |
| Tables of contents for monolith-form documents | the `knowledge` job in pre-commit and the "Tables of contents built" step in CI call `knowledge/index.sh` if it exists | the project's `knowledge/index.sh`: with `--stage` it rewrites the tables of contents and stages them, without arguments it only rewrites |
| biome | a managed common config | a starter `biome.json` with `extends` to the common one |

Where exactly the "harness dir" lives (`.harness/` or otherwise) is up to the builder.

screener's domain hooks `contract-touch.sh` and `guard-data.sh`, the domain skills `new-exchange-adapter`, `core-fsm-test`, `reel`, `contract-change` in their current form, and the `video-developer` agent go to project extensions. The domain paragraphs of the `rust-developer` and `rust-reviewer` prompts (prices in ticks, `f64`, FSM, `exchange`/`market`/`symbol` spans) go to agent addenda.

## Template questions

- `rust`, `frontend`, `monorepo` — booleans, as above.
- `linear` — whether to include the Linear module (the `linear-triage` skill, `DEN-N` in the PR title, Linear lines in `change-finish`). Without it a task is named after the change. The module works via Linear MCP; in Pi, once the owner sets up MCP there; until then Linear is unavailable in Pi.
- `telegram` — the `telegram-bot` skill for `rust-developer` (read as a file by path, like `core-fsm-test`): send limits and a queue with a pause on 429, markup and escaping, webhook or long polling, bot commands. Filled with screener's experience: there the bot is on bare `reqwest` — alerts, the owner bot, `/help`, plans (`crates/daemon/src/alerting/telegram.rs`, `crates/daemon/src/owner_bot/`). Available only with `rust`.
- `orca` — the Orca module: the "worktree per session" rule via `orca worktree`, the `session-tree` hook and the requirement that Orca be installed. The `orca-cli` and `orchestration` skills are not part of the template: Orca itself installs and updates them globally, like superpowers (my decision). Enabled by default. Without it — `git worktree`. The process must not refer to Orca directly, only through the module: the owner allows for the tool changing.
- `chat_language` — the language agents use to talk to the owner (Russian by default). Everything else — artifacts, comments, the journal — is in English regardless of the answer.
- Document paths: spec, revision journal, decisions, lessons, open questions. Skills, agents and hooks take paths from here, not from hard-coded strings. That way screener with the old form and new projects with the new form run on the same harness.
- Project name, Linear task prefix, package names (`<project>-<crate>`, `@<project>/<name>`).

### Layouts

| Rust | Frontend | Monorepo | Layout |
|---|---|---|---|
| yes | yes | yes | `crates/`, `apps/web`, `packages/uikit`; Cargo + bun + turbo |
| yes | no | yes | `crates/`, Cargo workspace |
| yes | no | no | a single crate at the root |
| no | yes | yes | `apps/web`, `packages/uikit`; bun + turbo |
| no | yes | no | a single application at the root, components in `src/components/ui` per the shadcn convention |
| yes | yes | no | does not exist: Rust and frontend together are always a monorepo (my decision) |

What depends on the answers: without Rust there is no `rust-developer`, `rust-reviewer`, `rustfmt`/`clippy` hooks, Rust CI job or Rust lefthook commands; without frontend, the same for frontend, `uikit-component`, `biome` for TS. Always present: the process, the spec, OpenSpec, `knowledge/`, `spec-auditor`, `change-finish`, `stage-*`, `knowledge-note`, session hooks and staging hooks.

The starter files' stack is the same as screener's: stable Rust, edition 2024, `[workspace.dependencies]` with pinned versions; a React SPA on Vite, bun, turbo, biome, Tailwind and the shadcn convention in `uikit`. The empty application builds and passes typecheck, lint and empty tests.

## Document form in a new project

The process is the same, the form differs — because of screener's pain: the spec grew to 894 KB, `decisions.md` to 7 thousand lines, neither can be read in full (DEN-173, DEN-172).

- The spec is a directory, one file per section.
- The revision journal is one file per revision; a revision's heading or frontmatter marks whether it is folded into the spec sections. The list of unfolded revisions is built by a script, not maintained by hand.
- Decisions and lessons are one file per entry, like ADRs.
- Open questions stay in one file with due dates (`due.sh` works as now); closed ones are moved to the archive by a script.

screener keeps its form (the spec as a file plus the journal as a file after DEN-173, monolithic `decisions.md` and `lessons.md`): there are hundreds of links to it, and the journals are append-only. Hence the requirement: `knowledge/` scripts and skills work with both forms, or the old-form scripts stay with screener as project files. How exactly is up to the builder.

Done this way (my decision): `due.sh` and `archive-questions.sh` are shared by both forms; tables of contents for the catalog form are built by the common `knowledge/index.sh`, while the monolith form has no common script — each project's monolith table of contents is its own (labels, anchors, which files). The project puts in its own `knowledge/index.sh`, the common `knowledge` job calls it after archiving questions, and CI checks the tables of contents with the same step as for catalog. One name for both forms: the job and CI need no branch, and project tests in `knowledge/tests/` are triggered by the same `knowledge-tests` job. A separate job for the project script is not possible: both would write `open-questions.md` and the git index in a race, and lefthook does not allow overriding `run` of a common job via `extends`. In the monolith form the template does not create `knowledge/index.sh`, so updates do not touch it.

## Claude Code and Pi

Checked against Pi 1.4.0 documentation (`~/.pi/agent/install/releases/1.4.0/.../docs`) and the owner's installation.

| Part | Claude Code | Pi | How |
|---|---|---|---|
| Instructions | `CLAUDE.md`, `@file` import | loads one context file per directory, `AGENTS.md` before `CLAUDE.md`; does not understand the `@file` import | project rules go in `AGENTS.md`: Pi, Codex and other agents read it, one source for all. `CLAUDE.md` holds only `@AGENTS.md` and `@.harness/process.md`, so Claude Code gets both. The shim brings `.harness/process.md` to Pi: it adds it to context files right after the main file. With `AGENTS.md` present it does not add `CLAUDE.md` while that file holds only imports; with its own rules it does add it: the update creates a starter `AGENTS.md` stub even in a project that still keeps its rules in `CLAUDE.md`, and without this Pi would lose them. Previously rules lived in `CLAUDE.md` with an `@.harness/process.md` import, and Codex did not see them (DEN-228) |
| Skills | `.claude/skills/` | the Agent Skills standard: `.agents/skills/`, `.pi/skills/` or a package | one copy of the files, visible to both. Skill text without tool names specific to one agent (`Agent`, `Skill`, `TodoWrite`) — described as an action, as in superpowers |
| Agents | `.claude/agents/<name>.md` | the `@gotgenes/pi-subagents` package: `.pi/agents/<name>.md`, similar frontmatter | one description → two files by generation. Tool mapping (`Read`→`read`, `Glob`→`find`, `Bash`→`bash`…) and model mapping (`opus`→`anthropic/claude-opus-…`) live in the generator |
| Hooks | shell scripts in `settings.json` | a TypeScript extension: `tool_call` (can block), `tool_result`, `session_start`, `session_shutdown`, `input`, `agent_before_settle` (can continue the run) | logic in shell scripts with a common JSON input; thin shims per agent. Hook tests run through both shims |
| OpenSpec | `openspec init --tools claude` | `--tools pi` is supported (OpenSpec 1.12) | `--tools claude,pi`; OpenSpec files are generated, as now |
| superpowers | plugin | Pi package | installed by the user, not part of the template |
| Permissions | `settings.json` | `@gotgenes/pi-permission-system`, its own format | Claude only; Pi is out of scope for the first version (my decision) |

The owner's Pi already has `pi-subagents`, `pi-permission-system`, `pi-subagents-worktrees`, `pi-autoformat`, `rpiv-ask-user-question`, `rpiv-todo` and the Orca extensions. The template may require `pi-subagents` as a dependency.

The owner's models in Pi go through OpenRouter. The agent model mapping (`opus`, `sonnet` → Pi identifier) is a table in project settings, not hard-coded strings: the provider may change. By default — Anthropic models through whichever provider is configured; skill texts are tuned for Claude (my decision).

Claude's async hooks (clippy and tsc in the background with a wake-up on error, exit 2) must be reproduced in Pi with extension means, or it must be honestly noted that in Pi they are synchronous or absent. The decision is up to the builder, but the divergence is recorded in shared's documentation.

### Executor checks on exit (DEN-229)

Async checks do not wake a subagent's edits: the executor follows TDD, and red between its edits is part of the work. So a report with red fmt, clippy or tsc was caught only by the main session's full run, and the executor was restarted. The owner's decision: the executor does not finish while fast checks are red for the packages it touched. The `agent-checks.sh` hook, slots `subagent-stop` and `pre-handback`; how it works — hooks README, "Executor checks".

- **Who is an executor.** An agent named `*-developer`, not a list of names: the agent naming convention already exists in the template (`rust-developer`, `frontend-developer`, reviewers are `*-reviewer`), a project executor of the same kind (`video-developer` in screener) is picked up without editing the harness, and a second list would lag behind the agents. The extension point is the agent name.
- **What is checked.** Working-tree changes relative to HEAD plus untracked files, reduced to crates and packages; commands and path parsing are shared with `rust-clippy` and `js-typecheck` (`lib/rust-crate.sh`, `lib/js-package.sh`). Git does not know whose edit it sees: the main session's changes before the executor started are included too.
- **Once.** The refusal happens once per stop (`stop_hook_active`) and once per report: an executor that cannot fix it within the task returns a question instead of looping.
- **`SubagentHandback`.** Checked against Claude Code documentation: in auto mode a subagent hands in its report with this tool before stopping, and `SubagentStop` fires when the report is already with the main session. So on top of `SubagentStop`, `PreToolUse` on `SubagentHandback` is wired: the report is refused once, with a marker in the worktree's git directory. Refusing more is not allowed: after three refusals Claude Code terminates the agent without a report.
- **No `Stop`.** In the main session edits are checked by `post-edit-async` with a wake-up, leftovers by `session-end`, and before a PR by a full run; `Stop` on every turn would cost time. An executor running as a separate session gets `Stop`, not `SubagentStop`; the reliable sign of such a session is `agent_type`, which Claude Code puts in the input only if the session was started with `claude --agent <name>`. An orchestrator that starts the executor as an ordinary session (Orca `worker-start --agent claude` chooses the agent program, it is not Claude Code's `--agent`) gives no such sign, and the template chose not to invent one from environment variables. The hook understands `Stop` too: a project that starts executors via `--agent` wires `Stop` → `dispatch.sh subagent-stop` with its own line in `.claude/settings.json`.
- **Pi.** There is an analogue of `SubagentStop`: `agent_before_settle` in a `pi-subagents` child session (same process, same extension) can append a message and continue the run once (`continue: true`) before the answer goes to the parent. Pi has no `SubagentHandback`, so the `pre-handback` slot is not wired.

### Claude Code permissions

`permissions.allow` in `.claude/settings.json` lists commands the agent calls constantly, without a prompt. A Claude Code rule `Bash(<prefix> *)` lets through everything after the prefix, so allow holds only forms whose arguments carry no execution or writing to an arbitrary path (#21): otherwise a command that looks like a "search" or a "log" goes through without confirmation, including via prompt injection from text it has read.

- **Not in allow:** `rg` (`--pre <command>`), `git diff`/`git log` (`--output=<file>`, `--ext-diff`), `lefthook` other than `lefthook validate` (`lefthook run` executes `lefthook.yml`), `bunx` other than `tsc --noEmit` and `biome` (`bunx <any package>` downloads and runs third-party code), `bun` other than the listed `package.json` scripts, `turbo` other than `turbo run`, `openspec` other than reading and working with changes (`init`, `update`, `config`, `completion`, `feedback` — with a prompt). Claude Code already lets safe forms of `git diff`, `git log`, `git status` through without a prompt — a built-in set of read-only commands with flag checks; searching is done with the agent's search tool, not `rg` in the shell.
- **In allow with a trailing `*`:** `cargo check|build|test|clippy|fmt|tree|metadata`, `bun test`, `biome check|format|lint`, `turbo run`, read-only `gh pr|run`, `jq`, `shellcheck`, `git add`. They execute project code (tests, `build.rs`, scripts), but the agent writes that code by editing files, and editing goes through its own permissions.
- **deny** — flags that turn an allowed or built-in read-only command into execution or writing: `rg --pre`, `git diff|log|show --output|--ext-diff`, `cargo --config` (`build.rustc-wrapper`), report and log files of `biome`, `turbo`, `bun test`. deny beats allow at any level, so it also holds against a broad rule from personal settings. Long git and rg flags are not abbreviated, so the `*--output*` pattern cannot be bypassed by abbreviation.

This is not a security boundary: a rule is matched against the command text, and `sh -c '…'` or a full program path bypasses it — the boundary there is the Claude Code sandbox. The goal is that an ordinary agent command, prompted or not, does no more than it appears to. A project that needs more adds its own line in its `.claude/settings.json` (a managed file; the project's edit survives updates) or in `.claude/settings.local.json`. In Pi the template sets no permissions (table above).

## Update flow

1. **Improvement.** A project session edits a clone of shared on its own branch and opens a PR to shared. Where the clone lives is up to the builder (next to the projects or temporary). Until the PR is merged, the project may fix its own file itself: the update will later see the same edit and go through without conflict.
2. **Shared checks.** Shared's CI generates each of the five layouts and runs build, typecheck, lint, tests and hook tests through both shims in each. A separate job on `windows-latest` (Git Bash) checks the project's git hooks (`scripts/check-lefthook.sh`: commit and push via lefthook, pre-push without and with upstream, `knowledge/` tests, line endings): for a developer on Windows, hooks must work without `LEFTHOOK=0`. Hence the rules of the common `lefthook.yml`: on Windows lefthook executes `files:` without a shell, so the script is called as `sh ./…` and written in POSIX sh; `run:` goes through `sh -c`, but in double quotes without escaping — there are no double quotes in `run:`. Shared has its own `CLAUDE.md` with rules for working on it.
3. **Version.** The main session merges PRs into shared after green CI. On merge a patch or minor tag is set automatically. A breaking change (a path renamed, a template question changed) is a major version, only manually, with a migration note; its PR in projects does not merge itself.
4. **Delivery.** Shared does not broadcast events: each project itself, once a day (and manually), compares shared's tags with its own version (`version` in `.rootstock.toml`). The managed workflow `harness-update.yml` installs a pinned rootstock version with a checksum check, runs `rootstock update` to the tag, conflicts as markers in files, and opens a PR "Harness update to vX" with the `harness:major` and `harness:conflict` labels as applicable. Moving off Copier: the bridge release v0.5.x workflow, on a tag with `rootstock.toml`, makes `rootstock import-copier` the PR's first commit (the project moves to `.rootstock.toml` at its previous version) and `rootstock update` to the tag the second; on a tag without it, `copier update`. So the v1.0.0 major reaches a project only through the bridge.
5. **Merge.** The PR merges itself if CI is green and there are no conflict markers. The merge is triggered by the CI completion event (`workflow_run` or `check_suite`), not by waiting inside a job: with one runner per repository, a waiting job would occupy the runner and block CI itself (my decision). A custom merge is needed because CI in screener is not required (owner's decision "not needed yet"), and GitHub's built-in auto-merge without required checks would merge the PR immediately.
6. **Conflict.** The PR stays open, CI is red on the markers. A Claude session resolves it as an ordinary task.

**Runners and access.**
- Shared's own CI runs on GitHub runners: the repository is public, minutes for it are free.
- Projects (screener) stay on their self-hosted runners. On a personal account a runner is bound to one repository, so the update and auto-merge workflows must coexist with one runner per project (merge by event — see item 5). The workflow installs rootstock itself, a pinned version with a checksum check; if `gh` is missing, it installs that too. Everything goes into the job directory without touching the runner's system.
- Shared is public, so projects read it without a token.
- A PR opened with the standard `GITHUB_TOKEN` does not trigger the project's CI, and it may not push changes to `.github/workflows/`. So the update PR is opened and merged with the project secret `HARNESS_UPDATE_TOKEN` — the owner's fine-grained PAT (Contents, Pull requests, Workflows — RW, Metadata — R); the owner creates the secret. There is no broadcast from shared — projects check tags on a schedule, and shared needs no access to them. The update workflow's runner is the repository variable `HARNESS_RUNNER`, the tag source is `HARNESS_TEMPLATE_URL` (for testing on a copy of the template). Setup is in the project's `.harness/local/README.md`.
- Where new projects' CI runs (own runner per repository or GitHub runners) is decided when the first new project is created.

## Moving screener over

In one migration, a separate PR in screener: the template is applied to the existing repository with screener's answers (Rust, frontend, monorepo, Linear, Orca, paths to the old document form), and divergences are resolved by hand once. After that, regular updates. screener's domain content moves to project extensions (see "Extension points"). Video (`apps/video`, `video-developer`, `reel`) is project-specific.

## Order of work

1. Shared grows out of screener's harness: the common is separated from the domain, paths become parameters, the Pi shim and the agent generator appear.
2. Shared CI on five layouts.
3. Moving screener over — the first consumer, a check on a live project.
4. Automatic update delivery.
5. The first new project.

The owner: "First shared from screener, then screener on it, then a new project" — this is my wording, which he did not dispute.

## Up to the builder

- The repository name (proposal: `bodasooqa/harness`) and the layout of the harness dir inside a project.
- The format of the source agent description and the generator.
- How exactly a skill is seen by both agents without duplicating files.
- The shape of `knowledge/` scripts for the two document forms.
- The mechanics of broadcasting a new-version event and the kind of secret.
- Linear tasks: shared is screener harness work, tracked in its Linear under its own tasks until the owner decides otherwise.
