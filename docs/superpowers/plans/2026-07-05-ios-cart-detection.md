# iOS Cart Auto-Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inject a content script into the iOS app's WKWebView that detects "add to cart" clicks on coles.com.au, extracts product info, and posts to the native bridge so the wizard auto-advances — porting the desktop Chrome extension's content-script logic.

**Architecture:** A plain JavaScript file (`cart-detection.js`) is loaded as an SPM resource via `Bundle.module` and injected as a `WKUserScript` at document end. It registers a capture-phase click listener, matches add-to-cart button clicks, extracts product name/image (with fallbacks to page metadata), and posts `addToCartDetected` through the existing `storeSessionBridge` message handler. The native overlay's "Added" button remains as a manual fallback.

**Tech Stack:** Swift (WKWebView/WKUserScript/WKScriptMessageHandler), JavaScript (plain, no framework), SPM resources, Node test runner (`node --test tests/*.test.mjs`)

## Global Constraints

- iOS deployment target: iOS 15 (Package.swift platforms: `[.iOS(.v15)]`)
- Swift tools version: 5.9
- Plugin registered as `StoreSession` (jsName), bridge name `storeSessionBridge`
- Selectors are hardcoded for `coles-au` (no multi-store config in first version)
- The store-session-plugin SPM build compiles from `packages/store-session-plugin/ios/` — the `packages/mobile/src/plugins/` and `packages/mobile/ios/Plugins/` copies are NOT compiled and must not be edited
- Source-level tests use `node --test tests/*.test.mjs` (reads file contents; no JS runtime or Swift compilation)
- The `addToCartDetected` event already flows correctly through Capacitor → `main.ts` `handleAdded` → `sendAction("ADVANCE")`; no `main.ts` changes in this plan

---

## Task 1: Add `cart-detection.js` content script

**Files:**
- Create: `packages/store-session-plugin/ios/Resources/cart-detection.js`
- Create: `packages/store-session-plugin/tests/cart-detection.test.mjs`

**Interfaces:**
- Produces: A plain JS file that posts `{type: "pageLoaded"}` at document end and `{type: "addToCartDetected", productName, productImageUrl}` on add-to-cart clicks, through `window.webkit.messageHandlers.storeSessionBridge`.

- [ ] **Step 1: Write the failing source-level test**

Create `packages/store-session-plugin/tests/cart-detection.test.mjs`:

```js
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
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd packages/store-session-plugin
npm test
```
Expected: FAIL — `ios/Resources/cart-detection.js` does not exist, `readFileSync` throws.

- [ ] **Step 3: Write the content script**

Create `packages/store-session-plugin/ios/Resources/cart-detection.js`:

