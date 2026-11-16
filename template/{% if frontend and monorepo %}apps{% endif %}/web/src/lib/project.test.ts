import { describe, expect, test } from "bun:test";
import { pageTitle, projectName } from "./project";

describe("pageTitle", () => {
  test("without a section: just the project name", () => {
    expect(pageTitle()).toBe(projectName);
  });

  test("with a section: the section comes first", () => {
    expect(pageTitle("Settings")).toBe(`Settings · ${projectName}`);
  });
});
