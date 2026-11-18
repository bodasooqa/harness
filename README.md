# harness

A shared harness for projects: the stack, the process, and the agent harness for Claude Code, Pi, and Codex in a single [rootstock](https://github.com/bodasooqa/rootstock) template. A project is created from the template, and template improvements reach every project as a PR.

Grew out of the screener project's harness over two months of work. Design — [`docs/design.md`](docs/design.md), plan — [`docs/plan.md`](docs/plan.md).

## Status

The plan is complete. `rootstock new` creates a project in any of the five layouts with green build, typecheck, lint, and tests, with agents, skills, hooks (a dispatcher and extension points in `.harness/local/`), process rules in `.harness/process.md`, lefthook, CI, and `knowledge/` scripts. Template CI runs all layouts and sets tags; new versions reach projects as a PR (phase 6, section "Updates"). The `harness-upstream` skill carries an improvement from a project into the template.

| Phase | What | Status |
|---|---|---|
| 0 | Repository, design, plan | done |
| 1 | Inventory of the screener harness | done |
| 2 | Template skeleton, five layouts | done |
| 3 | Harness for Claude Code | done |
| 4 | Harness for Pi | done |
| 5 | CI and releases | done |
| 6 | Delivering updates to projects | done |
| 7 | Moving screener over | done |
| 8 | Improvements from a project into shared | done |

## What's inside

- **Stack of your choice:** Rust (a Cargo workspace or a single crate), a React SPA on Vite with a `uikit` package following the shadcn convention, a bun and turbo monorepo or a single app; biome, lefthook, CI.
- **Process:** a spec with a revision journal, OpenSpec, stages with acceptance, `knowledge/` with decisions, lessons, and open questions with due dates.
- **Agents and skills:** executors and reviewers per area, `spec-auditor`, `change-finish`, stage and knowledge skills; optional Linear, Orca, and Telegram modules.
- **Hooks:** formatting and checks on edit, a guard for the shared directory, and a worktree report through a shared dispatcher.

## How it works

```sh
cargo install rootstock   # or a release binary: github.com/bodasooqa/rootstock/releases
rootstock new gh:bodasooqa/harness my-project --git
```

Before v1.0.0 the template was in Copier format; moving projects over — `CHANGELOG.md`, section v1.0.0.

Template questions (`rootstock.toml`):

| Question | What | Default |
|---|---|---|
| `project_name` | Name in kebab-case; package names `<name>-<crate>` and `@<name>/<package>` derive from it | — |
| `rust` | Rust in the project | yes |
| `frontend` | Frontend: React SPA on Vite, bun, biome | yes |
| `monorepo` | A monorepo, or a single crate / single app at the root. Not asked with Rust and frontend: always a monorepo | yes |
| `linear` | Linear module | no |
| `tracker_prefix` | Linear task prefix (`DEN`); only with `linear` | — |
| `orca` | Orca module: a worktree per session | yes |
| `telegram` | `telegram-bot` skill; only with `rust` | no |
| `pi_models` | Agent models in Pi: a map `opus`/`sonnet`/`haiku` → Pi model `provider/model` | Opus, Sonnet, and Haiku 5.5 via OpenRouter (`openrouter/anthropic/claude-…-5.5`) |
| `doc_form` | Document form: `catalog` — the spec as a directory, revisions, decisions, and lessons one per file; `monolith` — a single file each, for existing projects | `catalog` |
| `spec_path`, `revisions_path`, `decisions_path`, `lessons_path`, `open_questions_path` | Paths to the spec, the revision journal, decisions, lessons, open questions | with `catalog`: `docs/spec`, `docs/spec/revisions`, `knowledge/decisions`, `knowledge/lessons`, `knowledge/open-questions.md`; with `monolith` — entered |

Layouts:

| Rust | Frontend | Monorepo | What's at the root |
|---|---|---|---|
| yes | yes | yes | Cargo workspace `crates/app`, `apps/web`, `packages/uikit`; bun and turbo |
| yes | no | yes | Cargo workspace `crates/app` |
| yes | no | no | a single crate, `src/main.rs` |
| no | yes | yes | `apps/web`, `packages/uikit`; bun and turbo |
| no | yes | no | a single app, `src/` with components in `src/components/ui` |

Checking all layouts — `scripts/check-layouts.sh` (`--only <name>` for one).

## Claude Code, Pi, and Codex

All three clients share project rules, skills, agent prompts, and hook logic.

| What | Claude Code | Pi |
|---|---|---|
| Project and process rules | `CLAUDE.md` imports `@AGENTS.md` and `@.harness/process.md` | Pi finds `AGENTS.md` and its extension adds `.harness/process.md` |
| Skills | `.claude/skills/` | the same: path `../.claude/skills` in `.pi/settings.json`, no copies |
| Agents | `.claude/agents/` | `.pi/agents/` for `pi-subagents`; the prompt body is shared, models come from the `pi_models` answer |
| Hooks | `.claude/settings.json` → `.harness/hooks/dispatch.sh` | `.pi/extensions/harness.ts` → the same dispatcher with the same input |
| OpenSpec commands | `/opsx:propose` etc. | `/opsx-propose` etc. |

Codex uses `AGENTS.md` for project rules and reads `.harness/process.md` as directed there. Read the rules of each package you touch when starting from the root. Codex has a 32 KiB default limit for automatically loaded project instructions. If the combined files exceed that limit, set `project_doc_max_bytes = 65536` in your Codex config or read the package files explicitly.

- Trust the project and review the Harness hooks in Codex with `/hooks`. The hook definitions in `.codex/hooks.json` call the shared dispatcher through an adapter. Edit checks return feedback in the current tool response. Executor profiles run the shared checks on `SubagentStop`.
- Shared skills appear in `.agents/skills`. The project-scoped profiles in `.codex/agents` inherit the session model and use the same instructions and project addenda as the other clients. Reviewer profiles instruct agents to work without editing files.
- New projects initialize OpenSpec for all three clients. After updating an existing project, run `openspec init --tools claude,pi,codex --no-animation` once from its root to generate Codex skills such as `$openspec-propose`. Commit the generated files and use `openspec update` for subsequent updates.

To make the harness work in Pi:

- install the subagents extension: `pi install npm:@gotgenes/pi-subagents`;
- run `pi` from the project root: `.pi/` is looked up only in the working directory;
- trust the project: without trust Pi doesn't load `.pi/settings.json` and `.pi/extensions/` — in interactive mode it asks itself, `pi -p` needs `--approve`.

Differences:

- **Asynchronous post-edit check** (`post-edit-async`: clippy, tsc) runs in the background and wakes the model with a message, like `asyncRewake` in Claude Code. In `pi -p`, Pi exits after the reply and doesn't wait for the background run.
- **Executor checks on exit** (`subagent-stop`): in Claude Code — `SubagentStop` and the `SubagentHandback` report, in Pi — `agent_before_settle` of the `pi-subagents` child. Pi has no `pre-handback` slot: it has no report tool either.
- **`AGENTS.md` and `CLAUDE.md`.** Pi loads one file per directory, `AGENTS.md` before `CLAUDE.md`, and doesn't expand `@file` imports. A `CLAUDE.md` made only of imports isn't needed there; a `CLAUDE.md` with its own rules (the project hasn't moved to `AGENTS.md` yet) is put back into the context by the extension right after `AGENTS.md`.
- **Permissions** (`permissions` in `.claude/settings.json`) exist only in Claude Code; in Pi the guard is the `pre-bash` hooks.

Wiring details are in `template/.harness/hooks/README.md`.

## Updates

Updates are brought into a project by the managed `harness-update.yml` workflow: once a day it compares the template's tags with the project's version, runs `rootstock update`, leaves conflicts as markers in files, and opens a PR. `harness-automerge.yml` merges the PR after green CI if there's no conflict, no major version, and no foreign commits. The project needs a `HARNESS_UPDATE_TOKEN` secret; setup — `template/.harness/local/README.md`, section "Harness updates".

## Releases

A tag is set automatically after green CI of a merged PR, by its label: `release:minor` — minor, `release:patch` or no label — patch, `release:none` — no tag; `release:major` gets no automatic tag — a major is set manually with a migration note in [`CHANGELOG.md`](CHANGELOG.md).
