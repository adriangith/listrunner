# iOS Store Session Card Interaction Design

## Goal

Make the native store-session product cards behave like a real carousel: the full visible card area is swipeable, and tapping a card body selects that product, repeats its search, and updates the active selected state.

## Behavior

- The carousel swipe target must cover the entire visible card area, including card tops that protrude above the bottom panel.
- Tapping a card body selects that card's item and repeats the current search term for that item.
- Tapping the card action button keeps its existing behavior and must not also select the card.
- Selecting a card updates the wizard state source of truth, re-renders the native overlay, and centers the selected card.
- Selecting a card during cooldown is ignored so Undo/Add another/countdown behavior remains stable.
- Selecting an already active card still repeats the search.

## Architecture

- Add a `SELECT_INDEX` wizard action in `packages/core` for direct item selection during primary stepping/revisit states.
- Add a native `cardSelected` event from the Swift plugin to TypeScript with `{ index: number }`.
- Expand the Swift card hit area by making the scroll view cover the full visible card region and by allowing the overlay view to receive touches above its bounds.
- Keep UIKit-only implementation and no new dependencies.

## Testing

- Add reducer tests for selecting another item and ignoring/throwing invalid cooldown selection.
- Add mobile event routing tests only where practical through existing payload tests; native build verifies Swift event contract compiles.
- Verify on Mac with mobile/core tests, TypeScript builds, Capacitor sync, Xcode simulator/device build, and install to phone if signing/install path is available.
