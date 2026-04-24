/** Messages between service worker, side panel, and content script. */

import type { ParsedItem, ParsedList, WizardState } from "@listrunner/core";

// ── Side Panel → Service Worker ──

export type PanelMessage =
  | { type: "PARSE_LIST"; text: string }
  | { type: "START_WIZARD"; items: ParsedItem[] }
  | {
      type: "WIZARD_ACTION";
      action:
        | "ADVANCE"
        | "SKIP"
        | "ADD_ANOTHER"
        | "UNDO"
        | "COOLDOWN_COMPLETE"
        | "BEGIN_REVISIT"
        | "DISMISS"
        | "RESET";
    }
  | { type: "EDIT_SEARCH"; index: number; searchTerm: string }
  | { type: "RETRIGGER_SEARCH" }
  | { type: "GET_STATE" }
  | { type: "SET_STORE"; storeId: string }
  | { type: "PANTRY_ADD"; name: string }
  | { type: "PANTRY_REMOVE"; name: string }
  | { type: "PANTRY_GET" }
  | { type: "MANUAL_NEXT" }
  | { type: "GET_LOUPE_HINT"; searchTerm: string }
  | { type: "CLEAR_HISTORY" };

// ── Service Worker → Side Panel ──

export type LoupeHint = {
  productName: string;
  productImageUrl: string | null;
  timestamp: number;
};

export type WorkerResponse =
  | { type: "PARSED_LIST"; data: ParsedList }
  | {
      type: "STATE_UPDATE";
      state: WizardState;
      storeId: string | null;
      automationFailed?: boolean;
      loupeHint?: LoupeHint | null;
    }
  | { type: "PANTRY_LIST"; names: string[] }
  | {
      type: "STORE_LIST";
      stores: { id: string; name: string; logoUrl?: string }[];
    }
  | { type: "LOUPE_HINT"; hint: LoupeHint | null }
  | { type: "HISTORY_CLEARED"; removed: number }
  | { type: "ERROR"; message: string };

// ── Service Worker → Content Script ──

export type ContentMessage =
  | { type: "SEARCH"; query: string; storeId: string }
  | { type: "GET_CONFIG"; storeId: string }
  | { type: "STORE_CHANGED"; storeId: string | null }
  | { type: "PING" };

// ── Content Script → Service Worker ──

export type ContentResponse =
  | {
      type: "CART_ADD_DETECTED";
      productName: string;
      productImageUrl: string | null;
    }
  | { type: "AUTOMATION_TIMEOUT"; storeId: string }
  | { type: "SEARCH_COMPLETE" }
  | { type: "CONFIG_LOADED"; storeId: string }
  | { type: "NO_CONFIG" }
  | { type: "PONG" };
