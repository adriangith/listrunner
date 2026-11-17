# ListRunner

A native iOS shopping-list app with store-owned lists, an independent Inbox,
Paprika import via Reminders, and optional guided shopping on retailer websites.

Current product specification: `plan.md`. Native build and test instructions:
`packages/ios/README.md`.

## Current repository

The Chrome/Firefox extension has been retired. Current packages:

- `packages/ios/` — native SwiftUI app and its tests.
- `packages/core/` — shared TypeScript library and Vitest tests.
- `packages/harness/` — local web app for manual wizard testing.
- `packages/prototype/` — standalone simulated iPhone-flow prototype.

The harness and prototype are development tools, not the native app. Dated
extension and Capacitor plans/specs remain as historical references.

## Working on the core library

```bash
cd packages/core
npm install
npm test              # Vitest suite — parsing, wizard, models.
npm run typecheck
```

## Working on the harness

The harness is a standalone local web app for testing the TypeScript core's
parsing and wizard logic in a regular browser tab. It does not exercise the
native iOS implementation.

```bash
cd packages/harness
npm install
npm run dev           # Starts on http://localhost:3000
```

### How it works

1. Paste a shopping list and parse it (same parser as the extension).
2. Click **Start Wizard** — the store is hardcoded to Coles (AU).
3. For each item, click **Open Coles search** to open or reuse a dedicated Coles
   tab/window with the current search. Add the item on Coles manually, then
   return to the harness and click **Added**.
4. Skip, undo, revisit, and edit search terms all work the same as the
   core wizard.
5. Pantry exclusions and "last time you picked" hints persist in `localStorage`.

### Core dev loop

The harness builds `@listrunner/core` directly from source (via esbuild alias),
so editing `packages/core/src/*.ts` updates the harness immediately on
browser refresh. No `packages/core` rebuild step needed.

### What the harness tests well

- Parsing behaviour (quantities, cleanup, pantry filtering)
- Wizard progression, cooldown, revisit flow
- Search term quality against real Coles searches
- Edit-search overrides
- Pantry list management and selection history

### What it does not test

- Add-to-cart auto-detection
- Content-script selectors
- Native iOS UI, persistence, Reminders integration or WebKit behaviour

## Store configs

Native retailer definitions live in `packages/ios/ListRunner/Resources`.
Search, cart detection and cart Undo are independently verified capabilities;
registration alone does not mean a retailer supports all three.
See `docs/adding-a-store.md` and `packages/ios/VALIDATION.md`.

## Keyboard shortcuts in the harness wizard

| Key | Action |
|---|---|
| `S` | Skip current item |
| `E` | Focus the edit-search input |
| `Space` / `Enter` | Advance during cooldown |
| `U` | Undo during cooldown |
| `A` | Add another during cooldown |
| `D` | Dismiss (revisit only) |
| `R` | Revisit skipped items (done view) |
| `?` | Toggle the shortcut help overlay |

## Harness storage

The harness stores pantry entries and a local "last time you picked" history
in the browser; history can be cleared from its pantry settings view.
