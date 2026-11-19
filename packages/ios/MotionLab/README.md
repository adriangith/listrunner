# Motion Lab

Small, self-contained SwiftUI motion components for ListRunner, built and
fine-tuned in Xcode Previews before they are wired into the app. It's a local
Swift package (`ListRunnerMotion`) with no dependency on the app target, and
the app does not import it yet.

## Open it

On the Mac, open `packages/ios/MotionLab/Package.swift` in Xcode, choose the
`ListRunnerMotion` scheme with an iPhone simulator, and show the canvas
(Editor → Canvas). Use Live mode to tap.

Every playground has a **Tuning** panel: sliders for each timing, **Slow
motion** (stretches everything for inspection), **Simulate Reduce Motion**,
and **Values**, which prints the current numbers to copy back into
`MotionTuning`'s defaults.

## Principles (from the Ivy reference recording, 19 November 2026)

- Short and purposeful: small, fast feedback for everyday taps; bigger motion only at milestones.
- Things appear by fading from blurry to sharp, not by popping in; related items are staggered.
- Numbers roll to their new value rather than jumping.
- Elements change in place (badges, buttons) instead of being swapped.
- ListRunner's own visuals only: store colours and list cards, not the reference app's look.
- Reduce Motion always falls back to a short crossfade or the final state.
- iOS 17 is the deployment target, so no iOS 26-only APIs without a fallback.

## Animations

| # | Animation | Status | Preview |
|---|---|---|---|
| 1 | Marking items Added | Built, tuning | `Mark Added · playground`, `Status badge · loop` |
| 2 | Finishing a store list | Planned | |
| 3 | Welcome (W1) | Planned | |
| 4 | Setup screens (W2–W4) | Planned | |
| 5 | Adding items | Planned | |
| 6 | Morphing Show Store button | Planned | |

### 1. Marking items Added

- `StatusBadge` (`prominent`): the row you acted on. Pops slightly, resizes
  with a spring, blurs Pending across to Added and draws the tick, with a
  light haptic (`MotionHaptics.itemAdded`). Back to Pending has no pop.
- `StatusBadge` (`quiet`): the same shared item on its other lists. Plain
  crossfade, tick already drawn, no haptic.
- `SummaryCounts` / `RollingCount`: Pending / Added / Skipped counts roll;
  the heading blurs to "Complete" when nothing is Pending.
- The badge colour is always the store tint; only label and tick change.
