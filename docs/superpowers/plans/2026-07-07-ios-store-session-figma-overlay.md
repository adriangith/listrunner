# iOS Store Session Figma Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `Current Mobile UI` Figma store-session overlay in the native iOS WKWebView session.

**Architecture:** Keep the existing TypeScript wizard reducer as the source of truth. Add a typed native overlay payload builder in the mobile app, extend the Capacitor StoreSession bridge to accept that payload, and render the Figma-inspired carousel/cards/bottom actions in Swift over the WKWebView.

**Tech Stack:** TypeScript, Node test runner, Capacitor 8, Swift UIKit, WKWebView.

## Global Constraints

- Native iOS implementation target is `packages/store-session-plugin/ios`, because `packages/mobile/ios/App/CapApp-SPM/Package.swift` points at `../../../../store-session-plugin`.
- The old duplicated Swift files under `packages/mobile/src/plugins/store-session/ios` and `packages/mobile/ios/Plugins/StoreSession` have been removed; keep native overlay work in `packages/store-session-plugin/ios`.
- Preserve the WKWebView as full-screen website content.
- The native overlay owns the store-session UI only; the mobile web wizard remains the app-side state source.
- Bottom actions are navigation/recovery: before add uses Previous/Next, cooldown uses Undo/Next countdown.
- Card actions are product-specific: Current card uses Mark added, Current Added card uses Add another, Manual uses a badge on Current rather than a separate variant.
- Keep implementation UIKit-only; do not introduce SwiftUI or new package dependencies.
- Tests must run from `packages/mobile` with `npm test` and `npm run build`.

---

## File Structure

- Modify: `packages/core/src/types.ts` and `packages/core/src/wizard.ts`
  - Add a `PREVIOUS` wizard action so the native Previous button has a real state-machine action.
- Modify: `packages/core/tests/wizard.test.ts`
  - Cover the new `PREVIOUS` transition.
- Create: `packages/mobile/src/store-session-overlay.ts`
  - Build a serializable overlay payload from `WizardState`, cooldown timing, and automation availability.
- Create: `packages/mobile/tests/store-session-overlay.test.mjs`
  - Test payload states and card mapping without DOM or Capacitor.
- Modify: `packages/store-session-plugin/src/index.ts`
  - Extend the plugin TypeScript interface for richer `updateOverlay` payloads and new native event names.
- Modify: `packages/mobile/src/main.ts`
  - Send overlay payloads to native iOS on render and cooldown ticks.
  - Route native button events back to existing wizard actions.
- Modify: `packages/store-session-plugin/ios/StoreSessionPlugin.swift`
  - Parse the richer `updateOverlay` payload from Capacitor and pass it to the view controller.
- Replace most of: `packages/store-session-plugin/ios/StoreSessionViewController.swift`
  - Render WKWebView plus bottom overlay panel, horizontal cards, badges, and action buttons.

---

### Task 1: Add Previous Navigation To Wizard State

**Files:**
- Modify: `packages/core/src/types.ts:70-80`
- Modify: `packages/core/src/wizard.ts:47-68`
- Modify: `packages/core/tests/wizard.test.ts`

**Interfaces:**
- Produces: `WizardAction` supports `{ type: "PREVIOUS" }`.
- Produces: `wizardReducer(state, { type: "PREVIOUS" })` moves from `stepping` to the previous primary item and marks the previously active item as `pending`.
- Consumes: existing `WizardState.currentIndex`, `WizardItem.status`, and `currentItem(state)`.

- [ ] **Step 1: Write failing reducer tests**

Append these tests before the final `throws on invalid transitions` test in `packages/core/tests/wizard.test.ts`:

```ts
it("moves to the previous primary item while stepping", () => {
  let state = createWizardState();
  state = wizardReducer(state, { type: "START", items: testItems });
  state = wizardReducer(state, { type: "SKIP" });

  expect(currentItem(state)?.parsedItem.searchTerm).toBe("milk");

  state = wizardReducer(state, { type: "PREVIOUS" });

  expect(state.status).toBe("stepping");
  expect(state.currentIndex).toBe(0);
  expect(currentItem(state)?.parsedItem.searchTerm).toBe("eggs");
  expect(currentItem(state)?.status).toBe("active");
  expect(state.items[1]?.status).toBe("pending");
});

it("throws when moving previous from the first item", () => {
  let state = createWizardState();
  state = wizardReducer(state, { type: "START", items: testItems });

  expect(() => wizardReducer(state, { type: "PREVIOUS" })).toThrow(
    'Cannot PREVIOUS from first item',
  );
});
```

