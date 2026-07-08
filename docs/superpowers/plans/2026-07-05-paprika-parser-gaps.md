# Paprika Parser Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve deterministic parsing for Paprika-style recipe reminders and verify quantity display remains visible in review and wizard screens.

**Architecture:** Keep the existing parser pipeline: `splitItems()` -> `extractQuantities()` -> `cleanProductName()` -> pantry filtering. Add targeted quantity extraction and conservative product-name cleanup rules covered by regression tests. Reuse existing UI quantity rendering; no parsed data model changes.

**Tech Stack:** TypeScript, Vitest, esbuild, Chrome extension side panel, local harness

## Global Constraints

- Keep the parser deterministic and local.
- Do not add an AI cleanup step.
- Do not add a third-party recipe parser.
- Keep `ParsedItem` shape unchanged: `original`, `quantity`, `searchTerm`, `filtered`.
- Keep quantity separate from `searchTerm`.
- Keep useful shopping descriptors like `fresh` and `frozen`.
- Strip cooking-state descriptors like `uncooked`.
- Display formatted quantity in both review and wizard screens.
- Manual paste entry remains available and unchanged.
- All changes must preserve existing parser tests.

---

## File Structure

**Modified files:**

| File | Responsibility |
| --- | --- |
| `packages/core/src/quantity.ts` | Extract structured quantity and remaining product text. Add Paprika package-size order and full-word ounce support. |
| `packages/core/tests/quantity.test.ts` | Focused quantity extraction regression tests. |
| `packages/core/src/product-name.ts` | Clean product names by stripping conservative prep/action phrases and cooking-state descriptors. |
| `packages/core/tests/product-name.test.ts` | Focused product-name cleanup regression tests. |
| `packages/core/tests/parse.test.ts` | End-to-end Paprika screenshot regression test through `parseList()`. |
| `packages/harness/src/main.ts` | Verify existing review and wizard quantity display; change only if verification proves a gap. |
| `packages/extension/src/side-panel/side-panel.ts` | Verify existing review and wizard quantity display; change only if verification proves a gap. |

**Existing UI quantity display to preserve:**

| File | Existing behavior |
| --- | --- |
| `packages/harness/src/main.ts:358-360` | Review rows render `formatQuantity(item)` into `.item-qty`. |
| `packages/harness/src/main.ts:423-424` | Wizard active item renders `formatQuantity(activeItem.parsedItem)`. |
| `packages/extension/src/side-panel/side-panel.ts:490-492` | Review rows render `formatQuantity(item)` into `.item-qty`. |
| `packages/extension/src/side-panel/side-panel.ts:561-562` | Wizard active item renders `formatQuantity(activeItem.parsedItem)`. |

---

## Task 1: Quantity Extraction For Paprika Package Sizes

**Files:**
- Modify: `packages/core/tests/quantity.test.ts`
- Modify: `packages/core/src/quantity.ts`

**Interfaces:**
- Consumes: `extractQuantity(item: RawItem): ItemWithQuantity`
- Produces: Existing return type unchanged: `{ original: string; quantity: Quantity | null; remaining: string }`

- [ ] **Step 1: Add failing quantity tests**

Append these tests inside `describe("extractQuantity", () => { ... })` in `packages/core/tests/quantity.test.ts`:

```ts
  it("extracts Paprika parenthesized can size before container", () => {
    const result = extractQuantity({
      original: "1 (28 ounce) can diced tomatoes",
    });
    expect(result.quantity).toEqual({ amount: 1, unit: "can" });
    expect(result.remaining).toBe("diced tomatoes");
  });

  it("extracts plural Paprika parenthesized can size before container", () => {
    const result = extractQuantity({
      original: "2 (15 ounce) cans cannellini beans drained and rinsed",
    });
    expect(result.quantity).toEqual({ amount: 2, unit: "cans" });
    expect(result.remaining).toBe("cannellini beans drained and rinsed");
  });

  it("extracts Paprika parenthesized bag size before container", () => {
    const result = extractQuantity({
      original: "1 (6 ounce) bag fresh spinach",
    });
    expect(result.quantity).toEqual({ amount: 1, unit: "bag" });
    expect(result.remaining).toBe("fresh spinach");
  });

  it("extracts full-word ounce units", () => {
    const result = extractQuantity({
      original: "8 ounces uncooked ditalini pasta",
    });
    expect(result.quantity).toEqual({ amount: 8, unit: "ounces" });
    expect(result.remaining).toBe("uncooked ditalini pasta");
  });
```

