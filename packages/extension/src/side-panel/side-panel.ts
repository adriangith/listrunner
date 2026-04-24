import type {
  ParsedItem,
  ParsedList,
  WizardState,
  WizardItem,
} from "@listrunner/core";
import type { PanelMessage, WorkerResponse } from "../messages.js";

// ── State ──

let parsedList: ParsedList | null = null;
let wizardState: WizardState | null = null;
let activeStoreId: string | null = null;
let cooldownTimer: ReturnType<typeof setTimeout> | null = null;
let automationFailed = false;
let previousView: ViewName = "input";

const COOLDOWN_MS = 3000;

type ViewName = "input" | "review" | "wizard" | "done" | "pantry";

// ── DOM refs ──

const views: Record<ViewName, HTMLElement> = {
  input: document.getElementById("view-input") as HTMLElement,
  review: document.getElementById("view-review") as HTMLElement,
  wizard: document.getElementById("view-wizard") as HTMLElement,
  done: document.getElementById("view-done") as HTMLElement,
  pantry: document.getElementById("view-pantry") as HTMLElement,
};

// Input view
const listTextarea = document.getElementById("list-input") as HTMLTextAreaElement;
const parseBtn = document.getElementById("btn-parse") as HTMLButtonElement;
const pantryBtn = document.getElementById("btn-pantry") as HTMLButtonElement;

// Review view
const reviewList = document.getElementById("review-list") as HTMLElement;
const reviewCount = document.getElementById("review-count") as HTMLElement;
const storeSelect = document.getElementById("store-select") as HTMLSelectElement;
const startBtn = document.getElementById("btn-start") as HTMLButtonElement;
const backBtn = document.getElementById("btn-back") as HTMLButtonElement;
const filteredSection = document.getElementById("filtered-section") as HTMLElement;
const filteredList = document.getElementById("filtered-list") as HTMLElement;

// Wizard view
const currentItemName = document.getElementById("current-item-name") as HTMLElement;
const currentItemQty = document.getElementById("current-item-qty") as HTMLElement;
const currentSearchInput = document.getElementById(
  "current-search-input",
) as HTMLInputElement;
const updateSearchBtn = document.getElementById(
  "btn-update-search",
) as HTMLButtonElement;
const progressText = document.getElementById("progress-text") as HTMLElement;
const progressBar = document.getElementById("progress-fill") as HTMLElement;
const skipBtn = document.getElementById("btn-skip") as HTMLButtonElement;
const dismissBtn = document.getElementById("btn-dismiss") as HTMLButtonElement;
const revisitBadge = document.getElementById("revisit-badge") as HTMLElement;
const cooldownBar = document.getElementById("cooldown-bar") as HTMLElement;
const cooldownMsg = document.getElementById("cooldown-msg") as HTMLElement;
const addAnotherBtn = document.getElementById("btn-add-another") as HTMLButtonElement;
const undoBtn = document.getElementById("btn-undo") as HTMLButtonElement;
const automationWarning = document.getElementById(
  "automation-warning",
) as HTMLElement;
const manualNextBtn = document.getElementById(
  "btn-manual-next",
) as HTMLButtonElement;
const reportLink = document.getElementById("btn-report") as HTMLAnchorElement;

// Done view
const summaryEl = document.getElementById("summary") as HTMLElement;
const revisitBtn = document.getElementById("btn-revisit") as HTMLButtonElement;
const newListBtn = document.getElementById("btn-new-list") as HTMLButtonElement;

// Pantry view
const pantryBackBtn = document.getElementById(
  "btn-pantry-back",
) as HTMLButtonElement;
const pantryAddForm = document.getElementById("pantry-add-form") as HTMLFormElement;
const pantryNewInput = document.getElementById("pantry-new") as HTMLInputElement;
const pantryListEl = document.getElementById("pantry-list") as HTMLElement;
const pantryEmpty = document.getElementById("pantry-empty") as HTMLElement;

// ── Init ──

init();

