# harness

Общая обвязка проектов: стек, процесс и агентская обвязка для Claude Code и Pi в одном шаблоне [Copier](https://copier.readthedocs.io/). Проект создаётся из шаблона, а улучшения шаблона приходят во все проекты PR'ом.

Выросла из обвязки проекта screener за два месяца работы. Дизайн — [`docs/design.md`](docs/design.md), план — [`docs/plan.md`](docs/plan.md).

## Состояние

Фаза 3 из плана: обвязка для Claude Code. `copier copy` создаёт проект любой из пяти раскладок с зелёными сборкой, typecheck, lint и тестами, с агентами, скиллами, хуками (диспетчер и точки расширения в `.harness/local/`), правилами процесса `.harness/process.md`, lefthook, CI и скриптами `knowledge/`. Обвязки для Pi, своего CI шаблона и доставки обновлений ещё нет.

| Фаза | Что | Состояние |
|---|---|---|
| 0 | Репозиторий, дизайн, план | готово |
| 1 | Инвентаризация обвязки screener | готово |
| 2 | Каркас шаблона, пять раскладок | готово |
| 3 | Обвязка для Claude Code | готово |
| 4 | Обвязка для Pi | — |
| 5 | CI и релизы | — |
| 6 | Доставка обновлений в проекты | — |
| 7 | Перевод screener | — |
| 8 | Улучшения из проекта в shared | — |

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

Обновления в проект приносит workflow: новая версия шаблона → `copier update` → PR → вливается сам, если CI зелёный и конфликтов нет.
