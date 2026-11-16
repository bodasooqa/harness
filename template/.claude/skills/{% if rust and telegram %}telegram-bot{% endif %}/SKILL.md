---
name: telegram-bot
description: Use when writing or changing a Telegram bot in Rust — the Bot API client on plain reqwest, sending limits and the send queue with 429 handling, markup and escaping, long polling with getUpdates or a webhook, bot commands and /help, error classes, keeping the token out of logs, and testing all of it with paused time, fakes and a stub server.
---

# Telegram bot in Rust

First check `.harness/local/skills/telegram-bot.md`: if the file exists, read it before starting work. It is the project addendum — the project's bots, their config and constraints; where it disagrees with the text below, the addendum wins.

Techniques that have already cost mistakes. Each one is a rule and a reason. Numbers (timeouts, pauses, queue limits) live in the `[telegram]` section of the config, not in code. Facts about the Bot API are checked against https://core.telegram.org/bots/api and https://core.telegram.org/bots/faq; whatever isn't checked is marked **(unverified)**.

## Client: our own, on `reqwest`

**Rule.** A thin client on `reqwest` and `serde`: a `{ http, api_base: Url, timeout }` struct and a single private `call` that all methods go through. `api_base` is a config key, not a constant.

**Reason.** A bot usually needs four methods: `sendMessage`, `getUpdates`, `editMessageText`, `answerCallbackQuery`. That's a couple hundred lines, and `reqwest` is already in the project. Our own client gives full control over the error text, and the token sits in the URL (see "Token"). The `api_base` key lets tests point the client at a stub. Ready-made crates haven't been compared in detail. If a big chunk of the API is needed (payments, media, inline mode), weigh a crate, but first check that its errors don't print the request URL.

The client is built via `reqwest::Client::builder().build()?`: `Client::new()` panics if the TLS backend fails to start. The timeout is set per request, because long polling has its own.

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

## Token

**Rule.** The token comes only from the config or the environment, with no default value. It is wrapped in a newtype: `Debug` prints `BotToken(***)`, there is no `Display`, only `expose()` returns the string, and only the client calls it.

**Rule.** The token sits in the URL path (`/bot<token>/<method>`), so any `reqwest::Error` is turned into a string only via `without_url()`. The client's error type doesn't implement `From<reqwest::Error>`: that way `?` can't sneak a raw error past the rule. `without_url()` doesn't touch the `source()` chain, and it's worth appending it, otherwise the cause is a bare "error sending request".

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

**Check.** Tests set a marker token (`123456:secret-marker`) and check that it appears neither in the error's `Display` and `Debug`, nor in the body of the application's HTTP response, nor in the captured log. A closed port produces a network error, a stub produces a rejection.

## Errors

| What came back | Variant | Retry |
|---|---|---|
| Network, timeout, 5xx | `Unavailable(reason)` | yes, with a growing pause |
| 429 | `RetryAfter { after, description }` | always, no sooner than `after` |
| Other 4xx | `Rejected(description)` | no: the answer won't change |

- Branching is on the HTTP status. The documentation calls the `error_code` field "subject to change", and `description` is text for humans, not for parsing.
- `retry_after` is the number of seconds until a retry is allowed (`ResponseParameters`). If it's absent — retry after the usual pause, not immediately.
- A user who blocked the bot produces a 4xx, i.e. `Rejected`. The expected answer is 403 with the description "Forbidden: bot was blocked by the user" **(unverified)**. Retrying is pointless. The interval before the next send is set after a failure too: otherwise a dead chat would get a request on every event. Blocking can also be learned in advance: in a private chat the `my_chat_member` update arrives only when the user blocks or unblocks the bot (verified).
- A Telegram rejection doesn't crash the process. Sending lives in its own task, the error goes to the log at `warn`, the next iteration carries on.

## Limits and the queue

Limits from the FAQ: in one chat — no more than a message per second, short bursts are allowed. In a group — no more than 20 messages per minute. Broadcasting — about 30 messages per second. Beyond that Telegram answers 429. The `sendMessage` text is 1 to 4096 characters after markup parsing.

**Rule.** A single dispatcher task keeps per-recipient state: `pending`, `next_allowed: Option<Instant>`, `in_flight`. It sends a batch in a separate `tokio::spawn` task, and the result comes back on a second channel. **Reason:** a pause or a 429 for one recipient doesn't delay the others.

**Rule.** The interval is counted from the end of a send, including its retries. **Reason:** otherwise a send dragged out by retries longer than the interval would produce two messages in a row.