async function init(): Promise<void> {
  const data = await chrome.storage.session.get("pendingListText");
  if (data.pendingListText) {
    listTextarea.value = data.pendingListText;
    await chrome.storage.session.remove("pendingListText");
  }

  sendMessage({ type: "GET_STATE" }, (response) => {
    if (response.type === "STATE_UPDATE") {
      wizardState = response.state;
      activeStoreId = response.storeId;
      renderCurrentView();
    }
  });

  chrome.runtime.onMessage.addListener((message: WorkerResponse) => {
    if (message.type === "STATE_UPDATE") {
      wizardState = message.state;
      activeStoreId = message.storeId;
      if (message.automationFailed) automationFailed = true;
      renderCurrentView();
    }
  });

  loadStoreList();

  // Bindings
  parseBtn.addEventListener("click", handleParse);
  startBtn.addEventListener("click", handleStart);
  backBtn.addEventListener("click", () => showView("input"));
  skipBtn.addEventListener("click", () => sendAction("SKIP"));
  dismissBtn.addEventListener("click", () => sendAction("DISMISS"));
  addAnotherBtn.addEventListener("click", () => sendAction("ADD_ANOTHER"));
  undoBtn.addEventListener("click", () => sendAction("UNDO"));
  revisitBtn.addEventListener("click", () => sendAction("BEGIN_REVISIT"));
  newListBtn.addEventListener("click", handleNewList);
  storeSelect.addEventListener("change", handleStoreChange);
  updateSearchBtn.addEventListener("click", handleUpdateSearch);
  currentSearchInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") handleUpdateSearch();
  });
  manualNextBtn.addEventListener("click", handleManualNext);

  pantryBtn.addEventListener("click", openPantry);
  pantryBackBtn.addEventListener("click", closePantry);
  pantryAddForm.addEventListener("submit", handlePantryAdd);
}

// ── Actions ──

function handleParse(): void {
  const text = listTextarea.value.trim();
  if (!text) return;

  sendMessage({ type: "PARSE_LIST", text }, (response) => {
    if (response.type === "PARSED_LIST") {
      parsedList = response.data;
      renderReviewList();
      showView("review");
    }
  });
}

function handleStart(): void {
  if (!parsedList || !activeStoreId) return;
  if (parsedList.items.length === 0) return;

  automationFailed = false;
  sendMessage(
    { type: "START_WIZARD", items: parsedList.items },
    (response) => {
      if (response.type === "STATE_UPDATE") {
        wizardState = response.state;
        renderCurrentView();
      }
    },
  );
}

function handleNewList(): void {
  sendAction("RESET");
  parsedList = null;
  listTextarea.value = "";
  automationFailed = false;
  showView("input");
}

function handleStoreChange(): void {
  const storeId = storeSelect.value;
  if (storeId) {
    sendMessage({ type: "SET_STORE", storeId }, () => {
      activeStoreId = storeId;
      updateStartEnabled();
    });
  } else {
    activeStoreId = null;
    updateStartEnabled();
  }
}

function handleUpdateSearch(): void {
  if (!wizardState) return;
  const active = findActiveItem(wizardState);
  if (!active) return;
  const index = wizardState.items.indexOf(active);
  if (index < 0) return;

  const newTerm = currentSearchInput.value.trim();
  if (!newTerm) return;
  const current = active.searchTermOverride ?? active.parsedItem.searchTerm;
  if (newTerm === current) return;

  sendMessage(
    { type: "EDIT_SEARCH", index, searchTerm: newTerm },
    (response) => {
      if (response.type === "STATE_UPDATE") {
        wizardState = response.state;
        renderCurrentView();
        // After updating the term, re-fire the search on the current item.
        sendMessage({ type: "RETRIGGER_SEARCH" }, () => {
          /* no-op */
        });
      }
    },
  );
}

function handleManualNext(): void {
  automationFailed = false;
  sendMessage({ type: "MANUAL_NEXT" }, (response) => {
    if (response.type === "STATE_UPDATE") {
      wizardState = response.state;
      renderCurrentView();
    }
  });
}

function sendAction(
  action: Extract<PanelMessage, { type: "WIZARD_ACTION" }>["action"],
): void {
  sendMessage({ type: "WIZARD_ACTION", action }, (response) => {
    if (response.type === "STATE_UPDATE") {
      wizardState = response.state;
      renderCurrentView();
    }
  });
}

function sendMessage(
  message: PanelMessage,
  callback: (response: WorkerResponse) => void,
): void {
  chrome.runtime.sendMessage(message, callback);
}

// ── Rendering ──

function showView(name: ViewName): void {
  for (const key of Object.keys(views) as ViewName[]) {
    views[key].classList.toggle("hidden", key !== name);
  }
  if (name !== "pantry") previousView = name;
}

function renderCurrentView(): void {
  if (!wizardState || wizardState.status === "idle") {
    showView(parsedList ? "review" : "input");
    return;
  }

  if (wizardState.status === "done") {
    renderDoneView();
    showView("done");
    return;
  }

  renderWizardView();
  showView("wizard");
}

