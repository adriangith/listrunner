import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

const source = readFileSync(
  join(import.meta.dirname, "..", "ios", "StoreSessionViewController.swift"),
  "utf8",
);

test("loads cart-detection.js from Bundle.module", () => {
  assert.match(source, /Bundle\.module\.url\s*\(\s*forResource:\s*["']cart-detection["']/);
});

test("registers a WKUserScript at document end", () => {
  assert.match(source, /WKUserScript\s*\(/);
  assert.match(source, /\.atDocumentEnd/);
});

test("uses the loaded script source for the WKUserScript", () => {
  assert.match(source, /String\s*\(\s*contentsOf:\s*scriptURL/);
});

test("no longer contains the inline pageLoaded script source string", () => {
  // The old inline postMessage({type: 'pageLoaded'}) source string should be gone.
  assert.doesNotMatch(source, /postMessage\s*\(\s*\{\s*type:\s*['"]pageLoaded['"]\s*\}\s*\)/);
});
