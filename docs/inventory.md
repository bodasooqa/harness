# Inventory of the screener harness

Phase 1 of the plan. Taken from `bodasooqa/screener` at the `main` commit of 28.10.2026 (after #548). Each harness file gets a kind:

- **common** — a managed template file, present in every project;
- **module `<name>`** — managed, present when a template question is answered "yes" (`rust`, `frontend`, `linear`, `orca`, `telegram`);
- **starter** — created once, owned by the project afterwards;
- **screener** — stays a screener project extension, does not go into the template.

"Parameters" — what is hard-coded for screener in the file and becomes a template answer or a setting: `{{name}}` — the project name, `{{spec}}` — document paths, `{{tracker}}` — the task prefix.

## Agents `.claude/agents/`

| File | Kind | Parameters and what goes to the screener addendum |
|---|---|---|
| `rust-developer.md` | module `rust` | Skill paths — to the common form. To the screener addendum: `i64` prices in ticks, `Decimal`, `now_ms`, FSM, order book sync, `sqlx prepare` |
| `rust-reviewer.md` | module `rust` | Common: panics, `unsafe`, blocking in async, magic numbers, `println!`, branch diff. To the addendum: `f64` in prices, FSM, `exchange`/`market`/`symbol` spans |
| `frontend-developer.md` | module `frontend` | `@screener/*` → `@{{name}}/*`; the boundary between `uikit` and screens is common. To the addendum: the density domain, IPC |
| `frontend-reviewer.md` | module `frontend` | Same: theme tokens, shadcn, types only from the contract are common; the domain goes to the addendum |
| `spec-auditor.md` | common | Spec and journal paths — `{{spec}}`. To the addendum: core invariants §4.3–§4.5, §6, §11 |
| `video-developer.md` | screener | Remotion, episodes from the production library |

## Skills `.claude/skills/`

| Skill | Kind | Parameters |
|---|---|---|
| `change-finish` | common | Check commands — per module `rust`/`frontend`; `DEN-N` and Linear — to the `linear` module; paths `{{spec}}` |
| `knowledge-note` | common | `knowledge/` paths and the document form (old in screener, new one file per entry) |
| `stage-acceptance` | common | `{{spec}}` §12 → "the spec's stages section" at the path from settings |
| `stage-grooming` | common | Same; `due.sh` |
| `contract-change` | common (generalized) | The "spec first → regeneration → consumers" procedure is common; the list of contracts is taken from the source-of-truth table in the project's `CLAUDE.md`. screener's four contracts (proto, `MarketEvent`, migrations, `default.toml`) go to its `CLAUDE.md` |
| `uikit-component` | module `frontend` | `@screener/uikit` → `@{{name}}/uikit`; in the non-monorepo layout — `src/components/ui` |
| `linear-triage` | module `linear` | Team, prefix `{{tracker}}`, roles "owner/trader" → "owner/customer" per setting; the trader vocabulary is screener's |
| `core-fsm-test` | screener | Density FSM |
| `new-exchange-adapter` | screener | Exchange adapters |
| `reel` | screener | kelv videos |
| `telegram-bot` | module `telegram` (new) | Written from `crates/daemon/src/alerting/telegram.rs` and `owner_bot/` |
| `openspec-*`, `.claude/commands/opsx/` | generated | Installed by `openspec init --tools claude,pi`, not put into the template |

## Hooks `.claude/hooks/` and `settings.json`

| File | Event | Kind | Parameters |
|---|---|---|---|
| `guard-staging.sh` | PreToolUse/Bash | common | — |
| `bash-edit.sh` | PostToolUse/Bash | common | Hint text — per module (rustfmt/clippy — `rust`, biome/tsc — `frontend`) |
| `session-tree.sh` | SessionStart | common | `knowledge/due.sh` → path from settings. Does not call Orca, works via `git worktree` |
| `session-leftovers.sh` | SessionEnd | common | — |
| `knowledge-due.sh` | UserPromptSubmit | common | Path to `due.sh` |
| `lib/bash-scan.sh`, `lib/staleness.sh` | library | common | — |
| `rust-fmt.sh` | PostToolUse/Write\|Edit | module `rust` | — |
| `rust-clippy.sh` | same, async | module `rust` | `screener-$crate` → `{{name}}-$crate`; the `SCREENER_CLIPPY_STATE` variable → a common name; layout without a workspace (single crate) |
| `js-fmt.sh` | PostToolUse/Write\|Edit | module `frontend` | — |
| `js-typecheck.sh` | same, async | module `frontend` | Non-monorepo layout |
| `contract-touch.sh` | PostToolUse/Write\|Edit | screener | Paths of proto, migrations, `default.toml`, generated. No common version: a project hook |
| `guard-data.sh` | PreToolUse/Bash | screener | Size library, replay recordings |
| `tests/run.sh` (1456 lines) | tests | common + screener | Split: cases for common hooks — to shared (on a synthetic repository, without screener paths); cases for `contract-touch`, `guard-data`, protocol-generated — screener project tests |
| `settings.json` | wiring | common | Hooks → dispatcher. `permissions.allow`: common (`git`, `rg`, `jq`, `openspec`, `lefthook`), `rust` (`cargo …`, `rustfmt`), `frontend` (`bun`, `bunx`, `turbo`, `biome`); `cargo run -p screener-daemon`, `sqlx` — screener. `permissions.deny`: `.env*`, generated OpenSpec — common; `config/local.toml`, `fixtures/replay`, `data`, `.sqlx`, `packages/protocol/src/generated` — screener. `worktree.symlinkDirectories: node_modules` — module `frontend`. The `rust-analyzer-lsp` plugin — module `rust` |

## Git hooks and CI

| File | Kind | Parameters and what goes to screener |
|---|---|---|
| `lefthook.yml` | common + starter | Managed common: `secrets`, `knowledge-index`, `claude-hooks`, `knowledge-due-tests`, `knowledge-due`; `rustfmt` — `rust`; `biome` — `frontend`. The project's starter `lefthook.yml` with `extends`. `protocol-generated` — screener |
| `.lefthook/no-secrets.sh` | common | — |
| `.lefthook/push-files.sh` | common | — |
| `.lefthook/check-protocol-generated.sh` | screener | — |
| `.github/workflows/ci.yml` | common + starter | Jobs `changes` (path filters), `rust`, `js`, `harness` — a managed workflow with runner parameters (`runs-on`), path filters per module. `spec-defaults`, the Postgres service and `sqlx` in `rust` — screener. Runner labels (`mac`, `netcup-ci`) — a project setting |
| `.github/workflows/release.yml`, `deploy.yml` | screener | Daemon image and rollout |

## Documents and knowledge

| File | Kind | Parameters |
|---|---|---|
| `knowledge/index.sh` | common (old form) | Tables of contents for monolithic documents. The new form has its own catalog index script. If the common one cannot handle both forms, screener keeps it as a project file. It stayed a project file: in the monolith form the common `knowledge` job and CI call the project's `knowledge/index.sh` if it exists |
| `knowledge/due.sh`, `knowledge/tests/due.sh` | common | The "stage N §12" due date — the stages section path from settings; test examples without densities |
| `knowledge/README.md` | starter | The "where to put things" rule; the file list is project-specific |
| `knowledge/bot-*.sql/py/sh`, `research-*` | screener | Research |
| `openspec/config.yaml` | common + starter | Artifact rules, language, kebab-case — common; project context (domain, crates, spec paths) — the starter part. If OpenSpec cannot merge two files, the file is starter, and the template writes the common rules text into it once |
| `docs/DENSITY_SCREENER_SPEC*.md` | screener | The new spec form is a starter directory |
| `.mcp.json` | module `linear` | Linear server |

## `CLAUDE.md`

screener's root `CLAUDE.md` by section:

| Section | Kind |
|---|---|
| Introduction, "The spec is large…" | starter (with `{{spec}}` paths) |
| Stack | modules `rust`/`frontend`: the common part (edition 2024, `[workspace.dependencies]`, bun, biome); `rust_decimal`, `sqlx`, `figment`, "no `f64`" — screener |
| Package boundaries, four invariants | screener (the project's package map); the rule "each package has its own `CLAUDE.md`" is common |
| Sources of truth | starter: the project's table; the line "a change goes through the `contract-change` procedure" is common |
| Three places for documentation | common |
| Workflow, OpenSpec, superpowers | common |
| Harness outside OpenSpec | common |
| A worktree per session | common + module `orca` (the Orca paragraph) |
| Never edit generated | common (the generated list is project-specific: `.sqlx`, `Cargo.lock`, …) |
| Edit with Write/Edit | common |
| Commands | modules `rust`/`frontend`; `docker compose`, `record`/`replay`, `screenerd` — screener |
| Working order by stages | common |
| Commits | common; package prefixes are project-specific; `DEN-N` — module `linear` |
| Code rules | common (English identifiers, config instead of magic numbers, UTC `i64` ms, `tracing`/no `println!`, no `unwrap` outside tests) — module `rust`; adapters, FSM, anchor, MM flags — screener |
| Tests | screener (per package) |
| What not to do | common: ORM, `unsafe`, long explanations; exchanges, the Postgres decision — screener |
| Repository harness (skills, executors, hooks, lefthook, OpenSpec, Linear) | common, assembled per module |
| Separating head and hands | common |
| Definitions | screener |

Package `CLAUDE.md` files:

| File | Kind |
|---|---|
| `packages/uikit/CLAUDE.md` | module `frontend`, starter (boundaries, shadcn, color via tokens, checks) |
| `apps/web/CLAUDE.md` | module `frontend`, starter — the common "Boundaries / Checks" skeleton; "Main rule", "Display", "Delivery" — screener |
| `crates/*/CLAUDE.md`, `packages/protocol/CLAUDE.md`, `apps/landing/CLAUDE.md`, `apps/video/CLAUDE.md` | screener |

## Stack (starter files)

| File | Kind | Parameters |
|---|---|---|
| `Cargo.toml` (root) | starter, `rust` | `[workspace]` with empty `members`, `[workspace.dependencies]` with common ones (`tokio`, `serde`, `tracing`, `thiserror`, `anyhow`); domain ones (`sqlx`, `rust_decimal`, `tokio-tungstenite`, `figment`) are not included |
| `rust-toolchain.toml`, `rustfmt.toml` | common, `rust` | — |
| `package.json` (root) | starter, `frontend` | `name`, scripts `typecheck`/`build`/`test`/`lint`/`dev` via turbo |
| `turbo.json`, `tsconfig.base.json` | common, `frontend` | — |
| `biome.json` | common + starter | A managed common config; a starter `biome.json` with `extends`; `.sqlx` and fixtures exclusions — screener |
| `packages/uikit/` | starter, `frontend` | Only the package skeleton, no primitives (owner's decision of 28.10.2026): `package.json` (`@{{name}}/uikit`, exports as in screener), `tsconfig`, `components.json` for shadcn, `CLAUDE.md`, `src/styles/globals.css` with shadcn neutral theme tokens (zinc), `src/lib/utils.ts` (`cn`), empty `components/` and `hooks/`. Components are each project's own; screener's are not copied |
| `apps/web/` | starter, `frontend` | An empty Vite + React SPA on `uikit` |
| `docker-compose.yml` | screener | Postgres |

## Summary

| Kind | How many |
|---|---|
| common | 6 skills (with the generalized `contract-change`), `spec-auditor`, 7 hooks and `lib/`, hook tests (common part), `knowledge/` scripts, lefthook scripts, lefthook/biome/CI configs (common part) |
| module `rust` | 2 agents, 2 hooks, toolchain, rustfmt, cargo permissions |
| module `frontend` | 2 agents, `uikit-component`, 2 hooks, turbo, tsconfig, bun permissions |
| module `linear` | `linear-triage`, `.mcp.json`, `DEN-N` in `change-finish` and commits |
| module `orca` | the Orca paragraph in "A worktree per session"; Orca installs its skills itself |
| module `telegram` | the new `telegram-bot` |
| screener | 4 skills, `video-developer`, 2 hooks, protocol-generated, release/deploy, domain paragraphs of agents and `CLAUDE.md`, `spec-defaults`, research |

## Disputed — for the owner to decide

Nothing: the classification follows the design. Decisions I made:

- `contract-change` is common, not screener: the procedure does not depend on the domain, only the list of contracts does.
- `session-tree` is common, not module `orca`: the hook works via `git worktree` and does not call Orca.
- ~~Frost, plan locks and the kelv brand do not go from `uikit`, the remaining primitives are copied~~ — replaced by the owner's decision: the starter `uikit` is an empty skeleton with zinc tokens and `cn`, no primitives.
