import type { StoreConfig } from "../store-config.js";
import type { ContentMessage } from "../messages.js";

let activeConfig: StoreConfig | null = null;
let cartObserver: MutationObserver | null = null;
let selectorObserver: MutationObserver | null = null;
let selectorTimeoutId: ReturnType<typeof setTimeout> | null = null;
let clickListenerBound = false;

// How long to wait for expected selectors before declaring automation broken.
const SELECTOR_TIMEOUT_MS = 8000;

chrome.runtime.onMessage.addListener(
  (message: ContentMessage, _sender, sendResponse) => {
    switch (message.type) {
      case "SEARCH":
        handleSearch(message.query, message.storeId);
        sendResponse({ type: "SEARCH_COMPLETE" });
        break;
      case "STORE_CHANGED":
        if (message.storeId) {
          setupForStore(message.storeId);
        } else {
          activeConfig = null;
          teardownObservers();
        }
        break;
      case "PING":
        sendResponse({ type: "PONG" });
        break;
    }
    return true;
  },
);

// On load, ask the service worker which store we're targeting.
chrome.runtime.sendMessage({ type: "GET_STATE" }, (response) => {
  if (chrome.runtime.lastError) return;
  if (response?.storeId) {
    setupForStore(response.storeId);
  }
});

async function setupForStore(storeId: string): Promise<void> {
  const configModule = await import("../store-configs/index.js");
  activeConfig = configModule.getStoreConfig(storeId) ?? null;
  if (activeConfig) {
    observeCartChanges();
    watchForSelectorAvailability();
  }
}

function handleSearch(query: string, storeId: string): void {
  if (!activeConfig || activeConfig.id !== storeId) {
    setupForStore(storeId).then(() => {
      if (
        activeConfig?.search.method === "input" &&
        activeConfig.search.inputSelector
      ) {
        fillSearchInput(query);
      }
    });
    return;
  }

  if (
    activeConfig.search.method === "input" &&
    activeConfig.search.inputSelector
  ) {
    fillSearchInput(query);
  }
}

function fillSearchInput(query: string): void {
  if (!activeConfig?.search.inputSelector) return;

  const input = document.querySelector<HTMLInputElement>(
    activeConfig.search.inputSelector,
  );
  if (!input) return;

  const nativeSetter = Object.getOwnPropertyDescriptor(
    HTMLInputElement.prototype,
    "value",
  )?.set;
  nativeSetter?.call(input, query);
  input.dispatchEvent(new Event("input", { bubbles: true }));
  input.dispatchEvent(new Event("change", { bubbles: true }));

  if (activeConfig.search.submitSelector) {
    const submitBtn = document.querySelector<HTMLElement>(
      activeConfig.search.submitSelector,
    );
    submitBtn?.click();
  } else {
    input.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Enter", bubbles: true }),
    );
    input.form?.submit();
  }
}

function teardownObservers(): void {
  if (cartObserver) {
    cartObserver.disconnect();
    cartObserver = null;
  }
  if (selectorObserver) {
    selectorObserver.disconnect();
    selectorObserver = null;
  }
  if (selectorTimeoutId !== null) {
    clearTimeout(selectorTimeoutId);
    selectorTimeoutId = null;
  }
}

function observeCartChanges(): void {
  if (!activeConfig) return;

  if (!clickListenerBound) {
    document.addEventListener("click", handlePotentialCartClick, true);
    clickListenerBound = true;
  }

  if (activeConfig.cart.detectionMethod === "dom-mutation") {
    if (cartObserver) cartObserver.disconnect();

    const cartCountEl = activeConfig.cart.cartCountSelector
      ? document.querySelector(activeConfig.cart.cartCountSelector)
      : null;

    if (cartCountEl) {
      cartObserver = new MutationObserver(() => {
        // Cart count changed — click handler already notifies with product info.
      });
      cartObserver.observe(cartCountEl, {
        childList: true,
        characterData: true,
        subtree: true,
      });
    }
  }
}

/**
 * Wait until we can see either the search input OR an add-to-cart button.
 * If neither shows up within the timeout, report to the service worker so the
 * side panel can surface a manual-fallback UI.
 */
