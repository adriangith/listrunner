# iOS Store Session Added Card Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix added-card visual parity and preserve added status when selecting an already-added carousel card.

**Architecture:** TypeScript/Core owns wizard state and must not erase completion status during card selection. TypeScript/Mobile turns wizard state into overlay card states. Swift renders those states with Figma-style card visuals, keeping the existing native event names and carousel geometry.

**Tech Stack:** TypeScript, Node test runner, Swift/UIKit, Capacitor iOS plugin, Xcode simulator build.

## Global Constraints

- No new dependencies.
- Preserve existing card sizes, carousel overscan, buttons, and event names.
- Card tap must continue emitting the original payload index.
- Tapping an added card should center/search that item but keep added visual state.
- Verification must include local package tests, mobile tests/build/sync, and remote Mac simulator build.

---

## File Structure

- `packages/core/src/wizard.ts`: update `SELECT_INDEX` so selecting an already-added item does not rewrite its status to `active`.
- `packages/core/tests/wizard.test.ts`: add reducer regression coverage for selecting an added item.
- `packages/mobile/src/store-session-overlay.ts`: ensure overlay card state prefers `added` over `current` for items whose completion status is already `added`.
- `packages/mobile/tests/store-session-overlay.test.mjs`: add payload regression coverage for selected added cards.
- `packages/store-session-plugin/ios/StoreSessionViewController.swift`: add green added gradient, remove marker dots, add quantity pills, and shift the added label left.
- `packages/store-session-plugin/tests/ios-overlay-parity.test.mjs`: add Swift source-level parity checks for the visual changes.

---

### Task 1: Preserve Added Status During Card Selection

**Files:**
- Modify: `packages/core/src/wizard.ts`
- Test: `packages/core/tests/wizard.test.ts`

**Interfaces:**
- Consumes: existing `wizardReducer(state, { type: "SELECT_INDEX", index })`.
- Produces: unchanged reducer API; selected added items keep `status: "added"`.

- [ ] **Step 1: Write the failing reducer test**

Append this test near the existing `SELECT_INDEX` tests in `packages/core/tests/wizard.test.ts`:

```ts
  it("keeps an added item added when selected by index", () => {
    let state = createWizardState();
    state = wizardReducer(state, { type: "START", items: testItems });
    state = wizardReducer(state, { type: "ADVANCE" });
    state = wizardReducer(state, { type: "COOLDOWN_COMPLETE" });

    state = wizardReducer(state, { type: "SELECT_INDEX", index: 0 });

    expect(state.status).toBe("stepping");
    expect(state.currentIndex).toBe(0);
    expect(state.items[0]?.status).toBe("added");
  });
```

- [ ] **Step 2: Run the reducer test to verify it fails**

Run: `npm test -- tests/wizard.test.ts`

Expected: FAIL because `state.items[0]?.status` is currently `active`.

- [ ] **Step 3: Implement the minimal reducer fix**

In `packages/core/src/wizard.ts`, replace the selected-index assignment:

```ts
  items[index] = { ...items[index]!, status: "active" };
```

with:

```ts
  if (items[index]?.status !== "added") {
    items[index] = { ...items[index]!, status: "active" };
  }
```

- [ ] **Step 4: Run reducer tests**

Run: `npm test -- tests/wizard.test.ts`

Expected: PASS.

---

### Task 2: Keep Selected Added Cards Added In Overlay Payload

**Files:**
- Modify: `packages/mobile/src/store-session-overlay.ts`
- Test: `packages/mobile/tests/store-session-overlay.test.mjs`

**Interfaces:**
- Consumes: `buildStoreSessionOverlayPayload({ state, automationUnavailable, cooldownRemainingMs, cooldownTotalMs })`.
- Produces: unchanged payload shape; added items produce `card.state === "added"` even if selected.

- [ ] **Step 1: Write the failing overlay payload test**

Append this test to `packages/mobile/tests/store-session-overlay.test.mjs`:

```js
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
```

- [ ] **Step 2: Run the mobile overlay test to verify behavior**

Run: `npm test -- tests/store-session-overlay.test.mjs`

Expected before Task 1 fix: FAIL because the reducer rewrites the item to `active`. Expected after Task 1 fix: PASS if the current payload logic already prefers item status before active status.

