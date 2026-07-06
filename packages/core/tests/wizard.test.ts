import { describe, it, expect } from "vitest";
import {
  createWizardState,
  wizardReducer,
  currentItem,
  addedCount,
  totalCount,
} from "../src/wizard.js";
import type { ParsedItem } from "../src/types.js";

const testItems: ParsedItem[] = [
  { original: "eggs", quantity: { amount: 3, unit: null }, searchTerm: "eggs", filtered: false },
  { original: "milk", quantity: null, searchTerm: "milk", filtered: false },
  { original: "bread", quantity: null, searchTerm: "bread", filtered: false },
];

describe("wizard state machine", () => {
  it("starts in idle state", () => {
    const state = createWizardState();
    expect(state.status).toBe("idle");
    expect(currentItem(state)).toBeNull();
  });

  it("transitions to stepping on START", () => {
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: testItems });
    expect(state.status).toBe("stepping");
    expect(state.currentIndex).toBe(0);
    expect(currentItem(state)?.parsedItem.searchTerm).toBe("eggs");
    expect(totalCount(state)).toBe(3);
  });

  it("goes to done on START with empty items", () => {
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: [] });
    expect(state.status).toBe("done");
  });

  it("advances through items via cooldown", () => {
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: testItems });

    // Advance first item → cooldown
    state = wizardReducer(state, { type: "ADVANCE" });
    expect(state.status).toBe("cooldown");
    expect(addedCount(state)).toBe(1);

    // Cooldown complete → next item
    state = wizardReducer(state, { type: "COOLDOWN_COMPLETE" });
    expect(state.status).toBe("stepping");
    expect(currentItem(state)?.parsedItem.searchTerm).toBe("milk");
  });

  it("supports skip and revisit", () => {
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: testItems });

    // Skip first item
    state = wizardReducer(state, { type: "SKIP" });
    expect(state.skippedIndices).toEqual([0]);
    expect(currentItem(state)?.parsedItem.searchTerm).toBe("milk");

    // Add second item
    state = wizardReducer(state, { type: "ADVANCE" });
    state = wizardReducer(state, { type: "COOLDOWN_COMPLETE" });

    // Add third item
    state = wizardReducer(state, { type: "ADVANCE" });
    state = wizardReducer(state, { type: "COOLDOWN_COMPLETE" });

    // Should be stepping since there are skipped items
    expect(state.skippedIndices).toHaveLength(1);

    // Begin revisit
    state = wizardReducer(state, { type: "BEGIN_REVISIT" });
    expect(state.status).toBe("revisiting");
    expect(currentItem(state)?.parsedItem.searchTerm).toBe("eggs");
  });

  it("supports undo during cooldown", () => {
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: testItems });
    state = wizardReducer(state, { type: "ADVANCE" });
    expect(state.status).toBe("cooldown");

    state = wizardReducer(state, { type: "UNDO" });
    expect(state.status).toBe("stepping");
    expect(currentItem(state)?.parsedItem.searchTerm).toBe("eggs");
    expect(currentItem(state)?.status).toBe("active");
  });

  it("supports add another during cooldown", () => {
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: testItems });
    state = wizardReducer(state, { type: "ADVANCE" });

    state = wizardReducer(state, { type: "ADD_ANOTHER" });
    expect(state.status).toBe("stepping");
    expect(currentItem(state)?.parsedItem.searchTerm).toBe("eggs");
  });

  it("supports dismiss during revisit", () => {
    let state = createWizardState();
    state = wizardReducer(state, {
      type: "START",
      items: testItems.slice(0, 2),
    });

    // Skip both items
    state = wizardReducer(state, { type: "SKIP" });
    state = wizardReducer(state, { type: "SKIP" });

    state = wizardReducer(state, { type: "BEGIN_REVISIT" });
    state = wizardReducer(state, { type: "DISMISS" });

    expect(state.status).toBe("revisiting");
    // Second skipped item is now active
    expect(currentItem(state)?.parsedItem.searchTerm).toBe("milk");

    state = wizardReducer(state, { type: "DISMISS" });
    expect(state.status).toBe("done");
  });

  it("supports edit search term", () => {
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: testItems });
    state = wizardReducer(state, {
      type: "EDIT_SEARCH",
      index: 0,
      searchTerm: "free range eggs",
    });
    expect(state.items[0]?.searchTermOverride).toBe("free range eggs");
  });

  it("resets to idle", () => {
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: testItems });
    state = wizardReducer(state, { type: "RESET" });
    expect(state.status).toBe("idle");
  });

  it("moves to the previous primary item while stepping", () => {
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: testItems });
    state = wizardReducer(state, { type: "SKIP" });

    expect(currentItem(state)?.parsedItem.searchTerm).toBe("milk");

    state = wizardReducer(state, { type: "PREVIOUS" });

    expect(state.status).toBe("stepping");
    expect(state.currentIndex).toBe(0);
    expect(currentItem(state)?.parsedItem.searchTerm).toBe("eggs");
    expect(currentItem(state)?.status).toBe("active");
    expect(state.items[1]?.status).toBe("pending");
  });

  it("throws when moving previous from the first item", () => {
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: testItems });

    expect(() => wizardReducer(state, { type: "PREVIOUS" })).toThrow(
      "Cannot PREVIOUS from first item",
    );
  });

  it("throws on invalid transitions", () => {
    const state = createWizardState();
    expect(() => wizardReducer(state, { type: "ADVANCE" })).toThrow();
    expect(() => wizardReducer(state, { type: "SKIP" })).toThrow();
  });

  it("goes to done after skipping the last item, even if other items were skipped", () => {
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: testItems });

    // Skip all three items in sequence
    state = wizardReducer(state, { type: "SKIP" }); // eggs
    state = wizardReducer(state, { type: "SKIP" }); // milk
    state = wizardReducer(state, { type: "SKIP" }); // bread

    expect(state.status).toBe("done");
    expect(state.skippedIndices).toEqual([0, 1, 2]);
  });

  it("allows BEGIN_REVISIT from done when there are skipped items", () => {
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: testItems });
    state = wizardReducer(state, { type: "SKIP" });
    state = wizardReducer(state, { type: "ADVANCE" });
    state = wizardReducer(state, { type: "COOLDOWN_COMPLETE" });
    state = wizardReducer(state, { type: "ADVANCE" });
    state = wizardReducer(state, { type: "COOLDOWN_COMPLETE" });

    expect(state.status).toBe("done");
    expect(state.skippedIndices).toEqual([0]);

    state = wizardReducer(state, { type: "BEGIN_REVISIT" });
    expect(state.status).toBe("revisiting");
    expect(currentItem(state)?.parsedItem.searchTerm).toBe("eggs");
  });

  it("preserves search term override during revisit", () => {
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: testItems });
    state = wizardReducer(state, { type: "SKIP" });
    state = wizardReducer(state, {
      type: "EDIT_SEARCH",
      index: 0,
      searchTerm: "organic eggs",
    });
    state = wizardReducer(state, { type: "SKIP" });
    state = wizardReducer(state, { type: "SKIP" });
    state = wizardReducer(state, { type: "BEGIN_REVISIT" });
    const active = currentItem(state);
    expect(active?.searchTermOverride).toBe("organic eggs");
    expect(active?.parsedItem.searchTerm).toBe("eggs");
  });
});
