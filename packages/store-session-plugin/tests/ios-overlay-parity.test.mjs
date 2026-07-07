import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

const source = readFileSync(
  join(import.meta.dirname, "..", "ios", "StoreSessionViewController.swift"),
  "utf8",
);

test("non-cooldown primary action uses the Figma Skip label", () => {
  assert.match(source, /primaryTitle\s*=\s*"Skip"/);
});

test("manual mode renders a bottom-panel badge instead of a card badge", () => {
  assert.match(source, /payload\.mode\s*==\s*"manual"/);
  assert.match(source, /updateManualBadge\(for:\s*payload\)/);
  assert.doesNotMatch(source, /if\s+let\s+badge\s*=\s*card\.badge/);
});

test("currentAdded uses neutral added styling rather than current blue styling", () => {
  assert.match(source, /private func isBlueCurrentState\(_ state: String\) -> Bool/);
  assert.match(source, /return state == "current"/);
  assert.doesNotMatch(source, /state == "current" \|\| state == "currentAdded"/);
});

test("added states render Figma text labels instead of green pill badges", () => {
  assert.match(source, /private func makeAddedStateLabel\(\) -> UILabel/);
  assert.doesNotMatch(source, /addBadge\(text:\s*"✓ Added"/);
});

test("carousel uses the Figma overscan geometry", () => {
  assert.match(source, /carouselScrollView\.leadingAnchor\.constraint\(equalTo:\s*view\.leadingAnchor,\s*constant:\s*-43\)/);
  assert.match(source, /carouselScrollView\.widthAnchor\.constraint\(equalToConstant:\s*482\)/);
});

test("card tap gesture emits cardSelected event", () => {
  assert.match(source, /#selector\(cardTapped/);
  assert.match(source, /"cardSelected"/);
});

test("cooldown shows progress view inside the primary button", () => {
  assert.match(source, /primaryButton\.addSubview\(progressView\)/);
});

test("currentAdded uses a different title position than current", () => {
  assert.match(source, /"currentAdded" \? 29/);
});
