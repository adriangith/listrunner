/** A raw item extracted from splitting input text. */
export interface RawItem {
  /** The original text of the item as written by the user. */
  original: string;
}

/** Extracted quantity information from an item string. */
export interface Quantity {
  amount: number;
  unit: string | null;
}

/** An item after quantity extraction. */
export interface ItemWithQuantity {
  original: string;
  quantity: Quantity | null;
  /** The remaining text after quantity has been removed. */
  remaining: string;
}

/** A fully parsed shopping list item ready for review. */
export interface ParsedItem {
  original: string;
  quantity: Quantity | null;
  /** The cleaned search term to use on the store. */
  searchTerm: string;
  /** Whether this item was filtered out by the pantry exclusion list. */
  filtered: boolean;
}

/** The result of parsing a full shopping list. */
export interface ParsedList {
  items: ParsedItem[];
  filtered: ParsedItem[];
}

/** Options for the parsing pipeline. */
export interface ParseOptions {
  /** Items to exclude (pantry exclusion list). Case-insensitive match. */
  pantryExclusions?: string[];
}

// ── Wizard types ──

export type WizardStatus =
  | "idle"
  | "stepping"
  | "cooldown"
  | "revisiting"
  | "done";

export interface WizardItem {
  parsedItem: ParsedItem;
  /** Overridden search term (e.g., user edited during revisit). */
  searchTermOverride: string | null;
  status: "pending" | "active" | "added" | "skipped" | "dismissed";
}

export interface WizardState {
  status: WizardStatus;
  items: WizardItem[];
  currentIndex: number;
  /** Indices of items that were skipped and need revisiting. */
  skippedIndices: number[];
  /** Index within the revisit list (used during "revisiting" status). */
  revisitPointer: number;
  cooldownItemIndex: number | null;
}

export type WizardAction =
  | { type: "START"; items: ParsedItem[] }
  | { type: "ADVANCE" }
  | { type: "SKIP" }
  | { type: "PREVIOUS" }
  | { type: "SELECT_INDEX"; index: number }
  | { type: "ADD_ANOTHER" }
  | { type: "UNDO" }
  | { type: "COOLDOWN_COMPLETE" }
  | { type: "BEGIN_REVISIT" }
  | { type: "EDIT_SEARCH"; index: number; searchTerm: string }
  | { type: "DISMISS" }
  | { type: "RESET" };

// ── Data models ──

export interface PantryItem {
  name: string;
  addedAt: number;
}

export interface SelectionRecord {
  store: string;
  searchTerm: string;
  productName: string;
  productImageUrl: string | null;
  timestamp: number;
}
