# iOS Store Session Strict Figma Parity Design

**Date:** 2026-07-07  
**Status:** Approved for implementation planning  
**Target:** Native iOS store-session overlay

## Goal

Update the native iOS store-session overlay so it closely matches the `Current Mobile UI` Figma frames. The Figma design is the canonical source for overlay layout, card states, action labels, colors, spacing, and cooldown/manual state presentation.

## Source Context

The app opens grocery store websites in a native `WKWebView` and renders a native UIKit overlay on top. The current architecture is already correct: TypeScript owns wizard state, sends a serializable overlay payload through the Capacitor plugin, and Swift renders the native overlay.

Primary implementation files:

- `packages/mobile/src/store-session-overlay.ts`
- `packages/mobile/src/main.ts`
- `packages/store-session-plugin/src/index.ts`
- `packages/store-session-plugin/ios/StoreSessionPlugin.swift`
- `packages/store-session-plugin/ios/StoreSessionViewController.swift`

The main expected code changes are in `StoreSessionViewController.swift`. TypeScript payload changes should be avoided unless the Swift renderer cannot infer a Figma-required state from the existing payload.

## Canonical Figma Frames

Use page `Current Mobile UI` as the source of truth.

- Automation available: `28:58` and `135:127`
- No automation available: `127:1800`
- Cooldown: `127:1892`

Important measured frame values:

- iPhone frame: `393 x 852`
- Bottom overlay panel: `x 0`, `y 650`, `width 393`, `height 202`
- Carousel frame: `x -43`, `y 604`, `width 482`, `height 120`
- Active card: `width 132`, `height 182`, `cornerRadius 18`
- Inactive/upcoming card: `width 116`, `height 177`, `cornerRadius 18`
- Previously added card: `width 116`, `height 166`, `cornerRadius 18`
- Secondary button: `x 20`, `y 760`, `width 108`, `height 44`, `cornerRadius 10`
- Primary button: `x 140`, `y 760`, `width 233`, `height 44`, `cornerRadius 10`
- Home indicator: `x 132`, `y 836`, `width 129`, `height 5`, `cornerRadius 3`

## Required Visual Parity

### Overlay Panel

The panel should sit at the bottom of the screen with the same height and button geometry as Figma. It should preserve the underlying full-screen `WKWebView` and allow only the overlay controls to receive touch events.

The panel fill should use a UIKit gradient layer to approximate the Figma radial gradient treatment. Keep the existing shadow only if it does not visibly conflict with the Figma panel softness. Panel dimensions and content positions are higher priority than exact gradient interpolation.

### Carousel

The carousel should match the Figma scrollable timeline behavior:

- The carousel content extends beyond the visible iPhone width.
- The active card is visually centered around `x 147` in the Figma frame.
- Neighbor cards are partially visible where the Figma frame shows them.
- Tapping a card still emits the existing `cardSelected` event.

Use fixed Figma card sizes for each state rather than generic active/inactive sizing only.

### Card States

Render cards according to these Figma states:

- `current`: blue active card, white title and quantity, white card action button labeled `Mark added`.
- `inactive`: neutral upcoming card, dark title, smaller quantity treatment.
- `added`: neutral added card, dark title, `✓ Added` text treatment, no green pill badge.
- `currentAdded`: neutral added current card during cooldown, dark title and quantity, `✓ Added` text treatment, white card action button labeled `Add another` with green action text.

The existing green pill badge treatment should be removed for strict parity because Figma uses dark text for the added-state label.

### Automation Available

For normal automation-available state:

- Secondary action is `Previous`.
- Primary action label should match Figma: `Skip`.
- The active/current product card exposes `Mark added` as the card-level action.
- Do not display a manual badge.

The existing state architecture may still call this action `next` internally if that is how navigation is wired, but the user-facing label must be `Skip` for Figma parity.

### No Automation Available

For manual/no-automation state:

- Keep the same bottom action geometry as automation available.
- Primary action label remains `Skip`.
- Manual state should be shown as a small grey `Manual` badge in the bottom overlay area, matching Figma.
- Do not render the manual badge on the active product card.

### Cooldown

For cooldown state:

- Secondary action is `Undo`.
- Primary action is green and labeled `Next Ns`, where `N` is the current countdown seconds.
- Progress track and fill sit inside the primary button at Figma positions.
- The current card uses the `currentAdded` neutral added treatment, not the blue active treatment.
- The card-level action is `Add another`.

## Interaction Requirements

Keep the existing event model:

- Secondary button emits `previousRequested` or `undoRequested`.
- Primary button emits `nextRequested`.
- Current card action emits `markAddedRequested`.
- Current-added card action emits `addAnotherRequested`.
- Card tap emits `cardSelected` with an index.

Do not change the wizard reducer or browser automation behavior for this parity pass.

## Error Handling

If Swift receives an incomplete or invalid overlay payload, the plugin should continue rejecting it as invalid rather than attempting to render a partial overlay.

If Figma has duplicate or inconsistent automation-available frames, prefer the complete frame that includes the bottom panel and carousel cards. The single-card variant is useful only for confirming active card styling.

## Testing And Verification

Verification should include:

- TypeScript tests for existing overlay payload behavior if payload code changes.
- Mobile package build from `packages/mobile`.
- Store-session plugin build or iOS build path used by the project.
- Manual runtime verification on iPhone or simulator for automation available, no automation available, and cooldown states.
- Screenshot comparison against Figma frames for button labels, card state styling, carousel offsets, and cooldown progress.

## Out Of Scope

- Redesigning the broader mobile web UI.
- Changing parser behavior, wizard state transitions, or cart detection.
- Rebuilding the overlay in SwiftUI.
- Adding new package dependencies.
- Implementing Android parity.

## Success Criteria

- Native overlay visually matches the Figma `Current Mobile UI` overlay frames in the three target states.
- The primary non-cooldown button reads `Skip`.
- Manual badge appears in the bottom overlay area, not on the card.
- Cooldown current card uses neutral added styling with `Add another` card action.
- Added cards use Figma-style text treatment instead of green pill badges.
- Existing store-session event wiring continues to work.
