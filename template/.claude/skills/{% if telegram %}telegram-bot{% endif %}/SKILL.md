---
name: telegram-bot
description: Use when writing or changing a Telegram bot in Rust — the Bot API client on plain reqwest, sending limits and the send queue with 429 handling, markup and escaping, long polling with getUpdates or a webhook, bot commands and /help, error classes, keeping the token out of logs, and testing all of it with paused time, fakes and a stub server.
---

# Telegram-бот на Rust

Приёмы, которые уже стоили ошибок. Каждый — правило и причина. Числа (таймауты, паузы, пределы очереди) живут в секции `[telegram]` конфига, а не в коде. Факты о Bot API сверены с https://core.telegram.org/bots/api и https://core.telegram.org/bots/faq; что не сверено, помечено **(не проверено)**.

## Клиент: свой, на `reqwest`

**Правило.** Тонкий клиент на `reqwest` и `serde`: структура `{ http, api_base: Url, timeout }` и один приватный `call`, через который идут все методы. `api_base` — ключ конфига, а не константа.

**Причина.** Боту обычно хватает четырёх методов: `sendMessage`, `getUpdates`, `editMessageText`, `answerCallbackQuery`. Это пара сотен строк, а `reqwest` в проекте уже есть. Свой клиент даёт полный контроль над текстом ошибки, а токен лежит в URL (см. «Токен»). Ключ `api_base` позволяет тестам направить клиент на заглушку. Готовые крейты подробно не сравнивались. Если понадобится большой кусок API (платежи, медиа, inline-режим), взвесь крейт, но сначала проверь, что его ошибки не печатают URL запроса.

Клиент собирается через `reqwest::Client::builder().build()?`: `Client::new()` паникует, если не поднялся TLS-бэкенд. Таймаут ставится на каждый запрос, потому что у долгого опроса он свой.

```rust
async fn call<B: Serialize>(&self, token: &BotToken, method: &str, body: &B, timeout: Duration)
    -> Result<String, SendError>
{
    let base = self.api_base.as_str().trim_end_matches('/');
    let url = format!("{base}/bot{}/{method}", token.expose());
    let response = self.http.post(&url).timeout(timeout).json(body).send().await
        .map_err(|e| SendError::Unavailable(describe_reqwest_error(e)))?;
    let status = response.status();
    let text = response.text().await
        .map_err(|e| SendError::Unavailable(describe_reqwest_error(e)))?;
    if status.is_success() {
        return Ok(text);
    }
    // {"ok": false, "description": ..., "parameters": {"retry_after": ...}}
    let api: ApiError = serde_json::from_str(&text).unwrap_or_default();
    let description = api.description.unwrap_or_else(|| format!("HTTP {status}"));
    if status == StatusCode::TOO_MANY_REQUESTS {
        let after = api.parameters.and_then(|p| p.retry_after).map(Duration::from_secs);
        return Err(SendError::RetryAfter { after, description });
    }
    if status.is_server_error() {
        return Err(SendError::Unavailable(description));
    }
    Err(SendError::Rejected(description))
}
```

## Токен

**Правило.** Токен приходит только из конфига или окружения, без значения по умолчанию. Он завёрнут в тип-обёртку: `Debug` печатает `BotToken(***)`, `Display` нет, строку отдаёт только `expose()`, и зовёт его только клиент.

**Правило.** Токен лежит в пути URL (`/bot<token>/<method>`), поэтому любая `reqwest::Error` превращается в строку только через `without_url()`. Тип ошибки клиента не реализует `From<reqwest::Error>`: так `?` не протащит сырую ошибку в обход правила. `without_url()` не трогает цепочку `source()`, и её стоит приклеить, иначе причина будет голым «error sending request».

```rust
fn describe_reqwest_error(error: reqwest::Error) -> String {
    let error = error.without_url();
    let mut parts = vec![error.to_string()];
    let mut cause = std::error::Error::source(&error);
    while let Some(source) = cause {
        parts.push(source.to_string());
        cause = source.source();
    }
    parts.join(": ")
}
```

**Проверка.** Тесты ставят токен-метку (`123456:secret-marker`) и проверяют, что её нет ни в `Display` и `Debug` ошибки, ни в теле HTTP-ответа приложения, ни в перехваченном журнале. Сетевую ошибку даёт закрытый порт, отказ — заглушка.

## Ошибки

| Что пришло | Вариант | Повтор |
|---|---|---|
| Сеть, таймаут, 5xx | `Unavailable(reason)` | да, с растущей паузой |
| 429 | `RetryAfter { after, description }` | всегда, не раньше `after` |
| Прочие 4xx | `Rejected(description)` | нет: ответ не изменится |