- [ ] **Step 3: If needed, make payload state precedence explicit**

If Step 2 still fails, change `cardFromItem` state selection in `packages/mobile/src/store-session-overlay.ts` to prefer `item.status === "added"` before `isActive`:

```ts
    state: isCooldownActive
      ? "currentAdded"
      : item.status === "added"
        ? "added"
        : isActive
          ? "current"
          : "inactive",
```

- [ ] **Step 4: Run mobile overlay tests**

Run: `npm test -- tests/store-session-overlay.test.mjs`

Expected: PASS.

---

### Task 3: Render Added Gradients, Quantity Pills, And No Marker Dots

**Files:**
- Modify: `packages/store-session-plugin/ios/StoreSessionViewController.swift`
- Test: `packages/store-session-plugin/tests/ios-overlay-parity.test.mjs`

**Interfaces:**
- Consumes: existing Swift `StoreSessionOverlayCard.state` values: `current`, `inactive`, `added`, `currentAdded`.
- Produces: same native event model and card index behavior; changed visuals only.

- [ ] **Step 1: Write failing Swift parity tests**

Append these tests to `packages/store-session-plugin/tests/ios-overlay-parity.test.mjs`:

```js
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
```

- [ ] **Step 2: Run Swift parity tests to verify they fail**

Run: `npm test -- tests/ios-overlay-parity.test.mjs`

Expected: FAIL on the new visual parity checks.

- [ ] **Step 3: Add helper methods in Swift**

In `packages/store-session-plugin/ios/StoreSessionViewController.swift`, add these helpers near the existing visual helpers:

```swift
    private func isAddedState(_ state: String) -> Bool {
        return state == "added" || state == "currentAdded"
    }

    private func applyAddedGradient(to cardView: UIView) {
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(red: 0.78, green: 0.93, blue: 0.69, alpha: 1).cgColor,
            UIColor(red: 0.55, green: 0.83, blue: 0.48, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0.0, y: 0.0)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradient.cornerRadius = 18
        gradient.frame = cardView.bounds
        cardView.layer.insertSublayer(gradient, at: 0)
    }

    private func makeQuantityPill(text: String, state: String) -> UILabel {
        let quantityPill = UILabel()
        quantityPill.text = text
        quantityPill.textAlignment = .center
        quantityPill.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        quantityPill.textColor = textColor(for: state)
        quantityPill.backgroundColor = UIColor.white.withAlphaComponent(isAddedState(state) ? 0.58 : 0.72)
        quantityPill.layer.cornerRadius = 12
        quantityPill.clipsToBounds = true
        quantityPill.translatesAutoresizingMaskIntoConstraints = false
        return quantityPill
    }
```

- [ ] **Step 4: Apply helpers in `makeCard`**

In `makeCard`, after configuring `cardView`, apply the gradient conditionally:

```swift
        if isAddedState(card.state) {
            applyAddedGradient(to: cardView)
        }
```

Remove the entire `else` block that creates `let dot = UIView()`.

Replace the plain non-selected quantity label setup with a pill path:

```swift
        let quantityLabel = UILabel()
        quantityLabel.text = card.quantity
        quantityLabel.textAlignment = .center
        quantityLabel.font = UIFont.systemFont(ofSize: card.state == "inactive" || card.state == "added" ? 12 : 46, weight: .bold)
        quantityLabel.textColor = textColor(for: card.state)
        quantityLabel.translatesAutoresizingMaskIntoConstraints = false

        let quantityPill = card.state == "inactive" || card.state == "added"
            ? makeQuantityPill(text: card.quantity, state: card.state)
            : nil

        if let quantityPill = quantityPill {
            cardView.addSubview(quantityPill)
        } else {
            cardView.addSubview(quantityLabel)
        }
```

Update the added label leading constraint:

```swift
                addedLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
```

Update the quantity constraints so the pill and plain label are constrained separately:

