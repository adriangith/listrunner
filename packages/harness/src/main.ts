import {
  parseList,
  createWizardState,
  wizardReducer,
  currentItem,
  PantryList,
  SelectionHistory,
} from "@listrunner/core";
import type {
  ParsedList,
  ParsedItem,
  WizardState,
  WizardItem,
  WizardAction,
} from "@listrunner/core";
import colesConfig from "../../extension/src/store-configs/coles-au.js";

const COOLDOWN_MS = 3000;
const STORE_ID = colesConfig.id;
const COLES_WINDOW_NAME = "listrunner-coles";

let parsedList: ParsedList | null = null;
let colesWindow: Window | null = null;
let wizardState: WizardState | null = null;
let cooldownTimer: ReturnType<typeof setTimeout> | null = null;
let cooldownStartedAt: number | null = null;
let cooldownCountdownTimer: ReturnType<typeof setInterval> | null = null;
let previousView: ViewName = "input";
let lastAnnouncedKey: string | null = null;
let lastLoupeKey: string | null = null;

const pantry = new PantryList();
const history = new SelectionHistory();

type ViewName = "input" | "review" | "wizard" | "done" | "pantry";

const views: Record<ViewName, HTMLElement> = {
  input: document.getElementById("view-input") as HTMLElement,
  review: document.getElementById("view-review") as HTMLElement,
  wizard: document.getElementById("view-wizard") as HTMLElement,
  done: document.getElementById("view-done") as HTMLElement,
  pantry: document.getElementById("view-pantry") as HTMLElement,
};

const listTextarea = document.getElementById("list-input") as HTMLTextAreaElement;
const parseBtn = document.getElementById("btn-parse") as HTMLButtonElement;
const pantryBtn = document.getElementById("btn-pantry") as HTMLButtonElement;

const reviewList = document.getElementById("review-list") as HTMLElement;
const reviewCount = document.getElementById("review-count") as HTMLElement;
const startBtn = document.getElementById("btn-start") as HTMLButtonElement;
const backBtn = document.getElementById("btn-back") as HTMLButtonElement;
const filteredSection = document.getElementById("filtered-section") as HTMLElement;
const filteredList = document.getElementById("filtered-list") as HTMLElement;
const addItemForm = document.getElementById("add-item-form") as HTMLFormElement;
const addItemInput = document.getElementById("add-item-input") as HTMLInputElement;

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
const progressBarEl = document.getElementById("progress-bar") as HTMLElement;
const wizardAnnouncer = document.getElementById(
  "wizard-announcer",
) as HTMLElement;
const skipBtn = document.getElementById("btn-skip") as HTMLButtonElement;
const dismissBtn = document.getElementById("btn-dismiss") as HTMLButtonElement;
const revisitBadge = document.getElementById("revisit-badge") as HTMLElement;
const cooldownBar = document.getElementById("cooldown-bar") as HTMLElement;
const cooldownMsg = document.getElementById("cooldown-msg") as HTMLElement;
const addAnotherBtn = document.getElementById("btn-add-another") as HTMLButtonElement;
const undoBtn = document.getElementById("btn-undo") as HTMLButtonElement;
const shortcutsBtn = document.getElementById(
  "btn-shortcuts",
) as HTMLButtonElement;
const exitWizardBtn = document.getElementById(
  "btn-exit-wizard",
) as HTMLButtonElement;
const shortcutsOverlay = document.getElementById(
  "shortcuts-overlay",
) as HTMLElement;
const shortcutsCloseBtn = document.getElementById(
  "btn-shortcuts-close",
) as HTMLButtonElement;
const loupeHintEl = document.getElementById("loupe-hint") as HTMLElement;
const loupeName = document.getElementById("loupe-name") as HTMLElement;
const openColesBtn = document.getElementById("btn-open-coles") as HTMLButtonElement;
const addedBtn = document.getElementById("btn-added") as HTMLButtonElement;

const summaryEl = document.getElementById("summary") as HTMLElement;
const revisitBtn = document.getElementById("btn-revisit") as HTMLButtonElement;
const newListBtn = document.getElementById("btn-new-list") as HTMLButtonElement;

const pantryBackBtn = document.getElementById(
  "btn-pantry-back",
) as HTMLButtonElement;
const pantryAddForm = document.getElementById("pantry-add-form") as HTMLFormElement;
const pantryNewInput = document.getElementById("pantry-new") as HTMLInputElement;
const pantryListEl = document.getElementById("pantry-list") as HTMLElement;
const pantryEmpty = document.getElementById("pantry-empty") as HTMLElement;
const clearHistoryBtn = document.getElementById(
  "btn-clear-history",
) as HTMLButtonElement;
const clearHistoryFeedback = document.getElementById(
  "clear-history-feedback",
) as HTMLElement;

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
  openColesBtn.addEventListener("click", handleOpenColes);
  addedBtn.addEventListener("click", handleAdded);

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
  navigateColesToActiveItem(true);
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
  navigateColesToActiveItem(false);
  renderWizardView();
}