**Rule.** Everything that arrived during the interval goes out as one message. A long merged message is split into parts at a record boundary, not in the middle of one. The queue is bounded: beyond the limit the oldest is dropped, dropped items are counted, and the first line of the next message is "Skipped: N". **Reason:** merging keeps the message stream small under any burst, and a silently lost record reads as "nothing happened".

**Retry rule.** The pause grows ×2 from the initial value up to the limit, via `saturating_mul`. On 429 the pause is `max(pause, retry_after)`. The stated delay is respected even beyond the growth limit, but capped by its own limit `retry_after_max`: a huge delay must neither overflow `Instant` addition (`checked_add`) nor postpone delivery forever.

```rust
pub async fn send_with_retries<C: MessageSender>(client: &C, policy: &RetryPolicy,
    token: &BotToken, chat_id: &str, text: &str) -> Result<(), SendError>
{
    let mut pause = policy.backoff_initial;
    let mut last = SendError::Unavailable("no attempts made".to_owned());
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

### An alarm without a busy loop

**Rule.** The `sleep_until` branch in the dispatcher's `select!` waits for the nearest deadline only of those entries for which waking up will do something: there is something to send, or the entry can be removed. None like that — `std::future::pending()`.

**Reason.** Once, an entry that could no longer be removed (it held the skipped count) stayed in the alarm's selection with a deadline in the past. `sleep_until(past)` fired immediately, there was nothing to do, and the loop took a core at 100%. The test on paused time just spun the loop and stayed green. The invariant "only those worth waking are in the selection" is checked by a wake-up counter under `#[cfg(test)]`: after several `advance` calls without events it doesn't grow. A change to the cleanup condition is reviewed together with the alarm.

```rust
fn earliest_wake(users: &HashMap<UserId, UserState>) -> Option<Instant> {
    users.values()
        // There is something to send — or an idle entry that cleanup will remove on time.
        // An entry that cleanup won't remove doesn't get here: its deadline in the past
        // would wake the loop on every turn.
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

## Markup and escaping

**Rule.** By default `parse_mode` is not passed: the text goes as is, there is nothing to escape, and a name with `_` or `*` doesn't break the request. If markup is needed — choose `HTML`.

- **HTML:** every `&`, `<`, and `>` outside tags is replaced with `&amp;`, `&lt;`, and `&gt;` (verified). Inserted strings are escaped first, then the tags are placed around them.
- **MarkdownV2:** outside `pre` and `code`, ``_ * [ ] ( ) ~ ` > # + - = | { } . !`` are escaped with a backslash, and `\` itself always is. Inside `pre` and `code` only `` ` `` and `\` are escaped, inside the `(...)` of a link — `)` and `\` (verified). The set is large and a character is easy to forget, so HTML is more reliable.
- The 4096 limit is counted after markup parsing. The length in bytes (`str::len`) is no less than the length in characters: splitting by it leaves a margin.

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

## Updates: long polling or a webhook

**Rule.** By default — `getUpdates` long polling. A webhook requires a public HTTPS address and a secret check: the `X-Telegram-Bot-Api-Secret-Token` header must match the `secret_token` from `setWebhook`. While a webhook is set, `getUpdates` doesn't work (verified). A process that already talks to Telegram with outgoing requests gets by with polling.