```swift
        var constraints: [NSLayoutConstraint] = [
            cardView.widthAnchor.constraint(equalToConstant: card.state == "current" || card.state == "currentAdded" ? 132 : 116),
            cardView.heightAnchor.constraint(equalToConstant: card.state == "current" || card.state == "currentAdded" ? 182 : card.state == "added" ? 166 : 177),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: card.state == "added" ? 6 : 14),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: card.state == "added" ? -6 : -14),
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: card.state == "current" ? 22 : card.state == "currentAdded" ? 29 : card.state == "added" ? 27 : 31),
        ]

        if let quantityPill = quantityPill {
            constraints.append(contentsOf: [
                quantityPill.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
                quantityPill.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 44),
                quantityPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),
                quantityPill.heightAnchor.constraint(equalToConstant: 24),
            ])
        } else {
            constraints.append(contentsOf: [
                quantityLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
                quantityLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
                quantityLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            ])
        }

        NSLayoutConstraint.activate(constraints)
```

- [ ] **Step 5: Run Swift parity tests**

Run: `npm test -- tests/ios-overlay-parity.test.mjs`
Expected: PASS.

---

### Task 4: Verify And Sync To Mac

**Files:**
- Verify only; no intentional source changes unless tests expose a defect.

**Interfaces:**
- Consumes: completed Tasks 1-3.
- Produces: local and remote verified implementation.

- [ ] **Step 1: Run local package checks**

Run from `packages/core`: `npm test -- tests/wizard.test.ts`
Expected: PASS.

Run from `packages/mobile`: `npm test && npm run build && npm run cap:sync`
Expected: PASS and Capacitor sync completes.

Run from `packages/store-session-plugin`: `npm test && npm run build`
Expected: PASS.

- [ ] **Step 2: Copy changed files to the Mac test checkout**

Run from repo root:

```bash
scp "packages/core/src/wizard.ts" adrianzafir@192.168.4.182:"/Users/adrianzafir/Projects/listrunner-ios-test/packages/core/src/wizard.ts"
scp "packages/core/tests/wizard.test.ts" adrianzafir@192.168.4.182:"/Users/adrianzafir/Projects/listrunner-ios-test/packages/core/tests/wizard.test.ts"
scp "packages/mobile/src/store-session-overlay.ts" adrianzafir@192.168.4.182:"/Users/adrianzafir/Projects/listrunner-ios-test/packages/mobile/src/store-session-overlay.ts"
scp "packages/mobile/tests/store-session-overlay.test.mjs" adrianzafir@192.168.4.182:"/Users/adrianzafir/Projects/listrunner-ios-test/packages/mobile/tests/store-session-overlay.test.mjs"
scp "packages/store-session-plugin/ios/StoreSessionViewController.swift" adrianzafir@192.168.4.182:"/Users/adrianzafir/Projects/listrunner-ios-test/packages/store-session-plugin/ios/StoreSessionViewController.swift"
scp "packages/store-session-plugin/tests/ios-overlay-parity.test.mjs" adrianzafir@192.168.4.182:"/Users/adrianzafir/Projects/listrunner-ios-test/packages/store-session-plugin/tests/ios-overlay-parity.test.mjs"
```

- [ ] **Step 3: Run remote Mac checks**

Run from repo root:

```bash
ssh adrianzafir@192.168.4.182 'zsh -lc "cd /Users/adrianzafir/Projects/listrunner-ios-test/packages/core && npm test -- tests/wizard.test.ts"'
ssh adrianzafir@192.168.4.182 'zsh -lc "cd /Users/adrianzafir/Projects/listrunner-ios-test/packages/store-session-plugin && npm test && npm run build"'
ssh adrianzafir@192.168.4.182 'zsh -lc "cd /Users/adrianzafir/Projects/listrunner-ios-test/packages/mobile && npm test && npm run build && npm run cap:sync"'
ssh adrianzafir@192.168.4.182 'zsh -lc "cd /Users/adrianzafir/Projects/listrunner-ios-test/packages/mobile/ios/App && xcodebuild -project App.xcodeproj -scheme App -configuration Debug -destination \"generic/platform=iOS Simulator\" build"'
```

Expected: all commands pass and Xcode output ends with `** BUILD SUCCEEDED **`.

---

## Self-Review

- Spec coverage: all reported issues map to Tasks 1-3; verification maps to Task 4.
- Placeholder scan: no TBD/TODO/fill-in placeholders remain.
- Type consistency: all state strings match existing `WizardItem.status` and `StoreSessionOverlayCardState` values.