- [ ] **Step 2: Run tests to verify failure**

Run: `npm test --workspace packages/core` if workspace scripts exist. If not, run from the core package directory: `npm test`.

Expected: TypeScript/test failure because `PREVIOUS` is not part of `WizardAction` and `wizardReducer` does not handle it.

- [ ] **Step 3: Add `PREVIOUS` to the action type**

Modify `packages/core/src/types.ts` so `WizardAction` includes:

```ts
  | { type: "PREVIOUS" }
```

- [ ] **Step 4: Implement reducer handling**

In `packages/core/src/wizard.ts`, add this switch case after `SKIP`:

```ts
    case "PREVIOUS":
      return handlePrevious(state);
```

Add this helper after `handleSkip`:

```ts
function handlePrevious(state: WizardState): WizardState {
  if (state.status !== "stepping") {
    throw new Error(`Cannot PREVIOUS from status "${state.status}"`);
  }
  if (state.currentIndex <= 0) {
    throw new Error("Cannot PREVIOUS from first item");
  }

  const items = [...state.items];
  items[state.currentIndex] = { ...items[state.currentIndex]!, status: "pending" };
  const previousIndex = state.currentIndex - 1;
  items[previousIndex] = { ...items[previousIndex]!, status: "active" };

  return {
    ...state,
    items,
    currentIndex: previousIndex,
    cooldownItemIndex: null,
  };
}
```

- [ ] **Step 5: Run reducer tests**

Run from `packages/core`: `npm test`

Expected: all wizard tests pass, including the two new `PREVIOUS` tests.

- [ ] **Step 6: Commit Task 1**

```bash
git add packages/core/src/types.ts packages/core/src/wizard.ts packages/core/tests/wizard.test.ts
git commit -m "feat: add wizard previous action"
```

---

### Task 2: Build Native Overlay Payloads In TypeScript

**Files:**
- Create: `packages/mobile/src/store-session-overlay.ts`
- Create: `packages/mobile/tests/store-session-overlay.test.mjs`
- Modify: `packages/store-session-plugin/src/index.ts:3-8`

**Interfaces:**
- Produces type `StoreSessionOverlayMode = "automationAvailable" | "manual" | "cooldown"`.
- Produces type `StoreSessionOverlayCardState = "added" | "current" | "currentAdded" | "inactive"`.
- Produces function `buildStoreSessionOverlayPayload(options): StoreSessionOverlayPayload`.
- Consumes `WizardState`, `WizardItem`, `formatQuantity`, and search term override rules.

- [ ] **Step 1: Write failing payload tests**

Create `packages/mobile/tests/store-session-overlay.test.mjs`:

```js
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
  assert.deepEqual(payload.cards.map((card) => card.state), ["current", "inactive", "inactive"]);
  assert.equal(payload.cards[0].title, "chicken");
  assert.equal(payload.cards[0].quantity, "500 g");
});

test("buildStoreSessionOverlayPayload marks manual mode without changing card state", () => {
  let state = createWizardState();
  state = wizardReducer(state, { type: "START", items });

  const payload = buildStoreSessionOverlayPayload({
    state,
    automationUnavailable: true,
    cooldownRemainingMs: null,
    cooldownTotalMs: 3000,
  });

  assert.equal(payload.mode, "manual");
  assert.equal(payload.cards[0].badge, "Manual");
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
  assert.equal(payload.cooldownSeconds, 2);
  assert.equal(Math.round(payload.cooldownProgress * 100), 53);
  assert.equal(payload.cards[0].state, "currentAdded");
});
```

- [ ] **Step 2: Run test to verify failure**

Run from `packages/mobile`: `npm test`

Expected: FAIL because `../src/store-session-overlay.ts` does not exist.

- [ ] **Step 3: Implement payload helper**

Create `packages/mobile/src/store-session-overlay.ts`:

