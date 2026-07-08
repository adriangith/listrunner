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

test("current card uses the Figma blue radial gradient", () => {
  assert.match(source, /private func applyCurrentGradient\(to cardView: UIView\)/);
  assert.match(source, /currentGradientLayer\.type = \.radial/);
  assert.match(source, /UIColor\(red:\s*0\.00,\s*green:\s*0\.48,\s*blue:\s*1\.00,\s*alpha:\s*1\)/);
  assert.match(source, /UIColor\(red:\s*0\.10,\s*green:\s*0\.44,\s*blue:\s*0\.82,\s*alpha:\s*1\)/);
});

test("current card quantity font is smaller to fit the card width", () => {
  assert.match(source, /private func quantityFontSize\(for state: String\) -> CGFloat/);
  assert.match(source, /state == "current" \? 38 : 46/);
  assert.match(source, /quantityLabel\.adjustsFontSizeToFitWidth = true/);
  assert.match(source, /quantityLabel\.minimumScaleFactor = 0\.75/);
});

test("added cards use a green gradient layer", () => {
  assert.match(source, /private func applyAddedGradient\(to cardView: UIView\)/);
  assert.match(source, /CAGradientLayer\(\)/);
  assert.match(source, /UIColor\(red:\s*0\.78,\s*green:\s*0\.93,\s*blue:\s*0\.69,\s*alpha:\s*1\)/);
});

test("added card gradient frame updates after Auto Layout sizes the card", () => {
  assert.match(source, /private final class AddedGradientCardView: UIView/);
  assert.match(source, /override func layoutSubviews\(\)/);
  assert.match(source, /addedGradientLayer\.frame = bounds/);
  assert.doesNotMatch(source, /gradient\.frame = cardView\.bounds/);
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

test("added card quantity pill matches Figma color, type, size, and position", () => {
  assert.match(source, /quantityPill\.font = UIFont\.systemFont\(ofSize:\s*12,\s*weight:\s*\.semibold\)/);
  assert.match(source, /quantityPill\.textColor = isAddedState\(state\) \? UIColor\(red:\s*0\.12,\s*green:\s*0\.65,\s*blue:\s*0\.19,\s*alpha:\s*1\) : textColor\(for:\s*state\)/);
  assert.match(source, /quantityPill\.backgroundColor = isAddedState\(state\) \? UIColor\.white : UIColor\(red:\s*0\.96,\s*green:\s*0\.94,\s*blue:\s*0\.90,\s*alpha:\s*1\)/);
  assert.match(source, /quantityPill\.widthAnchor\.constraint\(equalToConstant:\s*54\)/);
  assert.match(source, /quantityPill\.heightAnchor\.constraint\(equalToConstant:\s*24\)/);
  assert.match(source, /quantityPill\.topAnchor\.constraint\(equalTo:\s*titleLabel\.bottomAnchor,\s*constant:\s*card\.state == "added" \? 48 : 44\)/);
});
