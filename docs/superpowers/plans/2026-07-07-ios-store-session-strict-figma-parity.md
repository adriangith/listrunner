# iOS Store Session Strict Figma Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the native iOS store-session overlay match the `Current Mobile UI` Figma overlay frames for automation available, manual/no automation, and cooldown states.

**Architecture:** Keep the existing TypeScript wizard state and Capacitor bridge. Make one small payload cleanup so manual mode is represented by `payload.mode` rather than a card badge, then implement the Figma visual parity in the UIKit renderer. Add source-level Swift parity tests because this repo already uses Node tests to guard Swift source behavior.

**Tech Stack:** TypeScript, Node test runner, Capacitor 8, Swift UIKit, WKWebView.

## Global Constraints

- Figma page `Current Mobile UI` is the canonical visual source.
- Native iOS implementation target is `packages/store-session-plugin/ios/StoreSessionViewController.swift`.
- Preserve the full-screen `WKWebView` website content.
- Do not change parser behavior, wizard state transitions, cart detection, or browser automation behavior.
- Keep implementation UIKit-only; do not introduce SwiftUI.
- Do not add new package dependencies.
- Do not edit the old duplicated Swift plugin copies under `packages/mobile/src/plugins/store-session/ios` or `packages/mobile/ios/Plugins/StoreSession`.

---

## File Structure

- Modify `packages/mobile/tests/store-session-overlay.test.mjs`: update the manual-mode payload expectation so card badges are not used for Figma manual state.
- Modify `packages/mobile/src/store-session-overlay.ts`: stop putting `Manual` on the active card; Swift will render manual mode from `payload.mode`.
- Create `packages/store-session-plugin/tests/ios-overlay-parity.test.mjs`: source-level tests for Figma-critical Swift renderer details.
- Modify `packages/store-session-plugin/ios/StoreSessionViewController.swift`: render Figma-matched panel, carousel, card states, labels, manual badge, and cooldown button progress.

---

### Task 1: Remove Manual Badge From Card Payload

**Files:**
- Modify: `packages/mobile/tests/store-session-overlay.test.mjs`
- Modify: `packages/mobile/src/store-session-overlay.ts`

**Interfaces:**
- Consumes: `buildStoreSessionOverlayPayload(options: BuildStoreSessionOverlayPayloadOptions): StoreSessionOverlayPayload`
- Produces: manual payloads where `payload.mode === "manual"` and every `StoreSessionOverlayCard.badge === null`

- [ ] **Step 1: Write the failing mobile payload test**

Replace the manual-mode assertions in `packages/mobile/tests/store-session-overlay.test.mjs` with this block:

```js
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
```

- [ ] **Step 2: Run the mobile test to verify failure**

Run from `packages/mobile`:

```bash
npm test -- store-session-overlay.test.mjs
```

Expected: FAIL because the current payload builder sets `payload.cards[0].badge` to `"Manual"`.

- [ ] **Step 3: Update the payload builder**

In `packages/mobile/src/store-session-overlay.ts`, change `cardFromItem()` so it returns `badge: null` for all cards:

```ts
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
    badge: null,
  };
```

Do not remove the `badge` property from the TypeScript interfaces in this task; keeping it nullable avoids bridge/interface churn.

- [ ] **Step 4: Run the mobile tests**

Run from `packages/mobile`:

```bash
npm test
```

Expected: PASS for all mobile tests.

- [ ] **Step 5: Run the mobile build**

Run from `packages/mobile`:

```bash
npm run build
```

Expected: PASS with Vite build output and no TypeScript errors.

---

### Task 2: Add Swift Source-Level Parity Tests

**Files:**
- Create: `packages/store-session-plugin/tests/ios-overlay-parity.test.mjs`

**Interfaces:**
- Consumes: Swift source text at `packages/store-session-plugin/ios/StoreSessionViewController.swift`
- Produces: Node tests that fail until the Swift renderer exposes Figma-parity implementation markers

- [ ] **Step 1: Create the failing parity test file**

Create `packages/store-session-plugin/tests/ios-overlay-parity.test.mjs`:

```js
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
```

- [ ] **Step 2: Run store-session tests to verify failure**

