import type { ParsedItem, ParsedList, WizardState, WizardItem } from "@listrunner/core";
import type { PanelMessage, WorkerResponse } from "../messages.js";

// ── State ──

let parsedList: ParsedList | null = null;
let wizardState: WizardState | null = null;
let activeStoreId: string | null = null;
let cooldownTimer: ReturnType<typeof setTimeout> | null = null;

const COOLDOWN_MS = 3000;

// ── DOM refs ──

const views = {
  input: document.getElementById("view-input") as HTMLElement,
  review: document.getElementById("view-review") as HTMLElement,
  wizard: document.getElementById("view-wizard") as HTMLElement,
  done: document.getElementById("view-done") as HTMLElement,
};

// Input view
const listTextarea = document.getElementById("list-input") as HTMLTextAreaElement;
const parseBtn = document.getElementById("btn-parse") as HTMLButtonElement;

// Review view
const reviewList = document.getElementById("review-list") as HTMLElement;
const storeSelect = document.getElementById("store-select") as HTMLSelectElement;
const startBtn = document.getElementById("btn-start") as HTMLButtonElement;
const backBtn = document.getElementById("btn-back") as HTMLButtonElement;
const filteredSection = document.getElementById("filtered-section") as HTMLElement;
const filteredList = document.getElementById("filtered-list") as HTMLElement;

// Wizard view
const currentItemName = document.getElementById("current-item-name") as HTMLElement;
const currentItemQty = document.getElementById("current-item-qty") as HTMLElement;
const progressText = document.getElementById("progress-text") as HTMLElement;
const progressBar = document.getElementById("progress-fill") as HTMLElement;
const skipBtn = document.getElementById("btn-skip") as HTMLButtonElement;
const cooldownBar = document.getElementById("cooldown-bar") as HTMLElement;
const cooldownMsg = document.getElementById("cooldown-msg") as HTMLElement;
const addAnotherBtn = document.getElementById("btn-add-another") as HTMLButtonElement;
const undoBtn = document.getElementById("btn-undo") as HTMLButtonElement;

// Done view
const summaryEl = document.getElementById("summary") as HTMLElement;
const revisitBtn = document.getElementById("btn-revisit") as HTMLButtonElement;
const newListBtn = document.getElementById("btn-new-list") as HTMLButtonElement;

// ── Init ──

init();

async function init(): Promise<void> {
  // Check for pending text from context menu
  const data = await chrome.storage.session.get("pendingListText");
  if (data.pendingListText) {
    listTextarea.value = data.pendingListText;
    await chrome.storage.session.remove("pendingListText");
  }

  // Get current state from service worker
  sendMessage({ type: "GET_STATE" }, (response) => {
    if (response.type === "STATE_UPDATE") {
      wizardState = response.state;
      activeStoreId = response.storeId;
      renderCurrentView();
    }
  });

  // Listen for state updates from service worker
  chrome.runtime.onMessage.addListener((message: WorkerResponse) => {
    if (message.type === "STATE_UPDATE") {
      wizardState = message.state;
      activeStoreId = message.storeId;
      renderCurrentView();
    }
  });

  // Load store list into selector
  loadStoreList();

  // Bind events
  parseBtn.addEventListener("click", handleParse);
  startBtn.addEventListener("click", handleStart);
  backBtn.addEventListener("click", () => showView("input"));
  skipBtn.addEventListener("click", () => sendAction("SKIP"));
  addAnotherBtn.addEventListener("click", () => sendAction("ADD_ANOTHER"));
  undoBtn.addEventListener("click", () => sendAction("UNDO"));
  revisitBtn.addEventListener("click", () => sendAction("BEGIN_REVISIT"));
  newListBtn.addEventListener("click", handleNewList);
  storeSelect.addEventListener("change", handleStoreChange);
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

  sendMessage({ type: "START_WIZARD", items: parsedList.items }, (response) => {
    if (response.type === "STATE_UPDATE") {
      wizardState = response.state;
      renderCurrentView();
    }
  });
}