function handleExitWizard(): void {
  if (
    !confirm(
      "Exit the wizard? You'll return to the review screen.",
    )
  ) {
    return;
  }
  wizardState = null;
  if (parsedList) {
    showView("review");
  } else {
    showView("input");
  }
}

function handleOpenColes(): void {
  navigateColesToActiveItem(true);
}

function handleAdded(): void {
  if (!wizardState) return;
  const item = currentItem(wizardState);
  if (!item) return;

  const searchTerm =
    item.searchTermOverride ?? item.parsedItem.searchTerm;

  history.add({
    store: STORE_ID,
    searchTerm,
    productName: searchTerm,
    productImageUrl: null,
  });
  persistData();

  sendAction("ADVANCE");
}

function sendAction(
  action: WizardAction["type"],
): void {
  if (!wizardState) return;

  const prevStatus = wizardState.status;
  wizardState = wizardReducer(wizardState, { type: action });

  if (wizardState.status === "cooldown") {
    startCooldown();
  } else {
    stopCooldown();
  }

  // Navigate Coles window when we land on a new active item
  if (wizardState.status === "stepping" || wizardState.status === "revisiting") {
    navigateColesToActiveItem(false);
  }

  renderCurrentView();
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

  startBtn.disabled = parsedList.items.length === 0;
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

function handleAddReviewItem(e: Event): void {
  e.preventDefault();
  const raw = addItemInput.value.trim();
  if (!raw || !parsedList) return;

  const added = parseList(raw).items[0];
  if (!added) return;
  parsedList.items.push(added);
  addItemInput.value = "";
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
    if (document.activeElement !== currentSearchInput) {
      currentSearchInput.value = searchTerm;
    }
    maybeFetchLoupeHint(searchTerm);
    announceItem(searchTerm, wizardState.status);
  } else {
    hideLoupeHint();
  }

  const added = items.filter((i) => i.status === "added").length;
  const total = items.length;
  progressText.textContent = `${added}/${total}`;
  progressBar.style.width = total > 0 ? `${(added / total) * 100}%` : "0%";
  progressBarEl.setAttribute("aria-valuenow", String(added));
  progressBarEl.setAttribute("aria-valuemax", String(total));

  const isCooldown = wizardState.status === "cooldown";
  const isRevisiting = wizardState.status === "revisiting";

  cooldownBar.classList.toggle("hidden", !isCooldown);
  skipBtn.classList.toggle("hidden", isCooldown);
  dismissBtn.classList.toggle("hidden", !isRevisiting || isCooldown);
  revisitBadge.classList.toggle("hidden", !isRevisiting);

  openColesBtn.classList.toggle("hidden", isCooldown);
  addedBtn.classList.toggle("hidden", isCooldown);

  if (isCooldown) {
    startCooldownDisplay();
  } else {
    stopCooldownDisplay();
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

function announceItem(term: string, status: string): void {
  const key = `${status}::${term}`;
  if (key === lastAnnouncedKey) return;
  lastAnnouncedKey = key;

  const prefix =
    status === "cooldown"
      ? "Added. Next up: "
      : status === "revisiting"
        ? "Revisiting: "
        : "Now on: ";
  wizardAnnouncer.textContent = `${prefix}${term}`;
}

function maybeFetchLoupeHint(searchTerm: string): void {
  const key = `${STORE_ID}::${searchTerm.toLowerCase()}`;
  if (key === lastLoupeKey) return;
  lastLoupeKey = key;

  const records = history.lookup(STORE_ID, searchTerm);
  if (records.length === 0) {
    hideLoupeHint();
    return;
  }

  const latest = records[0]!;
  renderLoupeHint(latest.productName);
}

function renderLoupeHint(productName: string): void {
  loupeName.textContent = productName;
  loupeHintEl.classList.remove("hidden");
}

function hideLoupeHint(): void {
  loupeHintEl.classList.add("hidden");
  lastLoupeKey = null;
}

function startCooldown(): void {
  cooldownStartedAt = Date.now();
  if (cooldownTimer) clearTimeout(cooldownTimer);
  cooldownTimer = setTimeout(() => {
    cooldownTimer = null;
    if (wizardState?.status !== "cooldown") return;
    sendAction("COOLDOWN_COMPLETE");
  }, COOLDOWN_MS);
  renderWizardView();
}

function stopCooldown(): void {
  cooldownStartedAt = null;
  if (cooldownTimer) {
    clearTimeout(cooldownTimer);
    cooldownTimer = null;
  }
  stopCooldownDisplay();
}

function startCooldownDisplay(): void {
  if (cooldownStartedAt === null) {
    cooldownStartedAt = Date.now();
  }
  updateCooldownText();
  if (cooldownCountdownTimer) return;
  cooldownCountdownTimer = setInterval(updateCooldownText, 200);
}

function stopCooldownDisplay(): void {
  if (cooldownCountdownTimer) {
    clearInterval(cooldownCountdownTimer);
    cooldownCountdownTimer = null;
  }
  cooldownStartedAt = null;
}

function updateCooldownText(): void {
  if (cooldownStartedAt === null) return;
  const elapsed = Date.now() - cooldownStartedAt;
  const remainingMs = Math.max(0, COOLDOWN_MS - elapsed);
  const remaining = Math.ceil(remainingMs / 1000);
  cooldownMsg.textContent =
    remaining > 0
      ? `Added! Next item in ${remaining}s…`
      : "Added! Advancing…";
}

function openShortcuts(): void {
  shortcutsOverlay.classList.remove("hidden");
  shortcutsCloseBtn.focus();
}

function closeShortcuts(): void {
  shortcutsOverlay.classList.add("hidden");
  shortcutsBtn.focus();
}

function openPantry(): void {
  renderPantry(pantry.getNames());
  showView("pantry");
}

function closePantry(): void {
  showView(previousView);
}

function handlePantryAdd(e: Event): void {
  e.preventDefault();
  const name = pantryNewInput.value.trim();
  if (!name) return;
  pantry.add(name);
  persistData();
  pantryNewInput.value = "";
  renderPantry(pantry.getNames());
}

function handleClearHistory(): void {
  if (
    !confirm(
      "Clear all stored product-selection history? You'll lose the 'last time you picked' hints.",
    )
  ) {
    return;
  }
  const removed = history.getAll().length;
  history.clear();
  persistData();
  hideLoupeHint();

  clearHistoryFeedback.textContent =
    removed === 0
      ? "No history to clear."
      : `Removed ${removed} record${removed === 1 ? "" : "s"}.`;
  clearHistoryFeedback.classList.remove("hidden");
  setTimeout(() => {
    clearHistoryFeedback.classList.add("hidden");
  }, 3000);
}

function handlePantryRemove(name: string): void {
  pantry.remove(name);
  persistData();
  renderPantry(pantry.getNames());
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

function handleKeyboardShortcut(e: KeyboardEvent): void {
  const target = e.target as HTMLElement | null;
  if (target) {
    const tag = target.tagName;
    if (
      tag === "INPUT" ||
      tag === "TEXTAREA" ||
      target.isContentEditable
    ) {
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
      handleCooldownAdvance();
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
      const hasSkipped = wizardState.items.some(
        (i) => i.status === "skipped",
      );
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
  } else if (
    e.key === "Escape" &&
    !shortcutsOverlay.classList.contains("hidden")
  ) {
    closeShortcuts();
  }
}

function handleCooldownAdvance(): void {
  if (cooldownTimer) {
    clearTimeout(cooldownTimer);
    cooldownTimer = null;
  }
  sendAction("COOLDOWN_COMPLETE");
}

function showView(name: ViewName): void {
  for (const key of Object.keys(views) as ViewName[]) {
    views[key].classList.toggle("hidden", key !== name);
  }
  if (name !== "pantry") previousView = name;
}

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

function getActiveSearchTerm(): string | null {
  if (!wizardState) return null;
  const active = findActiveItem(wizardState);
  if (!active) return null;
  return active.searchTermOverride ?? active.parsedItem.searchTerm;
}

function buildColesSearchUrl(query: string): string {
  return colesConfig.search.urlTemplate!.replace(
    "{query}",
    encodeURIComponent(query),
  );
}

function navigateColesToActiveItem(allowOpen?: boolean): void {
  const query = getActiveSearchTerm();
  if (!query) return;

  const url = buildColesSearchUrl(query);

  // If we have an existing window reference and it's still open, navigate it directly
  if (colesWindow && !colesWindow.closed) {
    colesWindow.location.href = url;
    colesWindow.focus();
    return;
  }

  // Window is closed or we don't have a reference
  if (allowOpen) {
    // User gesture - safe to open or reuse the named Coles window.
    colesWindow = window.open(url, COLES_WINDOW_NAME);
    if (colesWindow) colesWindow.focus();
  }
}