```ts
import type { WizardState, WizardItem } from "@listrunner/core";
import { formatQuantity } from "./item-display.js";

export type StoreSessionOverlayMode = "automationAvailable" | "manual" | "cooldown";
export type StoreSessionOverlayCardState = "added" | "current" | "currentAdded" | "inactive";
export type StoreSessionOverlayAction =
  | "previous"
  | "next"
  | "markAdded"
  | "addAnother"
  | "undo"
  | "nextCooldown";

export interface StoreSessionOverlayCard {
  id: string;
  title: string;
  quantity: string;
  state: StoreSessionOverlayCardState;
  badge: "Manual" | null;
}

export interface StoreSessionOverlayPayload {
  mode: StoreSessionOverlayMode;
  cards: StoreSessionOverlayCard[];
  activeIndex: number;
  primaryAction: StoreSessionOverlayAction;
  secondaryAction: StoreSessionOverlayAction;
  cooldownSeconds: number | null;
  cooldownProgress: number | null;
}

export interface BuildStoreSessionOverlayPayloadOptions {
  state: WizardState;
  automationUnavailable: boolean;
  cooldownRemainingMs: number | null;
  cooldownTotalMs: number;
}

export function buildStoreSessionOverlayPayload({
  state,
  automationUnavailable,
  cooldownRemainingMs,
  cooldownTotalMs,
}: BuildStoreSessionOverlayPayloadOptions): StoreSessionOverlayPayload {
  const activeIndex = getOverlayActiveIndex(state);
  const cards = state.items.map((item, index) => cardFromItem(item, index, activeIndex, state, automationUnavailable));
  const isCooldown = state.status === "cooldown";
  const remaining = isCooldown ? Math.max(0, cooldownRemainingMs ?? cooldownTotalMs) : null;
  const progress = remaining === null ? null : 1 - remaining / cooldownTotalMs;

  return {
    mode: isCooldown ? "cooldown" : automationUnavailable ? "manual" : "automationAvailable",
    cards,
    activeIndex,
    primaryAction: isCooldown ? "nextCooldown" : "next",
    secondaryAction: isCooldown ? "undo" : "previous",
    cooldownSeconds: remaining === null ? null : Math.ceil(remaining / 1000),
    cooldownProgress: progress === null ? null : Math.max(0, Math.min(1, progress)),
  };
}

function cardFromItem(
  item: WizardItem,
  index: number,
  activeIndex: number,
  state: WizardState,
  automationUnavailable: boolean,
): StoreSessionOverlayCard {
  const isActive = index === activeIndex;
  const title = item.searchTermOverride ?? item.parsedItem.searchTerm;
  const isCooldownActive = state.status === "cooldown" && isActive;

  return {
    id: String(index),
    title,
    quantity: formatQuantity(item.parsedItem),
    state: isCooldownActive
      ? "currentAdded"
      : item.status === "added"
        ? "added"
        : isActive
          ? "current"
          : "inactive",
    badge: isActive && automationUnavailable && state.status !== "cooldown" ? "Manual" : null,
  };
}

function getOverlayActiveIndex(state: WizardState): number {
  if (state.status === "cooldown" && state.cooldownItemIndex !== null) return state.cooldownItemIndex;
  if (state.status === "revisiting") return state.skippedIndices[state.revisitPointer] ?? state.currentIndex;
  return Math.max(0, state.currentIndex);
}
```

- [ ] **Step 4: Extend plugin TypeScript interface**

Modify `packages/store-session-plugin/src/index.ts` to export matching payload types and update `updateOverlay`:

```ts
export type StoreSessionOverlayMode = "automationAvailable" | "manual" | "cooldown";
export type StoreSessionOverlayCardState = "added" | "current" | "currentAdded" | "inactive";
export type StoreSessionOverlayAction =
  | "previous"
  | "next"
  | "markAdded"
  | "addAnother"
  | "undo"
  | "nextCooldown";

export interface StoreSessionOverlayCard {
  id: string;
  title: string;
  quantity: string;
  state: StoreSessionOverlayCardState;
  badge: "Manual" | null;
}

export interface StoreSessionOverlayPayload {
  mode: StoreSessionOverlayMode;
  cards: StoreSessionOverlayCard[];
  activeIndex: number;
  primaryAction: StoreSessionOverlayAction;
  secondaryAction: StoreSessionOverlayAction;
  cooldownSeconds: number | null;
  cooldownProgress: number | null;
}
```

Change the interface method to:

```ts
  updateOverlay(options: StoreSessionOverlayPayload & { itemName: string; searchTerm: string }): Promise<void>;
```

Add listeners:

