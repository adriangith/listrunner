import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

const source = readFileSync(
  join(import.meta.dirname, "..", "Package.swift"),
  "utf8",
);

test("Package.swift declares a Resources copy rule", () => {
  assert.match(source, /resources:\s*\[\s*\.copy\(\s*["']Resources["']\s*\)\s*\]/);
});

test("ListrunnerStoreSession target still has ios path", () => {
  assert.match(source, /path:\s*["']ios["']/);
});