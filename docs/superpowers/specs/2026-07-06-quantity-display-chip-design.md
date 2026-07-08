# Quantity Display Chip Design

## Goal

ListRunner should show parsed quantities as shopping context without making count-only quantities look like multiplication.

The store search should remain product-only. Quantity display should be visually distinct from the product/search term on the review list and wizard overlay.

## Decisions

- Count-only quantities render as plain numbers, not with `×`.
- Measured and container quantities render as `<amount> <unit>`.
- Quantity is display-only context and is not included in store search queries.
- Quantity should appear as a small badge/chip beside the product name when present.
- Quantity-less items should not show an empty chip or placeholder.
- Apply the behavior to the mobile app first because that is the active Xcode/iPhone flow.
- Keep extension and harness formatting consistent if touching shared-equivalent helpers is straightforward.

## Expected Display

Review list examples:

| Parsed item | Display |
| --- | --- |
| `{ quantity: { amount: 3, unit: null }, searchTerm: "carrots" }` | `[3] carrots` |
| `{ quantity: { amount: 12, unit: null }, searchTerm: "asparagus" }` | `[12] asparagus` |
| `{ quantity: { amount: 2, unit: "cans" }, searchTerm: "cannellini beans" }` | `[2 cans] cannellini beans` |
| `{ quantity: null, searchTerm: "curry paste" }` | `curry paste` |

Wizard overlay examples:

```text
[2 cans] cannellini beans
Search input: cannellini beans
```

```text
[12] asparagus
Search input: asparagus
```

```text
curry paste
Search input: curry paste
```

## Implementation Notes

The existing mobile app already has `formatQuantity(item)` and separates wizard quantity from `currentItemName`.

Update `formatQuantity()` so `unit: null` returns the amount as a string instead of `×<amount>`.

Change mobile review list rendering from one text string to separate elements:

- A quantity chip element when `formatQuantity(item)` is non-empty.
- A product text element containing `item.searchTerm`.

Change mobile wizard rendering so `current-item-qty` behaves like a chip and is hidden when empty.

CSS should make the quantity visually distinct using a compact badge/chip style.

## Testing

Add or update tests for quantity formatting if there is a practical test surface.

At minimum, run:

- Core tests and build.
- Mobile tests and build.
- Capacitor sync.

After syncing to the Mac Xcode checkout, verify:

- Core tests pass remotely.
- Mobile tests pass remotely.
- Mobile build and `cap:sync` pass remotely.
- Xcode build succeeds at least unsigned, and signed/device install if keychain access allows it.

## Out Of Scope

- Changing parser extraction behavior.
- Including quantity in store search queries.
- Adding quantity editing controls.
- Redesigning the full review page or wizard overlay.
