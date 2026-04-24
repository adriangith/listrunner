import { describe, it, expect } from "vitest";
import { normalizeImportedText, splitCSVLine } from "../src/import-file.js";

describe("splitCSVLine", () => {
  it("splits a plain comma-separated line", () => {
    expect(splitCSVLine("eggs,2,dozen")).toEqual(["eggs", "2", "dozen"]);
  });

  it("preserves quoted cells with commas", () => {
    expect(splitCSVLine('"item, with comma",2')).toEqual([
      "item, with comma",
      "2",
    ]);
  });

  it("handles escaped quotes inside quoted cells", () => {
    // CSV doubles quotes to escape: "pastry ""A"" grade" → pastry "A" grade
    expect(splitCSVLine('"pastry ""A"" grade",1')).toEqual([
      'pastry "A" grade',
      "1",
    ]);
  });

  it("returns empty cells for consecutive commas", () => {
    expect(splitCSVLine("a,,b")).toEqual(["a", "", "b"]);
  });
});

describe("normalizeImportedText", () => {
  it("returns .txt content unchanged", () => {
    const raw = "eggs\nmilk\nbread";
    expect(normalizeImportedText(raw, "list.txt")).toBe(raw);
  });

  it("extracts first non-empty cell per CSV row", () => {
    const raw = "item,qty,notes\neggs,12,free range\nmilk,2L,\nbread,1,";
    expect(normalizeImportedText(raw, "list.csv")).toBe(
      "item\neggs\nmilk\nbread",
    );
  });

  it("skips fully empty CSV rows", () => {
    const raw = "eggs,1\n\n\nmilk,2";
    expect(normalizeImportedText(raw, "list.csv")).toBe("eggs\nmilk");
  });

  it("handles CRLF line endings", () => {
    const raw = "eggs,1\r\nmilk,2\r\n";
    expect(normalizeImportedText(raw, "list.csv")).toBe("eggs\nmilk");
  });

  it("skips empty-first-cell rows by falling back to first non-empty", () => {
    const raw = ",eggs,1\n,,milk,2";
    expect(normalizeImportedText(raw, "list.csv")).toBe("eggs\nmilk");
  });
});
