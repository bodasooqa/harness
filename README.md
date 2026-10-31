# harness

Общая обвязка проектов: стек, процесс и агентская обвязка для Claude Code и Pi в одном шаблоне [Copier](https://copier.readthedocs.io/). Проект создаётся из шаблона, а улучшения шаблона приходят во все проекты PR'ом.

Выросла из обвязки проекта screener за два месяца работы. Дизайн — [`docs/design.md`](docs/design.md), план — [`docs/plan.md`](docs/plan.md).

## Состояние

План пройден целиком. `copier copy` создаёт проект любой из пяти раскладок с зелёными сборкой, typecheck, lint и тестами, с агентами, скиллами, хуками (диспетчер и точки расширения в `.harness/local/`), правилами процесса `.harness/process.md`, lefthook, CI и скриптами `knowledge/`; в Pi те же правила, скиллы, агенты и хуки приходят через `.pi/` (раздел «Claude Code и Pi»). CI шаблона гоняет все раскладки и ставит теги; новые версии приходят в проекты PR'ом (фаза 6, раздел «Обновления»). Screener переведён на шаблон и получает выпуски автоматически; улучшение из проекта несёт в шаблон скилл `harness-upstream`.

| Фаза | Что | Состояние |
|---|---|---|
| 0 | Репозиторий, дизайн, план | готово |
| 1 | Инвентаризация обвязки screener | готово |
| 2 | Каркас шаблона, пять раскладок | готово |
| 3 | Обвязка для Claude Code | готово |
| 4 | Обвязка для Pi | готово |
| 5 | CI и релизы | готово |
| 6 | Доставка обновлений в проекты | готово |
| 7 | Перевод screener | готово |
| 8 | Улучшения из проекта в shared | готово |

## Что будет внутри

- **Стек на выбор:** Rust (Cargo-воркспейс или один крейт), React SPA на Vite с пакетом `uikit` по соглашению shadcn, монорепо на bun и turbo или одно приложение; biome, lefthook, CI.
- **Процесс:** ТЗ с журналом ревизий, OpenSpec, этапы с приёмкой, `knowledge/` с решениями, уроками и открытыми вопросами со сроками.
- **Агенты и скиллы:** исполнители и ревьюеры по областям, `spec-auditor`, `change-finish`, скиллы этапов и знаний; модули Linear, Orca и Telegram по желанию.
- **Хуки:** форматирование и проверки на правку, охрана общего каталога, доклад о рабочем дереве — одной логикой для Claude Code и Pi.

## Как будет работать

```sh
uv tool install copier
copier copy gh:bodasooqa/harness my-project
```

Вопросы шаблона (`copier.yml`):

| Вопрос | Что | По умолчанию |
|---|---|---|
| `project_name` | Имя в kebab-case; из него имена пакетов `<имя>-<крейт>` и `@<имя>/<пакет>` | — |
| `rust` | Rust в проекте | да |
| `frontend` | Фронт: React SPA на Vite, bun, biome | да |
| `monorepo` | Монорепо или один крейт / одно приложение в корне. При Rust и фронте не спрашивается: всегда монорепо | да |
| `linear` | Модуль Linear | нет |
| `tracker_prefix` | Префикс задач Linear (`DEN`); только при `linear` | — |
| `orca` | Модуль Orca: рабочее дерево на сессию | да |
| `telegram` | Скилл `telegram-bot`; только при `rust` | нет |
| `pi_models` | Модели агентов в Pi: словарь `opus`/`sonnet`/`haiku` → модель Pi `провайдер/модель` | Opus, Sonnet и Haiku 5.5 через OpenRouter (`openrouter/anthropic/claude-…-5.5`) |
| `doc_form` | Форма документов: `catalog` — ТЗ каталогом, ревизии, решения и уроки по файлу; `monolith` — одним файлом, для существующих проектов | `catalog` |
| `spec_path`, `revisions_path`, `decisions_path`, `lessons_path`, `open_questions_path` | Пути к ТЗ, журналу ревизий, решениям, урокам, открытым вопросам | при `catalog`: `docs/spec`, `docs/spec/revisions`, `knowledge/decisions`, `knowledge/lessons`, `knowledge/open-questions.md`; при `monolith` — вводятся |

Раскладки:

| Rust | Фронт | Монорепо | Что в корне |
|---|---|---|---|
| да | да | да | Cargo-воркспейс `crates/app`, `apps/web`, `packages/uikit`; bun и turbo |
| да | нет | да | Cargo-воркспейс `crates/app` |
| да | нет | нет | один крейт, `src/main.rs` |
| нет | да | да | `apps/web`, `packages/uikit`; bun и turbo |
| нет | да | нет | одно приложение, `src/` с компонентами в `src/components/ui` |

Проверка всех раскладок — `scripts/check-layouts.sh` (`--only <имя>` для одной).

## Claude Code и Pi

Одна обвязка на оба агента: правила, скиллы, промпты агентов и логика хуков общие, у каждого агента своя тонкая проводка.

| Что | Claude Code | Pi |
|---|---|---|
| Правила проекта и процесса | `CLAUDE.md` с импортом `@.harness/process.md` | Pi берёт `CLAUDE.md` сам, но импорт не раскрывает; `.harness/process.md` добавляет в контекст расширение `.pi/extensions/harness.ts` |
| Скиллы | `.claude/skills/` | те же: путь `../.claude/skills` в `.pi/settings.json`, без копий |
| Агенты | `.claude/agents/` | `.pi/agents/` для `pi-subagents`; тело промпта общее, модели — из ответа `pi_models` |
| Хуки | `.claude/settings.json` → `.harness/hooks/dispatch.sh` | `.pi/extensions/harness.ts` → тот же диспетчер с тем же входом |
| Команды OpenSpec | `/opsx:propose` и др. | `/opsx-propose` и др. (`openspec init --tools claude,pi`) |

Чтобы обвязка заработала в Pi:

- поставить расширение субагентов: `pi install npm:@gotgenes/pi-subagents`;
- запускать `pi` из корня проекта: `.pi/` ищется только в рабочем каталоге;
- выдать проекту доверие: без него Pi не грузит `.pi/settings.json` и `.pi/extensions/` — в интерактивном режиме спросит сам, в `pi -p` нужен `--approve`.

Расхождения:

- **Асинхронная проверка после правки** (`post-edit-async`: clippy, tsc) идёт в фоне и будит модель сообщением, как `asyncRewake` в Claude Code. В `pi -p` Pi выходит после ответа и фоновый прогон не дожидается.
- **`AGENTS.md`.** Pi грузит из каталога один файл, `AGENTS.md` раньше `CLAUDE.md`. Если в корне появится `AGENTS.md`, расширение вернёт в контекст и `CLAUDE.md`.
- **Разрешения** (`permissions` в `.claude/settings.json`) есть только у Claude Code; в Pi охрана — хуки `pre-bash`.

Подробности проводки — `template/.harness/hooks/README.md`, раздел «Прослойка Pi».

## Обновления

Обновления в проект приносит управляемый workflow `harness-update.yml`: раз в сутки он сверяет теги шаблона с версией проекта, делает `copier update` (тег в формате [rootstock](https://github.com/bodasooqa/rootstock) — `rootstock import-copier` и `rootstock update`), конфликты оставляет маркерами в файлах и открывает PR. `harness-automerge.yml` вливает PR после зелёного CI, если нет конфликта, мажорной версии и посторонних коммитов. Проекту нужен секрет `HARNESS_UPDATE_TOKEN`; подключение — `template/.harness/local/README.md`, раздел «Обновления харнесса».

## Релизы

Тег ставится сам после зелёного CI влитого PR, по его метке: `release:minor` — minor, `release:patch` или без метки — patch, `release:none` — без тега; `release:major` автотега не получает — мажор ставится вручную с заметкой о миграции в [`CHANGELOG.md`](CHANGELOG.md).
