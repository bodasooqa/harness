# Shared harness: work plan

Based on the design in `docs/design.md`, approved by the owner on 28.10.2026. Order — by dependencies; each phase has a completion criterion. Phase 9 (the first new project) is outside the plan and starts when the owner creates a project.

Execution rules: work in shared — through its own PRs to `bodasooqa/harness`, merged by the main session after green CI (owner's permission of 28.10.2026). Work in screener — by its process: a Linear task, its own Orca worktree, a PR with `DEN-N`. Executors (`rust-developer`, `frontend-developer`) get self-contained tasks; decisions are made in the main session.

## Phase 0. Repository

1. Create the public `bodasooqa/harness`.
2. First commit:
   - `docs/design.md` — the design;
   - `docs/plan.md` — this plan;
   - `CLAUDE.md` with the rules for working on shared itself: language Russian, a PR is merged after green CI, tags, tests;
   - `README.md`: what it is, how to create a project, how to update.
3. A Linear task in the screener stage project (harness) linking to the repository.

**Done:** the repository exists, the task is In Progress.

## Phase 1. Inventory of the screener harness

Changes nothing in screener. A table `docs/inventory.md` in shared: every file of `.claude/` (agents, skills, hooks, `lib/`, tests, `settings.json`), `lefthook.yml`, `biome.json`, `.github/workflows/*`, `knowledge/*.sh` and tests, `openspec/config.yaml`, every section of `CLAUDE.md` and `crates/*/CLAUDE.md`, `apps/*/CLAUDE.md`, `packages/*/CLAUDE.md`.

For each:
- kind: shared, module (`rust`, `frontend`, `linear`, `orca`, `telegram`), or screener project;
- what is parameterized: document paths, project name, task prefix, package names;
- for shared agent prompts — which paragraphs are domain-specific and go to the screener addendum.

**Done:** no file without a kind; the owner has seen the table (disputed items — as a question).

## Phase 2. Template skeleton

1. `copier.yml`:
   - questions: name, `rust`, `frontend`, `monorepo`, `linear`, `orca`, `telegram`, document paths, task prefix;
   - forbid the Rust + frontend combination without a monorepo;
   - `_skip_if_exists` for starter files;
   - the template in a subdirectory.

   Only features reproducible outside Python: tasks are shell.
2. Starter files of the five layouts:
   - a Cargo workspace or a single crate, edition 2024, `[workspace.dependencies]`;
   - Vite + React SPA;
   - `uikit` from screener — only primitives without domain;
   - bun, turbo, `tsconfig`;
   - empty tests.
3. A new document form:
   - the spec as a directory;
   - a revision journal one per file, with a "folded" mark;
   - a script listing unfolded revisions;
   - decisions and lessons one per file;
   - `open-questions.md` as a single file.

**Done:** `copier copy` of each of the five layouts gives a project with green build, typecheck, lint, and tests.

## Phase 3. Harness for Claude Code

1. **Hooks.**
   - A dispatcher per event.
   - Shared screener hooks are moved over with parameters: `bash-edit`, `guard-staging`, `session-tree`, `session-leftovers`, `knowledge-due`, `rust-fmt`, `rust-clippy`, `js-fmt`, `js-typecheck`, `lib/`.
   - A directory for project hooks.
   - `settings.json` calls the dispatcher.
   - Hook tests (`run.sh`) are moved over and check both the pass-through and the trigger.
2. **Agents.**
   - A source format and a generator into `.claude/agents/`.
   - The addendum mechanism `local/agents/<name>.md`.
   - Shared prompts without the screener domain.
3. **Skills.**
   - Generalize: `change-finish`, `knowledge-note`, `stage-acceptance`, `stage-grooming`, `uikit-component`, `linear-triage` (module); `contract-change` — into a shared form with the contract table from the project's `CLAUDE.md`.
   - Take paths from the template answers.
   - Text without tool names of a single agent.
4. **A new `telegram-bot` skill** from screener's experience: `alerting/telegram.rs`, `owner_bot/`, the lesson about 429 and the queue. Written from screener's code, not from memory.
5. **`CLAUDE.md`.** A managed file of shared process rules and the project's starter `CLAUDE.md` linking to it. Check that Claude Code picks up the link.
6. **OpenSpec.** A managed `openspec/config.yaml`, the template task `openspec init --tools claude,pi`.
7. **`knowledge/`.** Scripts (`index.sh`, `due.sh`, and tests) for the new form. The old form stays in screener as project scripts if the shared ones can't handle both.
8. **Configs.**
   - lefthook: managed plus starter with `extends`.
   - biome: the same.
   - CI: a managed workflow with shared jobs plus the project's starter `ci.yml`.

**Done:** in the full layout, a Claude Code session:
- sees the skills and agents;
- the `guard-staging` hook rejects `git add -A` in the shared directory;
- an edit to `.rs` and `.tsx` is formatted;
- hook tests are green in all five layouts.

## Phase 4. Pi

1. Check on Pi 1.4:
   - which context files it loads if the directory has both `AGENTS.md` and `CLAUDE.md`;
   - whether it understands a link to a shared rules file.

   Choose a mechanism so that the shared rules reach Pi.
2. Skills are visible to Pi without a second copy of the files. Check `.agents/skills/` or a link.
3. Agent generator → `.pi/agents/` for `pi-subagents`: tool mapping and a model table in the project settings.
4. Pi extension `.pi/extensions/harness.ts`: events `tool_call` (with blocking), `tool_result`, `session_start`, `session_shutdown`, `input` → the same dispatcher, JSON input as in Claude.
5. Asynchronous hooks (clippy, tsc with wake-up on error): reproduce or record the difference in the shared README.
6. Hook tests through the Pi shim.

**Done:** in the full layout, a Pi session:
- sees the skills;
- runs `rust-reviewer` through `pi-subagents`;
- `guard-staging` blocks;
- an edit is formatted.

## Phase 5. CI and releases of shared

1. A workflow on GitHub runners: a matrix of the five layouts, in each `copier copy` → build, typecheck, lint, tests, hook tests through both shims.
2. A tag on merge:
   - patch or minor by PR label or commit prefix;
   - a major version — only manually, with a migration note in `CHANGELOG.md`.

**Done:** a PR in shared shows a green matrix; a merge produces a tag.

## Phase 6. Delivering updates

1. A managed project workflow:
   - trigger — an event from shared or a scheduled tag check;
   - `copier update` to the tag, conflicts as markers;
   - a PR with a token or a GitHub App (not `GITHUB_TOKEN`: its PR doesn't trigger CI).
2. A CI check "no conflict markers".
3. Automerge on the CI completion event: green, no markers, version not major.
4. The owner creates the secret — the kind is chosen here, with their consent.
5. A sandbox: a temporary private repository from the template, with three cases on it:
   - a clean update merges itself;
   - a conflict leaves a red open PR;
   - a major version waits.

   Delete the sandbox after the check, with the owner's permission.

**Done:** all three cases worked on the sandbox.

## Phase 7. Moving screener over

A Linear task, its own worktree, a PR to screener.

1. Apply the template to screener with its answers: Rust, frontend, monorepo, Linear, Orca, Telegram, old-form paths, prefix `DEN`.
2. Domain material — into project extensions:
   - hooks `contract-touch`, `guard-data`;
   - skills `new-exchange-adapter`, `core-fsm-test`, `reel`, the domain part of `contract-change`;
   - agent `video-developer`;
   - addenda for `rust-developer`/`rust-reviewer`/`spec-auditor`;
   - job `spec-defaults`;
   - domain sections of `CLAUDE.md`.
3. Resolve differences manually.
4. An entry in screener's `knowledge/decisions.md` about moving to shared. Update `README.md` (the harness section) and `CLAUDE.md` (the sources-of-truth table: the harness now comes from shared).
5. Checks: hook tests, `change-finish` in full, CI green.
6. Reinstall lefthook hooks from the main directory.

**Done:**
- the PR is merged;
- `.copier-answers.yml` in screener;
- the next shared release reaches screener as a PR and merges itself.

**Outcome (29.10.2026).** screener#550 merged at v0.3.3. The move found three template bugs, fixed in releases:
- v0.3.1 — `rust`/`js` inputs of `harness.yml`: the shared rust job got in the way of a project with its base in services;
- v0.3.2 — `copier update` lost the project's edits in managed files (`_skip_if_exists` with an answer was rendered without answers in `/**`) and recreated deleted starter files; test `scripts/check-update.sh`;
- v0.3.3 — `pi.test.ts` under pre-push wrote into the real repository: Bun doesn't pass `delete process.env` to child processes. It applied commits, created a branch, marked the clone as bare. The check — the `* as hook` steps in `check-layouts.sh`.

The last "Done" item waits for the `HARNESS_UPDATE_TOKEN` secret in screener.

Remarks from the move not yet addressed — candidates for phase 8 and later:
- ~~**Tables of contents for monolith-form documents** — no shared point. Screener keeps its own `knowledge/index.sh` and disables the shared lefthook job `knowledge`: with `extends` its `run` can't be overridden.~~ Fixed: in the monolith form the shared `knowledge` job calls the project's `knowledge/index.sh --stage` if it exists, and is triggered by edits to the decision and lesson journals; CI checks the tables of contents with the same script. Screener drops its own job and the disabling of the shared one.
- ~~**Project skill addenda.** `change-finish` and `linear-triage` refer to a "project addendum", but skills have no extension point, unlike agents (`.harness/local/agents/`). Screener keeps the addenda in `CLAUDE.md`.~~ Fixed: a skill addendum is `.harness/local/skills/<skill>.md`, every template skill reads it as its first step. Screener moves its rules there from `CLAUDE.md`.
- ~~**`js-fmt.sh` and a neighboring worktree.**~~ Fixed in phase 8: biome runs from the root of the file's own worktree.
- ~~**`harness-automerge.yml`** checks the commit author by signature, which is easy to forge. Protection rests on the filter "the PR was opened by the token owner"; this is recorded, not fixed.~~ Fixed after phase 8: the head is checked against GitHub's push log (`/activity`: the push that produced the head was made by the token owner), and the commit signature remains a hint.

## Phase 8. Improvements from a project into shared

1. A skill in shared: how a project session opens a PR to shared — where the clone is, the branch, shared's tests, the PR, the local fix until release.
2. Check it once on a real improvement from screener.

**Done:** one improvement went full circle: PR from a screener session → merge by the owner → tag → PR to screener → automerge.

### Outcome (29.10.2026)

- v0.4.0 — the `harness-upstream` skill.
- v0.4.1 — the first improvement from screener via the skill: `js-fmt.sh` formats a file of a neighboring worktree with its `biome.json`.
- v0.4.2 — the first run of `harness-update` in screener failed: its self-hosted runner has no `gh`. The update workflows install `gh` and `uv` themselves if they're missing. Screener was moved to v0.4.2 manually with the same command (screener#551): the old workflow couldn't update itself.
- v0.4.3–v0.4.5 — a background security review of v0.4.1: the hook ran `biome` from the edited file's worktree, and `js-typecheck` and `rust-clippy` had already been running `tsc` and `cargo` in a foreign directory. Now biome is project-only, and `lib/same-repo.sh` lets checks run only in the project's registered worktrees: by physical path, without nested `.git`, not in an ignored one. Git isn't consulted in the checked directory — its answer is set by the directory itself (`core.worktree`, a fake `.git`).
- The circle is closed: `harness-update` opened screener#552 (v0.3.3 → v0.4.5 on top of the manual v0.4.2), `harness-automerge` merged it after green CI.

Remarks:
- On screener's runner four `exchanges` adapter tests (timers: watchdog, subscriptions) failed once and passed on rerun — flaky under load.
- ~~The template repository root has no `biome.json`: the session hook formats `template/` files with biome defaults (tabs). Edit them with a `lint` check of the layouts.~~ Fixed after v1.0.1: the root `biome.json` extends the template's `.harness/biome.json`, template CI runs `biome check .`.

## What is needed from the owner along the way

- Phase 0: consent to create a public repository (already given in conversation).
- Phase 1: review of the inventory.
- Phase 6: creating the secret; permission to delete the sandbox.
- Later: MCP setup in Pi for Linear; a runner for the first new project.
