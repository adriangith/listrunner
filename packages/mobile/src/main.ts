import {
  parseList,
  createWizardState,
  wizardReducer,
  currentItem,
  PantryList,
  SelectionHistory,
  type ParsedList,
  type ParsedItem,
  type WizardState,
  type WizardItem,
  type WizardAction,
} from "@listrunner/core";
import StoreSession from "@listrunner/store-session";

const COOLDOWN_MS = 3000;
const STORE_ID = "coles-au";

// State
let parsedList: ParsedList | null = null;
let wizardState: WizardState | null = null;
let cooldownTimer: ReturnType<typeof setTimeout> | null = null;
let cooldownStartedAt: number | null = null;
let cooldownCountdownTimer: ReturnType<typeof setInterval> | null = null;
let previousView: ViewName = "input";
let lastAnnouncedKey: string | null = null;
let lastLoupeKey: string | null = null;
let pendingInitialStoreSearch = false;

const pantry = new PantryList();
const history = new SelectionHistory();

type ViewName = "input" | "review" | "wizard" | "done" | "pantry";
type SimpleWizardAction = Exclude<
  WizardAction,
  { type: "START" } | { type: "EDIT_SEARCH" }
>["type"];

// DOM refs - Views
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
const startBtn = document.getElementById("btn-start") as HTMLButtonElement;
const backBtn = document.getElementById("btn-back") as HTMLButtonElement;
const filteredSection = document.getElementById("filtered-section") as HTMLElement;
const filteredList = document.getElementById("filtered-list") as HTMLElement;
const addItemForm = document.getElementById("add-item-form") as HTMLFormElement;
const addItemInput = document.getElementById("add-item-input") as HTMLInputElement;

// Wizard view
const currentItemName = document.getElementById("current-item-name") as HTMLElement;
const currentItemQty = document.getElementById("current-item-qty") as HTMLElement;
const currentSearchInput = document.getElementById("current-search-input") as HTMLInputElement;
const updateSearchBtn = document.getElementById("btn-update-search") as HTMLButtonElement;
const progressText = document.getElementById("progress-text") as HTMLElement;
const progressBar = document.getElementById("progress-fill") as HTMLElement;
const wizardAnnouncer = document.getElementById("wizard-announcer") as HTMLElement;
const skipBtn = document.getElementById("btn-skip") as HTMLButtonElement;
const dismissBtn = document.getElementById("btn-dismiss") as HTMLButtonElement;
const revisitBadge = document.getElementById("revisit-badge") as HTMLElement;
const cooldownBar = document.getElementById("cooldown-bar") as HTMLElement;
const cooldownMsg = document.getElementById("cooldown-msg") as HTMLElement;
const addAnotherBtn = document.getElementById("btn-add-another") as HTMLButtonElement;
const undoBtn = document.getElementById("btn-undo") as HTMLButtonElement;
const shortcutsBtn = document.getElementById("btn-shortcuts") as HTMLButtonElement;
const exitWizardBtn = document.getElementById("btn-exit-wizard") as HTMLButtonElement;
const shortcutsOverlay = document.getElementById("shortcuts-overlay") as HTMLElement;
const shortcutsCloseBtn = document.getElementById("btn-shortcuts-close") as HTMLButtonElement;
const loupeHintEl = document.getElementById("loupe-hint") as HTMLElement;
const loupeName = document.getElementById("loupe-name") as HTMLElement;
const loupeImage = document.getElementById("loupe-image") as HTMLImageElement;
const addedBtn = document.getElementById("btn-added") as HTMLButtonElement;
const automationWarning = document.getElementById("automation-warning") as HTMLElement;

// Done view
const summaryEl = document.getElementById("summary") as HTMLElement;
const revisitBtn = document.getElementById("btn-revisit") as HTMLButtonElement;
const newListBtn = document.getElementById("btn-new-list") as HTMLButtonElement;

