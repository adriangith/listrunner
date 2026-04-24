# ListRunner

A shopping-list wizard. Paste a shopping list, pick a store, and ListRunner
steps you through each item on the store's actual website — pre-filling the
search, detecting when you add to cart, and advancing automatically.

Design spec: [`docs/superpowers/specs/2026-03-29-listrunner-design.md`](docs/superpowers/specs/2026-03-29-listrunner-design.md).

## Layout

```
packages/
├─ core/         Shared TypeScript library (parsing, wizard state machine,
│                pantry + selection history). No browser dependencies; the
│                same code is consumable from native mobile shells.
└─ extension/    Chrome + Firefox extension (MV3). Depends on @listrunner/core.
```

## Working on the core library

```bash
cd packages/core
npm install
npm test              # Vitest suite — parsing, wizard, models.
npm run typecheck
npm run build         # Emits to dist/; required before the extension builds.
```

## Working on the extension

```bash
cd packages/extension
npm install
npm run build         # → dist/chrome/ and dist/firefox/
npm run watch         # Rebuilds on file change.
npm run typecheck
```

### Load the Chrome build

1. Open `chrome://extensions`.
2. Toggle **Developer mode** on.
3. Click **Load unpacked** and select `packages/extension/dist/chrome`.
4. Click the ListRunner icon (or open the side panel from the extensions menu).

### Load the Firefox build

1. Open `about:debugging#/runtime/this-firefox`.
2. Click **Load Temporary Add-on…** and select any file inside
   `packages/extension/dist/firefox` (e.g. `manifest.json`).
3. Open the sidebar from Firefox's View → Sidebar → ListRunner menu.

## Store configs

Store automation is defined per-store in `packages/extension/src/store-configs`.
Each config declares the URL pattern, search method, and CSS selectors used to
detect cart-add clicks and extract product info.

Currently supported:
- Woolworths (AU)
- Coles (AU)
- IGA (AU)

Adding a new store is typically a couple of selectors plus a URL template. The
wizard's manual-fallback mode kicks in automatically when selectors don't
resolve, so broken configs degrade gracefully instead of stranding the user.

## Keyboard shortcuts in the wizard

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

## Privacy

ListRunner never sees your store login, password, or payment details. It only
reads the public shelf pages to locate search inputs and add-to-cart buttons.
Pantry entries and a local "last time you picked" history are stored in the
browser; the history can be cleared anytime from the pantry settings view.
