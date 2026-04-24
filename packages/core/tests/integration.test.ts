import { describe, it, expect } from "vitest";
import {
  parseList,
  createWizardState,
  wizardReducer,
  currentItem,
  addedCount,
  totalCount,
  PantryList,
  SelectionHistory,
} from "../src/index.js";

describe("integration: parse → wizard", () => {
  it("runs a realistic shopping list through the wizard end-to-end", () => {
    const raw = `
      500g flour
      1 dozen eggs
      2x chicken breast
      1 can (400g) tomatoes
      fresh basil
      salt to taste
      1/2 cup olive oil
      2-3 onions
    `;

    const parsed = parseList(raw);
    expect(parsed.items).toHaveLength(8);
    expect(parsed.items.map((i) => i.searchTerm)).toEqual([
      "flour",
      "eggs",
      "chicken breast",
      "tomatoes",
      "fresh basil",
      "salt",
      "olive oil",
      "onions",
    ]);

    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: parsed.items });
    expect(state.status).toBe("stepping");
    expect(totalCount(state)).toBe(8);

    // Add 4, skip 2, add 2, revisit 2
    for (let i = 0; i < 4; i++) {
      state = wizardReducer(state, { type: "ADVANCE" });
      state = wizardReducer(state, { type: "COOLDOWN_COMPLETE" });
    }
    state = wizardReducer(state, { type: "SKIP" }); // skip 5th (basil)
    state = wizardReducer(state, { type: "SKIP" }); // skip 6th (salt)
    for (let i = 0; i < 2; i++) {
      state = wizardReducer(state, { type: "ADVANCE" });
      state = wizardReducer(state, { type: "COOLDOWN_COMPLETE" });
    }

    expect(state.status).toBe("done");
    expect(addedCount(state)).toBe(6);
    expect(state.skippedIndices).toEqual([4, 5]);

    // Revisit — add one, dismiss one
    state = wizardReducer(state, { type: "BEGIN_REVISIT" });
    expect(state.status).toBe("revisiting");
    expect(currentItem(state)?.parsedItem.searchTerm).toBe("fresh basil");

    state = wizardReducer(state, { type: "ADVANCE" });
    state = wizardReducer(state, { type: "COOLDOWN_COMPLETE" });
    expect(currentItem(state)?.parsedItem.searchTerm).toBe("salt");

    state = wizardReducer(state, { type: "DISMISS" });
    expect(state.status).toBe("done");

    const dismissed = state.items.filter((i) => i.status === "dismissed").length;
    expect(dismissed).toBe(1);
    expect(addedCount(state)).toBe(7);
  });

  it("pantry filter keeps list lean, restore puts items back", () => {
    const pantry = new PantryList();
    pantry.add("salt");
    pantry.add("pepper");

    const parsed = parseList("eggs\nsalt\nmilk\npepper\nolive oil", {
      pantryExclusions: pantry.getNames(),
    });

    expect(parsed.items.map((i) => i.searchTerm)).toEqual([
      "eggs",
      "milk",
      "olive oil",
    ]);
    expect(parsed.filtered.map((i) => i.searchTerm)).toEqual([
      "salt",
      "pepper",
    ]);
  });

  it("selection history surfaces the most recent pick for a (store, term)", () => {
    const hist = new SelectionHistory();
    hist.add({
      store: "woolworths-au",
      searchTerm: "eggs",
      productName: "Woolworths Free Range 12pk",
      productImageUrl: null,
    });
    hist.add({
      store: "woolworths-au",
      searchTerm: "eggs",
      productName: "Woolworths Cage Free 18pk",
      productImageUrl: null,
    });

    const hits = hist.lookup("woolworths-au", "EGGS");
    expect(hits).toHaveLength(2);
    expect(hits[0]?.productName).toBe("Woolworths Cage Free 18pk");
  });

  it("edit-search override survives skip + revisit", () => {
    const parsed = parseList("chicken\nbeef\nlamb");
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: parsed.items });

    state = wizardReducer(state, {
      type: "EDIT_SEARCH",
      index: 0,
      searchTerm: "free range chicken breast",
    });
    state = wizardReducer(state, { type: "SKIP" });

    // Finish the others
    state = wizardReducer(state, { type: "ADVANCE" });
    state = wizardReducer(state, { type: "COOLDOWN_COMPLETE" });
    state = wizardReducer(state, { type: "ADVANCE" });
    state = wizardReducer(state, { type: "COOLDOWN_COMPLETE" });

    expect(state.status).toBe("done");

    state = wizardReducer(state, { type: "BEGIN_REVISIT" });
    const active = currentItem(state);
    expect(active?.searchTermOverride).toBe("free range chicken breast");
  });
});
