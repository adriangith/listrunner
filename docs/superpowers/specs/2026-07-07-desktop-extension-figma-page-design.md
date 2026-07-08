# ListRunner Desktop Extension Figma Page Design

**Date:** 2026-07-07  
**Status:** Approved design direction, pending spec review  
**Target:** New page in the existing Figma file

## Goal

Create a new Figma page for the ListRunner desktop browser extension. The page should show the full side-panel flow and use the mobile UI mockup as the visual foundation, adapted for desktop extension constraints.

## Source Context

The desktop extension UI is implemented in `packages/extension/public/side-panel.html`, `packages/extension/public/side-panel.css`, and `packages/extension/src/side-panel/side-panel.ts`.

The extension currently has these views:

- Input view: paste or import a shopping list, then parse it.
- Review view: choose a store, review parsed items, restore pantry-filtered items, add items, and start the wizard.
- Wizard view: show progress, current item, editable search term, loupe hint, shortcuts, skip/dismiss actions, cooldown, and automation warning states.
- Done view: summarize added, skipped, and dismissed items, with revisit and new-list actions.
- Pantry view: manage never-add items and clear local selection history.
- Shortcuts overlay: show keyboard shortcuts for wizard actions.

The visual direction should be based on the existing mobile mockup spec: soft off-white backgrounds, elevated white cards, rounded corners, Apple-blue primary actions, green success states, amber warning states, blue loupe/quantity accents, and friendly grocery-assistant hierarchy.

## Figma Page Structure

Create one new page named `Desktop Extension`.

Include eight frames arranged left-to-right or in a tidy grid:

- `01 Input`
- `02 Review`
- `03 Wizard`
- `04 Wizard Cooldown`
- `05 Wizard Warning`
- `06 Done`
- `07 Pantry`
- `08 Shortcuts Overlay`

Each frame should represent a browser extension side panel, approximately `380 x 720` pixels. The frames should not use phone chrome or mobile safe-area treatments.

## Visual Direction

The desktop extension should feel like the mobile app's sibling, not a direct copy.

Use:

- Compact browser-extension density.
- Soft off-white page background.
- White cards with subtle borders and shadows.
- Rounded controls, around 10-16 px radius depending on size.
- Apple-blue primary buttons and focus accents.
- Green success treatment for added/completed states.
- Amber warning treatment for automation fallback.
- Blue-tinted loupe hint and quantity/progress treatments.
- System typography matching the current app: `-apple-system`, BlinkMacSystemFont, `Segoe UI`, Roboto, sans-serif.

Desktop-specific affordances should be visible: keyboard shortcuts, editable fields, compact item rows, a store selector, and a small settings/pantry action in the header.

## Screen Requirements

### 01 Input

Show the ListRunner brand, pantry/settings action, a helper line, a populated multiline shopping-list input, an import-file action, and a primary parse action.

Use realistic grocery text such as eggs, flour, chicken breast, tomatoes, basil, and mozzarella.

### 02 Review

Show a store selector with Australian grocery stores, a parsed list with quantity chips or compact quantity labels, editable search terms, remove controls, an add-item row, a filtered-out pantry section, and Back / Start Wizard actions.

### 03 Wizard

Show the main active state: progress bar, current item, quantity, editable search term, update action, loupe hint, skip action, shortcut affordance, and exit/back-to-list action.

This is the core screen and should receive the strongest visual polish.

### 04 Wizard Cooldown

Show the success state after an item is added. Include green success styling, a countdown message such as `Added! Next item in 2s...`, and actions for Add another and Undo.

### 05 Wizard Warning

Show the automation fallback state. Include the current item, editable search term, amber warning card explaining that automation is not working, a manual next action, and a report issue link.

### 06 Done

Show a friendly completion summary with counts for added, skipped, and dismissed items. Include Revisit skipped items and New List actions.

### 07 Pantry

Show pantry settings with a back action, helper copy, add-item field, sample never-add rows, clear selection history action, and a small local-data explanation.

### 08 Shortcuts Overlay

Show the wizard screen dimmed behind a modal card. The modal should list these keyboard shortcuts: S, E, Space/Enter, U, A, D, and R.

## Success Criteria

- A Figma page named `Desktop Extension` exists.
- The page contains all eight frames.
- The frames reflect the current extension's actual side-panel views and states.
- The design visually relates to the mobile mockup while fitting a desktop extension side panel.
- The mockup is polished enough to guide future implementation work.

## Out Of Scope

- Changing extension code.
- Building a full reusable Figma component library.
- Designing popup, options-page, or marketing screens.
- Creating dark-mode variants.
- Pixel-perfect reproduction of the current CSS.
