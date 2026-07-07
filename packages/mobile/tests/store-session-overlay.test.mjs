import assert from "node:assert/strict";
import { test } from "node:test";

const { createWizardState, wizardReducer } = await import("../../core/src/wizard.ts");
const { buildStoreSessionOverlayPayload } = await import(
  "../src/store-session-overlay.ts"
);

const items = [
  { original: "500g chicken", quantity: { amount: 500, unit: "g" }, searchTerm: "chicken", filtered: false },
  { original: "1 sourdough bread", quantity: { amount: 1, unit: null }, searchTerm: "sourdough bread", filtered: false },
  { original: "1kg yoghurt", quantity: { amount: 1, unit: "kg" }, searchTerm: "yoghurt", filtered: false },
];

test("buildStoreSessionOverlayPayload returns current and inactive cards before add", () => {
  let state = createWizardState();
  state = wizardReducer(state, { type: "START", items });

  const payload = buildStoreSessionOverlayPayload({
    state,
    automationUnavailable: false,
    cooldownRemainingMs: null,
    cooldownTotalMs: 3000,
  });

  assert.equal(payload.mode, "automationAvailable");
  assert.equal(payload.primaryAction, "next");
  assert.equal(payload.secondaryAction, "previous");
  assert.equal(payload.secondaryEnabled, false);
  assert.deepEqual(payload.cards.map((card) => card.state), ["current", "inactive", "inactive"]);
  assert.equal(payload.cards[0].title, "chicken");
  assert.equal(payload.cards[0].quantity, "500 g");
});

test("buildStoreSessionOverlayPayload enables previous only for later primary items", () => {
  let state = createWizardState();
  state = wizardReducer(state, { type: "START", items });
  state = wizardReducer(state, { type: "SKIP" });

  const payload = buildStoreSessionOverlayPayload({
    state,
    automationUnavailable: false,
    cooldownRemainingMs: null,
    cooldownTotalMs: 3000,
  });

  assert.equal(payload.secondaryAction, "previous");
  assert.equal(payload.secondaryEnabled, true);
});

test("buildStoreSessionOverlayPayload disables previous during revisit", () => {
  let state = createWizardState();
  state = wizardReducer(state, { type: "START", items });
  state = wizardReducer(state, { type: "SKIP" });
  state = wizardReducer(state, { type: "SKIP" });
  state = wizardReducer(state, { type: "SKIP" });
  state = wizardReducer(state, { type: "BEGIN_REVISIT" });

  const payload = buildStoreSessionOverlayPayload({
    state,
    automationUnavailable: false,
    cooldownRemainingMs: null,
    cooldownTotalMs: 3000,
  });

  assert.equal(payload.secondaryAction, "previous");
  assert.equal(payload.secondaryEnabled, false);
});

test("buildStoreSessionOverlayPayload marks manual mode without card badges", () => {
  let state = createWizardState();
  state = wizardReducer(state, { type: "START", items });

  const payload = buildStoreSessionOverlayPayload({
    state,
    automationUnavailable: true,
    cooldownRemainingMs: null,
    cooldownTotalMs: 3000,
  });

  assert.equal(payload.mode, "manual");
  assert.equal(payload.cards[0].badge, null);
  assert.equal(payload.cards[0].state, "current");
});

test("buildStoreSessionOverlayPayload returns currentAdded and countdown during cooldown", () => {
  let state = createWizardState();
  state = wizardReducer(state, { type: "START", items });
  state = wizardReducer(state, { type: "ADVANCE" });

  const payload = buildStoreSessionOverlayPayload({
    state,
    automationUnavailable: false,
    cooldownRemainingMs: 1400,
    cooldownTotalMs: 3000,
  });

  assert.equal(payload.mode, "cooldown");
  assert.equal(payload.primaryAction, "nextCooldown");
  assert.equal(payload.secondaryAction, "undo");
  assert.equal(payload.secondaryEnabled, true);
  assert.equal(payload.cooldownSeconds, 2);
  assert.equal(Math.round(payload.cooldownProgress * 100), 53);
  assert.equal(payload.cards[0].state, "currentAdded");
});

test("buildStoreSessionOverlayPayload keeps selected added cards added", () => {
  let state = createWizardState();
  state = wizardReducer(state, { type: "START", items });
  state = wizardReducer(state, { type: "ADVANCE" });
  state = wizardReducer(state, { type: "COOLDOWN_COMPLETE" });
  state = wizardReducer(state, { type: "SELECT_INDEX", index: 0 });

  const payload = buildStoreSessionOverlayPayload({
    state,
    automationUnavailable: false,
    cooldownRemainingMs: null,
    cooldownTotalMs: 3000,
  });

  assert.equal(payload.activeIndex, 0);
  assert.equal(payload.cards[0].state, "added");
});
