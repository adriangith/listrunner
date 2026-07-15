# ListRunner Sketch State Matrix Design

## Goal

Create a high-fidelity Sketch prototype for reviewing ListRunner's launch-routing and shopping-run states while refining the design specification.

## Prototype Scope

The prototype uses one Sketch page containing eleven 390x844 iPhone frames arranged as a labeled state matrix. It is an exploratory visual review artifact for evaluating behavioral questions and design decisions, not an implementation handoff or a complete wired prototype.

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

### List Management

- List editing: show an item name and quantity edit state with `Save`, a per-row `Delete` action, and an `Add item` field with an `Add` button.

### Paprika Import

- Import entry: show the empty-list state with `Import from Paprika Reminders`, the permission timing note, and a paste-list alternative.
- Imported list: show source attribution to Paprika, imported quantities, editable rows, delete controls, and the normal `Add item` and `Show Store` actions.

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
- List management makes editing, deleting, and adding items visible without relying on hidden interactions.
- Paprika import makes the entry action, permission timing, source attribution, and imported-list result visible.
- The matrix can be reviewed side by side without relying on hidden interactions.
- Each frame makes open behavioral questions easy to discuss and compare before the written specification is finalized.
