import {
  parseList,
  createWizardState,
  wizardReducer,
  currentItem,
  PantryList,
  SelectionHistory,
} from "@listrunner/core";
import type { WizardState, WizardAction } from "@listrunner/core";
import type { PanelMessage, WorkerResponse, ContentResponse } from "../messages.js";
import { getAllStoreConfigs, getStoreConfig } from "../store-configs/index.js";

let wizardState: WizardState = createWizardState();
let activeStoreId: string | null = null;
const pantry = new PantryList();
const history = new SelectionHistory();

// Load persisted data on startup
loadPersistedData();

// Open side panel when extension icon is clicked
chrome.action.onClicked.addListener((tab) => {
  if (tab.id) {
    chrome.sidePanel.open({ tabId: tab.id });
  }
});

// Context menu: right-click selected text → Send to ListRunner
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "send-to-listrunner",
    title: "Send to ListRunner",
    contexts: ["selection"],
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === "send-to-listrunner" && info.selectionText && tab?.id) {
    chrome.sidePanel.open({ tabId: tab.id });
    // Store the text so the side panel can pick it up
    chrome.storage.session.set({ pendingListText: info.selectionText });
  }
});

// Handle messages from side panel
chrome.runtime.onMessage.addListener((message: PanelMessage, _sender, sendResponse) => {
  const response = handleMessage(message);
  sendResponse(response);
  return true; // keep channel open for async
});

// Handle cart detection from content scripts
chrome.runtime.onMessage.addListener((message: ContentResponse, _sender, sendResponse) => {
  if (message.type === "CART_ADD_DETECTED") {
    handleCartDetected(message.productName, message.productImageUrl);
    sendResponse({ type: "STATE_UPDATE", state: wizardState, storeId: activeStoreId });
  }
  return true;
});

function handleMessage(message: PanelMessage): WorkerResponse {
  switch (message.type) {
    case "PARSE_LIST": {
      const data = parseList(message.text, {
        pantryExclusions: pantry.getNames(),
      });
      return { type: "PARSED_LIST", data };
    }

    case "START_WIZARD": {
      try {
        wizardState = wizardReducer(createWizardState(), {
          type: "START",
          items: message.items,
        });
        triggerSearch();
        return { type: "STATE_UPDATE", state: wizardState, storeId: activeStoreId };
      } catch (e) {
        return { type: "ERROR", message: String(e) };
      }
    }

    case "WIZARD_ACTION": {
      try {
        const action: WizardAction = { type: message.action };
        wizardState = wizardReducer(wizardState, action);

        if (message.action === "COOLDOWN_COMPLETE") {
          // After cooldown completes, trigger search for next item
          if (wizardState.status === "stepping" || wizardState.status === "revisiting") {
            triggerSearch();
          }
        }

        return { type: "STATE_UPDATE", state: wizardState, storeId: activeStoreId };
      } catch (e) {
        return { type: "ERROR", message: String(e) };
      }
    }

    case "EDIT_SEARCH": {
      wizardState = wizardReducer(wizardState, {
        type: "EDIT_SEARCH",
        index: message.index,
        searchTerm: message.searchTerm,
      });
      return { type: "STATE_UPDATE", state: wizardState, storeId: activeStoreId };
    }

    case "SET_STORE": {
      activeStoreId = message.storeId;
      return { type: "STATE_UPDATE", state: wizardState, storeId: activeStoreId };
    }

    case "GET_STATE": {
      return { type: "STATE_UPDATE", state: wizardState, storeId: activeStoreId };
    }

    case "PANTRY_ADD": {
      pantry.add(message.name);
      persistData();
      return { type: "PANTRY_LIST", names: pantry.getNames() };
    }

    case "PANTRY_REMOVE": {
      pantry.remove(message.name);
      persistData();
      return { type: "PANTRY_LIST", names: pantry.getNames() };
    }

    case "PANTRY_GET": {
      return { type: "PANTRY_LIST", names: pantry.getNames() };
    }
  }
}

function handleCartDetected(productName: string, productImageUrl: string | null): void {
  const item = currentItem(wizardState);
  if (!item) return;

  const searchTerm = item.searchTermOverride ?? item.parsedItem.searchTerm;

  if (activeStoreId) {
    history.add({
      store: activeStoreId,
      searchTerm,
      productName,
      productImageUrl,
    });
    persistData();
  }

  // Advance the wizard (item added → cooldown)
  try {
    wizardState = wizardReducer(wizardState, { type: "ADVANCE" });
    broadcastState();
  } catch {
    // ignore invalid transitions
  }
}

function triggerSearch(): void {
  const item = currentItem(wizardState);
  if (!item || !activeStoreId) return;

  const query = item.searchTermOverride ?? item.parsedItem.searchTerm;
  const config = getStoreConfig(activeStoreId);
  if (!config) return;

  if (config.search.method === "url" && config.search.urlTemplate) {
    const url = config.search.urlTemplate.replace("{query}", encodeURIComponent(query));
    // Navigate the active tab to the search URL
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      const tab = tabs[0];
      if (tab?.id) {
        chrome.tabs.update(tab.id, { url });
      }
    });
  } else {
    // Send search command to content script
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      const tab = tabs[0];
      if (tab?.id) {
        chrome.tabs.sendMessage(tab.id, {
          type: "SEARCH",
          query,
          storeId: activeStoreId,
        });
      }
    });
  }
}

function broadcastState(): void {
  chrome.runtime.sendMessage({
    type: "STATE_UPDATE",
    state: wizardState,
    storeId: activeStoreId,
  } satisfies WorkerResponse).catch(() => {
    // Side panel might not be open
  });
}

async function persistData(): Promise<void> {
  await chrome.storage.local.set({
    pantryItems: pantry.toJSON(),
    selectionHistory: history.toJSON(),
  });
}

async function loadPersistedData(): Promise<void> {
  const data = await chrome.storage.local.get(["pantryItems", "selectionHistory"]);
  if (data.pantryItems) {
    pantry.merge(data.pantryItems);
  }
  // SelectionHistory is append-only, so just reconstruct
  if (data.selectionHistory) {
    for (const record of data.selectionHistory) {
      history.add(record);
    }
  }
}
