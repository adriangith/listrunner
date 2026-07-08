import assert from "node:assert/strict";
import { test } from "node:test";

const { formatItemDisplayName, formatQuantity } = await import(
  "../src/item-display.ts"
);

test("formatQuantity renders count-only quantities without multiplication symbol", () => {
  const item = {
    original: "3 apples",
    quantity: { amount: 3, unit: null },
    searchTerm: "apples",
    filtered: false,
  };

  assert.equal(formatQuantity(item), "3");
});

test("formatItemDisplayName includes quantity for overlay display", () => {
  const item = {
    original: "2 kg rice",
    quantity: { amount: 2, unit: "kg" },
    searchTerm: "rice",
    filtered: false,
  };

  assert.equal(formatItemDisplayName(item), "2 kg rice");
});

test("formatItemDisplayName combines quantity with edited search term", () => {
  const item = {
    original: "2 kg rice",
    quantity: { amount: 2, unit: "kg" },
    searchTerm: "rice",
    filtered: false,
  };

  assert.equal(formatItemDisplayName(item, "basmati rice"), "2 kg basmati rice");
});

test("formatItemDisplayName omits quantity placeholder when none exists", () => {
  const item = {
    original: "bread",
    quantity: null,
    searchTerm: "bread",
    filtered: false,
  };

  assert.equal(formatItemDisplayName(item), "bread");
});