function renderReviewList(): void {
  if (!parsedList) return;

  reviewList.innerHTML = "";
  reviewCount.textContent =
    parsedList.items.length > 0 ? `(${parsedList.items.length})` : "";

  if (parsedList.items.length === 0) {
    const li = document.createElement("li");
    li.className = "empty-hint";
    li.textContent = "No items. Go back and add some.";
    reviewList.appendChild(li);
  }

  for (let i = 0; i < parsedList.items.length; i++) {
    const item = parsedList.items[i]!;
    const li = buildReviewRow(item, i);
    reviewList.appendChild(li);
  }

  if (parsedList.filtered.length > 0) {
    filteredSection.classList.remove("hidden");
    filteredList.innerHTML = "";
    for (let i = 0; i < parsedList.filtered.length; i++) {
      const item = parsedList.filtered[i]!;
      const li = document.createElement("li");
      li.className = "filtered-row";

      const nameSpan = document.createElement("span");
      nameSpan.textContent = item.searchTerm;
      li.appendChild(nameSpan);

      const restoreBtn = document.createElement("button");
      restoreBtn.className = "btn small";
      restoreBtn.textContent = "Restore";
      restoreBtn.addEventListener("click", () => restoreFiltered(i));
      li.appendChild(restoreBtn);

      filteredList.appendChild(li);
    }
  } else {
    filteredSection.classList.add("hidden");
  }

  updateStartEnabled();
}

function buildReviewRow(item: ParsedItem, index: number): HTMLLIElement {
  const li = document.createElement("li");
  li.className = "review-item";

  const qtySpan = document.createElement("span");
  qtySpan.className = "item-qty";
  qtySpan.textContent = formatQuantity(item);

  const input = document.createElement("input");
  input.type = "text";
  input.className = "item-name-input";
  input.value = item.searchTerm;
  input.setAttribute("aria-label", `Search term for item ${index + 1}`);
  input.addEventListener("change", () => {
    const v = input.value.trim();
    if (!parsedList) return;
    if (!v) {
      // Empty = remove
      removeReviewItem(index);
      return;
    }
    parsedList.items[index] = { ...item, searchTerm: v };
  });

  const removeBtn = document.createElement("button");
  removeBtn.className = "btn small icon";
  removeBtn.textContent = "✕";
  removeBtn.setAttribute("aria-label", "Remove item");
  removeBtn.addEventListener("click", () => removeReviewItem(index));

  li.append(qtySpan, input, removeBtn);
  return li;
}

function removeReviewItem(index: number): void {
  if (!parsedList) return;
  parsedList.items.splice(index, 1);
  renderReviewList();
}

function restoreFiltered(index: number): void {
  if (!parsedList) return;
  const [restored] = parsedList.filtered.splice(index, 1);
  if (restored) {
    parsedList.items.push({ ...restored, filtered: false });
  }
  renderReviewList();
}

function renderWizardView(): void {
  if (!wizardState) return;

  const items = wizardState.items;
  const activeItem = findActiveItem(wizardState);

  if (activeItem) {
    const searchTerm =
      activeItem.searchTermOverride ?? activeItem.parsedItem.searchTerm;
    currentItemName.textContent = searchTerm;
    currentItemQty.textContent = formatQuantity(activeItem.parsedItem);
    // Only refresh input if user isn't typing in it
    if (document.activeElement !== currentSearchInput) {
      currentSearchInput.value = searchTerm;
    }
  }

  const added = items.filter((i) => i.status === "added").length;
  const total = items.length;
  progressText.textContent = `${added}/${total}`;
  progressBar.style.width = total > 0 ? `${(added / total) * 100}%` : "0%";

  const isCooldown = wizardState.status === "cooldown";
  const isRevisiting = wizardState.status === "revisiting";

  cooldownBar.classList.toggle("hidden", !isCooldown);
  skipBtn.classList.toggle("hidden", isCooldown);
  dismissBtn.classList.toggle("hidden", !isRevisiting || isCooldown);
  revisitBadge.classList.toggle("hidden", !isRevisiting);

  // Automation-fallback UI
  automationWarning.classList.toggle(
    "hidden",
    !automationFailed || isCooldown,
  );
  if (automationFailed && activeStoreId) {
    reportLink.href = buildReportUrl(activeStoreId);
  }

  if (isCooldown) {
    cooldownMsg.textContent = "Added! Next item in 3s...";
    startCooldownTimer();
  } else if (cooldownTimer) {
    clearTimeout(cooldownTimer);
    cooldownTimer = null;
  }
}