- **offset.** An update is confirmed when `getUpdates` is called with an `offset` greater than its `update_id`. After processing, `offset = update_id + 1` is set. Telegram keeps unconfirmed updates for up to 24 hours (verified).
- **offset in memory.** After a restart the first poll goes without an offset, and the last processed batch arrives again. So handlers are idempotent. The token changed — the offset is reset: another bot has its own counter.
- **Request timeout** — the poll `timeout` plus the usual request timeout, via `saturating_add`. Otherwise long polling is cut off by its own timeout.
- **`allowed_updates`** is listed explicitly, only the needed kinds.
- **Parsing one update at a time.** An unparseable update is reduced to its `update_id`, and the offset moves past it. Otherwise polling gets stuck on one update forever.
- **One poller per token.** A second process with the same bot gets a rejection; the expected code is 409 Conflict **(code not verified against the documentation)**. It writes a `warn` and waits.
- **The chat is checked.** If the bot serves a specific chat, updates from other chats are skipped without a reply, only the offset moves. `chat.id` is `i64`.
- **Button press.** `answerCallbackQuery` first, even without text: until then the client shows a waiting indicator on the button (verified). `callback_data` is 1 to 64 bytes (verified). The press's `message` is optional: without it the chat can't be checked.

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
            tracing::warn!(%description, "Telegram asks to wait");
            tokio::time::sleep(after.min(cfg.retry_after_max())).await;
        }
        Err(e) => {
            tracing::warn!(error = %e, "Telegram poll failed");
            let current = pause.unwrap_or(cfg.backoff_initial());
            tokio::time::sleep(current).await;
            pause = Some(current.saturating_mul(2).min(cfg.backoff_max()));
        }
    }
}
```

## Commands and `/help`

**Parsing rule.** A command is the first word of the text. The `@<bot_name>` suffix, which Telegram appends in groups and when a suggestion is tapped, is cut off. `/start` (the client sends it when the bot is first opened) answers the same as `/help`. Wrong arguments get a format hint. Text that isn't a command gets no reply. Parsing is a pure function with a table of tests: `/help@bot`, surrounding whitespace, `/helpme` as a non-command.

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

**Help rule.** The `/help` text is a constant next to the parser, and a test checks it line by line. A new command without a line in the help breaks the test rather than silently reaching the user.

**`setMyCommands`.** The command menu is visible to anyone who opens the bot. If the bot answers only its own chat, either no menu is set up or it is set with the `BotCommandScopeChat` scope for that chat. Constraints (verified): a command name is 1 to 32 characters, only lowercase Latin letters, digits, and `_`. A description is 1 to 256 characters, no more than 100 commands.

## Testing

**Narrow traits.** The dispatcher and the poll loop get their dependencies through traits scoped to what they need: the sender `MessageSender` and the settings source `DeliverySource`. The real implementations delegate to the client and the storage; the test ones live in memory.

```rust
pub trait MessageSender: Send + Sync {
    fn send(&self, token: &BotToken, chat_id: &str, text: &str)
        -> impl std::future::Future<Output = Result<(), SendError>> + Send;
}
```

**Paused time — only with in-memory fakes.** Under `tokio::time::pause()`, an idle runtime advances the clock to the nearest timer on its own. If a test waits for a real database or an HTTP stub with a fixed number of `yield_now`, on a slow machine the clock runs off to the pool or request timeout. Locally such a test went green dozens of times in a row, and hung on CI. Warning sign: `pause()` in the same test as a real pool, `reqwest`, or "wait N scheduler yields".

**Real network — in a separate file.** Scenarios that need the network or a database live in their own real-time test file, with small timeouts and attempt counts. The Bot API stub is a small HTTP server on the `/bot{token}/sendMessage` route, and the client points at it via `api_base`. A closed port produces a network error.

**Timer boundary.** On paused time, `advance(d)` doesn't wake a timer whose deadline is exactly `d` away. The helper advances the clock by `d + 1 ms`. A hypothesis about the mechanism: the tokio time driver rounds the deadline up to a millisecond, and paused time starts with a fractional part **(not verified against the tokio documentation)**. A test that "hangs" on paused time is first checked for this boundary, and only then is the code suspected.

```rust
async fn advance(d: Duration) {
    tokio::time::advance(d + Duration::from_millis(1)).await;
    for _ in 0..50 {
        tokio::task::yield_now().await;
    }
}
```

**Log capture.** A `set_default` subscriber is set per thread, but `tracing-core`'s callsite interest cache is one per process. While exactly one dispatcher is registered in the process (`has_just_one`), the interest of a new callsite is computed from the subscriber of the thread that hit it first. A parallel test without a subscriber caches `Interest::never`, and the capture loses lines. `rebuild_interest_cache()` doesn't cure it: a callsite first hit after it is again computed from a single thread. So capture is set up only via a shared helper. It holds a second, permanent `NoSubscriber` dispatcher, and the registry then polls all live subscribers. The helper is needed both in integration tests and in the crate's unit tests: their binary is shared too. One case is not covered: a neighbor hits a callsite at the same moment as the first capture in the process. Such a test is kept alone in its file.

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

## What must be covered

- Response parsing: success, 429 with and without `retry_after`, 5xx, 4xx, a non-JSON body.
- Retries: `Rejected` — one attempt; 429 waits no less than the delay; the pause doesn't grow above the limit.
- Queue: merging over the interval, splitting at 4096 on a record boundary, evicting the oldest and "Skipped: N", recipient independence, the alarm doesn't spin idle.
- Polling: offset after a batch, an unparseable update doesn't stall the offset, a token change resets the offset, a foreign chat gets no reply.
- Commands: the parsing table and the line-by-line check of `/help`.
- Token: absent from errors, responses, and the log.
