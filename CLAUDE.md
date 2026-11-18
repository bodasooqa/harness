# CLAUDE.md — harness

This repository is the shared harness of the owner's projects: a [rootstock](https://github.com/bodasooqa/rootstock) template with a stack (Rust, React, bun, turbo, biome, lefthook, CI) and a process (spec → OpenSpec → stages → `knowledge/`), with agents, skills, and hooks for Claude Code and Pi. A project is created from the template, and new template versions reach it as a PR.

Why and how it works — `docs/design.md`. Order of work and phase criteria — `docs/plan.md`. When in doubt about template behavior, read the design instead of recalling.

## Rules

- **Language — English** for everything in the repository: skill texts, prompts, hook messages, comments, documents, commits, PR titles and bodies. Agents talk to the owner in chat in Russian.
- **The repository is public.** No secrets and no domain knowledge of projects (screener and others): domain material lives in the projects' own extensions.
- **Two kinds of template files.** Managed files are updated in every project; starter files are created once and belong to the project from then on. For a new file, first decide which kind it is. An edit to a managed file reaches every project: check it on all layouts.
- **Extension points instead of edits.** If a project needs something of its own, give it a place for its file (project hooks, agent addenda, its own CI file), not a branch in the shared one.
- **Only what is reproducible outside one tool.** No Python Jinja extensions; template hooks are shell. Harness scripts read `.rootstock.toml` themselves, without the rootstock binary.
- **Claude Code, Pi, and Codex.** Check the shared behavior across all three clients. Hook logic lives in shell scripts and the adapters translate events. Agent profiles share one source across formats. Keep shared skills independent of any client's tools.
- **Edit files** with the Write and Edit tools, not the shell.

## Merge and versions

- Work goes through PRs. The main session merges a PR after green CI (owner's permission of 28.10.2026).
- On merge, a patch or minor tag is set. A major version (a path renamed, a template question changed, projects need a migration) — only manually, with a migration note in `CHANGELOG.md`.
- Tasks are tracked in the Linear project the work came from (currently screener, team DEN); `DEN-N` at the start of the PR title.

## Improvement from a project

A project session that finds a harness improvement edits a clone of this repository on its own branch and opens a PR here. Until the release is out, the project may fix its own file itself — the update will see the same edit and pass without a conflict.