- [ ] **Step 2: Run quantity tests and verify they fail**

Run: `npm test -- tests/quantity.test.ts`

Working directory: `packages/core`

Expected: FAIL for the four new tests because `1 (28 ounce) can ...` is currently treated as count-only and `ounces` is not currently a unit.

- [ ] **Step 3: Add minimal quantity implementation**

In `packages/core/src/quantity.ts`, update the unit constants near the top:

```ts
const UNITS =
  "g|kg|mg|ml|l|oz|ounce|ounces|lb|lbs|cups?|tbsp|tbsps|tsp|tsps|dozen|litres?|liters?|bunch|bunches|head|heads|cloves?|stalks?|sprigs?|slices?|pieces?|cans?|tins?|packets?|packs?|bags?|bottles?|boxes?|jars?|cartons?|punnets?|pots?|tubs?|trays?|loaves|loaf";

const CONTAINER_UNITS =
  "cans?|tins?|packets?|packs?|bags?|bottles?|boxes?|jars?|cartons?|bunches?|heads?|punnets?|pots?|tubs?|trays?";

const PACKAGE_SIZE_UNITS = "g|kg|ml|l|oz|ounce|ounces|lb|lbs";
```

Then insert this pattern in `extractQuantity()` after `const text = normalized;` and before the existing `containerMatch` block:

```ts
  // Pattern: "N (X unit) container item" — e.g., "1 (28 ounce) can tomatoes"
  const parenthesizedContainerMatch = text.match(
    new RegExp(
      String.raw`^(\d+\.?\d*)\s*\(\s*\d+\.?\d*\s*(?:${PACKAGE_SIZE_UNITS})\s*\)\s*(${CONTAINER_UNITS})\s+(.+)`,
      "i",
    ),
  );
  if (parenthesizedContainerMatch) {
    return {
      original: item.original,
      quantity: {
        amount: parseFloat(parenthesizedContainerMatch[1]!),
        unit: parenthesizedContainerMatch[2]!.toLowerCase(),
      },
      remaining: parenthesizedContainerMatch[3]!.trim(),
    };
  }
```

- [ ] **Step 4: Run quantity tests and verify they pass**

Run: `npm test -- tests/quantity.test.ts`

Working directory: `packages/core`

Expected: PASS for all quantity tests.

- [ ] **Step 5: Commit Task 1**

Run these only if commits are requested for this implementation session:

```bash
git add packages/core/src/quantity.ts packages/core/tests/quantity.test.ts
git commit -m "fix: parse paprika package quantities"
```

---

## Task 2: Product Name Cleanup For Recipe Prep Phrases

**Files:**
- Modify: `packages/core/tests/product-name.test.ts`
- Modify: `packages/core/src/product-name.ts`

**Interfaces:**
- Consumes: `cleanProductName(item: ItemWithQuantity): string`
- Produces: Clean shopping search terms with prep/action text removed conservatively.

- [ ] **Step 1: Add failing product-name tests**

Append these tests inside `describe("cleanProductName", () => { ... })` in `packages/core/tests/product-name.test.ts`:

```ts
  it("strips drained and rinsed prep phrase", () => {
    expect(
      cleanProductName({
        original: "2 cans cannellini beans drained and rinsed",
        quantity: { amount: 2, unit: "cans" },
        remaining: "cannellini beans drained and rinsed",
      }),
    ).toBe("cannellini beans");
  });

  it("strips peeled and sliced prep phrase", () => {
    expect(
      cleanProductName({
        original: "3 carrots peeled and sliced",
        quantity: { amount: 3, unit: null },
        remaining: "carrots peeled and sliced",
      }),
    ).toBe("carrots");
  });

  it("strips asparagus stem prep phrase", () => {
    expect(
      cleanProductName({
        original: "12 thin asparagus spears stems removed and cut into thirds",
        quantity: { amount: 12, unit: null },
        remaining: "thin asparagus spears stems removed and cut into thirds",
      }),
    ).toBe("asparagus");
  });

  it("strips leading uncooked cooking-state descriptor", () => {
    expect(
      cleanProductName({
        original: "8 ounces uncooked ditalini pasta",
        quantity: { amount: 8, unit: "ounces" },
        remaining: "uncooked ditalini pasta",
      }),
    ).toBe("ditalini pasta");
  });

  it("preserves frozen shopping descriptor", () => {
    expect(
      cleanProductName({
        original: "1 cup frozen sweet peas",
        quantity: { amount: 1, unit: "cup" },
        remaining: "frozen sweet peas",
      }),
    ).toBe("frozen sweet peas");
  });
```

