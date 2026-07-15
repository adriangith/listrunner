# ListRunner Sketch State Matrix Design

## Goal

Create a high-fidelity Sketch prototype for reviewing ListRunner's launch-routing and shopping-run states before native implementation.

## Prototype Scope

The prototype uses one Sketch page containing eight 390x844 iPhone frames arranged as a labeled state matrix. It is a visual review artifact, not a complete wired prototype.

### Launch Routing

- Same-day launch with pending items: restore the Coles overlay and the last selected item.
- Same-day launch with a completed list: show the list/summary screen without presenting Coles.
- Later-day launch: preserve the run and show the list/summary screen without presenting Coles.

### Shopping States

- Pending item: show the current item with `Mark Added` and `Skip` actions.
- Added cooldown: show the item as `Added`, a three-second progress treatment, `Undo`, and `Next`.
- Quantity increase: show the item remaining `Added`, the quantity delta context, and a restarted cooldown.
- Removal warning: show the inline `Could not undo store cart change` banner with a dismiss control.
- Completion summary: show `All items handled` while keeping `Show Store` available for a non-empty list.

## Visual Direction

- Use adaptive light-interface styling for ListRunner-owned surfaces.
- Use the established branded grocery-card gradients for shopping cards.
- Use clear status badges, strong hierarchy, and consistent spacing across frames.
- Use realistic Coles search context without reproducing arbitrary store content.
- Make the warning banner non-blocking and give its close control the accessibility label `Dismiss cart undo warning`.

## Review Criteria

- The launch states clearly distinguish same-day pending restore from completed and later-day summary routing.
- Shopping states make status, available actions, cooldown, quantity change, and warning behavior visually unambiguous.
- `Show Store` remains visibly available in the completed non-empty state.
- The matrix can be reviewed side by side without relying on hidden interactions.
