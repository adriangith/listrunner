# ListRunner Mobile Figma Recreation Design

**Date:** 2026-07-06  
**Status:** Approved for implementation planning  
**Target:** New Figma design file

## Goal

Recreate the current ListRunner mobile app as a polished iOS product mockup in a new Figma file. The mockup should preserve the actual app flow and screen inventory from `packages/mobile`, while improving visual polish, hierarchy, and presentation quality.

## Source Context

The current mobile app is a Capacitor/Vite iOS app in `packages/mobile`. Its UI is defined by `index.html`, `src/app.css`, and `src/main.ts`.

Primary views:

- Input view: paste shopping list, parse list, pantry settings, Paprika Reminders import.
- Review view: parsed list, excluded pantry items, add item, back, start wizard.
- Wizard view: progress, current item, quantity chip, editable search term, loupe hint, warning states, cooldown state, skip/added/undo/add-another/dismiss actions, shortcuts overlay.
- Done view: completion summary, revisit skipped, new list.
- Pantry view: add pantry item, pantry list, empty state, clear history, back.

## Design Direction

Use a polished iOS-style grocery assistant visual language:

- Modern iPhone 15/16-sized frames.
- Soft off-white app background.
- White elevated cards with rounded corners.
- Apple-blue primary actions.
- Green success accents for added/completed states.
- Amber warning accents for automation and reminder warnings.
- Blue quantity chips and subtle progress indicators.
- Bottom-safe-area action layouts with large touch targets.
- Clean native-feeling typography using SF-style system fonts.

The design should look like a plausible production iOS app, not a literal browser-rendered copy of the current HTML/CSS.

## Figma File Structure

Create one new Figma design file named `ListRunner Mobile Mockup`.

Include a main page with these frames:

- `01 Input`
- `02 Review`
- `03 Wizard`
- `04 Wizard Cooldown`
- `05 Wizard Warning`
- `06 Done`
- `07 Pantry`
- `08 Shortcuts Overlay`

Each frame should use an iPhone 15/16 portrait canvas, approximately 393 by 852 points.

## Screen Requirements

### Input

Show the ListRunner brand, a short helper subtitle, a large multiline shopping-list input card, and actions for parsing the list, pantry settings, and loading Paprika Reminders.

Use realistic sample grocery text so the screen reads as populated and understandable.

### Review

Show a parsed list with quantities and item names. Include a count summary, an excluded pantry section, an add-item row, and bottom actions for Back and Start Wizard.

Items should demonstrate the quantity-chip treatment from the current app.

### Wizard

Show the active shopping step with progress, current item, quantity, editable search term, loupe hint, and main actions for Skip and Added.

This should be the most polished core screen because it represents the main app experience.

### Wizard Cooldown

Show the added-success state after an item is added. Include a green success treatment, countdown/progress affordance, and actions for Undo and Add Another.

### Wizard Warning

Show the automation fallback state. Include the current item, editable search term, an amber warning card explaining that automation is unavailable, and manual controls.

### Done

Show a friendly completion summary with added and skipped counts, a list-style summary, and actions for Revisit Skipped and New List.

### Pantry

Show pantry settings with an add-item field, sample pantry exclusions, a clear-history control, and a back action.

### Shortcuts Overlay

Show the wizard screen dimmed with a modal sheet listing the keyboard shortcuts from the current app: S, E, Space/Enter, U, A, D, and R.

## Component Guidance

Create reusable visual patterns directly in Figma where useful:

- Primary and secondary buttons.
- Text input and multiline input fields.
- Quantity chips.
- Item rows.
- Warning and success cards.
- Progress bars.
- Modal sheet.

The file does not need a full formal design system page unless it can be added without slowing the main recreation.

## Success Criteria

- A new Figma file exists and is shareable.
- All eight requested frames are present.
- The frames reflect the current app’s actual screens and states.
- The visual design is more polished than the current HTML/CSS implementation.
- The mockup is useful both for presentation and future implementation reference.

## Out Of Scope

- Implementing code changes in the app.
- Building a full Figma component library.
- Designing Android or compact iPhone SE variants.
- Creating marketing screens unrelated to the current app flow.
- Capturing the current web app pixel-perfectly.