```js
// ListRunner cart-detection content script for coles.com.au (iOS WKWebView).
// Posts {type:"pageLoaded"} at document end and
// {type:"addToCartDetected", productName, productImageUrl} on add-to-cart clicks
// through the storeSessionBridge WKScriptMessageHandler.

(function () {
  var ADD_TO_CART_SELECTOR = "button[data-testid='add-to-cart-button'], button.add-to-cart";
  var PRODUCT_NAME_SELECTOR = ".product__title, .product-title a, h2.product__title";
  var PRODUCT_IMAGE_SELECTOR = ".product__image img, .product-image img";
  var PRODUCT_TILE_SELECTOR = "[class*='product'], [data-testid*='product'], article, .tile, li";

  function postToBridge(message) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.storeSessionBridge) {
      try {
        window.webkit.messageHandlers.storeSessionBridge.postMessage(message);
      } catch (e) {
        // Page may have navigated away mid-click; ignore.
      }
    }
  }

  function extractProductInfo(addButton) {
    var productName = "";
    var productImageUrl = null;

    var productTile = addButton.closest(PRODUCT_TILE_SELECTOR);
    if (productTile) {
      var nameEl = productTile.querySelector(PRODUCT_NAME_SELECTOR);
      if (nameEl) {
        productName = (nameEl.textContent || "").trim();
      }
      var imgEl = productTile.querySelector(PRODUCT_IMAGE_SELECTOR);
      if (imgEl) {
        productImageUrl = imgEl.currentSrc || imgEl.src || imgEl.getAttribute("data-src");
      }
    }

    if (!productName) {
      productName = readPageProductName();
    }
    if (!productImageUrl) {
      productImageUrl = readPageProductImage();
    }

    return {
      productName: productName || "Unknown product",
      productImageUrl: productImageUrl,
    };
  }

  function readPageProductName() {
    var ogTitle = document.querySelector('meta[property="og:title"]');
    if (ogTitle && ogTitle.content && ogTitle.content.trim()) {
      return ogTitle.content.trim();
    }
    var itemProp = document.querySelector("[itemprop='name']");
    if (itemProp && itemProp.textContent && itemProp.textContent.trim()) {
      return itemProp.textContent.trim();
    }
    var h1 = document.querySelector("h1");
    if (h1 && h1.textContent && h1.textContent.trim()) {
      return h1.textContent.trim();
    }
    // Fall through to page title — strip the " | Store" tail.
    return document.title.replace(/\s*[-|–]\s*.+$/, "").trim();
  }

  function readPageProductImage() {
    var ogImg = document.querySelector('meta[property="og:image"]');
    if (ogImg && ogImg.content) {
      return ogImg.content;
    }
    var itemPropImg = document.querySelector("img[itemprop='image']");
    if (itemPropImg) {
      return itemPropImg.currentSrc || itemPropImg.src;
    }
    return null;
  }

  function handleCartClick(event) {
    var target = event.target;
    if (!target || !target.closest) return;
    var addButton = target.closest(ADD_TO_CART_SELECTOR);
    if (!addButton) return;

    var info = extractProductInfo(addButton);
    postToBridge({
      type: "addToCartDetected",
      productName: info.productName,
      productImageUrl: info.productImageUrl,
    });
  }

  // Register capture-phase click listener (survives SPA re-renders).
  document.addEventListener("click", handleCartClick, true);

  // Announce page load.
  postToBridge({ type: "pageLoaded" });
})();
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd packages/store-session-plugin
npm test
```
Expected: PASS — all 9 cart-detection tests pass (plus the existing `ios-view-loading.test.mjs` tests).

- [ ] **Step 5: Commit**

```bash
git add packages/store-session-plugin/ios/Resources/cart-detection.js packages/store-session-plugin/tests/cart-detection.test.mjs
git commit -m "Add cart-detection content script for coles.com.au"
```

---

## Task 2: Declare SPM resources in Package.swift

**Files:**
- Modify: `packages/store-session-plugin/Package.swift`
- Create: `packages/store-session-plugin/tests/package-resources.test.mjs`

**Interfaces:**
- Produces: `Package.swift` declares `resources: [.copy("Resources")]` on the `ListrunnerStoreSession` target so `Bundle.module` exposes `cart-detection.js`.

- [ ] **Step 1: Write the failing source-level test**

Create `packages/store-session-plugin/tests/package-resources.test.mjs`:

