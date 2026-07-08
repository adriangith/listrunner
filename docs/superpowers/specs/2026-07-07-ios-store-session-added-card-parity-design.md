# iOS Store Session Added Card Parity Design

**Date:** 2026-07-07
**Status:** Approved design, pending implementation plan
**Target:** Native iOS store-session overlay and wizard selection state

## Goal

Fix the remaining native overlay parity issues reported during simulator review:

- Added cards should use the green Figma gradient treatment.
- Tapping an already-added card should not remove its added status.
- Top card marker circles should be removed.
- The `✓ Added` label should shift slightly left to better match Figma.
- Non-selected card quantities should use pill backgrounds.

## Root Cause

The visual issues are in `StoreSessionViewController.swift`: added cards are rendered with the same neutral flat background as inactive cards, non-current quantities are plain labels, and non-added cards still draw top-left dot markers.

The state-loss bug is in `packages/core/src/wizard.ts`: `SELECT_INDEX` rewrites the selected item to `active`, even when that item was already `added`. The overlay payload then sees the item as active/current rather than added.

## Design

Keep completion status separate from carousel selection.

When the user taps an added card, ListRunner should center/search that item but keep the card visually added. The item must not become pending/current just because it was selected. The selected added card should stay in the added visual state rather than switching to blue.

Swift rendering changes:

- Add a green gradient background for `added` and `currentAdded` cards.
- Remove the dot/circle marker from the top of all cards.
- Move the `✓ Added` label a few points left.
- Render inactive/added quantities inside compact rounded pill backgrounds.
- Preserve existing card sizes, carousel overscan, buttons, and event names.

State and payload changes:

- `SELECT_INDEX` should not overwrite an item whose status is already `added`.
- The overlay payload should prefer `added` state over `current` when an active/selected item has already been added.
- Card tap should continue emitting the original payload index.

## Alternatives Considered

1. Add a new `selectedAdded` overlay state.
   This is more explicit but adds a new state across TypeScript and Swift for a treatment that currently matches `added`.

2. Patch only the Swift renderer.
   This would not fix the root cause because TypeScript has already erased the item’s added status.

## Testing

Add or update tests for:

- `SELECT_INDEX` preserves an already-added item’s `added` status.
- Overlay payload keeps selected added cards as `added`.
- Swift source-level parity checks cover added gradient, no marker circles, shifted added label, and quantity pill creation.

Verification should include local package tests, mobile tests/build/sync, and the remote Mac simulator build.

## Out Of Scope

- Redesigning the whole overlay.
- Changing cart detection.
- Changing how quantities are parsed.
- Adding new dependencies.
