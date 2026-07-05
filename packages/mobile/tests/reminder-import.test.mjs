import assert from "node:assert/strict";
import { test } from "node:test";

const { importReminders, getReminderIdForItem } = await import(
  "../src/reminder-import.ts"
);

test("importReminders maps reminder titles to parsed items", () => {
  const reminders = [
    { id: "r1", title: "milk" },
    { id: "r2", title: "2 kg rice" },
    { id: "r3", title: "bread" },
  ];

  const { parsedList, reminderIdBySearchTerm } = importReminders(reminders, []);

  assert.equal(parsedList.items.length, 3);
  assert.equal(parsedList.items[0].searchTerm, "milk");
  assert.equal(parsedList.items[1].searchTerm, "rice");
  assert.equal(parsedList.items[2].searchTerm, "bread");

  assert.equal(reminderIdBySearchTerm.get("milk"), "r1");
  assert.equal(reminderIdBySearchTerm.get("rice"), "r2");
  assert.equal(reminderIdBySearchTerm.get("bread"), "r3");
});

test("importReminders applies pantry exclusions and keeps reminder IDs for kept items only", () => {
  const reminders = [
    { id: "r1", title: "salt" },
    { id: "r2", title: "pepper" },
  ];

  const { parsedList, reminderIdBySearchTerm } = importReminders(reminders, ["salt"]);

  assert.equal(parsedList.items.length, 1);
  assert.equal(parsedList.items[0].searchTerm, "pepper");
  assert.equal(parsedList.filtered.length, 1);
  assert.equal(parsedList.filtered[0].searchTerm, "salt");

  // Filtered reminder ID is still in the map but the parsed item is in filtered[],
  // not items[], so the wizard won't try to complete it.
  assert.equal(reminderIdBySearchTerm.get("salt"), "r1");
  assert.equal(reminderIdBySearchTerm.get("pepper"), "r2");
});

test("importReminders strips checkbox prefixes from Paprika exports", () => {
  const reminders = [
    { id: "r1", title: "☐ milk" },
    { id: "r2", title: "- [ ] bread" },
  ];

  const { parsedList, reminderIdBySearchTerm } = importReminders(reminders, []);

  assert.equal(parsedList.items.length, 2);
  assert.equal(parsedList.items[0].searchTerm, "milk");
  assert.equal(parsedList.items[1].searchTerm, "bread");

  assert.equal(reminderIdBySearchTerm.get("milk"), "r1");
  assert.equal(reminderIdBySearchTerm.get("bread"), "r2");
});

test("getReminderIdForItem returns ID for imported items and undefined for manual items", () => {
  const map = new Map([
    ["milk", "r1"],
    ["bread", "r2"],
  ]);

  const importedItem = { original: "milk", quantity: null, searchTerm: "milk", filtered: false };
  const manualItem = { original: "coffee", quantity: null, searchTerm: "coffee", filtered: false };

  assert.equal(getReminderIdForItem(importedItem, map), "r1");
  assert.equal(getReminderIdForItem(manualItem, map), undefined);
});

test("getReminderIdForItem looks up by searchTerm, not original", () => {
  const map = new Map([["rice", "r1"]]);

  const item = { original: "2 kg rice", quantity: "2 kg", searchTerm: "rice", filtered: false };

  assert.equal(getReminderIdForItem(item, map), "r1");
  assert.equal(map.get(item.original), undefined, "original key should not match");
});

test("importReminders handles empty reminder list", () => {
  const { parsedList, reminderIdBySearchTerm } = importReminders([], []);

  assert.equal(parsedList.items.length, 0);
  assert.equal(parsedList.filtered.length, 0);
  assert.equal(reminderIdBySearchTerm.size, 0);
});