Run from `packages/store-session-plugin`:

```bash
npm test
```

Expected: FAIL in `ios-overlay-parity.test.mjs` because the Swift renderer still renders `Next`, uses card badges, treats `currentAdded` as blue, and uses different carousel geometry.

---

### Task 3: Implement Figma-Parity Swift Renderer

**Files:**
- Modify: `packages/store-session-plugin/ios/StoreSessionViewController.swift`

**Interfaces:**
- Consumes: existing `StoreSessionOverlayPayload` and `StoreSessionOverlayCard`
- Produces: UIKit overlay matching Figma geometry and state presentation while preserving existing plugin events

- [ ] **Step 1: Add renderer state properties**

In `StoreSessionViewController.swift`, replace the property block near the existing carousel/button properties with this full block:

```swift
    var overlayView: UIView!
    private let carouselScrollView = UIScrollView()
    private let carouselStack = UIStackView()
    private let secondaryButton = UIButton(type: .system)
    private let primaryButton = UIButton(type: .system)
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let panelGradientLayer = CAGradientLayer()
    private var manualBadgeView: UILabel?
    var plugin: StoreSessionPlugin?
```

Keep the existing `currentPayload`, `activeStoreId`, `pendingStoreURL`, and `automationLoaded` properties below this block.

- [ ] **Step 2: Replace `setupOverlay()`**

Replace the entire `setupOverlay()` function with:

```swift
    private func setupOverlay() {
        overlayView = OverlayHitView()
        overlayView.backgroundColor = .clear
        overlayView.layer.shadowColor = UIColor.black.cgColor
        overlayView.layer.shadowOpacity = 0.08
        overlayView.layer.shadowRadius = 18
        overlayView.layer.shadowOffset = CGSize(width: 0, height: -8)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)

        panelGradientLayer.type = .radial
        panelGradientLayer.colors = [
            UIColor.white.withAlphaComponent(0.98).cgColor,
            UIColor.white.withAlphaComponent(0.94).cgColor,
        ]
        panelGradientLayer.locations = [0, 1]
        panelGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        panelGradientLayer.endPoint = CGPoint(x: 0.95, y: 1.0)
        overlayView.layer.insertSublayer(panelGradientLayer, at: 0)

        carouselScrollView.showsHorizontalScrollIndicator = false
        carouselScrollView.alwaysBounceHorizontal = true
        carouselScrollView.clipsToBounds = false
        carouselScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(carouselScrollView)

        carouselStack.axis = .horizontal
        carouselStack.alignment = .center
        carouselStack.distribution = .fill
        carouselStack.spacing = 10
        carouselStack.translatesAutoresizingMaskIntoConstraints = false
        carouselScrollView.addSubview(carouselStack)

        secondaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(secondaryButton)
        overlayView.addSubview(primaryButton)
        primaryButton.addSubview(progressView)

        styleActionButton(secondaryButton, background: UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1), foreground: UIColor(red: 0.17, green: 0.19, blue: 0.23, alpha: 1))
        styleActionButton(primaryButton, background: UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1), foreground: .white)

        secondaryButton.addTarget(self, action: #selector(secondaryTapped), for: .touchUpInside)
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayView.heightAnchor.constraint(equalToConstant: 202),

            carouselScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -43),
            carouselScrollView.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: -46),
            carouselScrollView.widthAnchor.constraint(equalToConstant: 482),
            carouselScrollView.heightAnchor.constraint(equalToConstant: 120),

            carouselStack.leadingAnchor.constraint(equalTo: carouselScrollView.contentLayoutGuide.leadingAnchor),
            carouselStack.trailingAnchor.constraint(equalTo: carouselScrollView.contentLayoutGuide.trailingAnchor),
            carouselStack.topAnchor.constraint(equalTo: carouselScrollView.contentLayoutGuide.topAnchor, constant: -47),
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

- [ ] **Step 3: Replace state color helpers**

Replace `backgroundColor(for:)` and `textColor(for:)` with:

```swift
    private func isBlueCurrentState(_ state: String) -> Bool {
        return state == "current"
    }

    private func backgroundColor(for state: String) -> UIColor {
        if isBlueCurrentState(state) {
            return UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1)
        }
        return UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
    }

    private func textColor(for state: String) -> UIColor {
        return isBlueCurrentState(state) ? .white : UIColor(red: 0.17, green: 0.19, blue: 0.23, alpha: 1)
    }

    private func actionTextColor(for state: String) -> UIColor {
        return state == "currentAdded"
            ? UIColor(red: 0.12, green: 0.65, blue: 0.19, alpha: 1)
            : UIColor(red: 0.00, green: 0.32, blue: 0.88, alpha: 1)
    }
