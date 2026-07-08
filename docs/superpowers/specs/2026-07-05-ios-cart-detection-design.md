# iOS Cart Auto-Detection Design

> **Status:** Approved
> **Date:** 2026-07-05
> **Goal:** Detect "add to cart" button taps on coles.com.au inside the iOS app's WKWebView and auto-advance the ListRunner wizard — porting the desktop Chrome extension's content-script logic to the native bridge.

## Problem

The desktop ListRunner Chrome extension (`packages/extension/src/content/content-script.ts`) detects taps on Coles "Add to cart" buttons, extracts product info, and messages the side panel so the wizard records the item as added and advances.

The iOS app (`packages/store-session-plugin/ios/StoreSessionViewController.swift`) loads coles.com.au inside a WKWebView with a floating native overlay. The overlay's native "Added" button fires `addToCartDetected` directly — but tapping "Add to cart" on coles.com.au itself is invisible to ListRunner. There is no JavaScript injected into the Coles page that observes add-to-cart clicks.

Result: tapping "Add" on coles.com.au inside the iOS app does nothing — the wizard stays on the same item.

## Solution

Inject a content script into the WKWebView that mirrors the desktop extension's click detection and product-info extraction. The script posts results to the existing `storeSessionBridge` message handler, which already routes `addToCartDetected` events to the Capacitor plugin → `main.ts` `handleAdded` → `sendAction("ADVANCE")`.

## Architecture

```
coles.com.au page (WKWebView)
  │
  ├─ document.addEventListener("click", handleCartClick, true)   ← capture phase
  │     └─ match add-to-cart selector
  │          └─ extractProductInfo(addButton)
  │               └─ postMessage({type:"addToCartDetected", productName, productImageUrl})
  │
  └─ document-end: postMessage({type:"pageLoaded"})
                                                 │
                                                 ▼
                              storeSessionBridge (WKScriptMessageHandler)
                                                 │
                                                 ▼
                              StoreSessionPlugin.notifyEvent("addToCartDetected", data)
                                                 │
                                                 ▼
                              Capacitor → main.ts handleAdded() → sendAction("ADVANCE")
```

The native overlay's "Added" button (`addedTapped` in `StoreSessionViewController.swift`) is kept as a manual fallback — it fires the same `addToCartDetected` event.

## Components

### 1. Content script: `packages/store-session-plugin/ios/Resources/cart-detection.js`

A plain JavaScript file loaded as a SPM resource via `Bundle.module`. Single-responsibility: detect add-to-cart clicks on coles.com.au and post product info to the native bridge.

**Behavior:**

- At document end, post `{type: "pageLoaded"}` to `window.webkit.messageHandlers.storeSessionBridge` (merges the existing one-line injected script — no duplication).
- Register a capture-phase `click` listener on `document` (survives SPA re-renders; re-injects automatically on full page navigation because `WKUserScript` runs at document end on every full load).
- On each click, match `event.target.closest("button[data-testid='add-to-cart-button'], button.add-to-cart")`. If no match, silently return.
- On match, call `extractProductInfo(addButton)` — a 1:1 port of the TypeScript `extractProductInfo` from `packages/extension/src/content/content-script.ts`:
  1. **Product tile lookup:** `addButton.closest("[class*='product'], [data-testid*='product'], article, .tile, li")`, then `querySelector(cfg.cart.productNameSelector)` for the name and `cfg.cart.productImageSelector` for the image (`currentSrc || src || data-src`).
  2. **Fallback — page metadata:** `og:title` meta → `itemprop="name"` → first `h1` → page title (stripped of ` | Store` tail).
  3. **Image fallback:** `og:image` meta → `img[itemprop='image']` `currentSrc || src`.
  4. Default to `"Unknown product"` if name extraction returns empty.
- Wrap the `postMessage` call in a guard so a navigation away mid-click doesn't throw.

**Selectors are hardcoded for `coles-au`** (matching the existing `if storeId == "coles-au"` Swift branch). Multi-store config driven by `storeId` is out of scope — YAGNI.

The selectors used (matching `packages/extension/src/store-configs/coles-au.ts`):
- `addToCartSelector`: `"button[data-testid='add-to-cart-button'], button.add-to-cart"`
- `productNameSelector`: from `coles-au.ts` (`cfg.cart.productNameSelector`)
- `productImageSelector`: from `coles-au.ts` (`cfg.cart.productImageSelector`)

### 2. `StoreSessionViewController.swift` changes