// Pantry view
const pantryBackBtn = document.getElementById("btn-pantry-back") as HTMLElement;
const pantryAddForm = document.getElementById("pantry-add-form") as HTMLFormElement;
const pantryNewInput = document.getElementById("pantry-new") as HTMLInputElement;
const pantryListEl = document.getElementById("pantry-list") as HTMLElement;
const pantryEmpty = document.getElementById("pantry-empty") as HTMLElement;
const clearHistoryBtn = document.getElementById("btn-clear-history") as HTMLButtonElement;
const clearHistoryFeedback = document.getElementById("clear-history-feedback") as HTMLElement;

// Initialize
loadPersistedData();
init();

function loadPersistedData(): void {
  try {
    const pantryData = localStorage.getItem("lr-pantry");
    if (pantryData) {
      pantry.merge(JSON.parse(pantryData));
    }
    const historyData = localStorage.getItem("lr-history");
    if (historyData) {
      for (const record of JSON.parse(historyData)) {
        history.add(record);
      }
    }
  } catch {
    // Ignore corrupt data
  }
}

function persistData(): void {
  try {
    localStorage.setItem("lr-pantry", JSON.stringify(pantry.toJSON()));
    localStorage.setItem("lr-history", JSON.stringify(history.toJSON()));
  } catch {
    // Storage full or unavailable
  }
}

function init(): void {
  parseBtn.addEventListener("click", handleParse);
  startBtn.addEventListener("click", handleStart);
  backBtn.addEventListener("click", () => showView("input"));
  skipBtn.addEventListener("click", () => sendAction("SKIP"));
  dismissBtn.addEventListener("click", () => sendAction("DISMISS"));
  addAnotherBtn.addEventListener("click", () => sendAction("ADD_ANOTHER"));
  undoBtn.addEventListener("click", () => sendAction("UNDO"));
  revisitBtn.addEventListener("click", () => sendAction("BEGIN_REVISIT"));
  newListBtn.addEventListener("click", handleNewList);
  addItemForm.addEventListener("submit", handleAddReviewItem);
  updateSearchBtn.addEventListener("click", handleUpdateSearch);
  currentSearchInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") handleUpdateSearch();
  });

  pantryBtn.addEventListener("click", openPantry);
  pantryBackBtn.addEventListener("click", closePantry);
  pantryAddForm.addEventListener("submit", handlePantryAdd);
  clearHistoryBtn.addEventListener("click", handleClearHistory);

  shortcutsBtn.addEventListener("click", openShortcuts);
  exitWizardBtn.addEventListener("click", handleExitWizard);
  shortcutsCloseBtn.addEventListener("click", closeShortcuts);
  shortcutsOverlay.addEventListener("click", (e) => {
    if (e.target === shortcutsOverlay) closeShortcuts();
  });

  document.addEventListener("keydown", handleKeyboardShortcut);

  // StoreSession plugin listeners
  StoreSession.addListener("pageReady", () => {
    if (pendingInitialStoreSearch) {
      pendingInitialStoreSearch = false;
      navigateToActiveItem();
    }
  });

  StoreSession.addListener("addToCartDetected", (info) => {
    handleAdded(info);
  });

  StoreSession.addListener("skipRequested", () => {
    sendAction("SKIP");
  });

  StoreSession.addListener("selectorReady", () => {
    // Automation selectors are ready
    console.log("Store automation ready");
  });

  StoreSession.addListener("automationTimeout", () => {
    // Automation failed, show manual fallback
    if (automationWarning) {
      automationWarning.classList.remove("hidden");
    }
  });

  showView("input");
}

function handleParse(): void {
  const text = listTextarea.value.trim();
  if (!text) return;

  parsedList = parseList(text, {
    pantryExclusions: pantry.getNames(),
  });
  renderReviewList();
  showView("review");
}

function handleStart(): void {
  if (!parsedList) return;
  if (parsedList.items.length === 0) return;

  wizardState = wizardReducer(createWizardState(), {
    type: "START",
    items: parsedList.items,
  });

  showView("wizard");
  renderWizardView();

  // Open store session in WKWebView
  const storeUrl = getStoreUrl(STORE_ID);
  pendingInitialStoreSearch = true;
  StoreSession.openSession({ storeId: STORE_ID, url: storeUrl });
}