```

- [ ] **Step 4: Replace badge helpers**

Delete `addBadge(text:to:color:)` and add these helpers in its place:

```swift
    private func makeAddedStateLabel() -> UILabel {
        let label = UILabel()
        label.text = "✓ Added"
        label.textAlignment = .center
        label.textColor = UIColor(red: 0.17, green: 0.19, blue: 0.23, alpha: 1)
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeManualBadge() -> UILabel {
        let badge = UILabel()
        badge.text = "Manual"
        badge.textAlignment = .center
        badge.textColor = .white
        badge.font = UIFont.systemFont(ofSize: 8, weight: .semibold)
        badge.backgroundColor = UIColor(red: 0.70, green: 0.70, blue: 0.70, alpha: 1)
        badge.layer.cornerRadius = 4
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        return badge
    }

    private func updateManualBadge(for payload: StoreSessionOverlayPayload) {
        manualBadgeView?.removeFromSuperview()
        manualBadgeView = nil

        guard payload.mode == "manual" else { return }

        let badge = makeManualBadge()
        overlayView.addSubview(badge)
        manualBadgeView = badge

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 134),
            badge.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 90),
            badge.widthAnchor.constraint(equalToConstant: 72),
            badge.heightAnchor.constraint(equalToConstant: 16),
        ])
    }
```

- [ ] **Step 5: Replace `makeCard(_:index:)`**

Replace the entire `makeCard(_ card: StoreSessionOverlayCard, index: Int) -> UIView` function with:

```swift
    private func makeCard(_ card: StoreSessionOverlayCard, index: Int) -> UIView {
        let cardView = UIView()
        cardView.isUserInteractionEnabled = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 18
        cardView.clipsToBounds = false
        cardView.backgroundColor = backgroundColor(for: card.state)
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.12
        cardView.layer.shadowRadius = 12
        cardView.layer.shadowOffset = CGSize(width: 0, height: 6)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(cardTapped(_:)))
        tapGesture.name = String(index)
        tapGesture.delegate = self
        cardView.addGestureRecognizer(tapGesture)

        let titleLabel = UILabel()
        titleLabel.text = card.title
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: card.state == "inactive" || card.state == "added" ? 16 : 19, weight: .semibold)
        titleLabel.textColor = textColor(for: card.state)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(titleLabel)

        let quantityLabel = UILabel()
        quantityLabel.text = card.quantity
        quantityLabel.textAlignment = .center
        quantityLabel.font = UIFont.systemFont(ofSize: card.state == "inactive" || card.state == "added" ? 12 : 46, weight: .bold)
        quantityLabel.textColor = textColor(for: card.state)
        quantityLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(quantityLabel)

        if card.state == "added" || card.state == "currentAdded" {
            let addedLabel = makeAddedStateLabel()
            cardView.addSubview(addedLabel)
            NSLayoutConstraint.activate([
                addedLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
                addedLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: card.state == "currentAdded" ? 11 : 9),
                addedLabel.widthAnchor.constraint(equalToConstant: card.state == "currentAdded" ? 72 : 88),
                addedLabel.heightAnchor.constraint(equalToConstant: 14),
            ])
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
            button.setTitleColor(actionTextColor(for: card.state), for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            button.backgroundColor = .white
            button.layer.cornerRadius = 14
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: card.state == "current" ? #selector(markAddedTapped) : #selector(addAnotherTapped), for: .touchUpInside)
            cardView.addSubview(button)
            actionButton = button
        }

        NSLayoutConstraint.activate([
            cardView.widthAnchor.constraint(equalToConstant: card.state == "current" || card.state == "currentAdded" ? 132 : 116),
            cardView.heightAnchor.constraint(equalToConstant: card.state == "current" || card.state == "currentAdded" ? 182 : card.state == "added" ? 166 : 177),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: card.state == "added" ? 6 : 14),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: card.state == "added" ? -6 : -14),
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: card.state == "current" ? 22 : card.state == "currentAdded" ? 42 : card.state == "added" ? 27 : 31),
            quantityLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            quantityLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            quantityLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: card.state == "inactive" || card.state == "added" ? 48 : 4),
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

