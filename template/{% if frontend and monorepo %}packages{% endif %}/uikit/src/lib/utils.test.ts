import { describe, expect, test } from "bun:test";
import { cn } from "./utils";

describe("cn", () => {
  test("конфликтующие классы Tailwind — побеждает последний", () => {
    expect(cn("px-2 py-1", "px-4")).toBe("py-1 px-4");
  });

  test("ложные значения пропускаются, условные классы включаются", () => {
    expect(cn("a", false, null, undefined, { b: true, c: false })).toBe("a b");
  });
});
