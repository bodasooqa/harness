# Инвентаризация обвязки screener

Фаза 1 плана. Снято с `bodasooqa/screener` на коммите `main` от 28.10.2026 (после #548). Каждый файл обвязки получает вид:

- **общее** — управляемый файл шаблона, есть в каждом проекте;
- **модуль `<имя>`** — управляемый, есть при ответе «да» на вопрос шаблона (`rust`, `frontend`, `linear`, `orca`, `telegram`);
- **стартовое** — создаётся один раз, дальше принадлежит проекту;
- **screener** — остаётся проектным расширением screener, в шаблон не идёт.

«Параметры» — что в файле зашито под screener и становится ответом шаблона или настройкой: `{{name}}` — имя проекта, `{{spec}}` — пути документов, `{{tracker}}` — префикс задач.

## Агенты `.claude/agents/`

| Файл | Вид | Параметры и что уходит в дополнение screener |
|---|---|---|
| `rust-developer.md` | модуль `rust` | Пути к скиллам — в общий вид. В дополнение screener: цены `i64` в тиках, `Decimal`, `now_ms`, FSM, синхронизация стаканов, `sqlx prepare` |
| `rust-reviewer.md` | модуль `rust` | Общее: паники, `unsafe`, блокирующее в async, магические числа, `println!`, дифф ветки. В дополнение: `f64` в ценах, FSM, спаны `exchange`/`market`/`symbol` |
| `frontend-developer.md` | модуль `frontend` | `@screener/*` → `@{{name}}/*`; граница `uikit` и экранов — общее. В дополнение: домен плотностей, IPC |
| `frontend-reviewer.md` | модуль `frontend` | То же: токены темы, shadcn, типы только из контракта — общее; домен — в дополнение |
| `spec-auditor.md` | общее | Пути ТЗ и журнала — `{{spec}}`. В дополнение: инварианты ядра §4.3–§4.5, §6, §11 |
| `video-developer.md` | screener | Remotion, эпизоды из библиотеки прода |

## Скиллы `.claude/skills/`

| Скилл | Вид | Параметры |
|---|---|---|
| `change-finish` | общее | Команды проверок — по модулям `rust`/`frontend`; `DEN-N` и Linear — в модуль `linear`; пути `{{spec}}` |
| `knowledge-note` | общее | Пути `knowledge/` и форма документов (старая у screener, новая по файлу на запись) |
| `stage-acceptance` | общее | `{{spec}}` §12 → «раздел этапов ТЗ» по пути из настроек |
| `stage-grooming` | общее | То же; `due.sh` |
| `contract-change` | общее (обобщённый) | Процедура «сначала ТЗ → регенерация → потребители» общая; список контрактов берётся из таблицы источников правды `CLAUDE.md` проекта. Четыре контракта screener (proto, `MarketEvent`, миграции, `default.toml`) — в его `CLAUDE.md` |
| `uikit-component` | модуль `frontend` | `@screener/uikit` → `@{{name}}/uikit`; в раскладке без монорепо — `src/components/ui` |
| `linear-triage` | модуль `linear` | Команда, префикс `{{tracker}}`, роли «владелец/трейдер» → «владелец/заказчик» по настройке; словарь трейдера — screener |
| `core-fsm-test` | screener | FSM плотностей |
| `new-exchange-adapter` | screener | Адаптеры бирж |
| `reel` | screener | Ролики kelv |
| `telegram-bot` | модуль `telegram` (новый) | Пишется по `crates/daemon/src/alerting/telegram.rs` и `owner_bot/` |
| `openspec-*`, `.claude/commands/opsx/` | generated | Ставит `openspec init --tools claude,pi`, в шаблон не кладутся |

## Хуки `.claude/hooks/` и `settings.json`

| Файл | Событие | Вид | Параметры |
|---|---|---|---|
| `guard-staging.sh` | PreToolUse/Bash | общее | — |
| `bash-edit.sh` | PostToolUse/Bash | общее | Текст подсказки — по модулям (rustfmt/clippy — `rust`, biome/tsc — `frontend`) |
| `session-tree.sh` | SessionStart | общее | `knowledge/due.sh` → путь из настроек. Orca не вызывает, работает по `git worktree` |
| `session-leftovers.sh` | SessionEnd | общее | — |
| `knowledge-due.sh` | UserPromptSubmit | общее | Путь `due.sh` |
| `lib/bash-scan.sh`, `lib/staleness.sh` | библиотека | общее | — |
| `rust-fmt.sh` | PostToolUse/Write\|Edit | модуль `rust` | — |
| `rust-clippy.sh` | то же, асинхронный | модуль `rust` | `screener-$crate` → `{{name}}-$crate`; переменная `SCREENER_CLIPPY_STATE` → общее имя; раскладка без воркспейса (один крейт) |
| `js-fmt.sh` | PostToolUse/Write\|Edit | модуль `frontend` | — |
| `js-typecheck.sh` | то же, асинхронный | модуль `frontend` | Раскладка без монорепо |
| `contract-touch.sh` | PostToolUse/Write\|Edit | screener | Пути proto, миграций, `default.toml`, generated. Общей версии нет: проектный хук |
| `guard-data.sh` | PreToolUse/Bash | screener | Библиотека сайзов, записи реплея |
| `tests/run.sh` (1456 строк) | тесты | общее + screener | Разделить: случаи общих хуков — в shared (на синтетическом репозитории, без путей screener); случаи `contract-touch`, `guard-data`, protocol-generated — проектные тесты screener |
| `settings.json` | проводка | общее | Хуки → диспетчер. `permissions.allow`: общие (`git`, `rg`, `jq`, `openspec`, `lefthook`), `rust` (`cargo …`, `rustfmt`), `frontend` (`bun`, `bunx`, `turbo`, `biome`); `cargo run -p screener-daemon`, `sqlx` — screener. `permissions.deny`: `.env*`, generated OpenSpec — общее; `config/local.toml`, `fixtures/replay`, `data`, `.sqlx`, `packages/protocol/src/generated` — screener. `worktree.symlinkDirectories: node_modules` — модуль `frontend`. Плагин `rust-analyzer-lsp` — модуль `rust` |

## Git-хуки и CI

| Файл | Вид | Параметры и что уходит в screener |
|---|---|---|
| `lefthook.yml` | общее + стартовое | Управляемый общий: `secrets`, `knowledge-index`, `claude-hooks`, `knowledge-due-tests`, `knowledge-due`; `rustfmt` — `rust`; `biome` — `frontend`. Стартовый `lefthook.yml` проекта с `extends`. `protocol-generated` — screener |
| `.lefthook/no-secrets.sh` | общее | — |
| `.lefthook/push-files.sh` | общее | — |
| `.lefthook/check-protocol-generated.sh` | screener | — |
| `.github/workflows/ci.yml` | общее + стартовое | Джобы `changes` (фильтры путей), `rust`, `js`, `harness` — управляемый workflow с параметрами раннера (`runs-on`), фильтры путей по модулям. `spec-defaults`, Postgres-сервис и `sqlx` в `rust` — screener. Метки раннеров (`mac`, `netcup-ci`) — настройка проекта |
| `.github/workflows/release.yml`, `deploy.yml` | screener | Образ и выкатка демона |

## Документы и знание

| Файл | Вид | Параметры |
|---|---|---|
| `knowledge/index.sh` | общее (старая форма) | Оглавления монолитных документов. У новой формы — свой скрипт индекса каталога. Если общий не потянет обе формы — у screener остаётся проектным |
| `knowledge/due.sh`, `knowledge/tests/due.sh` | общее | Срок «этап N §12» — путь раздела этапов из настроек; примеры тестов без плотностей |
| `knowledge/README.md` | стартовое | Правило «куда класть»; список файлов — проектный |
| `knowledge/bot-*.sql/py/sh`, `research-*` | screener | Исследования |
| `openspec/config.yaml` | общее + стартовое | Правила артефактов, язык, kebab-case — общее; контекст проекта (домен, крейты, ТЗ-пути) — стартовая часть. Если OpenSpec не умеет склеивать два файла — файл стартовый, общий текст правил шаблон пишет в него один раз |
| `docs/DENSITY_SCREENER_SPEC*.md` | screener | Новая форма ТЗ — стартовый каталог |
| `.mcp.json` | модуль `linear` | Сервер Linear |

## `CLAUDE.md`

Корневой `CLAUDE.md` screener по разделам:

| Раздел | Вид |
|---|---|
| Вступление, «ТЗ большое…» | стартовое (с путями `{{spec}}`) |
| Стек | модули `rust`/`frontend`: общая часть (edition 2024, `[workspace.dependencies]`, bun, biome); `rust_decimal`, `sqlx`, `figment`, «никаких `f64`» — screener |
| Границы пакетов, четыре инварианта | screener (карта пакетов проекта); правило «у каждого пакета свой `CLAUDE.md`» — общее |
| Источники правды | стартовое: таблица проекта; строка «изменение — процедура `contract-change`» — общее |
| Три места документации | общее |
| Рабочий процесс, OpenSpec, superpowers | общее |
| Обвязка вне OpenSpec | общее |
| Своё дерево на сессию | общее + модуль `orca` (абзац Orca) |
| Never edit generated | общее (список generated — проектный: `.sqlx`, `Cargo.lock`, …) |
| Правь Write/Edit | общее |
| Команды | модули `rust`/`frontend`; `docker compose`, `record`/`replay`, `screenerd` — screener |
| Порядок работы по этапам | общее |
| Коммиты | общее; префиксы пакетов — проектные; `DEN-N` — модуль `linear` |
| Правила кода | общие (английские идентификаторы, конфиг вместо магических чисел, UTC `i64` мс, `tracing`/без `println!`, без `unwrap` вне тестов) — модуль `rust`; адаптеры, FSM, якорь, ММ-флаги — screener |
| Тесты | screener (по пакетам) |
| Чего не делать | общее: ORM, `unsafe`, длинные пояснения; биржи, Postgres-решение — screener |
| Обвязка репозитория (скиллы, исполнители, хуки, lefthook, OpenSpec, Linear) | общее, собирается по модулям |
| Разделение головы и рук | общее |
| Определения | screener |

`CLAUDE.md` пакетов:

| Файл | Вид |
|---|---|
| `packages/uikit/CLAUDE.md` | модуль `frontend`, стартовое (границы, shadcn, цвет токенами, проверки) |
| `apps/web/CLAUDE.md` | модуль `frontend`, стартовое — общий каркас «Границы / Проверки»; «Главное правило», «Отображение», «Доставка» — screener |
| `crates/*/CLAUDE.md`, `packages/protocol/CLAUDE.md`, `apps/landing/CLAUDE.md`, `apps/video/CLAUDE.md` | screener |

## Стек (стартовые файлы)

| Файл | Вид | Параметры |
|---|---|---|
| `Cargo.toml` (корень) | стартовое, `rust` | `[workspace]` с пустым `members`, `[workspace.dependencies]` с общими (`tokio`, `serde`, `tracing`, `thiserror`, `anyhow`); доменные (`sqlx`, `rust_decimal`, `tokio-tungstenite`, `figment`) — нет |
| `rust-toolchain.toml`, `rustfmt.toml` | общее, `rust` | — |
| `package.json` (корень) | стартовое, `frontend` | `name`, скрипты `typecheck`/`build`/`test`/`lint`/`dev` через turbo |
| `turbo.json`, `tsconfig.base.json` | общее, `frontend` | — |
| `biome.json` | общее + стартовое | Управляемый общий конфиг; стартовый `biome.json` с `extends`; исключения `.sqlx`, fixtures — screener |
| `packages/uikit/` | стартовое, `frontend` | Только каркас пакета, без примитивов (решение владельца 28.10.2026): `package.json` (`@{{name}}/uikit`, экспорты как у screener), `tsconfig`, `components.json` для shadcn, `CLAUDE.md`, `src/styles/globals.css` с токенами нейтральной темы shadcn (zinc), `src/lib/utils.ts` (`cn`), пустые `components/` и `hooks/`. Компоненты в каждом проекте свои; screener'овские не копируются |
| `apps/web/` | стартовое, `frontend` | Пустое Vite + React SPA на `uikit` |
| `docker-compose.yml` | screener | Postgres |

## Итого

| Вид | Сколько |
|---|---|
| общее | 6 скиллов (с обобщённым `contract-change`), `spec-auditor`, 7 хуков и `lib/`, тесты хуков (общая часть), скрипты `knowledge/`, lefthook-скрипты, конфиги lefthook/biome/CI (общая часть) |
| модуль `rust` | 2 агента, 2 хука, toolchain, rustfmt, разрешения cargo |
| модуль `frontend` | 2 агента, `uikit-component`, 2 хука, turbo, tsconfig, разрешения bun |
| модуль `linear` | `linear-triage`, `.mcp.json`, `DEN-N` в `change-finish` и коммитах |
| модуль `orca` | абзац «Своё дерево на сессию» про Orca; скиллы Orca ставит сама Orca |
| модуль `telegram` | новый `telegram-bot` |
| screener | 4 скилла, `video-developer`, 2 хука, protocol-generated, release/deploy, доменные абзацы агентов и `CLAUDE.md`, `spec-defaults`, исследования |

## Спорное — на решение владельца

Ничего: классификация следует дизайну. Решения, которые принял я:

- `contract-change` — общий, а не screener: процедура не зависит от домена, зависит только список контрактов.
- `session-tree` — общее, а не модуль `orca`: хук работает через `git worktree` и Orca не вызывает.
- ~~Иней, замки тарифов и бренд kelv из `uikit` не идут, остальные примитивы копируются~~ — заменено решением владельца: стартовый `uikit` — пустой каркас с токенами zinc и `cn`, без примитивов.