- Ветвление идёт по HTTP-статусу. Поле `error_code` документация называет «subject to change», а `description` — текст для человека, не для разбора.
- `retry_after` — секунды до разрешённого повтора (`ResponseParameters`). Его нет — повтор по обычной паузе, а не немедленно.
- Пользователь, заблокировавший бота, даёт 4xx, то есть `Rejected`. Ожидаемый ответ — 403 с описанием «Forbidden: bot was blocked by the user» **(не проверено)**. Повторять бессмысленно. Промежуток до следующей отправки ставится и после неудачи: иначе мёртвый чат получал бы запрос на каждое событие. Блокировку можно узнать и заранее: в личном чате обновление `my_chat_member` приходит только при блокировке или разблокировке бота пользователем (сверено).
- Отказ Telegram не роняет процесс. Отправка живёт в своей задаче, ошибка уходит в журнал на `warn`, следующая итерация идёт дальше.

## Лимиты и очередь

Лимиты из FAQ: в одном чате — не чаще сообщения в секунду, короткие всплески допустимы. В группе — не больше 20 сообщений в минуту. Рассылка — около 30 сообщений в секунду. Дальше Telegram отвечает 429. Текст `sendMessage` — от 1 до 4096 символов после разбора разметки.

**Правило.** Одна задача-диспетчер держит состояние по получателю: `pending`, `next_allowed: Option<Instant>`, `in_flight`. Партию она отправляет в отдельной задаче `tokio::spawn`, а итог возвращается вторым каналом. **Причина:** пауза или 429 у одного получателя не задерживает остальных.

**Правило.** Промежуток считается от конца отправки, включая её повторы. **Причина:** отправка, затянутая повторами дольше промежутка, иначе дала бы два сообщения подряд.

**Правило.** Всё, что пришло за промежуток, уходит одним сообщением. Длинная склейка режется на части по границе записи, не посреди неё. Очередь ограничена: сверх предела выбрасывается самое старое, выброшенное считается и первой строкой следующего сообщения выходит «Пропущено: N». **Причина:** склейка держит поток сообщений малым при любом всплеске, а молча пропавшая запись читается как «ничего не было».

**Правило повтора.** Пауза растёт ×2 от начальной до предела, через `saturating_mul`. На 429 пауза равна `max(пауза, retry_after)`. Названный срок соблюдается и сверх предела роста, но обрезается своим пределом `retry_after_max`: огромный срок не должен ни переполнить сложение `Instant` (`checked_add`), ни отложить доставку навсегда.

```rust
pub async fn send_with_retries<C: MessageSender>(client: &C, policy: &RetryPolicy,
    token: &BotToken, chat_id: &str, text: &str) -> Result<(), SendError>
{
    let mut pause = policy.backoff_initial;
    let mut last = SendError::Unavailable("нет ни одной попытки".to_owned());
    for attempt in 0..policy.attempts {
        match client.send(token, chat_id, text).await {
            Ok(()) => return Ok(()),
            Err(SendError::Rejected(reason)) => return Err(SendError::Rejected(reason)),
            Err(SendError::RetryAfter { after, description }) => {
                let after = after.map(|a| a.min(policy.retry_after_max));
                if let Some(after) = after {
                    pause = pause.max(after);
                }
                last = SendError::RetryAfter { after, description };
            }
            Err(e @ SendError::Unavailable(_)) => last = e,
        }
        if attempt + 1 == policy.attempts {
            break;
        }
        tokio::time::sleep(pause).await;
        pause = pause.saturating_mul(2).min(policy.backoff_max);
    }
    Err(last)
}
```

### Будильник без холостого цикла

**Правило.** Ветка `sleep_until` в `select!` диспетчера ждёт ближайший срок только тех записей, у которых пробуждение что-то сделает: есть что отправить или запись можно убрать. Нет таких — `std::future::pending()`.

**Причина.** Однажды запись, которую уже нельзя было убрать (держала счёт пропущенного), осталась в выборке будильника со сроком в прошлом. `sleep_until(прошлое)` срабатывал сразу, делать было нечего, и цикл занимал ядро на 100 %. Тест на паузированных часах цикл просто прокручивал и оставался зелёным. Инвариант «в выборке только те, кого есть зачем будить» проверяется счётчиком пробуждений под `#[cfg(test)]`: после нескольких `advance` без событий он не растёт. Правку условия уборки ревьюят вместе с будильником.

```rust
fn earliest_wake(users: &HashMap<UserId, UserState>) -> Option<Instant> {
    users.values()
        // Есть что отправить — или запись без дела, которую уборка уберёт в срок.
        // Запись, которую уборка не уберёт, сюда не попадает: её срок в прошлом
        // будил бы цикл на каждом обороте.
        .filter(|s| !s.in_flight && (!s.pending.is_empty() || s.removable_when_due()))
        .filter_map(|s| s.next_allowed)
        .min()
}

async fn wait_until(at: Option<Instant>) {
    match at {
        Some(at) => tokio::time::sleep_until(at).await,
        None => std::future::pending::<()>().await,
    }
}
```

