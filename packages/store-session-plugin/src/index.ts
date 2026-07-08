import { registerPlugin } from '@capacitor/core';

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
  secondaryEnabled: boolean;
  cooldownSeconds: number | null;
  cooldownProgress: number | null;
}

export interface StoreSessionPlugin {
  openSession(options: { storeId: string; url: string }): Promise<void>;
  closeSession(): Promise<void>;
  search(options: { query: string }): Promise<void>;
  setStore(options: { storeId: string }): Promise<void>;
  updateOverlay(options: StoreSessionOverlayPayload & { itemName: string; searchTerm: string }): Promise<void>;
  addListener(
    eventName: 'pageReady',
    listenerFunc: () => void,
  ): Promise<any>;
  addListener(
    eventName: 'selectorReady',
    listenerFunc: () => void,
  ): Promise<any>;
  addListener(
    eventName: 'skipRequested',
    listenerFunc: () => void,
  ): Promise<any>;
  addListener(
    eventName: 'automationTimeout',
    listenerFunc: () => void,
  ): Promise<any>;
  addListener(
    eventName: 'addToCartDetected',
    listenerFunc: (info: { productName: string; productImageUrl: string | null }) => void,
  ): Promise<any>;
  addListener(
    eventName: 'urlChanged',
    listenerFunc: (info: { url: string }) => void,
  ): Promise<any>;
  addListener(eventName: 'previousRequested', listenerFunc: () => void): Promise<any>;
  addListener(eventName: 'nextRequested', listenerFunc: () => void): Promise<any>;
  addListener(eventName: 'markAddedRequested', listenerFunc: () => void): Promise<any>;
  addListener(eventName: 'addAnotherRequested', listenerFunc: () => void): Promise<any>;
  addListener(eventName: 'undoRequested', listenerFunc: () => void): Promise<any>;
  addListener(eventName: 'cardSelected', listenerFunc: (info: { index: number }) => void): Promise<any>;
  removeAllListeners(): Promise<void>;
}

const StoreSession = registerPlugin<StoreSessionPlugin>('StoreSession');
export default StoreSession;