function renderDoneView(): void {
  if (!wizardState) return;

  const added = wizardState.items.filter((i) => i.status === "added").length;
  const skipped = wizardState.items.filter((i) => i.status === "skipped").length;
  const dismissed = wizardState.items.filter(
    (i) => i.status === "dismissed",
  ).length;
  const total = wizardState.items.length;

  summaryEl.innerHTML = "";

  const addedP = document.createElement("p");
  const addedStrong = document.createElement("strong");
  addedStrong.textContent = String(added);
  addedP.append(addedStrong, ` of ${total} items added to cart`);
  summaryEl.appendChild(addedP);

  if (skipped > 0) {
    const p = document.createElement("p");
    p.textContent = `${skipped} items skipped`;
    summaryEl.appendChild(p);
  }
  if (dismissed > 0) {
    const p = document.createElement("p");
    p.textContent = `${dismissed} items dismissed`;
    summaryEl.appendChild(p);
  }

  const hasSkipped = wizardState.items.some((i) => i.status === "skipped");
  revisitBtn.classList.toggle("hidden", !hasSkipped);
}

function startCooldownTimer(): void {
  if (cooldownTimer) clearTimeout(cooldownTimer);
  cooldownTimer = setTimeout(() => {
    sendAction("COOLDOWN_COMPLETE");
    cooldownTimer = null;
  }, COOLDOWN_MS);
}

function loadStoreList(): void {
  const stores = [
    { id: "woolworths-au", name: "Woolworths (AU)" },
    { id: "coles-au", name: "Coles (AU)" },
  ];

  storeSelect.innerHTML = '<option value="">Choose a store...</option>';
  for (const store of stores) {
    const option = document.createElement("option");
    option.value = store.id;
    option.textContent = store.name;
    if (store.id === activeStoreId) option.selected = true;
    storeSelect.appendChild(option);
  }
}

function updateStartEnabled(): void {
  if (!parsedList) {
    startBtn.disabled = true;
    return;
  }
  startBtn.disabled = !activeStoreId || parsedList.items.length === 0;
}

// ── Pantry ──

function openPantry(): void {
  sendMessage({ type: "PANTRY_GET" }, (response) => {
    if (response.type === "PANTRY_LIST") {
      renderPantry(response.names);
      showView("pantry");
    }
  });
}

function closePantry(): void {
  showView(previousView);
}

function handlePantryAdd(e: Event): void {
  e.preventDefault();
  const name = pantryNewInput.value.trim();
  if (!name) return;
  sendMessage({ type: "PANTRY_ADD", name }, (response) => {
    if (response.type === "PANTRY_LIST") {
      pantryNewInput.value = "";
      renderPantry(response.names);
    }
  });
}

function handlePantryRemove(name: string): void {
  sendMessage({ type: "PANTRY_REMOVE", name }, (response) => {
    if (response.type === "PANTRY_LIST") {
      renderPantry(response.names);
    }
  });
}

function renderPantry(names: string[]): void {
  pantryListEl.innerHTML = "";
  pantryEmpty.classList.toggle("hidden", names.length > 0);

  for (const name of names) {
    const li = document.createElement("li");
    li.className = "pantry-row";

    const span = document.createElement("span");
    span.textContent = name;

    const btn = document.createElement("button");
    btn.className = "btn small icon";
    btn.textContent = "✕";
    btn.setAttribute("aria-label", `Remove ${name}`);
    btn.addEventListener("click", () => handlePantryRemove(name));

    li.append(span, btn);
    pantryListEl.appendChild(li);
  }
}

// ── Helpers ──

function findActiveItem(state: WizardState): WizardItem | null {
  if (state.status === "revisiting") {
    const idx = state.skippedIndices[state.revisitPointer];
    return idx !== undefined ? (state.items[idx] ?? null) : null;
  }
  if (state.status === "cooldown" && state.cooldownItemIndex !== null) {
    return state.items[state.cooldownItemIndex] ?? null;
  }
  return state.items[state.currentIndex] ?? null;
}

function formatQuantity(item: {
  quantity: { amount: number; unit: string | null } | null;
}): string {
  if (!item.quantity) return "";
  const { amount, unit } = item.quantity;
  return unit ? `${amount} ${unit}` : `×${amount}`;
}

function buildReportUrl(storeId: string): string {
  const title = encodeURIComponent(`[config] ${storeId} automation broken`);
  const body = encodeURIComponent(
    `The ListRunner wizard couldn't find the expected elements on ${storeId}.\n\n` +
      `URL: (paste the page URL)\n` +
      `Expected: search input / add-to-cart button / product name\n\n` +
      `Automatically generated from the ListRunner extension.`,
  );
  return `https://github.com/anthropics/listrunner-store-configs/issues/new?title=${title}&body=${body}`;
}
