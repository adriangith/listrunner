# ListRunner — Design Spec

**Date:** 2026-03-29
**Status:** Draft

## Overview

ListRunner is a shopping list wizard that takes a user's shopping list from any source and steps them through each item on a real online store's website. It auto-fills searches, lets the user pick the exact product they want, adds it to their cart, and advances to the next item. The goal is to eliminate the repetitive search-click-add friction of online grocery shopping while keeping the human in the loop for product selection.

## Target Audience

Broad consumer audience — the tool should be polished and accessible to anyone who shops for groceries online.

## Out of Scope

- Meal planning / recipe selection
- Auto-adding products without user confirmation
- Store account management, payment processing, or order tracking
- Favourite products or smart suggestions (future feature, but selection history is captured from day one)
- Android (second platform, after iOS is validated)

## Core User Flow

1. **Import list** — The user gets their shopping list into ListRunner via one of several input methods (share sheet, clipboard, file import, manual entry, or browser context menu).
2. **Review parsed list** — ListRunner parses the input into structured items with extracted product names and quantities. The user reviews and can edit before starting.
3. **Choose store** — User picks a store from the community-supported list. The store's website opens (in-browser on desktop, in-app browser on mobile).
4. **Step through items** — For each item:
   - ListRunner auto-fills the store's search with the parsed product name.
   - The user browses results on the actual store page and picks a product.
   - ListRunner detects the add-to-cart action.
   - A cooldown bar appears ("Added! Next item in 3s...") with "Add another" and "Undo" options.
   - After cooldown, the wizard advances to the next item.
5. **Skip & revisit** — The user can skip any item. After all items are processed, the wizard offers to revisit skipped items. On revisit, the user can edit the search term before retrying.
6. **Done** — Summary of what was added and what was skipped/unresolved. The user proceeds to checkout on the store's site normally.

## Architecture

### Three Main Components

#### 1. ListRunner Core (shared TypeScript library)

- **List parsing engine** — takes raw text/structured input and extracts item names, quantities, and units using intelligent cleanup.
- **Pantry exclusion list management** — filters out items the user has marked as always-skip.
- **Wizard state machine** — tracks current item, skipped items, progress, cooldown state.
- **Account sync client** — communicates with backend for pantry list and selection history sync.
- **Selection history capture** — silently records product picks per store for future loupe hints.

#### 2. Platform Clients

**Desktop: Browser Extension (Chrome + Firefox initially, Safari later)**
- Content script injected into store pages — reads DOM, auto-fills search, detects add-to-cart clicks.
- Extension popup/sidebar for list import, store selection, and wizard controls.
- Store configs define selectors and interactions per store site.
- Built with standard WebExtension APIs (Manifest V3 for Chrome).

**Mobile: iOS App (Android later)**
- Swift/SwiftUI shell with WKWebView for the store browser.
- Shared core compiled to JS and run in the WebView context (or bridged via native-to-JS messaging).
- Minimal wizard bar overlaid at top/bottom — current item, progress (e.g., "3/12"), skip button.
- Loupe peek — expand the bar for item details and product image from past selections.
- Share sheet extension for receiving lists from other apps.

#### 3. Backend (lightweight)

- **Auth service** — email + password or social auth (Google, Apple Sign-In).
- **Pantry exclusion list** — CRUD + sync.
- **Selection history storage** — store, search term, product name, product image URL, timestamp. Append-only.
- **Store config manifest** — serves the latest community configs to clients.

**Tech stack:** Node.js API, PostgreSQL database, hosted on Fly.io/Railway or similar.

## List Input & Parsing

### Input Methods

| Method | Platform | Description |
|--------|----------|-------------|
| Share sheet | iOS | Receive text from Paprika, Reminders, Notes, any app |
| Clipboard paste | All | "Paste list" button in extension popup or app |
| File import | All | Accepts .txt, .csv, or common recipe export formats |
| Manual entry | All | Type/edit items directly in the wizard |
| Context menu | Desktop | Right-click selected text → "Send to ListRunner" |

### Parsing Pipeline

