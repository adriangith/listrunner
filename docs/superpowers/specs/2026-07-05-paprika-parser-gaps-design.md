# Paprika Parser Gaps Design

## Goal

ListRunner should parse Paprika-style recipe reminders into useful grocery search terms while preserving quantity information for shopping.

The store search should stay focused on the product name. Quantity should be displayed in the review screen and the wizard so the user can choose the right amount on the store website.

## Current Problems

The current parser handles simple grocery lines well, but Paprika exports recipe ingredient lines that expose several gaps:

- `1 (28 ounce) can diced tomatoes` is parsed as quantity `1` with search term `can diced tomatoes`.
- `1 (6 ounce) bag fresh spinach` is parsed as quantity `1` with search term `bag fresh spinach`.
- `8 ounces uncooked ditalini pasta` misses the unit because only `oz` is supported.
- `3 carrots peeled and sliced` leaves `carrots peeled and`.
- `2 (15 ounce) cans cannellini beans drained and rinsed` leaves container and prep text in the search term.
- `12 thin asparagus spears stems removed and cut into thirds` leaves too much recipe preparation detail.

## Decisions

- Keep the parser deterministic and local. Do not add an AI cleanup step.
- Keep the existing parsed item shape: `original`, `quantity`, `searchTerm`, and `filtered`.
- Keep quantity separate from search term.
- Display formatted quantity in both review and wizard screens.
- Strip container words when they are part of package-size phrasing.
- Strip prep/action words and phrases that do not help shopping.
- Keep useful product-quality descriptors when they help shopping, such as `fresh` and `frozen`.
- Strip descriptors that only describe cooking state, such as `uncooked`.

## Parsing Behavior

Expected results for the screenshot list:

| Input | Quantity | Search term |
| --- | --- | --- |
| `2 (15 ounce) cans cannellini beans drained and rinsed` | `2 cans` | `cannellini beans` |
| `1 (28 ounce) can diced tomatoes` | `1 can` | `diced tomatoes` |
| `1 cup frozen sweet peas` | `1 cup` | `frozen sweet peas` |
| `curry paste` | none | `curry paste` |
| `Spray oil` | none | `Spray oil` |
| `8 ounces uncooked ditalini pasta` | `8 ounces` | `ditalini pasta` |
| `3 carrots peeled and sliced` | `3` | `carrots` |
| `1 (6 ounce) bag fresh spinach` | `1 bag` | `fresh spinach` |
| `12 thin asparagus spears stems removed and cut into thirds` | `12` | `asparagus` |
| `maple syrup` | none | `maple syrup` |

## Parser Changes

Quantity extraction should recognize Paprika package-size order:

```text
N (package size unit) container product
```

Examples:

- `1 (28 ounce) can diced tomatoes` -> quantity `{ amount: 1, unit: "can" }`, remaining `diced tomatoes`
- `2 (15 ounce) cans cannellini beans` -> quantity `{ amount: 2, unit: "cans" }`, remaining `cannellini beans`
- `1 (6 ounce) bag fresh spinach` -> quantity `{ amount: 1, unit: "bag" }`, remaining `fresh spinach`

Unit extraction should recognize full-word ounce units:

- `ounce`
- `ounces`

Product-name cleanup should remove common recipe-prep tails and cooking-state descriptors:

- trailing `drained and rinsed`
- trailing `peeled and sliced`
- trailing `stems removed and cut into thirds`
- leading `uncooked`
- leading `thin` for asparagus spear phrasing

The cleanup should remain conservative. It should not strip arbitrary words from every product name unless the pattern is covered by tests.

## UI Changes

The review screen should show the formatted quantity near each parsed item.

The wizard screen should show the formatted quantity for the active item near the item title or search term.

The existing `formatQuantity(parsedItem)` helper should be reused where possible so quantity display stays consistent.

Manual items and quantity-less items should not show empty placeholder text.

## Data Flow

1. The user imports from Paprika Reminders or pastes a list.
2. `parseList()` extracts quantity and search term.
3. Review renders the search term plus formatted quantity when present.
4. The wizard searches the store using only the search term.
5. The wizard displays formatted quantity as shopping context while the user chooses a product.

## Testing

Add parser regression coverage for the full Paprika screenshot list.

Add focused quantity tests for:

- `N (X ounce) can product`
- `N (X ounce) cans product`
- `N (X ounce) bag product`
- `N ounces product`

Add product-name cleanup tests for:

- `drained and rinsed`
- `peeled and sliced`
- `stems removed and cut into thirds`
- `uncooked ditalini pasta`
- `thin asparagus spears ...`

Add UI tests only if the existing UI package already has practical test coverage for review or wizard rendering. If not, verify by build/typecheck and keep the UI change small.

## Out Of Scope

- Replacing the parser with a third-party recipe parser.
- AI-based parsing or normalization.
- Changing the parsed item data model.
- Supporting every possible recipe ingredient format.
- Editing iOS Reminders titles.
