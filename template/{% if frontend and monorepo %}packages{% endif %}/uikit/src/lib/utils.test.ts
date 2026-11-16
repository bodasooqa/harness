import { describe, expect, test } from "bun:test";
import { cn } from "./utils";

describe("cn", () => {
  test("conflicting Tailwind classes: the last one wins", () => {
    expect(cn("px-2 py-1", "px-4")).toBe("py-1 px-4");
  });

  test("falsy values are skipped, conditional classes are included", () => {
    expect(cn("a", false, null, undefined, { b: true, c: false })).toBe("a b");
  });
});