## Разметка и экранирование

**Правило.** По умолчанию `parse_mode` не передаётся: текст уходит как есть, экранировать нечего, а имя с `_` или `*` не ломает запрос. Разметка нужна — выбирай `HTML`.

- **HTML:** все `&`, `<` и `>` вне тегов заменяются на `&amp;`, `&lt;` и `&gt;` (сверено). Сначала экранируются вставляемые строки, потом вокруг них ставятся теги.
- **MarkdownV2:** вне `pre` и `code` обратной косой чертой экранируются ``_ * [ ] ( ) ~ ` > # + - = | { } . !``, а сама `\` — всегда. Внутри `pre` и `code` экранируются только `` ` `` и `\`, внутри `(...)` ссылки — `)` и `\` (сверено). Набор велик и легко забыть знак, поэтому HTML надёжнее.
- Предел 4096 считается после разбора разметки. Длина в байтах (`str::len`) не меньше длины в символах: резать по ней — с запасом.

```rust
fn escape_html(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for ch in text.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            _ => out.push(ch),
        }
    }
    out
}
```

## Обновления: долгий опрос или webhook

**Правило.** По умолчанию — долгий опрос `getUpdates`. Webhook требует публичного HTTPS-адреса и проверки секрета: заголовок `X-Telegram-Bot-Api-Secret-Token` должен совпасть с `secret_token` из `setWebhook`. Пока webhook установлен, `getUpdates` не работает (сверено). Процесс, который и так ходит в Telegram исходящими запросами, обходится опросом.

- **offset.** Обновление подтверждено, когда `getUpdates` вызван с `offset` больше его `update_id`. После обработки ставится `offset = update_id + 1`. Неподтверждённые обновления Telegram хранит до 24 часов (сверено).
- **offset в памяти.** После перезапуска первый опрос идёт без offset, и последний обработанный пакет приходит повторно. Обработчики поэтому идемпотентны. Сменился токен — offset сбрасывается: у другого бота свой счёт.
- **Таймаут запроса** — `timeout` опроса плюс обычный таймаут запроса, через `saturating_add`. Иначе долгий опрос обрывается собственным таймаутом.
- **`allowed_updates`** перечисляется явно, только нужные виды.
- **Разбор по одному обновлению.** Неразборчивое обновление сводится к одному `update_id`, и offset уходит за него. Иначе опрос навсегда застревает на одном обновлении.
- **Один опрашивающий на токен.** Второй процесс с тем же ботом получает отказ; ожидаемый код — 409 Conflict **(код не проверен по документации)**. Он пишет `warn` и ждёт.
- **Чат проверяется.** Если бот служит конкретному чату, обновления из других чатов пропускаются без ответа, только offset сдвигается. `chat.id` — `i64`.
- **Нажатие кнопки.** Сначала `answerCallbackQuery`, даже без текста: до этого клиент показывает у кнопки индикатор ожидания (сверено). `callback_data` — от 1 до 64 байт (сверено). `message` у нажатия необязателен: без него чат не проверить.

```rust
let mut offset: Option<i64> = None;
let mut pause: Option<Duration> = None;
loop {
    match client.get_updates(&token, offset, cfg.poll_timeout_sec).await {
        Ok(updates) => {
            pause = None;
            for update in updates {
                offset = Some(update.update_id + 1);
                handle(update).await;
            }
        }
        Err(SendError::RetryAfter { after: Some(after), description }) => {
            tracing::warn!(%description, "Telegram просит подождать");
            tokio::time::sleep(after.min(cfg.retry_after_max())).await;
        }
        Err(e) => {
            tracing::warn!(error = %e, "опрос Telegram не удался");
            let current = pause.unwrap_or(cfg.backoff_initial());
            tokio::time::sleep(current).await;
            pause = Some(current.saturating_mul(2).min(cfg.backoff_max()));
        }
    }
}
```

## Команды и `/help`

**Правило разбора.** Команда — первое слово текста. Суффикс `@<имя_бота>`, который Telegram дописывает в группах и по нажатию подсказки, отрезается. `/start` (его шлёт клиент при первом открытии бота) отвечает тем же, что `/help`. Неверные аргументы получают подсказку формата. Текст, который не команда, остаётся без ответа. Разбор — чистая функция с таблицей тестов: `/help@bot`, пробелы по краям, `/helpme` как не-команда.

```rust
pub fn parse(text: &str) -> Option<Command> {
    let mut words = text.split_whitespace();
    let first = words.next()?;
    let name = first.split_once('@').map_or(first, |(name, _)| name);
    let args: Vec<&str> = words.collect();
    match name {
        "/help" | "/start" => Some(Command::Help),
        "/status" => Some(Command::Status),
        "/set" => Some(match args.as_slice() {
            [key, value] => Command::Set { key: (*key).to_owned(), value: (*value).to_owned() },
            _ => Command::SetFormat,
        }),
        _ => None,
    }
}
```

**Правило справки.** Текст `/help` — константа рядом с разбором, и тест сверяет её построчно. Новая команда без строки в справке ломает тест, а не доходит до пользователя молча.

**`setMyCommands`.** Меню команд видит любой, кто откроет бота. Бот отвечает только своему чату — меню не заводится либо ставится с областью `BotCommandScopeChat` на этот чат. Ограничения (сверено): имя команды — от 1 до 32 символов, только строчные латинские буквы, цифры и `_`. Описание — от 1 до 256 символов, команд не больше 100.

## Тестирование

**Узкие трейты.** Диспетчер и цикл опроса получают зависимости через трейты в объём того, что им нужно: отправитель `MessageSender` и источник настроек `DeliverySource`. Настоящие реализации делегируют клиенту и хранилищу, тестовые живут в памяти.

```rust
pub trait MessageSender: Send + Sync {
    fn send(&self, token: &BotToken, chat_id: &str, text: &str)
        -> impl std::future::Future<Output = Result<(), SendError>> + Send;
}
```

**Паузированные часы — только с подделками в памяти.** Под `tokio::time::pause()` простаивающий рантайм сам двигает часы до ближайшего таймера. Если тест ждёт настоящую базу или HTTP-заглушку фиксированным числом `yield_now`, на медленной машине часы убегают к таймауту пула или запроса. Локально такой тест зеленел десятки раз подряд, а на CI зависал. Признак беды: `pause()` в одном тесте с настоящим пулом, `reqwest` или «подождать N уступок планировщику».

**Настоящая сеть — отдельным файлом.** Сценарии, которым нужна сеть или база, лежат в своём файле тестов в реальном времени, с малыми таймаутами и числом попыток. Заглушка Bot API — маленький HTTP-сервер на маршруте `/bot{token}/sendMessage`, и клиент смотрит на неё через `api_base`. Сетевую ошибку даёт закрытый порт.

**Граница таймера.** На паузированных часах `advance(d)` не будит таймер, срок которого ровно через `d`. Хелпер продвигает часы на `d + 1 мс`. Гипотеза о механизме: драйвер времени tokio округляет срок вверх до миллисекунды, а паузированные часы стартуют с дробной частью **(документацией tokio не проверено)**. Тест, который «висит» на паузированных часах, сначала проверяют на эту границу, и только потом подозревают код.

```rust
async fn advance(d: Duration) {
    tokio::time::advance(d + Duration::from_millis(1)).await;
    for _ in 0..50 {
        tokio::task::yield_now().await;
    }
}
```

**Перехват журнала.** Подписчик `set_default` ставится на поток, но кэш интереса места вызова у `tracing-core` один на процесс. Пока в процессе зарегистрирован ровно один диспетчер (`has_just_one`), интерес нового места вызова считается по подписчику того потока, который задел его первым. Параллельный тест без подписчика кэширует `Interest::never`, и перехват теряет строки. `rebuild_interest_cache()` не лечит: место вызова, впервые задетое после него, снова считается по одному потоку. Поэтому перехват ставится только через общий хелпер. Он держит второй, вечный диспетчер `NoSubscriber`, и реестр опрашивает всех живых подписчиков. Хелпер нужен и в интеграционных тестах, и в юнит-тестах крейта: их бинарь тоже общий. Не закрыт один случай: сосед задевает место вызова одновременно с первым перехватом в процессе. Такой тест держат в файле одного.

```rust
pub fn capture_logs<S>(subscriber: S) -> tracing::subscriber::DefaultGuard
where
    S: tracing::Subscriber + Send + Sync + 'static,
{
    static SECOND: std::sync::OnceLock<tracing::Dispatch> = std::sync::OnceLock::new();
    SECOND.get_or_init(|| tracing::Dispatch::new(tracing::subscriber::NoSubscriber::default()));
    tracing::subscriber::set_default(subscriber)
}
```

## Что обязано быть покрыто

- Разбор ответа: успех, 429 с `retry_after` и без, 5xx, 4xx, тело не JSON.
- Повторы: `Rejected` — одна попытка; 429 ждёт не меньше срока; пауза не растёт выше предела.
- Очередь: склейка за промежуток, резка по 4096 на границе записи, вытеснение старого и «Пропущено: N», независимость получателей, будильник не крутится вхолостую.
- Опрос: offset после пакета, неразборчивое обновление не стопорит offset, смена токена сбрасывает offset, чужой чат без ответа.
- Команды: таблица разбора и построчная сверка `/help`.
- Токен: нет в ошибках, ответах и журнале.
