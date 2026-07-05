import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

const source = readFileSync(
  join(import.meta.dirname, "..", "ios", "StoreSessionViewController.swift"),
  "utf8",
);

function methodBody(name) {
  const signature = `public func ${name}`;
  const start = source.indexOf(signature);
  assert.notEqual(start, -1, `${name} should exist`);

  const openBrace = source.indexOf("{", start);
  assert.notEqual(openBrace, -1, `${name} should have a body`);

  let depth = 0;
  for (let index = openBrace; index < source.length; index += 1) {
    const char = source[index];
    if (char === "{") depth += 1;
    if (char === "}") depth -= 1;
    if (depth === 0) {
      return source.slice(openBrace + 1, index);
    }
  }

  assert.fail(`${name} body should close`);
}

test("loadStore does not require WKWebView to exist before the view loads", () => {
  const body = methodBody("loadStore");

  assert.doesNotMatch(
    body,
    /webView\.load\(/,
    "loadStore is called before presentation, so direct webView.load can crash when webView is nil",
  );
  assert.match(
    source,
    /pendingStoreURL/,
    "store URL should be saved until viewDidLoad creates the WKWebView",
  );
});