```ts
  addListener(eventName: 'previousRequested', listenerFunc: () => void): Promise<any>;
  addListener(eventName: 'nextRequested', listenerFunc: () => void): Promise<any>;
  addListener(eventName: 'markAddedRequested', listenerFunc: () => void): Promise<any>;
  addListener(eventName: 'addAnotherRequested', listenerFunc: () => void): Promise<any>;
  addListener(eventName: 'undoRequested', listenerFunc: () => void): Promise<any>;
```

- [ ] **Step 5: Run mobile tests**

Run from `packages/mobile`: `npm test`

Expected: all tests pass, including `store-session-overlay.test.mjs`.

- [ ] **Step 6: Commit Task 2**

```bash
git add packages/mobile/src/store-session-overlay.ts packages/mobile/tests/store-session-overlay.test.mjs packages/store-session-plugin/src/index.ts
git commit -m "feat: build native store session overlay payloads"
```

---

### Task 3: Wire Mobile Wizard State To Native Overlay Events

**Files:**
- Modify: `packages/mobile/src/main.ts`
- Test: `packages/mobile/tests/store-session-overlay.test.mjs` from Task 2 remains the unit coverage for payload construction.

**Interfaces:**
- Consumes: `buildStoreSessionOverlayPayload(options)` from Task 2.
- Consumes: native events `previousRequested`, `nextRequested`, `markAddedRequested`, `addAnotherRequested`, `undoRequested`.
- Produces: `StoreSession.updateOverlay({ itemName, searchTerm, ...payload })` calls on active-item render and cooldown ticks.

- [ ] **Step 1: Import payload builder**

At the top of `packages/mobile/src/main.ts`, add:

```ts
import { buildStoreSessionOverlayPayload } from "./store-session-overlay.js";
```

- [ ] **Step 2: Add native event listeners**

In `init()`, after existing StoreSession listeners, add:

```ts
  StoreSession.addListener("previousRequested", () => {
    sendAction("PREVIOUS");
  });

  StoreSession.addListener("nextRequested", () => {
    sendAction("SKIP");
  });

  StoreSession.addListener("markAddedRequested", () => {
    handleAdded();
  });

  StoreSession.addListener("addAnotherRequested", () => {
    sendAction("ADD_ANOTHER");
  });

  StoreSession.addListener("undoRequested", () => {
    sendAction("UNDO");
  });
```

Use `SKIP` for `nextRequested` before add because the user is moving past the item without marking it added. Cooldown next uses a separate Swift-side action name that maps to `nextRequested`; in `handleNativeNextRequested()` below it will branch on status.

- [ ] **Step 3: Replace `nextRequested` listener with status-aware handler**

Define this helper near `sendAction`:

```ts
function handleNativeNextRequested(): void {
  if (!wizardState) return;
  if (wizardState.status === "cooldown") {
    sendAction("COOLDOWN_COMPLETE");
    return;
  }
  sendAction("SKIP");
}
```

Then make the listener:

```ts
  StoreSession.addListener("nextRequested", handleNativeNextRequested);
```

- [ ] **Step 4: Include PREVIOUS in simple action type mapping**

Change `SimpleWizardAction` so it includes `PREVIOUS` by updating its `Exclude` if necessary, then add a `toWizardAction` case:

```ts
    case "PREVIOUS":
      return { type: "PREVIOUS" };
```

- [ ] **Step 5: Add native overlay sync helper**

Add this function near `navigateToActiveItem()`:

```ts
function syncNativeOverlay(): void {
  if (!wizardState) return;
  const active = findActiveItem(wizardState);
  if (!active) return;

  const searchTerm = active.searchTermOverride ?? active.parsedItem.searchTerm;
  const overlayItemName = formatItemDisplayName(active.parsedItem, searchTerm);
  const payload = buildStoreSessionOverlayPayload({
    state: wizardState,
    automationUnavailable: !automationWarning.classList.contains("hidden"),
    cooldownRemainingMs: getCooldownRemainingMs(),
    cooldownTotalMs: COOLDOWN_MS,
  });

  StoreSession.updateOverlay({
    itemName: overlayItemName,
    searchTerm,
    ...payload,
  });
}

function getCooldownRemainingMs(): number | null {
  if (cooldownStartedAt === null || !wizardState || wizardState.status !== "cooldown") return null;
  return Math.max(0, COOLDOWN_MS - (Date.now() - cooldownStartedAt));
}
```

- [ ] **Step 6: Call overlay sync from render and cooldown paths**

At the end of `renderWizardView()`, add:

```ts
  syncNativeOverlay();
```