- [ ] **Step 2: Run product-name tests and verify they fail**

Run: `npm test -- tests/product-name.test.ts`

Working directory: `packages/core`

Expected: FAIL for the new prep/cooking-state tests. The `frozen sweet peas` test may already pass and should keep passing.

- [ ] **Step 3: Add minimal product-name cleanup implementation**

In `packages/core/src/product-name.ts`, add these phrases to `STRIP_PHRASES`:

```ts
  "drained and rinsed",
  "peeled and sliced",
  "stems removed and cut into thirds",
```

Add this constant after `LEADING_ARTICLES`:

```ts
/** Leading cooking/prep descriptors that do not help store search. */
const LEADING_PREP_WORDS = new Set(["uncooked"]);
```

Then replace the existing leading article block with this block:

```ts
  // Drop leading article and cooking/prep words.
  const tokens = text.trim().split(/\s+/);
  while (
    tokens.length > 1 &&
    (LEADING_ARTICLES.has(tokens[0]!.toLowerCase()) ||
      LEADING_PREP_WORDS.has(tokens[0]!.toLowerCase()))
  ) {
    tokens.shift();
  }
  text = tokens.join(" ");

  // Normalize common asparagus recipe wording to the product shoppers search for.
  text = text.replace(/^thin\s+asparagus\s+spears?\b/i, "asparagus");
```

Do not add `fresh` or `frozen` to `LEADING_PREP_WORDS`.

- [ ] **Step 4: Run product-name tests and verify they pass**

Run: `npm test -- tests/product-name.test.ts`

Working directory: `packages/core`

Expected: PASS for all product-name tests.

- [ ] **Step 5: Commit Task 2**

Run these only if commits are requested for this implementation session:

```bash
git add packages/core/src/product-name.ts packages/core/tests/product-name.test.ts
git commit -m "fix: clean paprika prep phrases"
```

---

## Task 3: End-To-End Paprika Screenshot Regression

**Files:**
- Modify: `packages/core/tests/parse.test.ts`

**Interfaces:**
- Consumes: `parseList(input: string, options?: ParseOptions): ParsedList`
- Produces: End-to-end confidence that quantity extraction and product cleanup work together.

- [ ] **Step 1: Add failing end-to-end parse test**

Append this test inside `describe("parseList", () => { ... })` in `packages/core/tests/parse.test.ts`:

```ts
  it("parses Paprika recipe reminder ingredients", () => {
    const input = `2 (15 ounce) cans cannellini beans drained and rinsed
1 (28 ounce) can diced tomatoes
1 cup frozen sweet peas
curry paste
Spray oil
8 ounces uncooked ditalini pasta
3 carrots peeled and sliced
1 (6 ounce) bag fresh spinach
12 thin asparagus spears stems removed and cut into thirds
maple syrup`;

    const result = parseList(input);

    expect(result.filtered).toHaveLength(0);
    expect(result.items.map((item) => item.searchTerm)).toEqual([
      "cannellini beans",
      "diced tomatoes",
      "frozen sweet peas",
      "curry paste",
      "Spray oil",
      "ditalini pasta",
      "carrots",
      "fresh spinach",
      "asparagus",
      "maple syrup",
    ]);
    expect(result.items.map((item) => item.quantity)).toEqual([
      { amount: 2, unit: "cans" },
      { amount: 1, unit: "can" },
      { amount: 1, unit: "cup" },
      null,
      null,
      { amount: 8, unit: "ounces" },
      { amount: 3, unit: null },
      { amount: 1, unit: "bag" },
      { amount: 12, unit: null },
      null,
    ]);
  });
```

- [ ] **Step 2: Run parse tests**

Run: `npm test -- tests/parse.test.ts`

Working directory: `packages/core`

Expected: PASS if Tasks 1 and 2 are complete. If this fails, inspect the failed diff and adjust only the smallest parser rule needed to satisfy the approved expected output.

- [ ] **Step 3: Run full core test suite**

Run: `npm test`

Working directory: `packages/core`

Expected: PASS for all core tests.

- [ ] **Step 4: Build core**

Run: `npm run build`

Working directory: `packages/core`

Expected: TypeScript build exits successfully.

- [ ] **Step 5: Commit Task 3**

