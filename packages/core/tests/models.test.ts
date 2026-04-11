import { describe, it, expect } from "vitest";
import { PantryList } from "../src/pantry.js";
import { SelectionHistory } from "../src/selection-history.js";

describe("PantryList", () => {
  it("adds and checks items", () => {
    const pantry = new PantryList();
    pantry.add("Salt");
    pantry.add("Pepper");
    expect(pantry.has("salt")).toBe(true);
    expect(pantry.has("SALT")).toBe(true);
    expect(pantry.has("sugar")).toBe(false);
  });

  it("removes items", () => {
    const pantry = new PantryList();
    pantry.add("Salt");
    expect(pantry.remove("salt")).toBe(true);
    expect(pantry.has("salt")).toBe(false);
    expect(pantry.remove("salt")).toBe(false);
  });

  it("returns names for exclusion list", () => {
    const pantry = new PantryList();
    pantry.add("Salt");
    pantry.add("Pepper");
    expect(pantry.getNames()).toEqual(["Salt", "Pepper"]);
  });

  it("merges with last-write-wins", () => {
    const pantry = new PantryList([{ name: "Salt", addedAt: 100 }]);
    pantry.merge([
      { name: "Salt", addedAt: 200 },
      { name: "Sugar", addedAt: 150 },
    ]);
    const items = pantry.getAll();
    expect(items).toHaveLength(2);
    expect(items.find((i) => i.name === "Salt")?.addedAt).toBe(200);
  });

  it("does not downgrade on merge", () => {
    const pantry = new PantryList([{ name: "Salt", addedAt: 300 }]);
    pantry.merge([{ name: "Salt", addedAt: 100 }]);
    expect(pantry.getAll().find((i) => i.name === "Salt")?.addedAt).toBe(300);
  });
});

describe("SelectionHistory", () => {
  it("records selections", () => {
    const history = new SelectionHistory();
    history.add({
      store: "woolworths",
      searchTerm: "eggs",
      productName: "Woolworths Free Range Eggs 12pk",
      productImageUrl: "https://example.com/eggs.jpg",
    });
    expect(history.getAll()).toHaveLength(1);
    expect(history.getAll()[0]?.productName).toBe(
      "Woolworths Free Range Eggs 12pk",
    );
  });

  it("looks up by store and search term", () => {
    const history = new SelectionHistory();
    history.add({
      store: "woolworths",
      searchTerm: "eggs",
      productName: "Product A",
      productImageUrl: null,
    });
    history.add({
      store: "coles",
      searchTerm: "eggs",
      productName: "Product B",
      productImageUrl: null,
    });
    history.add({
      store: "woolworths",
      searchTerm: "milk",
      productName: "Product C",
      productImageUrl: null,
    });

    const results = history.lookup("woolworths", "eggs");
    expect(results).toHaveLength(1);
    expect(results[0]?.productName).toBe("Product A");
  });

  it("filters by store", () => {
    const history = new SelectionHistory();
    history.add({
      store: "woolworths",
      searchTerm: "eggs",
      productName: "A",
      productImageUrl: null,
    });
    history.add({
      store: "coles",
      searchTerm: "eggs",
      productName: "B",
      productImageUrl: null,
    });
    expect(history.getAll("woolworths")).toHaveLength(1);
  });
});
