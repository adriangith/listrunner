const app = document.querySelector("#app");
const liveRegion = document.querySelector("#live-region");
const sampleItems = [
  { name: "Milk", qty: "2 L", status: "Pending" },
  { name: "Bread", qty: "1 loaf", status: "Pending" },
  { name: "Apples", qty: "5", status: "Pending" },
  { name: "BBQ sauce", qty: "1", status: "Pending" },
];
const products = [
  { icon: "🥛", name: "Dairy Farmers Full Cream Milk", price: "$3.60" },
  { icon: "🥛", name: "Coles Full Cream Milk", price: "$2.75" },
  { icon: "🍞", name: "Sourdough Sandwich Bread", price: "$4.50" },
  { icon: "🍎", name: "Royal Gala Apples", price: "$5.90" },
];
let items = structuredClone(sampleItems);
let view = "list";
let selected = 0;
let collapsed = false;
let undoTarget = null;
let cooldownTimer = null;
let toastTimer = null;
let finalUndoTarget = null;

function escapeHTML(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
}
function announce(message) { liveRegion.textContent = ""; requestAnimationFrame(() => { liveRegion.textContent = message; }); }
function counts() { return items.reduce((result, item) => { result[item.status] = (result[item.status] || 0) + 1; return result; }, {}); }
function pendingIndices() { return items.map((item, index) => item.status === "Pending" ? index : -1).filter((index) => index >= 0); }
function firstPending(from = selected, direction = 1) {
  if (!items.length) return -1;
  for (let step = 1; step <= items.length; step++) {
    const index = (from + direction * step + items.length * 2) % items.length;
    if (items[index].status === "Pending") return index;
  }
  return -1;
}
function showToast(message) {
  document.querySelector(".toast-message")?.remove();
  const toast = document.createElement("div"); toast.className = "toast-message"; toast.textContent = message; app.append(toast);
  setTimeout(() => toast.remove(), 2300);
}
function statusBadge(status) {
  const cls = status === "Added" ? "added" : status === "Skipped" ? "skipped" : "";
  return `<span class="status-tag ${cls}">${escapeHTML(status)}</span>`;
}
function listScreen() {
  const c = counts();
  const rows = items.length ? `<div class="grocery-list">${items.map((item, index) => `<div class="grocery-row" data-status="${item.status}" data-select="${index}" role="button" tabindex="0" aria-label="Open ${escapeHTML(item.name)}, ${escapeHTML(item.qty)}, ${item.status}"><span class="row-check">${item.status === "Added" ? "✓" : ""}</span><div><div class="row-name">${escapeHTML(item.name)}</div><div class="row-qty">${escapeHTML(item.qty)}</div></div>${statusBadge(item.status)}</div>`).join("")}</div>` : `<div class="grocery-list empty-list">Add a few groceries to get started.</div>`;
  return `<section class="screen list-screen"><div class="topline"><div><p class="eyebrow" style="margin:0 0 7px">YOUR SHOPPING RUN</p><h1 class="screen-title">Your list</h1></div><button class="settings-button" data-action="settings" aria-label="Settings"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.06.06-1.7 2.94-.09-.03a1.7 1.7 0 0 0-1.76.28l-.08.06h-3.4l-.02-.1a1.7 1.7 0 0 0-1.25-1.3l-.1-.02-2.4-2.4.04-.09a1.7 1.7 0 0 0-.28-1.76l-.06-.08v-3.4l.1-.02a1.7 1.7 0 0 0 1.3-1.25l.02-.1 2.4-2.4.09.04a1.7 1.7 0 0 0 1.76-.28l.08-.06h3.4l.02.1a1.7 1.7 0 0 0 1.25 1.3l.1.02 2.4 2.4-.04.09a1.7 1.7 0 0 0 .28 1.76l.06.08v1.3z" transform="translate(-2 -2)"/></svg></button></div><p class="subtitle">ListRunner <span aria-hidden="true">·</span> Shopping at Coles</p><div class="summary-row"><span class="count-chip pending">${c.Pending || 0} pending</span><span class="count-chip">${c.Added || 0} added</span><span class="count-chip">${c.Skipped || 0} skipped</span></div><p class="list-label">GROCERIES</p>${rows}<form class="input-card" id="add-form"><label for="add-input">Add items</label><div class="input-row"><input id="add-input" name="items" placeholder="e.g. 2 avocados, yoghurt" autocomplete="off"/><button class="add-btn" type="submit">Add</button></div></form><button class="text-link" data-action="reset-sample">Restore sample list</button><div class="bottom-actions"><button class="primary-button" data-action="show-store" ${items.length ? "" : "disabled"}>Show Store <span aria-hidden="true">↗</span></button></div></section>`;
}
function activeCards() {
  if (selected < 0 || !items.length) return "";
  const current = items[selected];
  const prevIndex = (selected - 1 + items.length) % items.length;
  const nextIndex = (selected + 1) % items.length;
  const card = (item, index, role) => role === "selected"
    ? `<div class="item-card selected" data-status="${item.status}" aria-label="Selected item: ${escapeHTML(item.name)}, ${item.status}" aria-current="step"><span class="card-status">${item.status.toUpperCase()}</span><span class="card-number">${selected + 1} / ${items.length}</span><h3>${escapeHTML(item.name)}</h3><p>${escapeHTML(item.qty)}</p><span class="card-divider"></span><button class="card-action" data-action="mark-added">${item.status === "Added" ? "More Time" : "Mark Added"}</button></div>`
    : `<button class="item-card ${role}" data-status="${item.status}" data-card-select="${index}" aria-label="Select ${escapeHTML(item.name)}, ${item.status}"><span class="card-status">${item.status.toUpperCase()}</span><h3>${escapeHTML(item.name)}</h3><p>${escapeHTML(item.qty)}</p></button>`;
  return `${items.length > 1 ? card(items[prevIndex], prevIndex, "previous") : ""}${card(current, selected, "selected")}${items.length > 1 ? card(items[nextIndex], nextIndex, "next") : ""}`;
}
function storeScreen() {
  const current = items[selected];
  const remaining = pendingIndices().length;
  return `<section class="screen store-screen" aria-label="Simulated Coles store"><div class="store-web"><div class="coles-bar"><span class="coles-wordmark">coles</span><div class="web-icons"><span aria-hidden="true">⌕</span><span aria-hidden="true">♙</span><span aria-hidden="true">♧</span></div></div><div class="web-content"><label class="web-search"><b aria-hidden="true">⌕</b><input id="store-search" type="search" aria-label="Search simulated Coles" value="${escapeHTML(current?.name || "")}" /></label><h2 class="web-greeting">Good food, good life</h2><p class="web-sub">Discover this week's fresh picks</p><div class="web-promo"><strong>Fresh picks<br/>for your table</strong><span>Shop fresh, every day</span><div class="promo-fruit" aria-hidden="true">🍊</div></div><div class="web-section-title"><span>Popular groceries</span><small>View all</small></div><div class="product-grid">${products.map((product) => `<article class="product-tile" data-product-name="${escapeHTML(product.name.toLowerCase())}"><div class="product-art" aria-hidden="true">${product.icon}</div><div class="product-title">${product.name}</div><div class="product-price">${product.price} <small>each</small></div><button class="tile-add" data-action="mock-add">ADD</button></article>`).join("")}</div></div></div><div class="store-handle-zone"><button class="store-handle" data-action="dismiss-store" aria-label="Dismiss store" title="Dismiss store"></button></div><div class="cooldown-toast" ${undoTarget === null ? "hidden" : ""}><div class="toast-copy"><strong>Added to your list</strong><span id="cooldown-copy">Next item in 3 seconds</span></div><button class="undo-button" data-action="undo">Undo</button></div>${finalUndoTarget !== null ? `<div class="finish-banner"><span>All items handled</span><div class="finish-actions"><button class="finish-undo" data-action="final-undo">Undo</button><button class="finish-done" data-action="finish">Finish</button></div></div>` : ""}<div class="runner-panel ${collapsed ? "collapsed" : ""}"><div class="card-carousel">${activeCards()}</div><div class="panel-caption">LISTRUNNER</div><div class="item-counter">${selected + 1} of ${items.length}</div><button class="collapse-button" data-action="collapse" aria-label="Collapse overlay">Collapse ↓</button><div class="panel-actions"><button class="nav-button" data-action="back" ${selected <= 0 ? "disabled" : ""}>‹ &nbsp;Back</button><span class="browse-hint">${remaining ? `${remaining} pending` : "All items handled"} &nbsp;·&nbsp; Browse</span><button class="nav-button" data-action="next">Skip &nbsp;›</button></div><div class="collapsed-summary"><span class="collapsed-item">${current ? `${escapeHTML(current.name)} · ${current.status}` : "Shopping run"}</span><button class="expand-button" data-action="expand">Expand overlay ↑</button></div></div></section>`;
}
function render() {
  app.innerHTML = view === "store" ? storeScreen() : listScreen();
  if (view === "list" && finalUndoTarget !== null) {
    const banner = document.createElement("div");
    banner.className = "list-finish-banner";
    banner.innerHTML = `<span>All items handled</span><div class="finish-actions"><button class="finish-undo" data-action="final-undo">Undo</button><button class="finish-done" data-action="finish">Finish</button></div>`;
    app.querySelector(".list-screen .bottom-actions")?.before(banner);
  }
  if (view === "store") {
    const toast = app.querySelector(".cooldown-toast");
    if (toast) {
      toast.hidden = cooldownTimer === null;
      toast.querySelector("strong").textContent = undoTarget !== null ? "Added to your list" : "More time";
      toast.querySelector(".undo-button").hidden = undoTarget === null;
    }
    if (cooldownTimer) startCooldownDisplay();
  }
}
function startCooldownDisplay() {
  const update = () => {
    const label = app.querySelector("#cooldown-copy");
    if (!label || !cooldownTimer) return;
    const seconds = Math.max(1, Math.ceil((cooldownTimer.expires - Date.now()) / 1000));
    label.textContent = undoTarget !== null ? `Next item in ${seconds} second${seconds === 1 ? "" : "s"}` : `More time · ${seconds}s`;
  };
  update();
  if (!cooldownTimer.interval) cooldownTimer.interval = setInterval(update, 200);
}
function startStore() {
  if (!items.length) return;
  if (selected < 0 || selected >= items.length) selected = Math.max(0, items.findIndex((item) => item.status === "Pending"));
  view = "store"; collapsed = false; render(); announce(`Coles store opened. ${items[selected].name}, ${items[selected].qty}, ${items[selected].status}, item ${selected + 1} of ${items.length}.`);
}
function dismissStore() { clearCooldown(); view = "list"; collapsed = false; render(); announce("Store dismissed. Your shopping list is visible."); }
function selectItem(index, speak = true) {
  if (index < 0 || index >= items.length) return;
  if (undoTarget !== null) clearCooldown();
  selected = index; render(); if (speak) announce(`${items[index].name}, ${items[index].qty}, ${items[index].status}, item ${index + 1} of ${items.length}.`);
}
function advance(direction = 1) {
  if (undoTarget !== null) clearCooldown();
  const next = firstPending(selected, direction);
  if (next >= 0) selectItem(next);
  else { selected = items.findIndex((item) => item.status !== "Pending"); render(); announce("All pending items have been handled."); }
}
function clearCooldown() { if (cooldownTimer) { clearTimeout(cooldownTimer.id); clearInterval(cooldownTimer.interval); } cooldownTimer = null; undoTarget = null; }
function markAdded() {
  const item = items[selected]; if (!item) return;
  if (item.status === "Added") {
    clearCooldown(); undoTarget = null;
    cooldownTimer = { expires: Date.now() + 3000, id: setTimeout(() => { const next = firstPending(selected, 1); clearInterval(cooldownTimer?.interval); cooldownTimer = null; if (next >= 0) selectItem(next); else render(); }, 3000) };
    render(); announce(`More time for ${item.name}. It remains selected for three seconds.`); return;
  }
  const previousStatus = item.status; item.status = "Added";
  const nextPending = pendingIndices().length > 0;
  if (!nextPending) { finalUndoTarget = { index: selected, previousStatus }; render(); announce(`${item.name} added. All items handled. Use Undo or Finish.`); return; }
  clearCooldown(); undoTarget = { index: selected, previousStatus };
  cooldownTimer = { expires: Date.now() + 3000, id: setTimeout(() => { const next = firstPending(selected, 1); clearInterval(cooldownTimer?.interval); undoTarget = null; cooldownTimer = null; if (next >= 0) { selected = next; render(); announce(`Next item: ${items[selected].name}.`); } else render(); }, 3000) };
  render(); announce(`${item.name} marked added. Undo is available for three seconds.`);
}
function undo() {
  if (undoTarget !== null) { const { index, previousStatus } = undoTarget; clearCooldown(); items[index].status = previousStatus; selected = index; render(); announce(`Undo. ${items[index].name} is ${previousStatus}.`); }
  else if (finalUndoTarget !== null) { items[finalUndoTarget.index].status = finalUndoTarget.previousStatus; selected = finalUndoTarget.index; finalUndoTarget = null; render(); announce(`Undo. ${items[selected].name} is ${items[selected].status}.`); }
}
function parseAndAdd(raw) {
  const incoming = raw.split(/[\n,]/).map((part) => part.replace(/^\s*[-*•]+\s*/, "").trim()).filter(Boolean);
  for (const entry of incoming) {
    const match = entry.match(/^(\d+(?:\.\d+)?\s*(?:x|×)?\s*(?:kg|g|ml|mL|l|L|litre|litres|cans?|loaves?|packs?)?)\s+(.+)$/i);
    const name = (match?.[2] || entry).replace(/\s+/g, " ").trim();
    const qty = match?.[1]?.replace(/\s+/g, " ").trim() || "1";
    const existing = items.find((item) => item.name.toLowerCase() === name.toLowerCase());
    if (existing) { existing.status = "Pending"; existing.qty = qty === "1" ? existing.qty : qty; }
    else items.push({ name, qty, status: "Pending" });
  }
}
function openModal(title, description, body) {
  const backdrop = document.createElement("div"); backdrop.className = "modal-backdrop"; backdrop.innerHTML = `<section class="sheet-modal" role="dialog" aria-modal="true" aria-labelledby="modal-title"><h2 id="modal-title">${title}</h2><p>${description}</p>${body}<button class="primary-button modal-close" data-action="close-modal">Done</button></section>`; app.append(backdrop); backdrop.querySelector("button")?.focus();
}
function handleAction(action) {
  switch (action) {
    case "show-store": startStore(); break;
    case "dismiss-store": dismissStore(); break;
    case "mark-added": markAdded(); break;
    case "undo": undo(); break;
    case "final-undo": undo(); break;
    case "finish": clearCooldown(); finalUndoTarget = null; dismissStore(); showToast("Shopping run complete"); break;
    case "back": if (selected > 0) selectItem(selected - 1); break;
    case "next": if (items[selected]?.status !== "Added") { items[selected].status = "Skipped"; announce(`${items[selected].name} skipped.`); } advance(1); break;
    case "collapse": collapsed = true; render(); announce("ListRunner overlay collapsed."); break;
    case "expand": collapsed = false; render(); announce("ListRunner overlay expanded."); break;
    case "settings": openModal("Settings", "Prototype settings are local to this demo.", `<button class="modal-row" data-action="reset-session"><span>Reset Coles session</span><span>›</span></button><button class="modal-row" data-action="clear-diagnostics"><span>Clear diagnostics</span><span>›</span></button><button class="modal-row" data-action="clear-list"><span>Clear list</span><span>›</span></button>`); break;
    case "reset-session": closeModal(); showToast("Coles session reset (simulated)"); break;
    case "clear-diagnostics": closeModal(); showToast("Diagnostics cleared"); break;
    case "clear-list": closeModal(); if (confirm("Clear this prototype list?")) { clearCooldown(); items = []; selected = -1; finalUndoTarget = null; view = "list"; render(); } break;
    case "close-modal": closeModal(); break;
    case "reset-sample": clearCooldown(); items = structuredClone(sampleItems); selected = 0; finalUndoTarget = null; render(); showToast("Sample list restored"); break;
    case "mock-add": markAdded(); showToast("Added to simulated Coles cart"); break;
  }
}
function closeModal() { app.querySelector(".modal-backdrop")?.remove(); }
app.addEventListener("click", (event) => {
  const button = event.target.closest("[data-action]");
  if (button) { handleAction(button.dataset.action); return; }
  const card = event.target.closest("[data-card-select]"); if (card) { selectItem(Number(card.dataset.cardSelect)); return; }
  const row = event.target.closest("[data-select]"); if (row) { selectItem(Number(row.dataset.select), false); startStore(); }
});
app.addEventListener("keydown", (event) => {
  const row = event.target.closest("[data-select]");
  if (row && (event.key === "Enter" || event.key === " ")) { event.preventDefault(); selectItem(Number(row.dataset.select), false); startStore(); }
  if (event.key === "Escape" && app.querySelector(".modal-backdrop")) closeModal();
});
app.addEventListener("submit", (event) => {
  if (event.target.id !== "add-form") return;
  event.preventDefault(); const field = event.target.elements.items; const value = field.value.trim(); if (!value) { field.focus(); return; }
  const oldLength = items.length; parseAndAdd(value); selected = oldLength === 0 ? 0 : selected; render(); announce("Items added to your list.");
});
app.addEventListener("input", (event) => {
  if (event.target.id !== "store-search") return;
  const query = event.target.value.trim().toLowerCase();
  app.querySelectorAll(".product-tile").forEach((tile) => { tile.hidden = Boolean(query) && !tile.dataset.productName.includes(query); });
});
app.addEventListener("click", (event) => {
  if (event.target.classList.contains("modal-backdrop")) closeModal();
});
render();
