# Расширения обвязки проекта

`.harness/` целиком принадлежит шаблону и обновляется `copier update`, кроме этого каталога: `.harness/local/` создаётся один раз и дальше принадлежит проекту. Обновление шаблона его не трогает.

Правило: проект не правит управляемый файл, а кладёт своё в точку расширения. Тогда обновление почти не конфликтует.

## Точки расширения

| Что | Своё — сюда | Как подключается |
|---|---|---|
| Хуки агента | `.harness/local/hooks/<слот>/<имя>.sh` | диспетчер `.harness/hooks/dispatch.sh` запускает их после общих хуков слота, по алфавиту. Слоты и контракт — `.harness/hooks/README.md` |
| Дополнения агентов | `.harness/local/agents/<имя>.md` | агент читает файл, если он есть |
| Git-хуки | `lefthook.yml` в корне | подключает общий `.harness/lefthook.yml` через `extends`; свои джобы — в нём же |
| CI | `.github/workflows/ci.yml` | зовёт общий `.github/workflows/harness.yml`; свои джобы — рядом |
| biome | `biome.json` в корне | `extends` на `.harness/biome.json` |
| Разрешения Claude Code | `.claude/settings.json` | файл управляемый, но свои строки в `permissions.allow` и `permissions.deny` проект дописывает прямо в него: `copier update` сливает правки трёхсторонним слиянием и их сохраняет |

## Хук проекта

Пример: запрет команды, которая сносит данные проекта.

```bash
#!/usr/bin/env bash
# .harness/local/hooks/pre-bash/guard-data.sh
set -uo pipefail
. "${BASH_SOURCE[0]%/*}/../../../hooks/lib/bash-scan.sh"

scan=$(bash_scan) || exit 0
if printf '%s' "$scan" | grep -Eq 'docker[[:space:]]+volume[[:space:]]+rm'; then
  deny "Том хранит данные, которые не восстанавливаются. Попроси пользователя удалить его самому."
fi
exit 0
```

Файл должен быть исполняемым (`chmod +x`): хук без права на исполнение диспетчер пропускает — так его можно выключить, не удаляя. Тесты своих хуков — тоже здесь, например `.harness/local/hooks/tests/`.
