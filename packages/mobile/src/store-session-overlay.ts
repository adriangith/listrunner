import type { WizardState, WizardItem } from "@listrunner/core";
import { formatQuantity } from "./item-display.js";

export type StoreSessionOverlayMode = "automationAvailable" | "manual" | "cooldown";
export type StoreSessionOverlayCardState = "added" | "current" | "currentAdded" | "inactive";
export type StoreSessionOverlayAction =
  | "previous"
  | "next"
  | "markAdded"
  | "addAnother"
  | "undo"
  | "nextCooldown";

export interface StoreSessionOverlayCard {
  id: string;
  title: string;
  quantity: string;
  state: StoreSessionOverlayCardState;
  badge: "Manual" | null;
}

export interface StoreSessionOverlayPayload {
  mode: StoreSessionOverlayMode;
  cards: StoreSessionOverlayCard[];
  activeIndex: number;
  primaryAction: StoreSessionOverlayAction;
  secondaryAction: StoreSessionOverlayAction;
  cooldownSeconds: number | null;
  cooldownProgress: number | null;
}

export interface BuildStoreSessionOverlayPayloadOptions {
  state: WizardState;
  automationUnavailable: boolean;
  cooldownRemainingMs: number | null;
  cooldownTotalMs: number;
}

export function buildStoreSessionOverlayPayload({
  state,
  automationUnavailable,
  cooldownRemainingMs,
  cooldownTotalMs,
}: BuildStoreSessionOverlayPayloadOptions): StoreSessionOverlayPayload {
  const activeIndex = getOverlayActiveIndex(state);
  const cards = state.items.map((item, index) => cardFromItem(item, index, activeIndex, state, automationUnavailable));
  const isCooldown = state.status === "cooldown";
  const remaining = isCooldown ? Math.max(0, cooldownRemainingMs ?? cooldownTotalMs) : null;
  const progress = remaining === null ? null : 1 - remaining / cooldownTotalMs;

  return {
    mode: isCooldown ? "cooldown" : automationUnavailable ? "manual" : "automationAvailable",
    cards,
    activeIndex,
    primaryAction: isCooldown ? "nextCooldown" : "next",
    secondaryAction: isCooldown ? "undo" : "previous",
    cooldownSeconds: remaining === null ? null : Math.ceil(remaining / 1000),
    cooldownProgress: progress === null ? null : Math.max(0, Math.min(1, progress)),
  };
}

function cardFromItem(
  item: WizardItem,
  index: number,
  activeIndex: number,
  state: WizardState,
  automationUnavailable: boolean,
): StoreSessionOverlayCard {
  const isActive = index === activeIndex;
  const title = item.searchTermOverride ?? item.parsedItem.searchTerm;
  const isCooldownActive = state.status === "cooldown" && isActive;

  return {
    id: String(index),
    title,
    quantity: formatQuantity(item.parsedItem),
    state: isCooldownActive
      ? "currentAdded"
      : item.status === "added"
        ? "added"
        : isActive
          ? "current"
          : "inactive",
    badge: null,
  };
}

function getOverlayActiveIndex(state: WizardState): number {
  if (state.status === "cooldown" && state.cooldownItemIndex !== null) return state.cooldownItemIndex;
  if (state.status === "revisiting") return state.skippedIndices[state.revisitPointer] ?? state.currentIndex;
  return Math.max(0, state.currentIndex);
}