```js
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

const source = readFileSync(
  join(import.meta.dirname, "..", "Package.swift"),
  "utf8",
);

test("Package.swift declares a Resources copy rule", () => {
  assert.match(source, /resources:\s*\[\s*\.copy\(\s*["']Resources["']\s*\)\s*\]/);
});

test("ListrunnerStoreSession target still has ios path", () => {
  assert.match(source, /path:\s*["']ios["']/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd packages/store-session-plugin
npm test
```
Expected: FAIL — `Package.swift` does not contain a `resources:` declaration (readFileSync succeeds but the regex doesn't match).

- [ ] **Step 3: Add resources to Package.swift**

Modify `packages/store-session-plugin/Package.swift` — replace the targets block with:

```swift
    targets: [
        .target(
            name: "ListrunnerStoreSession",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios",
            resources: [.copy("Resources")])
    ]
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd packages/store-session-plugin
npm test
```
Expected: PASS — all tests pass (the new `package-resources` test passes; existing tests still pass).

- [ ] **Step 5: Commit**

```bash
git add packages/store-session-plugin/Package.swift packages/store-session-plugin/tests/package-resources.test.mjs
git commit -m "Declare SPM Resources bundle for store-session-plugin"
```

---

## Task 3: Inject cart-detection.js from Bundle.module into WKWebView

**Files:**
- Modify: `packages/store-session-plugin/ios/StoreSessionViewController.swift`
- Create: `packages/store-session-plugin/tests/ios-injection.test.mjs`

**Interfaces:**
- Consumes: `cart-detection.js` SPM resource (Task 1) and `ListrunnerStoreSession` target resources declaration (Task 2)
- Produces: `StoreSessionViewController` injects the cart-detection script at document end via `WKUserScript`, replacing the inline `pageLoaded` script.

- [ ] **Step 1: Write the failing source-level test**

Create `packages/store-session-plugin/tests/ios-injection.test.mjs`:

```js
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

const source = readFileSync(
  join(import.meta.dirname, "..", "ios", "StoreSessionViewController.swift"),
  "utf8",
);

test("loads cart-detection.js from Bundle.module", () => {
  assert.match(source, /Bundle\.module\.url\s*\(\s*forResource:\s*["']cart-detection["']/);
});

test("registers a WKUserScript at document end", () => {
  assert.match(source, /WKUserScript\s*\(/);
  assert.match(source, /\.atDocumentEnd/);
});

test("uses the loaded script source for the WKUserScript", () => {
  assert.match(source, /String\s*\(\s*contentsOf:\s*scriptURL/);
});

test("no longer contains the inline pageLoaded script source string", () => {
  // The old inline postMessage({type: 'pageLoaded'}) source string should be gone.
  assert.doesNotMatch(source, /postMessage\s*\(\s*\{\s*type:\s*['"]pageLoaded['"]\s*\}\s*\)/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd packages/store-session-plugin
npm test
```
Expected: FAIL — `StoreSessionViewController.swift` does not reference `Bundle.module.url(forResource: "cart-detection"`, and still contains the inline `pageLoaded` postMessage string.

- [ ] **Step 3: Modify StoreSessionViewController.swift to load and inject the script**

In `packages/store-session-plugin/ios/StoreSessionViewController.swift`, find the `setupWebView()` function. Replace the block that creates and adds the inline `readyScript` (lines 36–42 in the current file):

```swift
        // Send page events to JS bridge
        let readyScript = WKUserScript(
            source: "window.webkit.messageHandlers.storeSessionBridge.postMessage({type: 'pageLoaded'});",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(readyScript)
```

with this:

```swift
        // Inject the cart-detection content script (posts pageLoaded and addToCartDetected).
        if let scriptURL = Bundle.module.url(forResource: "cart-detection", withExtension: "js"),
           let scriptSource = try? String(contentsOf: scriptURL, encoding: .utf8) {
            let cartScript = WKUserScript(
                source: scriptSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(cartScript)
        }
```

Read the file before editing to confirm the exact block to replace.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd packages/store-session-plugin
npm test
```
Expected: PASS — all tests pass (the new `ios-injection` test passes; existing tests still pass).

- [ ] **Step 5: Verify TypeScript build still passes**

Run:
```bash
cd packages/store-session-plugin
npm run build
```
Expected: `tsc` completes with no errors.

- [ ] **Step 6: Commit**

```bash
git add packages/store-session-plugin/ios/StoreSessionViewController.swift packages/store-session-plugin/tests/ios-injection.test.mjs
git commit -m "Inject cart-detection.js from Bundle.module into WKWebView"
```

---

## Task 4: Mac build + sync + unsigned Xcode verification

**Files:**
- No new files. This task verifies that the Swift package compiles with the new Resources bundle and the iOS app builds.

**Interfaces:**
- Consumes: All prior tasks.

- [ ] **Step 1: Sync the branch to Mac**

From the Linux workspace, create a git bundle and pull it on the Mac:

```bash
git bundle create /tmp/cart-detection.bundle --all
scp /tmp/cart-detection.bundle adrianzafir@192.168.4.182:~/cart-detection.bundle
ssh adrianzafir@192.168.4.182 'cd ~/Projects/listrunner-ios-test && git fetch ~/cart-detection.bundle main:tmp-fix && git reset --hard tmp-fix && git branch -D tmp-fix && rm ~/cart-detection.bundle'
```

- [ ] **Step 2: Build core and store-session-plugin on Mac**

Run:
```bash
ssh adrianzafir@192.168.4.182 'cd ~/Projects/listrunner-ios-test && export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH" && cd packages/core && npm run build && cd ../store-session-plugin && npm install && npm run build && npm run cap:sync'
```

Wait — `cap:sync` runs from the mobile package. Correct the command:

```bash
ssh adrianzafir@192.168.4.182 'cd ~/Projects/listrunner-ios-test && export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH" && cd packages/core && npm run build && cd ../store-session-plugin && npm run build && cd ../mobile && npm install && npm run build && npm run cap:sync 2>&1 | tail -8'
```

Expected: `cap sync` finishes with `Sync finished` and lists `@listrunner/store-session@0.1.0` among the discovered plugins.

- [ ] **Step 3: Unsigned Xcode build**

Run:
```bash
ssh adrianzafir@192.168.4.182 'cd ~/Projects/listrunner-ios-test/packages/mobile/ios/App && export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH" && xcodebuild -project App.xcodeproj -scheme App -sdk iphoneos -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -3'
```

Expected: `** BUILD SUCCEEDED **` — proves the SPM Resources bundle compiles and the modified `StoreSessionViewController.swift` builds against the Capacitor Swift package.

- [ ] **Step 4: Verify no cart-detection test regressions**

Run the plugin test suite on the Mac to confirm the source-level tests still pass in that environment:

```bash
ssh adrianzafir@192.168.4.182 'cd ~/Projects/listrunner-ios-test && export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH" && cd packages/store-session-plugin && npm test 2>&1 | tail -15'
```

Expected: All tests pass (cart-detection, package-resources, ios-injection, ios-view-loading).

- [ ] **Step 5: Commit (no source changes — this task only verifies)**

No commit needed unless the build surfaced a fix. If a fix was required, commit it with a descriptive message before declaring the task complete.

---

## File Structure Summary

| File | Responsibility |
|------|----------------|
| `packages/store-session-plugin/ios/Resources/cart-detection.js` | Plain JS content script: capture-phase click listener, add-to-cart selector, product-info extraction with metadata fallbacks, posts to storeSessionBridge |
| `packages/store-session-plugin/ios/StoreSessionViewController.swift` | Loads cart-detection.js from `Bundle.module`, injects as `WKUserScript` at document end; unchanged bridge routing |
| `packages/store-session-plugin/Package.swift` | Declares `resources: [.copy("Resources")]` so SPM bundles the JS file |
| `packages/store-session-plugin/tests/cart-detection.test.mjs` | Source-level test: reads cart-detection.js, asserts click listener, selectors, postMessage shape, extraction function, fallbacks |
| `packages/store-session-plugin/tests/package-resources.test.mjs` | Source-level test: asserts Package.swift declares the Resources copy rule |
| `packages/store-session-plugin/tests/ios-injection.test.mjs` | Source-level test: asserts StoreSessionViewController.swift loads cart-detection.js from Bundle.module and injects at document end; no inline pageLoaded source string remains |