import {
  parseList,
  createWizardState,
  wizardReducer,
  currentItem,
  PantryList,
  SelectionHistory,
} from "@listrunner/core";
import type { WizardState, WizardAction } from "@listrunner/core";
import type {
  PanelMessage,
  WorkerResponse,
  ContentResponse,
} from "../messages.js";
import { getStoreConfig } from "../store-configs/index.js";

let wizardState: WizardState = createWizardState();
let activeStoreId: string | null = null;
/** Tab the user chose to run the wizard in. Locked once the wizard starts. */
let wizardTabId: number | null = null;
const pantry = new PantryList();
const history = new SelectionHistory();

function setWizardState(next: WizardState): void {
  wizardState = next;
  void persistSession();
}

function setActiveStore(id: string | null): void {
  activeStoreId = id;
  void persistSession();
}

function setWizardTab(id: number | null): void {
  wizardTabId = id;
  void persistSession();
}

loadPersistedData();

chrome.action.onClicked.addListener((tab) => {
  if (tab.id) {
    chrome.sidePanel.open({ tabId: tab.id });
  }
});

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "send-to-listrunner",
    title: "Send to ListRunner",
    contexts: ["selection"],
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (
    info.menuItemId === "send-to-listrunner" &&
    info.selectionText &&
    tab?.id
  ) {
    chrome.sidePanel.open({ tabId: tab.id });
    chrome.storage.session.set({ pendingListText: info.selectionText });
  }
});

// Single message listener: dispatches by type across panel and content messages.
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  // Content-originated: CART_ADD_DETECTED. Identified by presence of type + productName.
  if (message?.type === "CART_ADD_DETECTED") {
    handleCartDetected(
      (message as Extract<ContentResponse, { type: "CART_ADD_DETECTED" }>)
        .productName,
      (message as Extract<ContentResponse, { type: "CART_ADD_DETECTED" }>)
        .productImageUrl,
    );
    sendResponse({
      type: "STATE_UPDATE",
      state: wizardState,
      storeId: activeStoreId,
    } satisfies WorkerResponse);
    return false;
  }

  // Content-originated: AUTOMATION_TIMEOUT. Selectors missing.
  if (message?.type === "AUTOMATION_TIMEOUT") {
    handleAutomationTimeout();
    sendResponse({
      type: "STATE_UPDATE",
      state: wizardState,
      storeId: activeStoreId,
    } satisfies WorkerResponse);
    return false;
  }

  // Panel-originated: dispatch.
  const response = handleMessage(message as PanelMessage, sender);
  if (response) sendResponse(response);
  return false;
});

