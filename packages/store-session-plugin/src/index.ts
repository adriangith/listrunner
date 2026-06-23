import { registerPlugin } from '@capacitor/core';

export interface StoreSessionPlugin {
  openSession(options: { storeId: string; url: string }): Promise<void>;
  closeSession(): Promise<void>;
  search(options: { query: string }): Promise<void>;
  setStore(options: { storeId: string }): Promise<void>;
  updateOverlay(options: { itemName: string; searchTerm: string }): Promise<void>;
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
  removeAllListeners(): Promise<void>;
}

const StoreSession = registerPlugin<StoreSessionPlugin>('StoreSession');
export default StoreSession;