function handleNewList(): void {
  sendAction("RESET");
  parsedList = null;
  listTextarea.value = "";
  showView("input");
}

function handleStoreChange(): void {
  const storeId = storeSelect.value;
  if (storeId) {
    sendMessage({ type: "SET_STORE", storeId }, () => {
      activeStoreId = storeId;
    });
  }
}

function sendAction(action: PanelMessage["type"] extends "WIZARD_ACTION" ? never : string): void {
  sendMessage(
    { type: "WIZARD_ACTION", action: action as any },
    (response) => {
      if (response.type === "STATE_UPDATE") {
        wizardState = response.state;
        renderCurrentView();
      }
    },
  );
}

function sendMessage(message: PanelMessage, callback: (response: WorkerResponse) => void): void {
  chrome.runtime.sendMessage(message, callback);
}

// ── Rendering ──

function showView(name: keyof typeof views): void {
  for (const [key, el] of Object.entries(views)) {
    el.classList.toggle("hidden", key !== name);
  }
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
  for (const item of parsedList.items) {
    const li = document.createElement("li");
    li.className = "review-item";

    const nameSpan = document.createElement("span");
    nameSpan.className = "item-name";
    nameSpan.textContent = item.searchTerm;

    const qtySpan = document.createElement("span");
    qtySpan.className = "item-qty";
    qtySpan.textContent = formatQuantity(item);

    li.append(qtySpan, nameSpan);
    reviewList.appendChild(li);
  }

  // Filtered items
  if (parsedList.filtered.length > 0) {
    filteredSection.classList.remove("hidden");
    filteredList.innerHTML = "";
    for (const item of parsedList.filtered) {
      const li = document.createElement("li");
      li.textContent = item.searchTerm;
      filteredList.appendChild(li);
    }
  } else {
    filteredSection.classList.add("hidden");
  }

  startBtn.disabled = !activeStoreId;
}

function renderWizardView(): void {
  if (!wizardState) return;

  const items = wizardState.items;
  const activeItem = findActiveItem(wizardState);

  if (activeItem) {
    const searchTerm = activeItem.searchTermOverride ?? activeItem.parsedItem.searchTerm;
    currentItemName.textContent = searchTerm;
    currentItemQty.textContent = formatQuantity(activeItem.parsedItem);
  }

  // Progress
  const added = items.filter((i) => i.status === "added").length;
  const total = items.length;
  progressText.textContent = `${added}/${total}`;
  progressBar.style.width = `${(added / total) * 100}%`;

  // Cooldown state
  const isCooldown = wizardState.status === "cooldown";
  cooldownBar.classList.toggle("hidden", !isCooldown);
  skipBtn.classList.toggle("hidden", isCooldown);

  if (isCooldown) {
    cooldownMsg.textContent = "Added! Next item in 3s...";
    startCooldownTimer();
  }
}

function renderDoneView(): void {
  if (!wizardState) return;

  const added = wizardState.items.filter((i) => i.status === "added").length;
  const skipped = wizardState.items.filter((i) => i.status === "skipped").length;
  const dismissed = wizardState.items.filter((i) => i.status === "dismissed").length;
  const total = wizardState.items.length;

  summaryEl.innerHTML = `
    <p><strong>${added}</strong> of ${total} items added to cart</p>
    ${skipped > 0 ? `<p>${skipped} items skipped</p>` : ""}
    ${dismissed > 0 ? `<p>${dismissed} items dismissed</p>` : ""}
  `;

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
  // Hard-coded for now — would come from config manifest in production
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

function formatQuantity(item: { quantity: { amount: number; unit: string | null } | null }): string {
  if (!item.quantity) return "";
  const { amount, unit } = item.quantity;
  return unit ? `${amount} ${unit}` : `×${amount}`;
}
