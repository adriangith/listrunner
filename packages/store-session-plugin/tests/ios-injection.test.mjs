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
  assert.match(source, /subdirectory:\s*["']Resources["']/);
});

test("registers a WKUserScript at document end", () => {
  assert.match(source, /WKUserScript\s*\(/);
  assert.match(source, /\.atDocumentEnd/);
});

test("uses the loaded script source for the WKUserScript", () => {
  assert.match(source, /String\s*\(\s*contentsOf:\s*scriptURL/);
});

test("falls back to pageLoaded script if cart-detection resource is unavailable", () => {
  assert.match(source, /else\s*\{/);
  assert.match(source, /postMessage\s*\(\s*\{\s*type:\s*['"]pageLoaded['"]\s*\}\s*\)/);
});
