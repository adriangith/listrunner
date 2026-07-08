# iOS Store Session Card Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make native store-session cards fully swipeable and selectable.

**Architecture:** The TypeScript wizard remains the source of truth. Swift emits `cardSelected(index)` for card body taps; TypeScript dispatches a new `SELECT_INDEX` reducer action and repeats the search. Swift expands carousel touch handling so the full visible card region scrolls.

**Tech Stack:** TypeScript, Vitest/node:test, Capacitor 8, Swift UIKit/WKWebView, Xcode.

## Global Constraints

- Keep implementation UIKit-only; no SwiftUI or new dependencies.
- Do not make card action buttons also select the card.
- Ignore card selection during cooldown.
- Run tests from `packages/core`, `packages/mobile`, and builds from `packages/mobile`/`packages/store-session-plugin`.

---

### Task 1: Add Wizard Card Selection

**Files:**
- Modify: `packages/core/src/types.ts`
- Modify: `packages/core/src/wizard.ts`
- Modify: `packages/core/tests/wizard.test.ts`

**Interfaces:**
- Produces: `WizardAction` supports `{ type: "SELECT_INDEX"; index: number }`.
- Produces: `wizardReducer(state, { type: "SELECT_INDEX", index })` selects a valid item during `stepping` or `revisiting`, keeps statuses coherent, and throws during cooldown.

- [ ] **Step 1:** Write failing reducer tests for selecting another item, repeating selection of current item, and rejecting cooldown selection.
- [ ] **Step 2:** Run `npm test` in `packages/core` and verify failures.
- [ ] **Step 3:** Implement `SELECT_INDEX` action and reducer handling.
- [ ] **Step 4:** Run `npm test` in `packages/core` and verify pass.

### Task 2: Wire Native Card Selection Event

**Files:**
- Modify: `packages/store-session-plugin/src/index.ts`
- Modify: `packages/store-session-plugin/ios/StoreSessionViewController.swift`
- Modify: `packages/mobile/src/main.ts`

**Interfaces:**
- Produces native event: `cardSelected` with `{ index: number }`.
- Consumes: `SELECT_INDEX` reducer action from Task 1.

- [ ] **Step 1:** Add TypeScript listener type for `cardSelected`.
- [ ] **Step 2:** Add Swift tap recognizer to each card body and emit `cardSelected` with the card index.
- [ ] **Step 3:** Add TypeScript listener that dispatches `SELECT_INDEX` and repeats search.
- [ ] **Step 4:** Run `npm run build` in `packages/mobile` and `packages/store-session-plugin`.

### Task 3: Expand Carousel Swipe Hit Area

**Files:**
- Modify: `packages/store-session-plugin/ios/StoreSessionViewController.swift`

**Interfaces:**
- Produces: full visible card area can receive scroll/tap touches.

- [ ] **Step 1:** Move the scroll view to cover the protruding card region rather than only the panel area.
- [ ] **Step 2:** Override hit testing so overlay subviews can receive touches outside `overlayView.bounds`.
- [ ] **Step 3:** Run Xcode simulator build.

### Task 4: Sync To Mac And Install

**Files:**
- Mac checkout: `/Users/adrianzafir/Projects/listrunner-ios-test`

- [ ] **Step 1:** Copy touched files to the Mac checkout.
- [ ] **Step 2:** Run `npm test`, `npm run build`, `npm run cap:sync`, and Xcode build on Mac.
- [ ] **Step 3:** Install and launch on `Adrian’s iPhone` if a signed app is available.