function getStoreUrl(storeId: string): string {
  // Map store IDs to their base URLs
  const storeUrls: Record<string, string> = {
    "coles-au": "https://www.coles.com.au",
    "woolworths-au": "https://www.woolworths.com.au",
    "iga-au": "https://www.iga.com.au",
  };
  return storeUrls[storeId] || "https://www.coles.com.au";
}

function handleNewList(): void {
  wizardState = null;
  parsedList = null;
  listTextarea.value = "";
  showView("input");
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

  wizardState = wizardReducer(wizardState, {
    type: "EDIT_SEARCH",
    index,
    searchTerm: newTerm,
  });

  // Re-trigger search in webview
  StoreSession.search({ query: newTerm });
  renderWizardView();
}

function handleExitWizard(): void {
  if (!confirm("Exit the wizard? You'll return to the review screen.")) {
    return;
  }
  wizardState = null;

  // Close store session
  StoreSession.closeSession();

  if (parsedList) {
    showView("review");
  } else {
    showView("input");
  }
}

function handleAddReviewItem(e: Event): void {
  e.preventDefault();
  const text = addItemInput.value.trim();
  if (!text || !parsedList) return;

  const parsed = parseList(text, { pantryExclusions: pantry.getNames() });
  if (parsed.items.length > 0) {
    parsedList.items.push(...parsed.items);
    renderReviewList();
    addItemInput.value = "";
  }
}

function sendAction(action: SimpleWizardAction): void {
  if (!wizardState) return;

  wizardState = wizardReducer(wizardState, toWizardAction(action));

  if (wizardState.status === "cooldown") {
    startCooldown();
  } else {
    stopCooldown();
  }

  if (wizardState.status === "stepping" || wizardState.status === "revisiting") {
    navigateToActiveItem();
  }

  renderCurrentView();
}

function navigateToActiveItem(): void {
  if (!wizardState) return;
  const item = currentItem(wizardState);
  if (!item) return;

  const searchTerm = item.searchTermOverride ?? item.parsedItem.searchTerm;

  // Update native overlay
  StoreSession.setStore({ storeId: STORE_ID });
  StoreSession.updateOverlay({
    itemName: searchTerm,
    searchTerm,
  });

  // Navigate to search
  StoreSession.search({ query: searchTerm });
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

  reviewCount.textContent = `${parsedList.items.length} item${parsedList.items.length !== 1 ? "s" : ""}`;

  reviewList.innerHTML = "";
  for (const item of parsedList.items) {
    const li = document.createElement("li");
    li.textContent = `${formatQuantity(item)} ${item.searchTerm}`.trim();
    reviewList.appendChild(li);
  }

  // Filtered items
  filteredSection.classList.toggle("hidden", parsedList.filtered.length === 0);
  filteredList.innerHTML = "";
  for (const item of parsedList.filtered) {
    const li = document.createElement("li");
    li.textContent = `${formatQuantity(item)} ${item.searchTerm}`.trim();
    li.style.textDecoration = "line-through";
    li.style.color = "#999";
    filteredList.appendChild(li);
  }
}

function renderWizardView(): void {
  if (!wizardState) return;

  const item = currentItem(wizardState);
  if (!item) return;

  const parsedItem = item.parsedItem;
  const searchTerm = item.searchTermOverride ?? parsedItem.searchTerm;

  currentItemName.textContent = searchTerm;
  currentItemQty.textContent = formatQuantity(parsedItem);
  currentSearchInput.value = searchTerm;

  // Progress
  const total = wizardState.items.length;
  const done = wizardState.items.filter(
    (i) => i.status === "added" || i.status === "skipped" || i.status === "dismissed"
  ).length;
  const pct = total > 0 ? (done / total) * 100 : 0;
  progressBar.style.width = `${pct}%`;
  progressText.textContent = `${done} / ${total}`;

  // Buttons
  dismissBtn.classList.toggle("hidden", wizardState.status !== "revisiting");
  undoBtn.classList.toggle("hidden", wizardState.status !== "cooldown");
  addAnotherBtn.classList.toggle("hidden", wizardState.status !== "cooldown");
  revisitBadge.classList.toggle("hidden", wizardState.status !== "revisiting");

  // Loupe hint
  updateLoupeHint(searchTerm);

  // Announce
  const announceKey = `${wizardState.status}:${searchTerm}`;
  if (announceKey !== lastAnnouncedKey) {
    lastAnnouncedKey = announceKey;
    wizardAnnouncer.textContent = `Now: ${searchTerm}`;
  }
}

