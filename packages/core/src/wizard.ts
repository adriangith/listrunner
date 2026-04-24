import type {
  WizardState,
  WizardAction,
  WizardItem,
  ParsedItem,
} from "./types.js";

/** Creates the initial idle wizard state. */
export function createWizardState(): WizardState {
  return {
    status: "idle",
    items: [],
    currentIndex: -1,
    skippedIndices: [],
    revisitPointer: -1,
    cooldownItemIndex: null,
  };
}

/** Returns the currently active wizard item, or null. */
export function currentItem(state: WizardState): WizardItem | null {
  if (state.status === "revisiting") {
    const skippedIdx = state.skippedIndices[state.revisitPointer];
    return skippedIdx !== undefined ? (state.items[skippedIdx] ?? null) : null;
  }
  return state.items[state.currentIndex] ?? null;
}

/** Returns the number of items that have been added to cart. */
export function addedCount(state: WizardState): number {
  return state.items.filter((i) => i.status === "added").length;
}

/** Returns the total number of items in the wizard. */
export function totalCount(state: WizardState): number {
  return state.items.length;
}

/**
 * Pure reducer: applies a WizardAction to produce a new WizardState.
 * Throws on invalid transitions.
 */
export function wizardReducer(
  state: WizardState,
  action: WizardAction,
): WizardState {
  switch (action.type) {
    case "START":
      return handleStart(state, action.items);
    case "ADVANCE":
      return handleAdvance(state);
    case "SKIP":
      return handleSkip(state);
    case "ADD_ANOTHER":
      return handleAddAnother(state);
    case "UNDO":
      return handleUndo(state);
    case "COOLDOWN_COMPLETE":
      return handleCooldownComplete(state);
    case "BEGIN_REVISIT":
      return handleBeginRevisit(state);
    case "EDIT_SEARCH":
      return handleEditSearch(state, action.index, action.searchTerm);
    case "DISMISS":
      return handleDismiss(state);
    case "RESET":
      return createWizardState();
  }
}

function toWizardItems(items: ParsedItem[]): WizardItem[] {
  return items.map((parsedItem) => ({
    parsedItem,
    searchTermOverride: null,
    status: "pending" as const,
  }));
}

function handleStart(state: WizardState, items: ParsedItem[]): WizardState {
  if (state.status !== "idle") {
    throw new Error(`Cannot START from status "${state.status}"`);
  }
  if (items.length === 0) {
    return { ...state, status: "done", items: [] };
  }
  const wizardItems = toWizardItems(items);
  wizardItems[0] = { ...wizardItems[0]!, status: "active" };
  return {
    ...state,
    status: "stepping",
    items: wizardItems,
    currentIndex: 0,
    skippedIndices: [],
    revisitPointer: -1,
    cooldownItemIndex: null,
  };
}

function handleAdvance(state: WizardState): WizardState {
  if (state.status !== "stepping" && state.status !== "revisiting") {
    throw new Error(`Cannot ADVANCE from status "${state.status}"`);
  }

  // Mark current item as added
  const items = [...state.items];
  const activeIdx = getActiveIndex(state);
  items[activeIdx] = { ...items[activeIdx]!, status: "added" };

  // Enter cooldown
  return {
    ...state,
    items,
    status: "cooldown",
    cooldownItemIndex: activeIdx,
  };
}

function handleCooldownComplete(state: WizardState): WizardState {
  if (state.status !== "cooldown") {
    throw new Error(`Cannot COOLDOWN_COMPLETE from status "${state.status}"`);
  }
  return moveToNext({
    ...state,
    cooldownItemIndex: null,
  });
}

function handleSkip(state: WizardState): WizardState {
  if (state.status !== "stepping" && state.status !== "revisiting") {
    throw new Error(`Cannot SKIP from status "${state.status}"`);
  }

  const items = [...state.items];
  const activeIdx = getActiveIndex(state);
  items[activeIdx] = { ...items[activeIdx]!, status: "skipped" };

  const newState = { ...state, items };

  if (state.status === "revisiting") {
    // During revisit, move to next revisit item
    return moveToNextRevisit(newState);
  }

  // Add to skipped list and move on
  newState.skippedIndices = [...state.skippedIndices, activeIdx];
  return moveToNext(newState);
}

