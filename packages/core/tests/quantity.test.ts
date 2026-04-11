import { describe, it, expect } from "vitest";
import { extractQuantity } from "../src/quantity.js";

describe("extractQuantity", () => {
  it("extracts count + item", () => {
    const result = extractQuantity({ original: "3 eggs" });
    expect(result.quantity).toEqual({ amount: 3, unit: null });
    expect(result.remaining).toBe("eggs");
  });

  it("extracts unit + item", () => {
    const result = extractQuantity({ original: "500g flour" });
    expect(result.quantity).toEqual({ amount: 500, unit: "g" });
    expect(result.remaining).toBe("flour");
  });

  it("extracts multiplier notation", () => {
    const result = extractQuantity({ original: "2x chicken breast" });
    expect(result.quantity).toEqual({ amount: 2, unit: null });
    expect(result.remaining).toBe("chicken breast");
  });

  it("extracts container with weight", () => {
    const result = extractQuantity({ original: "1 can (400g) tomatoes" });
    expect(result.quantity).toEqual({ amount: 1, unit: "can" });
    expect(result.remaining).toBe("tomatoes");
  });

  it("extracts kg units", () => {
    const result = extractQuantity({ original: "2 kg rice" });
    expect(result.quantity).toEqual({ amount: 2, unit: "kg" });
    expect(result.remaining).toBe("rice");
  });

  it("extracts dozen", () => {
    const result = extractQuantity({ original: "1 dozen eggs" });
    expect(result.quantity).toEqual({ amount: 1, unit: "dozen" });
    expect(result.remaining).toBe("eggs");
  });

  it("handles no quantity", () => {
    const result = extractQuantity({ original: "fresh basil" });
    expect(result.quantity).toBeNull();
    expect(result.remaining).toBe("fresh basil");
  });

  it("handles decimal amounts", () => {
    const result = extractQuantity({ original: "1.5 kg chicken" });
    expect(result.quantity).toEqual({ amount: 1.5, unit: "kg" });
    expect(result.remaining).toBe("chicken");
  });
});
