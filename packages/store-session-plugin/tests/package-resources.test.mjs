import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

const source = readFileSync(
  join(import.meta.dirname, "..", "Package.swift"),
  "utf8",
);

test("Package.swift processes Resources for a signable SwiftPM resource bundle", () => {
  assert.match(source, /resources:\s*\[\s*\.process\(\s*["']Resources["']\s*\)\s*\]/);
});

test("ListrunnerStoreSession target still has ios path", () => {
  assert.match(source, /path:\s*["']ios["']/);
});