- Remove the inline `WKUserScript` source string (the one-line `pageLoaded` post).
- Load `cart-detection.js` from `Bundle.module` and inject as a single `WKUserScript` at `.atDocumentEnd` with `forMainFrameOnly: true`.
- `userContentController(_:didReceive:)` is unchanged — it already routes `addToCartDetected` and `pageLoaded`.
- `addedTapped` (native overlay "Added" button) unchanged — kept as manual fallback.

### 3. `Package.swift` resources

Add `resources: [.copy("Resources")]` to the `ListrunnerStoreSession` target in `packages/store-session-plugin/Package.swift` so `Bundle.module` exposes `cart-detection.js`.

### 4. Tests

**`packages/store-session-plugin/tests/cart-detection.test.mjs`** — source-level test (reads the `.js` file) asserting:
- Capture-phase `document.addEventListener("click", ..., true)`
- Add-to-cart selector string present
- `postMessage` call with `type: "addToCartDetected"` and `productName` / `productImageUrl` keys
- `extractProductInfo` function present
- `pageLoaded` post at document end
- Guard around `postMessage` (no bare `window.webkit.messageHandlers.storeSessionBridge.postMessage` without a guard)

**`packages/store-session-plugin/tests/ios-injection.test.mjs`** — source-level test on `StoreSessionViewController.swift` asserting:
- Loads `cart-detection.js` from `Bundle.module` (regex: `Bundle.module.url\(forResource: "cart-detection"`)
- Registers a `WKUserScript` at `.atDocumentEnd`
- No remaining inline `pageLoaded` script source string (verifies the merge removed duplication)

## Data Flow

1. User taps "Add to cart" on coles.com.au inside the WKWebView.
2. `cart-detection.js` capture-phase click listener fires.
3. Target matches the add-to-cart selector → `extractProductInfo(addButton)` runs.
4. Script posts `{type: "addToCartDetected", productName, productImageUrl}` to `storeSessionBridge`.
5. `StoreSessionViewController.userContentController(_:didReceive:)` routes it: calls `plugin?.notifyEvent(eventName: "addToCartDetected", data: ...)`.
6. Capacitor delivers the event to `main.ts`'s `StoreSession.addListener("addToCartDetected", (info) => handleAdded(info))`.
7. `handleAdded(info)` records history, fires `tryCompleteReminder` for Paprika items, calls `sendAction("ADVANCE")`.
8. Wizard advances to the next item.

## Error Handling

- **Click misses selector:** silently return (matches desktop).
- **Product name empty after extraction:** default to `"Unknown product"` (matches desktop).
- **`window.webkit.messageHandlers.storeSessionBridge` unavailable** (page navigated away mid-click): wrap the post in a guard so the script doesn't throw.
- **Script fails to load from bundle:** `WKUserScript` injection silently no-ops; the native overlay "Added" button still works as fallback.

## Out of Scope

- Multi-store config driven by `storeId` (coles-au only; selectors are constants in `cart-detection.js`).
- The `dom-mutation` cart-count observer path (desktop's secondary fallback). Click detection is the primary path and sufficient for the first version.
- Changes to `main.ts`, the wizard reducer, or the Capacitor plugin TypeScript interface — the `addToCartDetected` event already flows through to advancement correctly.
- Removing the native overlay "Added" button — kept as a manual fallback per design decision.

## Testing Strategy

- Source-level tests on both `cart-detection.js` and `StoreSessionViewController.swift` (Node reads file contents; asserts against regex). Same pattern as the existing `packages/store-session-plugin/tests/ios-view-loading.test.mjs`.
- Mac build verification: `cap sync` + unsigned Xcode build must succeed (Swift compiles, SPM resource bundles correctly).

## Relevant Files

- `packages/extension/src/content/content-script.ts` — desktop source being ported (lines 118–130, 209–298).
- `packages/extension/src/store-configs/coles-au.ts` — selector source of truth.
- `packages/store-session-plugin/ios/StoreSessionViewController.swift` — Swift integration point; the old duplicate plugin copies under `packages/mobile` have been removed.
- `packages/store-session-plugin/Package.swift` — needs `resources` declaration.
- `packages/store-session-plugin/tests/ios-view-loading.test.mjs` — existing source-level test pattern to mirror.
- `packages/mobile/src/main.ts` — already correctly routes `addToCartDetected` → `handleAdded` → `sendAction("ADVANCE")`. No changes.