function updateLoupeHint(searchTerm: string): void {
  if (!wizardState || !searchTerm) {
    loupeHintEl.classList.add("hidden");
    return;
  }
  if (searchTerm === lastLoupeKey) return;
  lastLoupeKey = searchTerm;

  const records = history.lookup(STORE_ID, searchTerm);
  if (records.length === 0) {
    loupeHintEl.classList.add("hidden");
    return;
  }

  const latest = records[0];
  loupeName.textContent = latest.productName;
  if (latest.productImageUrl) {
    loupeImage.src = latest.productImageUrl;
    loupeImage.classList.remove("hidden");
  } else {
    loupeImage.classList.add("hidden");
  }
  loupeHintEl.classList.remove("hidden");
}

function renderDoneView(): void {
  if (!wizardState) return;

  const doneItems = wizardState.items.filter((i) => i.status === "added");
  const skippedItems = wizardState.items.filter((i) => i.status === "skipped");

  let html = `<p>Added: ${doneItems.length} item${doneItems.length !== 1 ? "s" : ""}</p>`;
  if (skippedItems.length > 0) {
    html += `<p>Skipped: ${skippedItems.length} item${skippedItems.length !== 1 ? "s" : ""}</p>`;
  }
  summaryEl.innerHTML = html;

  revisitBtn.classList.toggle("hidden", skippedItems.length === 0);
}

function startCooldown(): void {
  stopCooldown();
  cooldownStartedAt = Date.now();
  cooldownBar.classList.remove("hidden");
  automationWarning.classList.add("hidden");

  updateCooldownMessage();
  cooldownCountdownTimer = setInterval(updateCooldownMessage, 100);

  cooldownTimer = setTimeout(() => {
    sendAction("COOLDOWN_COMPLETE");
  }, COOLDOWN_MS);
}

function updateCooldownMessage(): void {
  if (!cooldownStartedAt) return;
  const remaining = Math.max(0, COOLDOWN_MS - (Date.now() - cooldownStartedAt));
  const secs = Math.ceil(remaining / 1000);
  cooldownMsg.textContent = `Cooldown: ${secs}s...`;
}

function stopCooldown(): void {
  if (cooldownTimer !== null) {
    clearTimeout(cooldownTimer);
    cooldownTimer = null;
  }
  if (cooldownCountdownTimer !== null) {
    clearInterval(cooldownCountdownTimer);
    cooldownCountdownTimer = null;
  }
  cooldownBar.classList.add("hidden");
  cooldownStartedAt = null;
}

function findActiveItem(state: WizardState): WizardItem | null {
  if (state.status === "cooldown" && state.cooldownItemIndex !== null) {
    return state.items[state.cooldownItemIndex] ?? null;
  }
  return currentItem(state);
}

function formatQuantity(item: ParsedItem): string {
  if (!item.quantity) return "";
  const { amount, unit } = item.quantity;
  return unit ? `${amount} ${unit}` : `×${amount}`;
}

function toWizardAction(action: SimpleWizardAction): WizardAction {
  switch (action) {
    case "ADVANCE":
      return { type: "ADVANCE" };
    case "SKIP":
      return { type: "SKIP" };
    case "ADD_ANOTHER":
      return { type: "ADD_ANOTHER" };
    case "UNDO":
      return { type: "UNDO" };
    case "COOLDOWN_COMPLETE":
      return { type: "COOLDOWN_COMPLETE" };
    case "BEGIN_REVISIT":
      return { type: "BEGIN_REVISIT" };
    case "DISMISS":
      return { type: "DISMISS" };
    case "RESET":
      return { type: "RESET" };
  }
}