At the end of `updateCooldownMessage()`, add:

```ts
  syncNativeOverlay();
```

In the `automationTimeout` listener, after showing the warning, add:

```ts
    syncNativeOverlay();
```

- [ ] **Step 7: Remove duplicate overlay update from navigation**

In `navigateToActiveItem()`, keep `StoreSession.setStore(...)` and `StoreSession.search(...)`, but replace the direct `StoreSession.updateOverlay(...)` block with:

```ts
  syncNativeOverlay();
```

- [ ] **Step 8: Run mobile tests and build**

Run from `packages/mobile`:

```bash
npm test
npm run build
```

Expected: tests pass and Vite build completes.

- [ ] **Step 9: Commit Task 3**

```bash
git add packages/mobile/src/main.ts
git commit -m "feat: sync wizard state to native store overlay"
```

---

### Task 4: Parse Overlay Payload In The iOS Plugin

**Files:**
- Modify: `packages/store-session-plugin/ios/StoreSessionPlugin.swift`
- Modify: `packages/store-session-plugin/ios/StoreSessionViewController.swift`

**Interfaces:**
- Consumes: `StoreSession.updateOverlay(...)` payload from Task 3.
- Produces Swift structs `StoreSessionOverlayPayload` and `StoreSessionOverlayCard`.
- Produces controller method `updateOverlay(payload: StoreSessionOverlayPayload)`.

- [ ] **Step 1: Add Swift payload models**

At the top of `packages/store-session-plugin/ios/StoreSessionViewController.swift`, after imports, add:

```swift
struct StoreSessionOverlayCard {
    let id: String
    let title: String
    let quantity: String
    let state: String
    let badge: String?
}

struct StoreSessionOverlayPayload {
    let mode: String
    let cards: [StoreSessionOverlayCard]
    let activeIndex: Int
    let primaryAction: String
    let secondaryAction: String
    let cooldownSeconds: Int?
    let cooldownProgress: Double?
    let itemName: String
    let searchTerm: String
}
```

- [ ] **Step 2: Parse payload in plugin**

Replace `updateOverlay(_:)` in `packages/store-session-plugin/ios/StoreSessionPlugin.swift` with:

```swift
    @objc func updateOverlay(_ call: CAPPluginCall) {
        guard let itemName = call.getString("itemName"),
              let searchTerm = call.getString("searchTerm"),
              let mode = call.getString("mode"),
              let activeIndex = call.getInt("activeIndex"),
              let primaryAction = call.getString("primaryAction"),
              let secondaryAction = call.getString("secondaryAction"),
              let rawCards = call.getArray("cards") as? [[String: Any]] else {
            call.reject("Invalid overlay payload")
            return
        }

        let cards = rawCards.compactMap { raw -> StoreSessionOverlayCard? in
            guard let id = raw["id"] as? String,
                  let title = raw["title"] as? String,
                  let quantity = raw["quantity"] as? String,
                  let state = raw["state"] as? String else {
                return nil
            }
            return StoreSessionOverlayCard(
                id: id,
                title: title,
                quantity: quantity,
                state: state,
                badge: raw["badge"] as? String
            )
        }

        let payload = StoreSessionOverlayPayload(
            mode: mode,
            cards: cards,
            activeIndex: activeIndex,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction,
            cooldownSeconds: call.getInt("cooldownSeconds"),
            cooldownProgress: call.getDouble("cooldownProgress"),
            itemName: itemName,
            searchTerm: searchTerm
        )

        DispatchQueue.main.async {
            self.storeSessionVC?.updateOverlay(payload: payload)
            call.resolve()
        }
    }
```

- [ ] **Step 3: Add compatibility method to view controller**

In `StoreSessionViewController`, replace the old method:

```swift
    public func updateOverlay(itemName: String, searchTerm: String) {
        DispatchQueue.main.async {
            self.currentItemLabel.text = itemName
            self.searchInput.text = searchTerm
        }
    }
```

with a temporary method that compiles until Task 5 renders real UI:

```swift
    public func updateOverlay(payload: StoreSessionOverlayPayload) {
        DispatchQueue.main.async {
            self.currentPayload = payload
            self.renderOverlay()
        }
    }
```

Also add this property to the class:

```swift
    private var currentPayload: StoreSessionOverlayPayload?
```

Add this placeholder method inside the class:

```swift
    private func renderOverlay() {
        guard let payload = currentPayload else { return }
        currentItemLabel.text = payload.itemName
        searchInput.text = payload.searchTerm
    }
```

- [ ] **Step 4: Build iOS package through mobile sync**

Run from `packages/mobile`:

```bash
npm run build
npm run cap:sync
```

Expected: TypeScript build completes and Capacitor sync does not fail on plugin type generation.

- [ ] **Step 5: Commit Task 4**

```bash
git add packages/store-session-plugin/ios/StoreSessionPlugin.swift packages/store-session-plugin/ios/StoreSessionViewController.swift
git commit -m "feat: parse native store overlay payload"
```

---

### Task 5: Render The Native Overlay UI In Swift

**Files:**
- Modify: `packages/store-session-plugin/ios/StoreSessionViewController.swift`

**Interfaces:**
- Consumes: `StoreSessionOverlayPayload` from Task 4.
- Produces: native UIKit overlay matching Figma states: automation available, manual, cooldown.
- Emits events: `previousRequested`, `nextRequested`, `markAddedRequested`, `addAnotherRequested`, `undoRequested`.

- [ ] **Step 1: Replace legacy overlay properties**

Replace these properties:

```swift
    var overlayView: UIView!
    var currentItemLabel: UILabel!
    var searchInput: UITextField!
```

with:

```swift
    var overlayView: UIView!
    private let carouselStack = UIStackView()
    private let secondaryButton = UIButton(type: .system)
    private let primaryButton = UIButton(type: .system)
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private var currentPayload: StoreSessionOverlayPayload?
```

- [ ] **Step 2: Replace `setupOverlay()`**

Implement this overlay skeleton:

```swift
    private func setupOverlay() {
        overlayView = UIView()
        overlayView.backgroundColor = UIColor.white.withAlphaComponent(0.94)
        overlayView.layer.shadowColor = UIColor.black.cgColor
        overlayView.layer.shadowOpacity = 0.12
        overlayView.layer.shadowRadius = 18
        overlayView.layer.shadowOffset = CGSize(width: 0, height: -8)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)

        carouselStack.axis = .horizontal
        carouselStack.alignment = .center
        carouselStack.distribution = .equalSpacing
        carouselStack.spacing = 10
        carouselStack.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(carouselStack)

        secondaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(secondaryButton)
        overlayView.addSubview(primaryButton)
        primaryButton.addSubview(progressView)

        styleActionButton(secondaryButton, background: UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1), foreground: .darkText)
        styleActionButton(primaryButton, background: UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1), foreground: .white)

        secondaryButton.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayView.heightAnchor.constraint(equalToConstant: 202),

            carouselStack.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: -42),
            carouselStack.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: 42),
            carouselStack.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: -92),
            carouselStack.heightAnchor.constraint(equalToConstant: 182),

            secondaryButton.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 20),
            secondaryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            secondaryButton.widthAnchor.constraint(equalToConstant: 108),
            secondaryButton.heightAnchor.constraint(equalToConstant: 44),

            primaryButton.leadingAnchor.constraint(equalTo: secondaryButton.trailingAnchor, constant: 12),
            primaryButton.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -20),
            primaryButton.bottomAnchor.constraint(equalTo: secondaryButton.bottomAnchor),
            primaryButton.heightAnchor.constraint(equalToConstant: 44),

            progressView.leadingAnchor.constraint(equalTo: primaryButton.leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: primaryButton.trailingAnchor, constant: -16),
            progressView.bottomAnchor.constraint(equalTo: primaryButton.bottomAnchor, constant: -8),
            progressView.heightAnchor.constraint(equalToConstant: 4),
        ])
    }
```

- [ ] **Step 3: Add button styling helper**

Add:

```swift
    private func styleActionButton(_ button: UIButton, background: UIColor, foreground: UIColor) {
        button.backgroundColor = background
        button.setTitleColor(foreground, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
    }
```

- [ ] **Step 4: Add card rendering**

Add:

```swift
    private func makeCard(_ card: StoreSessionOverlayCard) -> UIView {
        let cardView = UIView()
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 18
        cardView.clipsToBounds = false
        cardView.backgroundColor = backgroundColor(for: card.state)
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.12
        cardView.layer.shadowRadius = 12
        cardView.layer.shadowOffset = CGSize(width: 0, height: 6)

        let titleLabel = UILabel()
        titleLabel.text = card.title
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: card.state == "inactive" ? 16 : 19, weight: .semibold)
        titleLabel.textColor = textColor(for: card.state)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(titleLabel)

        let quantityLabel = UILabel()
        quantityLabel.text = card.quantity
        quantityLabel.textAlignment = .center
        quantityLabel.font = UIFont.systemFont(ofSize: card.state == "inactive" ? 12 : 46, weight: .bold)
        quantityLabel.textColor = textColor(for: card.state)
        quantityLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(quantityLabel)

        if let badge = card.badge {
            addBadge(text: badge, to: cardView, color: UIColor(red: 0.93, green: 0.55, blue: 0.10, alpha: 1))
        } else if card.state == "currentAdded" || card.state == "added" {
            addBadge(text: "✓ Added", to: cardView, color: UIColor(red: 0.10, green: 0.62, blue: 0.33, alpha: 1))
        } else {
            let dot = UIView()
            dot.backgroundColor = card.state == "current" ? .white : UIColor(red: 0.86, green: 0.88, blue: 0.91, alpha: 1)
            dot.layer.cornerRadius = 7
            dot.translatesAutoresizingMaskIntoConstraints = false
            cardView.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
                dot.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
                dot.widthAnchor.constraint(equalToConstant: 14),
                dot.heightAnchor.constraint(equalToConstant: 14),
            ])
        }

        let actionTitle = card.state == "current" ? "Mark added" : card.state == "currentAdded" ? "Add another" : nil
        var actionButton: UIButton?
        if let actionTitle = actionTitle {
            let button = UIButton(type: .system)
            button.setTitle(actionTitle, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            button.backgroundColor = .white
            button.layer.cornerRadius = 14
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: card.state == "current" ? #selector(markAddedTapped) : #selector(addAnotherTapped), for: .touchUpInside)
            cardView.addSubview(button)
            actionButton = button
        }

        NSLayoutConstraint.activate([
            cardView.widthAnchor.constraint(equalToConstant: card.state == "inactive" ? 116 : 132),
            cardView.heightAnchor.constraint(equalToConstant: card.state == "inactive" ? 168 : 182),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: card.state == "inactive" ? 35 : 42),
            quantityLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            quantityLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            quantityLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: card.state == "inactive" ? 48 : 4),
        ])

        if let actionButton = actionButton {
            NSLayoutConstraint.activate([
                actionButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
                actionButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
                actionButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -11),
                actionButton.heightAnchor.constraint(equalToConstant: 28),
            ])
        }

        return cardView
    }
```

- [ ] **Step 5: Add card color and badge helpers**

Add:

```swift
    private func backgroundColor(for state: String) -> UIColor {
        switch state {
        case "current", "currentAdded":
            return UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1)
        case "added":
            return UIColor(red: 0.88, green: 1.00, blue: 0.92, alpha: 1)
        default:
            return UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
        }
    }

    private func textColor(for state: String) -> UIColor {
        return state == "current" || state == "currentAdded" ? .white : UIColor(red: 0.17, green: 0.19, blue: 0.23, alpha: 1)
    }

    private func addBadge(text: String, to cardView: UIView, color: UIColor) {
        let badge = UILabel()
        badge.text = text
        badge.textAlignment = .center
        badge.textColor = .white
        badge.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        badge.backgroundColor = color
        badge.layer.cornerRadius = 11
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            badge.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 13),
            badge.widthAnchor.constraint(equalToConstant: text == "Manual" ? 72 : 78),
            badge.heightAnchor.constraint(equalToConstant: 22),
        ])
    }
```

- [ ] **Step 6: Implement `renderOverlay()`**

Replace placeholder `renderOverlay()` with:

```swift
    private func renderOverlay() {
        guard let payload = currentPayload else { return }

        carouselStack.arrangedSubviews.forEach { view in
            carouselStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for card in payload.cards {
            carouselStack.addArrangedSubview(makeCard(card))
        }

        let primaryTitle: String
        switch payload.primaryAction {
        case "nextCooldown":
            primaryTitle = "Next \(payload.cooldownSeconds ?? 0)s"
            progressView.isHidden = false
            progressView.progress = Float(payload.cooldownProgress ?? 0)
            styleActionButton(primaryButton, background: UIColor(red: 0.10, green: 0.62, blue: 0.33, alpha: 1), foreground: .white)
        default:
            primaryTitle = "Next"
            progressView.isHidden = true
            styleActionButton(primaryButton, background: UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1), foreground: .white)
        }
        primaryButton.setTitle(primaryTitle, for: .normal)

        secondaryButton.setTitle(payload.secondaryAction == "undo" ? "Undo" : "Previous", for: .normal)
    }
```