1. **Split** — Break raw text into individual items (by newline, comma, or bullet).
2. **Quantity extraction** — Pull out numbers, units, and multipliers ("2x", "500g", "1 can").
3. **Product name extraction** — Intelligent cleanup:
   - Strip preparation instructions ("sliced", "diced", "finely chopped", "to taste").
   - Strip container descriptions ("1 can (400g)" → keep "400g" as context, search for the product name).
   - Collapse to the searchable product term ("200g fresh mozzarella, sliced" → "fresh mozzarella").
4. **Pantry filter** — Check against the user's exclusion list. Filtered items are removed but shown in a "Filtered out" section the user can review.
5. **Review screen** — User sees the parsed list with extracted search terms and quantities. They can edit any item, remove items, or restore filtered items before starting.

Parsing is best-effort and transparent — the review screen is the safety net.

## Wizard Interaction Detail

### Step-Through Cycle

1. **Search** — Wizard injects the parsed search term into the store's search. The store page updates with results.
2. **Browse & select** — User scrolls through results on the actual store page. They click "add to cart" on whichever product they want, adjusting quantity if needed.
3. **Detection & cooldown** — Wizard detects the add-to-cart action (via DOM mutation or network interception, per store config). A cooldown bar appears: "Added! Next item in 3s..." with:
   - **"Add another"** — stays on this item, resets the cooldown.
   - **"Undo"** — removes the last product from cart (if store supports it, otherwise rewinds the wizard step) and stays on the item.
4. **Advance** — After cooldown, the wizard clears the search and injects the next item. Progress indicator updates.
5. **Skip** — At any point the user can skip. Item moves to the revisit list.

### Revisit Loop

After the last item, if there are skipped items: "You have N skipped items. Revisit them?" For each revisited item, the user can edit the search term before the wizard searches again. They can also permanently dismiss an item.

### Edge Cases

- **Store page navigation** — If the user navigates away from search results (e.g., product detail page), the wizard waits. When they return or add to cart, it picks back up.
- **Config failure** — If expected selectors aren't found within a timeout, the wizard shows "Automation isn't working for this store. You can search and add manually." A fallback "Next" button appears for manual advancement.
- **Empty search results** — The wizard offers "Edit search term" or "Skip."

## Store Config System

### Config Structure

Each store is defined in a JSON file in a public GitHub repo:

- **Store metadata:** name, logo URL, supported regions/countries, base URL.
- **Search:** URL pattern (e.g., "/search?q={query}") or input selector + submit method.
- **Results:** product container selector, product name selector, price selector.
- **Add to cart:** button selector, quantity input selector, cart change detection method.
- **Cart detection:** strategy — DOM mutation observer, network request intercept, or polling.
- **Fallback:** manual mode trigger conditions.

### Versioning

Each config has a schema version. Old configs continue to work until explicitly migrated. Breaking changes bump the major version.

### Community Contribution Flow

1. Contributor forks the store config repo.
2. Adds/updates a store JSON file following the schema.
3. Opens a PR — automated CI validates the config against the schema.
4. Maintainers review and merge.
5. Clients pull updated configs periodically (or on demand).

### Config Delivery

The backend serves a config manifest (list of stores + versions). Clients cache configs locally and check for updates on launch. If the backend is unreachable, cached configs still work.

### Broken Config Handling

- Client-side detection: if expected selectors aren't found within a timeout, the config is flagged as potentially broken.
- User can tap "Report issue" which opens a pre-filled GitHub issue on the config repo.
- Wizard falls back to manual mode for that store.

## Account & Data

### Account System

- Email + password or social auth (Google, Apple Sign-In).
- Account is **optional** for basic usage — the wizard works without one using local storage.
- Signing in enables: pantry list sync across devices, selection history for loupe hints.

### Data Model

**Pantry exclusion list:**
- List of item names the user wants to always skip.
- Sync model: last-write-wins per item, synced on app launch and on change.

**Selection history (per entry):**
- Store identifier
- Search term used
- Product name and image URL (scraped from the store page at time of selection)
- Timestamp
- Sync model: append-only, synced in background.

### Privacy

ListRunner never touches the user's store login or payment details. It only automates the search-and-browse part of the store's public-facing website.

## Initial Scope

- **Stores:** Coles and Woolworths (Australia) as the first two configs.
- **Platforms:** Chrome extension + iOS app.
- **Account features:** Pantry exclusion list sync only. Selection history captured silently for future use.
- **Android and Safari extension:** Deferred to later phases.