Run these only if commits are requested for this implementation session:

```bash
git add packages/core/tests/parse.test.ts
git commit -m "test: cover paprika reminder parsing"
```

---

## Task 4: Verify Quantity Display In Review And Wizard

**Files:**
- Read/verify: `packages/harness/src/main.ts`
- Read/verify: `packages/extension/src/side-panel/side-panel.ts`
- Modify only if verification reveals the current display is missing or broken.

**Interfaces:**
- Consumes: `ParsedItem.quantity`
- Produces: Review rows and wizard active item display `formatQuantity(...)` while store search still uses `searchTerm` only.

- [ ] **Step 1: Verify harness review and wizard quantity rendering**

Confirm `packages/harness/src/main.ts` still contains these lines or equivalent behavior:

```ts
  qtySpan.textContent = formatQuantity(item);
```

and:

```ts
    currentItemQty.textContent = formatQuantity(activeItem.parsedItem);
```

- [ ] **Step 2: Verify extension review and wizard quantity rendering**

Confirm `packages/extension/src/side-panel/side-panel.ts` still contains these lines or equivalent behavior:

```ts
  qtySpan.textContent = formatQuantity(item);
```

and:

```ts
    currentItemQty.textContent = formatQuantity(activeItem.parsedItem);
```

- [ ] **Step 3: Verify search still uses product term only**

Confirm both UI files set active search text from `searchTerm` and not from formatted quantity:

```ts
    const searchTerm =
      activeItem.searchTermOverride ?? activeItem.parsedItem.searchTerm;
    currentItemName.textContent = searchTerm;
```

Expected: The quantity appears as context but is not included in the store search query.

- [ ] **Step 4: Run extension typecheck and build**

Run: `npm run typecheck`

Working directory: `packages/extension`

Expected: TypeScript exits successfully.

Run: `npm run build`

Working directory: `packages/extension`

Expected: Extension bundle builds successfully.

- [ ] **Step 5: Run harness build**

Run: `npm run build`

Working directory: `packages/harness`

Expected: Harness bundle builds successfully.

- [ ] **Step 6: Commit Task 4**

Run these only if commits are requested and Task 4 changed files:

```bash
git add packages/harness/src/main.ts packages/extension/src/side-panel/side-panel.ts
git commit -m "fix: show parsed quantities in shopping flow"
```

If Task 4 changes no files, do not create a commit for this task.

---

## Final Verification

- [ ] Run core tests: `npm test` in `packages/core`; expect all tests pass.
- [ ] Run core build: `npm run build` in `packages/core`; expect TypeScript exits successfully.
- [ ] Run extension typecheck: `npm run typecheck` in `packages/extension`; expect TypeScript exits successfully.
- [ ] Run extension build: `npm run build` in `packages/extension`; expect bundle builds successfully.
- [ ] Run harness build: `npm run build` in `packages/harness`; expect bundle builds successfully.
- [ ] Run a one-off parse of the Paprika screenshot list against `packages/core/dist/parse.js` and confirm the output matches the table in `docs/superpowers/specs/2026-07-05-paprika-parser-gaps-design.md`.

One-off parse command:

```bash
node --input-type=module -e 'import("./dist/parse.js").then(({ parseList }) => { const input = `2 (15 ounce) cans cannellini beans drained and rinsed
1 (28 ounce) can diced tomatoes
1 cup frozen sweet peas
curry paste
Spray oil
8 ounces uncooked ditalini pasta
3 carrots peeled and sliced
1 (6 ounce) bag fresh spinach
12 thin asparagus spears stems removed and cut into thirds
maple syrup`; console.log(JSON.stringify(parseList(input), null, 2)); })'
```

Working directory: `packages/core`

Expected output includes these search terms in order:

```json
[
  "cannellini beans",
  "diced tomatoes",
  "frozen sweet peas",
  "curry paste",
  "Spray oil",
  "ditalini pasta",
  "carrots",
  "fresh spinach",
  "asparagus",
  "maple syrup"
]
```

## Plan Self-Review

- Spec coverage: Parser gaps, quantity display, deterministic local parsing, unchanged data model, and testing are covered by Tasks 1-4 and Final Verification.
- Placeholder scan: No placeholder markers or undefined implementation steps remain.
- Type consistency: The plan uses existing interfaces `extractQuantity`, `cleanProductName`, `parseList`, `ParsedItem.quantity`, and `formatQuantity` consistently.