function showView(name: ViewName): void {
  previousView = name;
  for (const key of Object.keys(views) as ViewName[]) {
    views[key].classList.toggle("hidden", key !== name);
  }
}

function openPantry(): void {
  renderPantryList();
  showView("pantry");
}

function closePantry(): void {
  showView(previousView);
}

function renderPantryList(): void {
  const names = pantry.getNames();
  pantryListEl.innerHTML = "";
  pantryEmpty.classList.toggle("hidden", names.length > 0);

  for (const name of names) {
    const li = document.createElement("li");
    li.textContent = name;
    const removeBtn = document.createElement("button");
    removeBtn.textContent = "Remove";
    removeBtn.className = "btn btn-small btn-secondary";
    removeBtn.addEventListener("click", () => {
      pantry.remove(name);
      persistData();
      renderPantryList();
    });
    li.appendChild(removeBtn);
    pantryListEl.appendChild(li);
  }
}

function handlePantryAdd(e: Event): void {
  e.preventDefault();
  const name = pantryNewInput.value.trim();
  if (!name) return;
  pantry.add(name);
  persistData();
  pantryNewInput.value = "";
  renderPantryList();
}

function handleClearHistory(): void {
  const removed = history.getAll().length;
  history.clear();
  persistData();
  clearHistoryFeedback.textContent = `Cleared ${removed} record${removed !== 1 ? "s" : ""}`;
  clearHistoryFeedback.classList.remove("hidden");
  setTimeout(() => clearHistoryFeedback.classList.add("hidden"), 3000);
}

function handleAdded(product?: {
  productName?: string;
  productImageUrl?: string | null;
}): void {
  if (!wizardState) return;
  const item = currentItem(wizardState);
  if (!item) return;

  const searchTerm = item.searchTermOverride ?? item.parsedItem.searchTerm;

  history.add({
    store: STORE_ID,
    searchTerm,
    productName: product?.productName || searchTerm,
    productImageUrl: product?.productImageUrl || null,
  });
  persistData();

  sendAction("ADVANCE");
}

function handleKeyboardShortcut(e: KeyboardEvent): void {
  const target = e.target as HTMLElement | null;
  if (target) {
    const tag = target.tagName;
    if (tag === "INPUT" || tag === "TEXTAREA" || target.isContentEditable) {
      return;
    }
  }
  if (!wizardState) return;

  const status = wizardState.status;

  if (status === "stepping" || status === "revisiting") {
    if (e.key === "s" || e.key === "S") {
      e.preventDefault();
      sendAction("SKIP");
      return;
    }
    if (status === "revisiting" && (e.key === "d" || e.key === "D")) {
      e.preventDefault();
      sendAction("DISMISS");
      return;
    }
    if (e.key === "e" || e.key === "E") {
      e.preventDefault();
      currentSearchInput.focus();
      currentSearchInput.select();
      return;
    }
  }

  if (status === "cooldown") {
    if (e.key === " " || e.key === "Enter") {
      e.preventDefault();
      sendAction("COOLDOWN_COMPLETE");
      return;
    }
    if (e.key === "u" || e.key === "U") {
      e.preventDefault();
      sendAction("UNDO");
      return;
    }
    if (e.key === "a" || e.key === "A") {
      e.preventDefault();
      sendAction("ADD_ANOTHER");
      return;
    }
  }

  if (status === "done") {
    if (e.key === "r" || e.key === "R") {
      const hasSkipped =
        wizardState.items.some((i) => i.status === "skipped") ?? false;
      if (hasSkipped) {
        e.preventDefault();
        sendAction("BEGIN_REVISIT");
      }
    }
  }

  if (e.key === "?") {
    e.preventDefault();
    if (shortcutsOverlay.classList.contains("hidden")) {
      openShortcuts();
    } else {
      closeShortcuts();
    }
  } else if (e.key === "Escape" && !shortcutsOverlay.classList.contains("hidden")) {
    closeShortcuts();
  }
}

function openShortcuts(): void {
  shortcutsOverlay.classList.remove("hidden");
}

function closeShortcuts(): void {
  shortcutsOverlay.classList.add("hidden");
}
