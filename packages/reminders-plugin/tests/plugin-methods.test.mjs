import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

const source = readFileSync(
  join(import.meta.dirname, "..", "ios", "RemindersPlugin.swift"),
  "utf8",
);

test("plugin declares CAPBridgedPlugin with Reminders jsName", () => {
  assert.match(source, /class RemindersPlugin:\s*CAPPlugin,\s*CAPBridgedPlugin/);
  assert.match(source, /let jsName = "Reminders"/);
});

test("plugin registers getPaprikaItems and completeReminder methods", () => {
  assert.match(source, /CAPPluginMethod\(name: "getPaprikaItems"/);
  assert.match(source, /CAPPluginMethod\(name: "completeReminder"/);
});

test("plugin imports EventKit", () => {
  assert.match(source, /^import EventKit/m);
});

test("plugin fetches calendars named Paprika", () => {
  assert.match(source, /\$0\.title == "Paprika"/);
});
