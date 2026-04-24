/**
 * Thin cross-browser adapter for API differences between Chrome and Firefox.
 * Chrome has chrome.sidePanel; Firefox has browser.sidebarAction.
 * Most chrome.* namespaces are aliased to browser.* in Firefox (and vice
 * versa), so we only need adapters for the APIs that genuinely differ.
 */

// `browser` exists in Firefox as the WebExtensions-standard namespace;
// Chrome uses `chrome`. Firefox also aliases `chrome` for compatibility.
type AnyGlobal = typeof globalThis & {
  browser?: {
    sidebarAction?: {
      open: () => Promise<void>;
      close?: () => Promise<void>;
    };
  };
};

const g = globalThis as AnyGlobal;
const anyChrome = chrome as typeof chrome & {
  sidePanel?: {
    open: (opts: { tabId?: number; windowId?: number }) => Promise<void>;
    setOptions?: (opts: {
      tabId?: number;
      path?: string;
      enabled?: boolean;
    }) => Promise<void>;
  };
};

export async function openExtensionPanel(tabId?: number): Promise<void> {
  if (anyChrome.sidePanel?.open) {
    try {
      await anyChrome.sidePanel.open(tabId ? { tabId } : {});
      return;
    } catch {
      // fall through to sidebar
    }
  }
  if (g.browser?.sidebarAction?.open) {
    try {
      await g.browser.sidebarAction.open();
      return;
    } catch {
      // no-op — user may need to click the toolbar icon
    }
  }
}
