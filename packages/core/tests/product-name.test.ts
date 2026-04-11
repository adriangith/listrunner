import { describe, it, expect } from "vitest";
import { cleanProductName } from "../src/product-name.js";

describe("cleanProductName", () => {
  it("strips trailing prep instructions after comma", () => {
    expect(
      cleanProductName({
        original: "200g fresh mozzarella, sliced",
        quantity: { amount: 200, unit: "g" },
        remaining: "fresh mozzarella, sliced",
      }),
    ).toBe("fresh mozzarella");
  });

  it("strips parenthetical asides", () => {
    expect(
      cleanProductName({
        original: "cream cheese (softened)",
        quantity: null,
        remaining: "cream cheese (softened)",
      }),
    ).toBe("cream cheese");
  });

  it("strips 'to taste'", () => {
    expect(
      cleanProductName({
        original: "salt to taste",
        quantity: null,
        remaining: "salt to taste",
      }),
    ).toBe("salt");
  });

  it("strips 'finely chopped'", () => {
    expect(
      cleanProductName({
        original: "onion, finely chopped",
        quantity: null,
        remaining: "onion, finely chopped",
      }),
    ).toBe("onion");
  });

  it("preserves important descriptors", () => {
    expect(
      cleanProductName({
        original: "fresh basil",
        quantity: null,
        remaining: "fresh basil",
      }),
    ).toBe("fresh basil");
  });

  it("strips weight parenthetical", () => {
    expect(
      cleanProductName({
        original: "canned tomatoes (400g)",
        quantity: null,
        remaining: "canned tomatoes (400g)",
      }),
    ).toBe("canned tomatoes");
  });

  it("handles multiple parentheticals", () => {
    expect(
      cleanProductName({
        original: "yoghurt (plain) (500g)",
        quantity: null,
        remaining: "yoghurt (plain) (500g)",
      }),
    ).toBe("yoghurt");
  });
});
