import { describe, it, expect } from "vitest";
import { parseList } from "../src/parse.js";

describe("parseList", () => {
  it("parses a simple newline-separated list", () => {
    const result = parseList("eggs\nmilk\nbread");
    expect(result.items).toHaveLength(3);
    expect(result.items[0]?.searchTerm).toBe("eggs");
    expect(result.items[1]?.searchTerm).toBe("milk");
    expect(result.items[2]?.searchTerm).toBe("bread");
  });

  it("extracts quantities and cleans names", () => {
    const result = parseList("2 kg rice\n500g flour\n3 eggs");
    expect(result.items[0]?.quantity).toEqual({ amount: 2, unit: "kg" });
    expect(result.items[0]?.searchTerm).toBe("rice");
    expect(result.items[1]?.quantity).toEqual({ amount: 500, unit: "g" });
    expect(result.items[1]?.searchTerm).toBe("flour");
    expect(result.items[2]?.quantity).toEqual({ amount: 3, unit: null });
    expect(result.items[2]?.searchTerm).toBe("eggs");
  });

  it("filters pantry items", () => {
    const result = parseList("eggs\nsalt\npepper\nmilk", {
      pantryExclusions: ["salt", "pepper"],
    });
    expect(result.items).toHaveLength(2);
    expect(result.items.map((i) => i.searchTerm)).toEqual(["eggs", "milk"]);
    expect(result.filtered).toHaveLength(2);
    expect(result.filtered.map((i) => i.searchTerm)).toEqual([
      "salt",
      "pepper",
    ]);
  });

  it("handles a realistic recipe list", () => {
    const input = `200g fresh mozzarella, sliced
1 can (400g) diced tomatoes
2x chicken breast
fresh basil
salt to taste
1.5 kg potatoes, peeled`;

    const result = parseList(input, { pantryExclusions: ["salt"] });

    expect(result.items).toHaveLength(5);
    expect(result.filtered).toHaveLength(1);

    expect(result.items[0]?.searchTerm).toBe("fresh mozzarella");
    expect(result.items[0]?.quantity).toEqual({ amount: 200, unit: "g" });

    expect(result.items[1]?.searchTerm).toBe("diced tomatoes");
    expect(result.items[1]?.quantity).toEqual({ amount: 1, unit: "can" });

    expect(result.items[2]?.searchTerm).toBe("chicken breast");
    expect(result.items[2]?.quantity).toEqual({ amount: 2, unit: null });

    expect(result.items[3]?.searchTerm).toBe("fresh basil");

    expect(result.items[4]?.searchTerm).toBe("potatoes");
    expect(result.items[4]?.quantity).toEqual({ amount: 1.5, unit: "kg" });
  });

  it("handles empty input", () => {
    const result = parseList("");
    expect(result.items).toHaveLength(0);
    expect(result.filtered).toHaveLength(0);
  });
});
