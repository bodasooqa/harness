/**
 * Тесты прослойки Pi `.pi/extensions/harness.ts`: обработчики событий зовутся с подставным
 * API Pi, а за ними работают настоящие диспетчер и хуки проекта. Проверяется перевод
 * в обе стороны: событие Pi → вход хука в форме Claude Code, ответ хука → решение Pi.
 *
 * Как и `run.sh`, всё гоняется на синтетических репозиториях во временных каталогах.
 * Случаи модульных хуков (rust-fmt, rust-clippy — модуль rust; js-fmt — модуль frontend)
 * идут, только если хук в проекте есть.
 *
 * Запуск: bun test ./.harness/hooks/tests/pi.test.ts
 */
import { afterAll, describe, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import harness from "../../../.pi/extensions/harness.ts";

const unset = (name: string) => {
  delete process.env[name];
};

// Под git-хуком в окружении стоят GIT_DIR и прочие — см. `run.sh`.
for (const name of Object.keys(process.env)) {
  if (name.startsWith("GIT_")) unset(name);
}
unset("CLAUDE_PROJECT_DIR");
// Настоящие clippy и tsc в фоне не нужны: где проверка нужна, подставляется своя.
process.env.HARNESS_CLIPPY = "true";
process.env.HARNESS_TSC = "true";

const root = resolve(import.meta.dir, "..", "..", "..");
const hooks = join(root, ".harness", "hooks");
const has = (hook: string) => existsSync(join(hooks, hook));

const base = mkdtempSync(join(tmpdir(), "harness-pi-test."));
const inProject = join(root, ".tmp-pi-test");

afterAll(() => {
  rmSync(base, { recursive: true, force: true });
  rmSync(inProject, { recursive: true, force: true });
});

// Окружение — явно: Bun (1.3) отдаёт дочернему процессу без `env` окружение,
// с которым стартовал сам, и `delete process.env` выше до git не доходит. Под
// pre-push git с унаследованным GIT_DIR писал коммиты в настоящий репозиторий.
function git(cwd: string, ...args: string[]) {
  execFileSync("git", args, { cwd, stdio: "ignore", env: { ...process.env } });
}

/** Временный git-репозиторий с пустым коммитом на main. */
function newRepo(): string {
  const dir = mkdtempSync(join(base, "repo."));
  git(dir, "init", "-q", "-b", "main");
  git(
    dir,
    "-c",
    "user.name=t",
    "-c",
    "user.email=t@t",
    "commit",
    "-q",
    "--allow-empty",
    "-m",
    "init",
  );
  return dir;
}

type Handler = (event: unknown, ctx: unknown) => unknown;

interface Sent {
  message: { customType: string; content: unknown; display: boolean };
  options: { triggerTurn?: boolean; deliverAs?: string } | undefined;
}

interface ContextFile {
  path: string;
  content: string;
}

type Extension = typeof harness;

/** Подставной Pi: собирает обработчики и отправленные сообщения. */
function fakePi(options: { cwd: string; systemPrompt?: string; extension?: Extension }) {
  const handlers = new Map<string, Handler[]>();
  const sent: Sent[] = [];
  const api = {
    on(name: string, handler: Handler) {
      handlers.set(name, [...(handlers.get(name) ?? []), handler]);
    },
    sendMessage(message: Sent["message"], sendOptions?: Sent["options"]) {
      sent.push({ message, options: sendOptions });
    },
  };
  const ctx = {
    cwd: options.cwd,
    hasUI: false,
    ui: { notify() {} },
    sessionManager: {
      getSessionId: () => "pi-test",
      getSessionFile: () => undefined,
    },
    getSystemPrompt: () => options.systemPrompt ?? "",
  };
  (options.extension ?? harness)(api as unknown as Parameters<Extension>[0]);
  const emit = async (name: string, event: unknown) => {
    let result: unknown;
    for (const handler of handlers.get(name) ?? []) result = await handler(event, ctx);
    return result;
  };
  return { emit, sent };
}

const bash = (command: string) => ({
  type: "tool_call",
  toolName: "bash",
  toolCallId: `call-${command}`,
  input: { command },
});

const edited = (toolName: "edit" | "write", path: string, input: Record<string, unknown>) => ({
  type: "tool_result",
  toolName,
  toolCallId: `call-${path}`,
  input: { path, ...input },
  content: [{ type: "text", text: "ok" }],
  isError: false,
});

const agentStart = (contextFiles: ContextFile[], systemPrompt = "") => ({
  type: "before_agent_start",
  prompt: "привет",
  systemPrompt,
  systemPromptOptions: { cwd: root, contextFiles, skills: [] },
});

async function waitFor(check: () => boolean, ms: number): Promise<boolean> {
  const until = Date.now() + ms;
  while (Date.now() < until) {
    if (check()) return true;
    await Bun.sleep(50);
  }
  return check();
}

describe("pre-bash: tool_call bash", () => {
  test("git add -A в общем каталоге — отказ с причиной", async () => {
    const pi = fakePi({ cwd: newRepo() });
    const result = (await pi.emit("tool_call", bash("git add -A"))) as {
      block: boolean;
      reason: string;
    };
    expect(result.block).toBe(true);
    expect(result.reason).toContain("валовая постановка");
  });

  test("обычная команда проходит", async () => {
    const pi = fakePi({ cwd: newRepo() });
    expect(await pi.emit("tool_call", bash("ls"))).toBeUndefined();
  });

  test("git add -A в своём дереве проходит", async () => {
    const repo = newRepo();
    git(repo, "worktree", "add", "-q", join(repo, "wt"), "-b", "wt");
    const pi = fakePi({ cwd: join(repo, "wt") });
    expect(await pi.emit("tool_call", bash("git add -A"))).toBeUndefined();
  });

  test("не bash — не трогает", async () => {
    const pi = fakePi({ cwd: newRepo() });
    const event = { type: "tool_call", toolName: "read", toolCallId: "r", input: { path: "a" } };
    expect(await pi.emit("tool_call", event)).toBeUndefined();
  });
});

describe("post-edit: tool_result edit/write", () => {
  test.if(has("rust-fmt.sh"))("правка .rs форматируется, путь от cwd", async () => {
    const dir = mkdtempSync(join(base, "fmt."));
    writeFileSync(join(dir, "a.rs"), "fn  main ( )  {\nlet x=1;\n}\n");
    const pi = fakePi({ cwd: dir });
    await pi.emit("tool_result", edited("edit", "a.rs", { edits: [] }));
    expect(readFileSync(join(dir, "a.rs"), "utf8")).toStartWith("fn main() {\n");
  });

  test.if(has("js-fmt.sh"))(
    "запись .tsx форматируется",
    async () => {
      // Внутри проекта: biome берётся из его node_modules, правила — из его biome.json.
      mkdirSync(inProject, { recursive: true });
      const file = join(inProject, "a.tsx");
      const content = "const  x  =   1;\nexport  {x}\n";
      writeFileSync(file, content);
      const pi = fakePi({ cwd: root });
      await pi.emit("tool_result", edited("write", file, { content }));
      expect(readFileSync(file, "utf8")).toStartWith("const x = 1;\n");
    },
    30_000,
  );

  test("правка с ошибкой хуки не зовёт", async () => {
    const dir = mkdtempSync(join(base, "err."));
    const raw = "fn  main ( )  {}\n";
    writeFileSync(join(dir, "a.rs"), raw);
    const pi = fakePi({ cwd: dir });
    await pi.emit("tool_result", { ...edited("edit", "a.rs", { edits: [] }), isError: true });
    expect(readFileSync(join(dir, "a.rs"), "utf8")).toBe(raw);
  });

  test.if(has("rust-clippy.sh"))(
    "post-edit-async: код 2 будит модель сообщением",
    async () => {
      // Крейт — внутри проекта: файл чужого репозитория clippy не проверяет.
      const crate = join(inProject, "crates", "core", "src");
      mkdirSync(crate, { recursive: true });
      writeFileSync(join(crate, "lib.rs"), "fn main() {}\n");
      const fake = join(base, "fake-clippy");
      writeFileSync(fake, "#!/usr/bin/env bash\necho 'error[E0061]: сломано'\nexit 1\n");
      chmodSync(fake, 0o755);
      process.env.HARNESS_CLIPPY = fake;
      process.env.HARNESS_CLIPPY_STATE = mkdtempSync(join(base, "clippy-state."));
      try {
        const pi = fakePi({ cwd: root });
        await pi.emit(
          "tool_result",
          edited("edit", ".tmp-pi-test/crates/core/src/lib.rs", { edits: [] }),
        );
        expect(await waitFor(() => pi.sent.length > 0, 20_000)).toBe(true);
        const [wake] = pi.sent;
        expect(String(wake?.message.content)).toContain("E0061");
        expect(wake?.options).toEqual({ triggerTurn: true, deliverAs: "steer" });
      } finally {
        process.env.HARNESS_CLIPPY = "true";
        unset("HARNESS_CLIPPY_STATE");
      }
    },
    30_000,
  );
});

describe("subagent-stop: agent_before_settle ребёнка-исполнителя", () => {
  const settle = (entries: unknown[] = []) => ({
    type: "agent_before_settle",
    entries,
    continue: false,
    outcome: "completed",
  });
  const tag = (name: string) => `<active_agent name="${name}"/>`;

  /** Изменения в дереве проекта и красные подставные clippy и tsc на время теста. */
  async function withRedChecks(run: () => Promise<void>) {
    // Внутри проекта: хук проверяет только свой репозиторий. Годится всем раскладкам:
    // крейт в crates/, пакет в packages/ — монорепо; корень проекта — один крейт или
    // одно приложение.
    const crate = join(inProject, "crates", "core", "src");
    const pkg = join(inProject, "packages", "web");
    mkdirSync(crate, { recursive: true });
    mkdirSync(join(pkg, "src"), { recursive: true });
    writeFileSync(join(crate, "lib.rs"), "pub fn a() {}\n");
    writeFileSync(join(pkg, "tsconfig.json"), "{}\n");
    writeFileSync(join(pkg, "src", "index.ts"), "export const n = 1;\n");
    const fake = join(base, "fake-red-check");
    writeFileSync(fake, "#!/usr/bin/env bash\necho 'error: сломано'\nexit 1\n");
    chmodSync(fake, 0o755);
    process.env.HARNESS_CLIPPY = fake;
    process.env.HARNESS_TSC = fake;
    try {
      await run();
    } finally {
      process.env.HARNESS_CLIPPY = "true";
      process.env.HARNESS_TSC = "true";
      rmSync(inProject, { recursive: true, force: true });
    }
  }

  type Settled = { entries: Array<{ type: string; content: string }>; continue: boolean };

  test("исполнитель с красными проверками — одно продолжение с выводом", async () => {
    await withRedChecks(async () => {
      const pi = fakePi({ cwd: root, systemPrompt: tag("rust-developer") });
      const prior = { type: "custom", customType: "other" };
      const first = (await pi.emit("agent_before_settle", settle([prior]))) as Settled;
      expect(first.continue).toBe(true);
      expect(first.entries[0]).toEqual(prior);
      const [, note] = first.entries;
      expect(note?.type).toBe("custom_message");
      expect(note?.content).toContain("сломано");
      // Продолжение по отказу — как stop_hook_active у Claude Code: второй раз не держит.
      expect(await pi.emit("agent_before_settle", settle())).toBeUndefined();
      // Новый запуск ребёнка — снова под проверкой.
      await pi.emit("before_agent_start", agentStart([], tag("rust-developer")));
      const again = (await pi.emit("agent_before_settle", settle())) as Settled;
      expect(again.continue).toBe(true);
    });
  }, 30_000);

  test("не исполнитель и главная сессия — без проверки", async () => {
    await withRedChecks(async () => {
      for (const systemPrompt of [tag("rust-reviewer"), ""]) {
        const pi = fakePi({ cwd: root, systemPrompt });
        expect(await pi.emit("agent_before_settle", settle())).toBeUndefined();
      }
    });
  }, 30_000);

  test("прерванный запуск не держится", async () => {
    await withRedChecks(async () => {
      const pi = fakePi({ cwd: root, systemPrompt: tag("frontend-developer") });
      const aborted = { ...settle(), outcome: "aborted" };
      expect(await pi.emit("agent_before_settle", aborted)).toBeUndefined();
    });
  }, 30_000);
});

/**
 * Копия прослойки в синтетическом проекте с заданными файлами: корень прослойка берёт от
 * своего пути, так набор файлов инструкций проверяется, не трогая настоящий проект.
 */
async function isolatedHarness(files: Record<string, string>) {
  // Путь без ссылок (на macOS временный каталог — ссылка в /private): корень прослойки
  // считается от пути модуля, и пути в ожиданиях должны совпасть с ним.
  const dir = realpathSync(mkdtempSync(join(base, "project.")));
  const copy = join(dir, ".pi", "extensions", "harness.ts");
  mkdirSync(dirname(copy), { recursive: true });
  writeFileSync(copy, readFileSync(join(root, ".pi", "extensions", "harness.ts"), "utf8"));
  for (const [path, content] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), content);
  }
  const module = (await import(copy)) as { default: Extension };
  return { dir, extension: module.default };
}