function handleMessage(
  message: PanelMessage,
  sender: chrome.runtime.MessageSender,
): WorkerResponse | null {
  switch (message.type) {
    case "PARSE_LIST": {
      const data = parseList(message.text, {
        pantryExclusions: pantry.getNames(),
      });
      return { type: "PARSED_LIST", data };
    }

    case "START_WIZARD": {
      try {
        setWizardState(
          wizardReducer(createWizardState(), {
            type: "START",
            items: message.items,
          }),
        );
        captureActiveTab();
        triggerSearch();
        return {
          type: "STATE_UPDATE",
          state: wizardState,
          storeId: activeStoreId,
        };
      } catch (e) {
        return { type: "ERROR", message: String(e) };
      }
    }

    case "WIZARD_ACTION": {
      try {
        const action: WizardAction = { type: message.action };
        const prevStatus = wizardState.status;
        setWizardState(wizardReducer(wizardState, action));

        // Any transition that lands us on a new active item should trigger a search.
        const enteredNewActive =
          (wizardState.status === "stepping" ||
            wizardState.status === "revisiting") &&
          prevStatus !== "idle";

        // But only when the active item changed — ADD_ANOTHER/UNDO stay put.
        const shouldSearch =
          enteredNewActive &&
          (message.action === "COOLDOWN_COMPLETE" ||
            message.action === "SKIP" ||
            message.action === "BEGIN_REVISIT" ||
            message.action === "DISMISS" ||
            message.action === "ADVANCE");

        if (shouldSearch) {
          triggerSearch();
        }

        return {
          type: "STATE_UPDATE",
          state: wizardState,
          storeId: activeStoreId,
        };
      } catch (e) {
        return { type: "ERROR", message: String(e) };
      }
    }

    case "EDIT_SEARCH": {
      setWizardState(
        wizardReducer(wizardState, {
          type: "EDIT_SEARCH",
          index: message.index,
          searchTerm: message.searchTerm,
        }),
      );
      return {
        type: "STATE_UPDATE",
        state: wizardState,
        storeId: activeStoreId,
      };
    }

    case "RETRIGGER_SEARCH": {
      triggerSearch();
      return {
        type: "STATE_UPDATE",
        state: wizardState,
        storeId: activeStoreId,
      };
    }

    case "SET_STORE": {
      setActiveStore(message.storeId);
      notifyActiveContentScript();
      return {
        type: "STATE_UPDATE",
        state: wizardState,
        storeId: activeStoreId,
      };
    }

    case "GET_STATE": {
      return {
        type: "STATE_UPDATE",
        state: wizardState,
        storeId: activeStoreId,
      };
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

    case "MANUAL_NEXT": {
      // Mark current item skipped (not added) and advance; user handled it off-script.
      try {
        setWizardState(wizardReducer(wizardState, { type: "SKIP" }));
        if (
          wizardState.status === "stepping" ||
          wizardState.status === "revisiting"
        ) {
          triggerSearch();
        }
      } catch {
        // ignore
      }
      return {
        type: "STATE_UPDATE",
        state: wizardState,
        storeId: activeStoreId,
      };
    }
  }

  // sender unused for now; kept for future use (e.g., binding content script tab)
  void sender;
  return null;
}

function handleCartDetected(
  productName: string,
  productImageUrl: string | null,
): void {
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

  try {
    setWizardState(wizardReducer(wizardState, { type: "ADVANCE" }));
    broadcastState();
  } catch {
    // Ignore — advance may be invalid if we're already in cooldown, etc.
  }
}

function handleAutomationTimeout(): void {
  // Surface a manual-fallback flag to the side panel via state broadcast.
  // The side panel renders a "Next" button when it sees this flag.
  broadcastState({ automationFailed: true });
}

function triggerSearch(): void {
  const item = currentItem(wizardState);
  if (!item || !activeStoreId) return;

  const query = item.searchTermOverride ?? item.parsedItem.searchTerm;
  const config = getStoreConfig(activeStoreId);
  if (!config) return;

  if (config.search.method === "url" && config.search.urlTemplate) {
    const url = config.search.urlTemplate.replace(
      "{query}",
      encodeURIComponent(query),
    );
    withWizardTab((tabId) => {
      chrome.tabs.update(tabId, { url });
    });
  } else {
    withWizardTab((tabId) => {
      chrome.tabs.sendMessage(tabId, {
        type: "SEARCH",
        query,
        storeId: activeStoreId,
      });
    });
  }
}

function captureActiveTab(): void {
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    const tab = tabs[0];
    if (tab?.id) setWizardTab(tab.id);
  });
}

function withWizardTab(fn: (tabId: number) => void): void {
  if (wizardTabId !== null) {
    chrome.tabs.get(wizardTabId, (tab) => {
      if (chrome.runtime.lastError || !tab) {
        setWizardTab(null);
        chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
          const t = tabs[0];
          if (t?.id) {
            setWizardTab(t.id);
            fn(t.id);
          }
        });
        return;
      }
      fn(tab.id!);
    });
    return;
  }
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    const t = tabs[0];
    if (t?.id) {
      setWizardTab(t.id);
      fn(t.id);
    }
  });
}

function notifyActiveContentScript(): void {
  withWizardTab((tabId) => {
    chrome.tabs.sendMessage(
      tabId,
      { type: "STORE_CHANGED", storeId: activeStoreId },
      () => {
        // Swallow lastError — content script may not be loaded yet.
        void chrome.runtime.lastError;
      },
    );
  });
}

function broadcastState(extra?: { automationFailed?: boolean }): void {
  chrome.runtime
    .sendMessage({
      type: "STATE_UPDATE",
      state: wizardState,
      storeId: activeStoreId,
      ...(extra ?? {}),
    } satisfies WorkerResponse)
    .catch(() => {
      // Side panel may not be open.
    });
}

async function persistData(): Promise<void> {
  await chrome.storage.local.set({
    pantryItems: pantry.toJSON(),
    selectionHistory: history.toJSON(),
  });
}

async function persistSession(): Promise<void> {
  await chrome.storage.session.set({
    wizardState,
    activeStoreId,
    wizardTabId,
  });
}

async function loadPersistedData(): Promise<void> {
  const [persistent, session] = await Promise.all([
    chrome.storage.local.get(["pantryItems", "selectionHistory"]),
    chrome.storage.session.get([
      "wizardState",
      "activeStoreId",
      "wizardTabId",
    ]),
  ]);

  if (persistent.pantryItems) {
    pantry.merge(persistent.pantryItems);
  }
  if (persistent.selectionHistory) {
    for (const record of persistent.selectionHistory) {
      history.add(record);
    }
  }

  if (session.wizardState) {
    wizardState = session.wizardState as WizardState;
  }
  if (typeof session.activeStoreId === "string") {
    activeStoreId = session.activeStoreId;
  }
  if (typeof session.wizardTabId === "number") {
    wizardTabId = session.wizardTabId;
  }
}