- [ ] **Step 6: Update `renderOverlay()` labels and manual badge**

Inside `renderOverlay()`, after the loop that adds cards, add:

```swift
        updateManualBadge(for: payload)
```

Then replace the non-cooldown `primaryTitle` default branch with:

```swift
        default:
            primaryTitle = "Skip"
            progressView.isHidden = true
            styleActionButton(primaryButton, background: UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1), foreground: .white)
```

Keep the cooldown branch as `Next \(payload.cooldownSeconds ?? 0)s` with the green button.

- [ ] **Step 7: Update layout lifecycle**

Replace `viewDidLayoutSubviews()` with:

```swift
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        webView.frame = view.bounds
        panelGradientLayer.frame = overlayView.bounds
    }
```

- [ ] **Step 8: Run store-session tests**

Run from `packages/store-session-plugin`:

```bash
npm test
```

Expected: PASS for all store-session plugin tests, including `ios-overlay-parity.test.mjs`.

- [ ] **Step 9: Build the store-session plugin TypeScript package**

Run from `packages/store-session-plugin`:

```bash
npm run build
```

Expected: PASS with no TypeScript errors.

---

### Task 4: Final Mobile Build And Runtime Verification

**Files:**
- No code files changed in this task unless verification exposes an implementation bug.

**Interfaces:**
- Consumes: Task 1 payload cleanup and Task 3 Swift renderer changes
- Produces: verified local build artifacts and a runtime checklist for iOS visual parity

- [ ] **Step 1: Run all package tests touched by the parity work**

Run from repo root:

```bash
npm test --workspace packages/mobile
npm test --workspace packages/store-session-plugin
```

If the repo root does not support npm workspaces in this checkout, run the equivalent commands from each package:

```bash
cd packages/mobile && npm test
cd ../store-session-plugin && npm test
```

Expected: both package test suites pass.

- [ ] **Step 2: Build the mobile package**

Run from `packages/mobile`:

```bash
npm run build
```

Expected: PASS with Vite build output.

- [ ] **Step 3: Sync Capacitor iOS assets if the environment supports it**

Run from `packages/mobile`:

```bash
npm run cap:sync
```

Expected: PASS. If this headless environment lacks native iOS tooling, record the failure reason and continue to Step 4 on an iOS-capable machine.

- [ ] **Step 4: Verify in iOS runtime**

On an iOS simulator or device, open a store session and check these visual requirements against Figma page `Current Mobile UI`:

```text
Automation available:
- Bottom panel sits at y=650 and height=202 on a 393x852 frame.
- Secondary button reads Previous.
- Primary button reads Skip.
- Current card is blue, 132x182, with Mark added card action.
- Neighbor cards are partially visible in the carousel.

No automation available:
- Primary button still reads Skip.
- Manual badge appears in the bottom overlay panel around x=134, y=740 absolute frame position.
- Manual badge does not appear on the product card.

Cooldown:
- Secondary button reads Undo.
- Primary button is green and reads Next Ns.
- Progress track/fill appears inside the green primary button.
- Current-added card is neutral, not blue.
- Current-added card shows ✓ Added and Add another.
```

Expected: all checklist items match the Figma frames closely enough that remaining differences are only store webpage content behind the overlay.

---

## Self-Review

- Spec coverage: Tasks cover payload cleanup, bottom-panel manual badge, non-cooldown `Skip` label, cooldown button/progress, neutral current-added card, text added labels, carousel overscan geometry, and event preservation.
- Placeholder scan: No TBD/TODO/fill-in-later placeholders remain.
- Type consistency: Existing payload types are preserved. `badge` remains nullable for bridge compatibility. New Swift helper names are introduced before tests assert them.