- [ ] **Step 7: Implement native button event actions**

Replace old `skipTapped` / `addedTapped` methods with:

```swift
    @objc private func secondaryTapped() {
        guard let payload = currentPayload else { return }
        plugin?.notifyEvent(eventName: payload.secondaryAction == "undo" ? "undoRequested" : "previousRequested")
    }

    @objc private func primaryTapped() {
        plugin?.notifyEvent(eventName: "nextRequested")
    }

    @objc private func markAddedTapped() {
        plugin?.notifyEvent(eventName: "markAddedRequested")
    }

    @objc private func addAnotherTapped() {
        plugin?.notifyEvent(eventName: "addAnotherRequested")
    }
```

- [ ] **Step 8: Build/sync**

Run from `packages/mobile`:

```bash
npm run build
npm run cap:sync
```

Expected: build and sync complete without Swift/Capacitor interface errors.

- [ ] **Step 9: Commit Task 5**

```bash
git add packages/store-session-plugin/ios/StoreSessionViewController.swift
git commit -m "feat: render native store session overlay"
```

---

### Task 6: Manual Verification On iOS Simulator Or Device

**Files:**
- No code files required unless verification finds defects.

**Interfaces:**
- Consumes: complete implementation from Tasks 1-5.
- Produces: verified runtime behavior matching the Figma flow.

- [ ] **Step 1: Sync native project**

Run from `packages/mobile`:

```bash
npm run build
npm run cap:sync
```

Expected: both commands complete successfully.

- [ ] **Step 2: Open iOS project**

Run from `packages/mobile`:

```bash
npm run cap:open
```

Expected: Xcode opens the iOS project.

- [ ] **Step 3: Verify automation-available state**

In the app:

1. Enter a short list with at least three items, including one with a quantity.
2. Start the wizard.
3. Confirm the store session opens in full-screen WKWebView.
4. Confirm the overlay shows overlapping product cards.
5. Confirm the active card has `Mark added`.
6. Confirm bottom buttons show `Previous` and `Next`.

- [ ] **Step 4: Verify mark-added and cooldown state**

In the store session:

1. Tap `Mark added` on the active card.
2. Confirm active card changes to `✓ Added` and `Add another`.
3. Confirm bottom buttons change to `Undo` and `Next 3s`.
4. Confirm the progress bar inside `Next 3s` advances.
5. Tap `Next 3s` and confirm the wizard advances immediately.

- [ ] **Step 5: Verify undo and add-another state**

In cooldown:

1. Tap `Undo`.
2. Confirm the active card returns to `Mark added` and bottom buttons return to `Previous` / `Next`.
3. Add again.
4. Tap `Add another` on the card.
5. Confirm the same item remains active with `Mark added`.

- [ ] **Step 6: Verify manual fallback state**

Trigger `automationTimeout` from the existing plugin flow or temporarily call the listener in Web Inspector:

```js
window.dispatchEvent(new Event('automationTimeout'))
```

If that does not trigger the Capacitor listener, temporarily add a debug button in local development only and remove it before commit.

Expected: active card shows `Manual` badge and still has `Mark added`; bottom buttons remain `Previous` / `Next`.

- [ ] **Step 7: Final command verification**

Run from `packages/mobile`:

```bash
npm test
npm run build
npm run cap:sync
```

Expected: all commands complete successfully.

- [ ] **Step 8: Commit verification fixes if any**

If manual verification required code changes:

```bash
git add packages/mobile packages/store-session-plugin packages/core
git commit -m "fix: polish native store overlay behavior"
```

If no code changes were required, do not create an empty commit.

---

## Self-Review

- Spec coverage: The plan covers the Figma states for automation available, no automation available/manual badge, and cooldown; it implements card-level actions and bottom navigation/recovery actions in native Swift.
- Placeholder scan: No task contains `TBD`, `TODO`, or unspecified tests. Each task includes concrete file paths, code snippets, commands, and expected outcomes.
- Type consistency: The TypeScript payload names match the Swift model fields: `mode`, `cards`, `activeIndex`, `primaryAction`, `secondaryAction`, `cooldownSeconds`, `cooldownProgress`, `itemName`, and `searchTerm`.