describe("session-start и правила процесса: before_agent_start", () => {
  // Главный файл проекта — AGENTS.md; у проекта, ещё не перешедшего на него, — CLAUDE.md.
  const instructions = existsSync(join(root, "AGENTS.md"))
    ? join(root, "AGENTS.md")
    : join(root, "CLAUDE.md");
  const processRules = join(root, ".harness", "process.md");

  test("контекст session-start приходит сообщением, process.md — после главного файла", async () => {
    const pi = fakePi({ cwd: newRepo() });
    await pi.emit("session_start", { type: "session_start", reason: "startup" });
    const files: ContextFile[] = [{ path: instructions, content: "правила проекта" }];
    const result = (await pi.emit("before_agent_start", agentStart(files))) as {
      message: { content: string };
    };
    expect(result.message.content).toContain("ОБЩЕМ каталоге");
    // Между ними может стоять CLAUDE.md со своими правилами: проект ещё не перешёл на
    // AGENTS.md, а заготовку создало обновление. Набор по видам проекта — тесты ниже.
    const paths = files.map((file) => file.path);
    expect(paths[0]).toBe(instructions);
    expect(paths.at(-1)).toBe(processRules);
    expect(files.at(-1)?.content).toBe(readFileSync(processRules, "utf8"));

    // Второй ход: контекст уже доставлен, ничего не дублируется.
    expect(await pi.emit("before_agent_start", agentStart(files))).toBeUndefined();
    expect(files.map((file) => file.path)).toEqual(paths);
  });

  test("AGENTS.md и CLAUDE.md из импортов — доливается process.md, CLAUDE.md нет", async () => {
    const { dir, extension } = await isolatedHarness({
      "AGENTS.md": "# правила проекта\n",
      "CLAUDE.md": "@AGENTS.md\n@.harness/process.md\n",
      ".harness/process.md": "# правила процесса\n",
    });
    const agents = join(dir, "AGENTS.md");
    const rules = join(dir, ".harness", "process.md");
    const pi = fakePi({ cwd: dir, extension });

    // Pi взял из каталога AGENTS.md, CLAUDE.md рядом с ним не грузит.
    const files: ContextFile[] = [{ path: agents, content: "# правила проекта\n" }];
    await pi.emit("before_agent_start", agentStart(files));
    expect(files.map((file) => file.path)).toEqual([agents, rules]);
    expect(files[1]?.content).toBe("# правила процесса\n");

    // Pi не взял ничего — прослойка доводит AGENTS.md, а не CLAUDE.md.
    const bare: ContextFile[] = [];
    await pi.emit("before_agent_start", agentStart(bare));
    expect(bare.map((file) => file.path)).toEqual([agents, rules]);
    expect(bare[0]?.content).toBe("# правила проекта\n");
  });

  test("AGENTS.md-заготовка и CLAUDE.md со своими правилами — доливаются оба", async () => {
    // Обновление шаблона создаёт стартовый AGENTS.md и в проекте, который ещё держит
    // правила в CLAUDE.md: Pi берёт заготовку, и правила проекта не должны потеряться.
    const { dir, extension } = await isolatedHarness({
      "AGENTS.md": "# заготовка\n",
      "CLAUDE.md": "# правила проекта\n\n@.harness/process.md\n",
      ".harness/process.md": "# правила процесса\n",
    });
    const agents = join(dir, "AGENTS.md");
    const claude = join(dir, "CLAUDE.md");
    const rules = join(dir, ".harness", "process.md");
    const pi = fakePi({ cwd: dir, extension });

    const files: ContextFile[] = [{ path: agents, content: "# заготовка\n" }];
    await pi.emit("before_agent_start", agentStart(files));
    expect(files.map((file) => file.path)).toEqual([agents, claude, rules]);
  });

  test("только CLAUDE.md (проект до AGENTS.md) — он и process.md, как раньше", async () => {
    const { dir, extension } = await isolatedHarness({
      "CLAUDE.md": "# правила проекта\n\n@.harness/process.md\n",
      ".harness/process.md": "# правила процесса\n",
    });
    const claude = join(dir, "CLAUDE.md");
    const rules = join(dir, ".harness", "process.md");
    const pi = fakePi({ cwd: dir, extension });

    const files: ContextFile[] = [{ path: claude, content: "# правила проекта\n" }];
    await pi.emit("before_agent_start", agentStart(files));
    expect(files.map((file) => file.path)).toEqual([claude, rules]);

    const bare: ContextFile[] = [];
    await pi.emit("before_agent_start", agentStart(bare));
    expect(bare.map((file) => file.path)).toEqual([claude, rules]);
  });

  test("субагент pi-subagents: session-start молчит, контекст не забирает", async () => {
    const tag = '<active_agent name="rust-reviewer"/>';
    const pi = fakePi({ cwd: newRepo(), systemPrompt: tag });
    await pi.emit("session_start", { type: "session_start", reason: "startup" });
    const files: ContextFile[] = [{ path: instructions, content: "" }];
    expect(await pi.emit("before_agent_start", agentStart(files, tag))).toBeUndefined();
  });

  test("выход сессии проходит", async () => {
    const pi = fakePi({ cwd: newRepo() });
    await pi.emit("session_shutdown", { type: "session_shutdown", reason: "quit" });
    expect(pi.sent).toEqual([]);
  });
});
