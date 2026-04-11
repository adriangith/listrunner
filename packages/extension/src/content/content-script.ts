import type { StoreConfig } from "../store-config.js";
import type { ContentMessage } from "../messages.js";

let activeConfig: StoreConfig | null = null;
let cartObserver: MutationObserver | null = null;

// Listen for messages from the service worker
chrome.runtime.onMessage.addListener((message: ContentMessage, _sender, sendResponse) => {
  switch (message.type) {
    case "SEARCH":
      handleSearch(message.query, message.storeId);
      sendResponse({ type: "SEARCH_COMPLETE" });
      break;
    case "PING":
      sendResponse({ type: "PONG" });
      break;
  }
  return true;
});

// Request store config on load — check if current page matches a store
chrome.runtime.sendMessage({ type: "GET_STATE" }, (response) => {
  if (chrome.runtime.lastError) return;
  if (response?.storeId) {
    setupForStore(response.storeId);
  }
});

async function setupForStore(storeId: string): Promise<void> {
  // Dynamically import the store config registry
  const configModule = await import("../store-configs/index.js");
  activeConfig = configModule.getStoreConfig(storeId) ?? null;
  if (activeConfig) {
    observeCartChanges();
  }
}

function handleSearch(query: string, storeId: string): void {
  if (!activeConfig || activeConfig.id !== storeId) {
    setupForStore(storeId).then(() => {
      if (activeConfig?.search.method === "input" && activeConfig.search.inputSelector) {
        fillSearchInput(query);
      }
    });
    return;
  }

  if (activeConfig.search.method === "input" && activeConfig.search.inputSelector) {
    fillSearchInput(query);
  }
}

function fillSearchInput(query: string): void {
  if (!activeConfig?.search.inputSelector) return;

  const input = document.querySelector<HTMLInputElement>(activeConfig.search.inputSelector);
  if (!input) return;

  // Set value and dispatch events to trigger framework reactivity
  const nativeSetter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")?.set;
  nativeSetter?.call(input, query);
  input.dispatchEvent(new Event("input", { bubbles: true }));
  input.dispatchEvent(new Event("change", { bubbles: true }));

  // Submit if there's a submit button
  if (activeConfig.search.submitSelector) {
    const submitBtn = document.querySelector<HTMLElement>(activeConfig.search.submitSelector);
    submitBtn?.click();
  } else {
    // Try pressing Enter
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
    input.form?.submit();
  }
}

function observeCartChanges(): void {
  if (!activeConfig || cartObserver) return;

  // Listen for clicks on add-to-cart buttons
  document.addEventListener("click", handlePotentialCartClick, true);

  // Also set up a mutation observer for dynamic cart changes
  if (activeConfig.cart.detectionMethod === "dom-mutation") {
    const cartCountEl = activeConfig.cart.cartCountSelector
      ? document.querySelector(activeConfig.cart.cartCountSelector)
      : null;

    if (cartCountEl) {
      cartObserver = new MutationObserver(() => {
        // Cart count changed — likely an item was added
        // We rely on the click handler for product info
      });
      cartObserver.observe(cartCountEl, {
        childList: true,
        characterData: true,
        subtree: true,
      });
    }
  }
}

function handlePotentialCartClick(event: Event): void {
  if (!activeConfig) return;

  const target = event.target as HTMLElement;
  const addButton = target.closest(activeConfig.cart.addToCartSelector);
  if (!addButton) return;

  // Found an add-to-cart click — extract product info from the nearest product tile
  const productTile = addButton.closest("[class*='product'], [data-testid*='product'], article, .tile");
  let productName = "Unknown product";
  let productImageUrl: string | null = null;

  if (productTile) {
    const nameEl = productTile.querySelector(activeConfig.cart.productNameSelector);
    if (nameEl) {
      productName = nameEl.textContent?.trim() ?? productName;
    }

    if (activeConfig.cart.productImageSelector) {
      const imgEl = productTile.querySelector<HTMLImageElement>(activeConfig.cart.productImageSelector);
      if (imgEl) {
        productImageUrl = imgEl.src || imgEl.getAttribute("data-src") || null;
      }
    }
  }

  // Notify service worker
  chrome.runtime.sendMessage({
    type: "CART_ADD_DETECTED",
    productName,
    productImageUrl,
  });
}