function watchForSelectorAvailability(): void {
  if (!activeConfig) return;
  // Dispose any previous watch — setupForStore may be called repeatedly
  // on SPA store pages.
  if (selectorObserver) {
    selectorObserver.disconnect();
    selectorObserver = null;
  }
  if (selectorTimeoutId !== null) {
    clearTimeout(selectorTimeoutId);
    selectorTimeoutId = null;
  }

  const storeId = activeConfig.id;
  const addSel = activeConfig.cart.addToCartSelector;
  const searchSel = activeConfig.search.inputSelector;

  const check = (): boolean => {
    try {
      if (addSel && document.querySelector(addSel)) return true;
      if (searchSel && document.querySelector(searchSel)) return true;
    } catch {
      // Invalid selector — give up, report broken.
      return false;
    }
    return false;
  };

  if (check()) return;

  selectorObserver = new MutationObserver(() => {
    if (check()) {
      selectorObserver?.disconnect();
      selectorObserver = null;
      if (selectorTimeoutId !== null) {
        clearTimeout(selectorTimeoutId);
        selectorTimeoutId = null;
      }
    }
  });
  selectorObserver.observe(document.documentElement, {
    childList: true,
    subtree: true,
  });

  selectorTimeoutId = setTimeout(() => {
    if (!check()) {
      selectorObserver?.disconnect();
      selectorObserver = null;
      chrome.runtime.sendMessage({
        type: "AUTOMATION_TIMEOUT",
        storeId,
      });
    }
    selectorTimeoutId = null;
  }, SELECTOR_TIMEOUT_MS);
}

function handlePotentialCartClick(event: Event): void {
  if (!activeConfig) return;

  const target = event.target as HTMLElement;
  const addButton = target.closest(activeConfig.cart.addToCartSelector);
  if (!addButton) return;

  const { productName, productImageUrl } = extractProductInfo(addButton);

  chrome.runtime.sendMessage({
    type: "CART_ADD_DETECTED",
    productName,
    productImageUrl,
  });
}

/**
 * Extract product info from the DOM around an add-to-cart button.
 * First looks for a product tile (search-results page), then falls back to
 * page-level structured metadata (product detail page, single-product view).
 */
function extractProductInfo(addButton: Element): {
  productName: string;
  productImageUrl: string | null;
} {
  const cfg = activeConfig!;
  let productName = "";
  let productImageUrl: string | null = null;

  const productTile = addButton.closest(
    "[class*='product'], [data-testid*='product'], article, .tile, li",
  );

  if (productTile) {
    const nameEl = productTile.querySelector(cfg.cart.productNameSelector);
    if (nameEl) {
      productName = nameEl.textContent?.trim() ?? "";
    }
    if (cfg.cart.productImageSelector) {
      const imgEl = productTile.querySelector<HTMLImageElement>(
        cfg.cart.productImageSelector,
      );
      if (imgEl) {
        productImageUrl =
          imgEl.currentSrc || imgEl.src || imgEl.getAttribute("data-src");
      }
    }
  }

  // Fall back to page-level metadata when tile lookup came up empty.
  if (!productName) {
    productName = readPageProductName();
  }
  if (!productImageUrl) {
    productImageUrl = readPageProductImage();
  }

  return {
    productName: productName || "Unknown product",
    productImageUrl,
  };
}

function readPageProductName(): string {
  // Structured data first (most reliable on product detail pages).
  const ogTitle = document
    .querySelector<HTMLMetaElement>('meta[property="og:title"]')
    ?.content?.trim();
  if (ogTitle) return ogTitle;

  const itemProp = document
    .querySelector<HTMLElement>("[itemprop='name']")
    ?.textContent?.trim();
  if (itemProp) return itemProp;

  const h1 = document.querySelector<HTMLElement>("h1")?.textContent?.trim();
  if (h1) return h1;

  // Fall through to page title — strip the " | Store" tail commonly appended.
  return document.title.replace(/\s*[-|–]\s*.+$/, "").trim();
}

function readPageProductImage(): string | null {
  const ogImg = document
    .querySelector<HTMLMetaElement>('meta[property="og:image"]')
    ?.content;
  if (ogImg) return ogImg;

  const itemPropImg = document
    .querySelector<HTMLImageElement>("img[itemprop='image']");
  if (itemPropImg) return itemPropImg.currentSrc || itemPropImg.src;

  return null;
}
