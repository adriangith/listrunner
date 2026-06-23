import { describe, it, expect } from "vitest";
import { splitItems } from "../src/split.js";

describe("splitItems", () => {
  it("splits by newlines", () => {
    const result = splitItems("eggs\nmilk\nbread");
    expect(result).toEqual([
      { original: "eggs" },
      { original: "milk" },
      { original: "bread" },
    ]);
  });

  it("splits by commas on a single line", () => {
    const result = splitItems("eggs, milk, bread");
    expect(result).toEqual([
      { original: "eggs" },
      { original: "milk" },
      { original: "bread" },
    ]);
  });

  it("handles bullet lists", () => {
    const result = splitItems("- eggs\n- milk\n- bread");
    expect(result).toEqual([
      { original: "eggs" },
      { original: "milk" },
      { original: "bread" },
    ]);
  });

  it("handles numbered lists", () => {
    const result = splitItems("1. eggs\n2. milk\n3. bread");
    expect(result).toEqual([
      { original: "eggs" },
      { original: "milk" },
      { original: "bread" },
    ]);
  });

  it("handles checkbox lists", () => {
    const result = splitItems("- [ ] eggs\n- [x] milk\n- [ ] bread");
    expect(result).toEqual([
      { original: "eggs" },
      { original: "milk" },
      { original: "bread" },
    ]);
  });

  it("strips pasted checkbox glyphs without a space", () => {
    const result = splitItems("☒bread\n☐ milk\n☑eggs");
    expect(result).toEqual([
      { original: "bread" },
      { original: "milk" },
      { original: "eggs" },
    ]);
  });

  it("handles bullet characters •", () => {
    const result = splitItems("• eggs\n• milk");
    expect(result).toEqual([{ original: "eggs" }, { original: "milk" }]);
  });

  it("skips empty lines", () => {
    const result = splitItems("eggs\n\nmilk\n\n");
    expect(result).toEqual([{ original: "eggs" }, { original: "milk" }]);
  });

  it("returns empty array for empty input", () => {
    expect(splitItems("")).toEqual([]);
    expect(splitItems("   ")).toEqual([]);
  });

  it("handles \\r\\n line endings", () => {
    const result = splitItems("eggs\r\nmilk\r\nbread");
    expect(result.length).toBe(3);
  });
});
