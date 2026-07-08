# Quantity Display Chip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show parsed quantities as visually distinct chips and render count-only quantities without a multiplication symbol.

**Architecture:** Keep parser output unchanged. Update the mobile renderer so review rows and the wizard header use separate quantity/product elements, then style quantity as a compact chip. Keep store search inputs bound to `searchTerm` only.

**Tech Stack:** TypeScript, Vite, Capacitor, iOS/Xcode, Node test runner

## Global Constraints

- Count-only quantities render as plain numbers, not with `×`.
- Measured and container quantities render as `<amount> <unit>`.
- Quantity is display-only context and is not included in store search queries.
- Quantity should appear as a small badge/chip beside the product name when present.
- Quantity-less items should not show an empty chip or placeholder.
- Apply the behavior to the mobile app first because that is the active Xcode/iPhone flow.
- Keep extension and harness formatting consistent only if touching shared-equivalent helpers is straightforward.
- Do not change parser extraction behavior.
- Do not add quantity editing controls.
- Do not redesign the full review page or wizard overlay.

---

## File Structure

**Modified files:**

| File | Responsibility |
| --- | --- |
| `packages/mobile/src/main.ts` | Render quantity/product as separate elements and format count-only quantity as a plain number. |
| `packages/mobile/src/app.css` | Style quantity chips in review list and wizard overlay. |

**Remote deployment target:**

| Path | Responsibility |
| --- | --- |
| `/Users/adrianzafir/Projects/listrunner-ios-test` on `adrianzafir@192.168.4.182` | Xcode checkout that must receive the updated mobile files and run `npm run build` + `npm run cap:sync`. |

---

## Task 1: Mobile Quantity Chip Rendering

**Files:**
- Modify: `packages/mobile/src/main.ts`
- Modify: `packages/mobile/src/app.css`

**Interfaces:**
- Consumes: `ParsedItem` from `@listrunner/core`, with `quantity: { amount: number; unit: string | null } | null` and `searchTerm: string`.
- Produces: `formatQuantity(item: ParsedItem): string`, where `unit: null` returns `String(amount)`.
- Produces: `renderItemLabel(item: ParsedItem): HTMLSpanElement`, a reusable DOM label containing optional `.quantity-chip` and `.item-name` children.

- [ ] **Step 1: Add failing formatting/rendering test by inspection command**

Because the mobile app has no DOM unit-test harness, first capture the current failure with a source-level check and one-off runtime observation:

Run:

```bash
grep -n "return unit ?.*×" packages/mobile/src/main.ts
```

Expected before the fix: output includes the current `×${amount}` branch in `formatQuantity()`.

- [ ] **Step 2: Update mobile renderer**

In `packages/mobile/src/main.ts`, change `renderReviewList()` item rendering from a single text string to appending a reusable label element:

```ts
  reviewList.innerHTML = "";
  for (const item of parsedList.items) {
    const li = document.createElement("li");
    li.appendChild(renderItemLabel(item));
    reviewList.appendChild(li);
  }
```

For filtered items, keep the existing crossed-out styling and also use the label:

```ts
  filteredList.innerHTML = "";
  for (const item of parsedList.filtered) {
    const li = document.createElement("li");
    li.appendChild(renderItemLabel(item));
    li.style.textDecoration = "line-through";
    li.style.color = "#999";
    filteredList.appendChild(li);
  }
```

In `renderWizardView()`, hide the quantity element when no quantity exists:

```ts
  const quantityText = formatQuantity(parsedItem);
  currentItemName.textContent = searchTerm;
  currentItemQty.textContent = quantityText;
  currentItemQty.classList.toggle("hidden", quantityText.length === 0);
  currentSearchInput.value = searchTerm;
```

Replace `formatQuantity()` and add `renderItemLabel()` above it:

```ts
function renderItemLabel(item: ParsedItem): HTMLSpanElement {
  const wrapper = document.createElement("span");
  wrapper.className = "item-label";

  const quantityText = formatQuantity(item);
  if (quantityText) {
    const quantity = document.createElement("span");
    quantity.className = "quantity-chip";
    quantity.textContent = quantityText;
    wrapper.appendChild(quantity);
  }

  const name = document.createElement("span");
  name.className = "item-name";
  name.textContent = item.searchTerm;
  wrapper.appendChild(name);

  return wrapper;
}

function formatQuantity(item: ParsedItem): string {
  if (!item.quantity) return "";
  const { amount, unit } = item.quantity;
  return unit ? `${amount} ${unit}` : String(amount);
}
```

- [ ] **Step 3: Add chip CSS**

In `packages/mobile/src/app.css`, add these rules after the `.item-list li` block:

```css
.item-label {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.quantity-chip {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex: 0 0 auto;
  min-width: 2.2em;
  padding: 2px 8px;
  border-radius: 999px;
  background: #e8f1ff;
  color: #0b5ec9;
  font-size: 0.85rem;
  font-weight: 700;
  line-height: 1.5;
}

.item-name {
  min-width: 0;
}
```

Update the wizard quantity style by replacing `.current-item p { color: #666; }` with:

```css
.current-item p {
  margin-top: 4px;
}

#current-item-qty.quantity-chip,
.current-item .quantity-chip {
  width: fit-content;
}
```

In `packages/mobile/index.html`, add `quantity-chip` to the wizard quantity element so the static overlay gets the chip style:

```html
<p id="current-item-qty" class="quantity-chip"></p>
```

- [ ] **Step 4: Verify formatting source check passes**

Run:

```bash
grep -n "×" packages/mobile/src/main.ts
```

Expected: no output.

- [ ] **Step 5: Run local verification**

Run:

```bash
cd packages/mobile && npm test && npm run build && npm run cap:sync
```

Expected: mobile tests pass, Vite build succeeds, Capacitor sync succeeds.

- [ ] **Step 6: Commit Task 1**

Only run if commits are explicitly requested:

```bash
git add packages/mobile/src/main.ts packages/mobile/src/app.css packages/mobile/index.html
git commit -m "fix: show quantities as chips"
```

---

## Task 2: Sync To Mac Xcode Checkout

**Files:**
- Copy: `packages/mobile/src/main.ts`
- Copy: `packages/mobile/src/app.css`
- Copy: `packages/mobile/index.html`

**Interfaces:**
- Consumes: local mobile source changes from Task 1.
- Produces: updated Xcode checkout at `/Users/adrianzafir/Projects/listrunner-ios-test`.

- [ ] **Step 1: Copy changed mobile files to Mac checkout**

Run:

```bash
scp packages/mobile/src/main.ts packages/mobile/src/app.css adrianzafir@192.168.4.182:/Users/adrianzafir/Projects/listrunner-ios-test/packages/mobile/src/
scp packages/mobile/index.html adrianzafir@192.168.4.182:/Users/adrianzafir/Projects/listrunner-ios-test/packages/mobile/index.html
```

Expected: both `scp` commands complete with no output.

- [ ] **Step 2: Run remote tests/build/sync**

Run:

```bash
ssh adrianzafir@192.168.4.182 'set -e; export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"; cd ~/Projects/listrunner-ios-test/packages/mobile; npm test; npm run build; npm run cap:sync'
```

Expected: mobile tests pass, Vite build succeeds, Capacitor sync succeeds.

- [ ] **Step 3: Verify remote bundle contains chip markup/classes**

Run:

```bash
ssh adrianzafir@192.168.4.182 'cd ~/Projects/listrunner-ios-test && grep -R "quantity-chip\|item-label" -n packages/mobile/ios/App/App/public | head -10'
```

Expected: output from bundled HTML/CSS/JS includes `quantity-chip` and `item-label`.

- [ ] **Step 4: Build Xcode project unsigned**

Run:

```bash
ssh adrianzafir@192.168.4.182 'set -e; export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"; cd ~/Projects/listrunner-ios-test/packages/mobile/ios/App; xcodebuild -project App.xcodeproj -scheme App -configuration Debug -destination "generic/platform=iOS" build CODE_SIGNING_ALLOWED=NO'
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Report signed install caveat**

If an SSH signed/device build is attempted and fails with `errSecInternalComponent`, report that Xcode GUI should be used to Run because SSH lacks keychain signing access.

---

## Final Verification

- [ ] Local `packages/mobile`: `npm test` passes.
- [ ] Local `packages/mobile`: `npm run build` passes.
- [ ] Local `packages/mobile`: `npm run cap:sync` passes.
- [ ] Remote `packages/mobile`: `npm test` passes.
- [ ] Remote `packages/mobile`: `npm run build` passes.
- [ ] Remote `packages/mobile`: `npm run cap:sync` passes.
- [ ] Remote Xcode unsigned build succeeds.
- [ ] User can Run from Xcode GUI to install the signed build on device.

## Plan Self-Review

- Spec coverage: Count-only formatting, measured/container formatting, visual chip display, product-only search, no empty chip, active Xcode checkout sync, and verification are covered.
- Placeholder scan: No placeholder markers or undefined implementation steps remain.
- Type consistency: The plan uses existing `ParsedItem`, `formatQuantity(item: ParsedItem): string`, and DOM element IDs/classes consistently.
