import { describe, expect, test } from "bun:test";
import { pageTitle, projectName } from "./project";

describe("pageTitle", () => {
  test("без раздела — одно имя проекта", () => {
    expect(pageTitle()).toBe(projectName);
  });

  test("с разделом — раздел впереди", () => {
    expect(pageTitle("Настройки")).toBe(`Настройки · ${projectName}`);
  });
});
