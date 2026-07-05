import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

const source = readFileSync(
  join(import.meta.dirname, "..", "ios", "Resources", "cart-detection.js"),
  "utf8",
);

test("script registers a capture-phase click listener on document", () => {
  assert.match(source, /document\.addEventListener\s*\(\s*["']click["']\s*,\s*\w+\s*,\s*true\s*\)/);
});

test("script matches the coles add-to-cart selector", () => {
  assert.match(source, /button\[data-testid=['"]add-to-cart-button['"]\]/);
  assert.match(source, /button\.add-to-cart/);
});

test("script posts addToCartDetected with productName and productImageUrl", () => {
  assert.match(source, /type:\s*["']addToCartDetected["']/);
  assert.match(source, /productName/);
  assert.match(source, /productImageUrl/);
});

test("script posts pageLoaded at document end", () => {
  assert.match(source, /type:\s*["']pageLoaded["']/);
});

test("script guards the postMessage call against a missing bridge", () => {
  // Must not be a bare unguarded call to window.webkit.messageHandlers.storeSessionBridge.postMessage
  assert.match(source, /if\s*\(\s*window\.webkit\s*&&\s*window\.webkit\.messageHandlers\b/);
});

test("script defines an extractProductInfo function", () => {
  assert.match(source, /function\s+extractProductInfo\s*\(/);
});

test("script falls back to og:title metadata for product name", () => {
  assert.match(source, /og:title/);
});

test("script falls back to og:image for product image", () => {
  assert.match(source, /og:image/);
});

test("script defaults to Unknown product when name extraction is empty", () => {
  assert.match(source, /Unknown product/);
});