function handleAddAnother(state: WizardState): WizardState {
  if (state.status !== "cooldown") {
    throw new Error(`Cannot ADD_ANOTHER from status "${state.status}"`);
  }

  // Cancel cooldown, stay on same item
  const items = [...state.items];
  const idx = state.cooldownItemIndex!;
  items[idx] = { ...items[idx]!, status: "active" };

  // Determine if we were in revisiting mode before cooldown
  const wasRevisiting = state.skippedIndices.includes(idx);

  return {
    ...state,
    items,
    status: wasRevisiting ? "revisiting" : "stepping",
    cooldownItemIndex: null,
  };
}

function handleUndo(state: WizardState): WizardState {
  if (state.status !== "cooldown") {
    throw new Error(`Cannot UNDO from status "${state.status}"`);
  }

  const items = [...state.items];
  const idx = state.cooldownItemIndex!;
  items[idx] = { ...items[idx]!, status: "active" };

  const wasRevisiting = state.skippedIndices.includes(idx);

  return {
    ...state,
    items,
    status: wasRevisiting ? "revisiting" : "stepping",
    cooldownItemIndex: null,
  };
}

function handleBeginRevisit(state: WizardState): WizardState {
  // Allow from stepping (all items done) or when status transitions to needing revisit
  if (state.skippedIndices.length === 0) {
    return { ...state, status: "done" };
  }

  const items = [...state.items];
  const firstSkippedIdx = state.skippedIndices[0]!;
  items[firstSkippedIdx] = { ...items[firstSkippedIdx]!, status: "active" };

  return {
    ...state,
    items,
    status: "revisiting",
    revisitPointer: 0,
  };
}

function handleEditSearch(
  state: WizardState,
  index: number,
  searchTerm: string,
): WizardState {
  const items = [...state.items];
  items[index] = { ...items[index]!, searchTermOverride: searchTerm };
  return { ...state, items };
}

function handleDismiss(state: WizardState): WizardState {
  if (state.status !== "revisiting") {
    throw new Error(`Cannot DISMISS from status "${state.status}"`);
  }

  const items = [...state.items];
  const activeIdx = getActiveIndex(state);
  items[activeIdx] = { ...items[activeIdx]!, status: "dismissed" };

  return moveToNextRevisit({ ...state, items });
}

// ── Helpers ──

function getActiveIndex(state: WizardState): number {
  if (state.status === "revisiting" || state.status === "cooldown") {
    if (state.cooldownItemIndex !== null) return state.cooldownItemIndex;
    const idx = state.skippedIndices[state.revisitPointer];
    if (idx !== undefined) return idx;
  }
  return state.currentIndex;
}

function moveToNext(state: WizardState): WizardState {
  const nextIndex = state.currentIndex + 1;

  if (nextIndex >= state.items.length) {
    // All primary items processed. The Done view decides whether to offer a
    // revisit pass based on the presence of skipped items.
    return { ...state, status: "done", currentIndex: nextIndex };
  }

  const items = [...state.items];
  items[nextIndex] = { ...items[nextIndex]!, status: "active" };

  return {
    ...state,
    items,
    status: "stepping",
    currentIndex: nextIndex,
  };
}

function moveToNextRevisit(state: WizardState): WizardState {
  const nextPointer = state.revisitPointer + 1;

  if (nextPointer >= state.skippedIndices.length) {
    return { ...state, status: "done", revisitPointer: nextPointer };
  }

  const items = [...state.items];
  const nextIdx = state.skippedIndices[nextPointer]!;
  items[nextIdx] = { ...items[nextIdx]!, status: "active" };

  return {
    ...state,
    items,
    status: "revisiting",
    revisitPointer: nextPointer,
  };
}
