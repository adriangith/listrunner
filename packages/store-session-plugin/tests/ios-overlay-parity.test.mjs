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

test("carousel includes edge spacers so end cards can fully enter the viewport", () => {
  assert.match(source, /private func makeCarouselSpacer\(width: CGFloat\) -> UIView/);
  assert.equal(
    source.match(/carouselStack\.addArrangedSubview\(makeCarouselSpacer\(width:\s*165\)\)/g)?.length,
    2,
  );
  assert.match(source, /centerActiveCard\(for:\s*payload\.activeIndex \+ 1\)/);
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

test("added cards use a green gradient layer", () => {
  assert.match(source, /private func applyAddedGradient\(to cardView: UIView\)/);
  assert.match(source, /CAGradientLayer\(\)/);
  assert.match(source, /UIColor\(red:\s*0\.78,\s*green:\s*0\.93,\s*blue:\s*0\.69,\s*alpha:\s*1\)/);
});

test("cards do not render top marker circles", () => {
  assert.doesNotMatch(source, /let dot = UIView\(\)/);
  assert.doesNotMatch(source, /dot\.layer\.cornerRadius/);
});

test("added label is shifted left for Figma parity", () => {
  assert.match(source, /addedLabel\.leadingAnchor\.constraint\(equalTo:\s*cardView\.leadingAnchor,\s*constant:\s*8\)/);
});

test("non-selected quantities render inside pill backgrounds", () => {
  assert.match(source, /private func makeQuantityPill\(text: String, state: String\) -> UILabel/);
  assert.match(source, /quantityPill\.layer\.cornerRadius = 12/);
  assert.match(source, /cardView\.addSubview\(quantityPill\)/);
});
