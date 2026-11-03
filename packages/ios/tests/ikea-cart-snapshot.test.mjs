import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../ListRunner/Resources/CartSnapshotAutomation.js', import.meta.url), 'utf8');
const bundled = JSON.parse(readFileSync(new URL('../ListRunner/Resources/ikeaAU.json', import.meta.url)));

// Deterministic semantic DOM. Every cart document is a new server snapshot,
// independent of the purchase draft and family-only success toast.
function fixture({ before = 0, detail = false, amount = 1, fault = '', production = false } = {}) {
  const config = structuredClone(bundled);
  if (!production) config.capabilities = { search: true, cartDetection: true, cartUndo: true };
  const id = '40515525', otherID = '80515528';
  const server = new Map([[otherID, 2]]);
  if (before) server.set(id, before);
  const listeners = {}, timers = [], messages = [], changes = [];
  let now = 0, loads = 0, frame, activeDocument;
  const location = new URL(`https://www.ikea.com/au/en/${detail ? 'p/dragon-spoon-40515525/' : 'search/?q=spoon'}`);
  class Element {
    constructor(attrs = {}, text = '') { this.attrs = attrs; this.textContent = text; this.isConnected = true; this.disabled = false; this.map = {}; this.tagName = 'DIV'; }
    getAttribute(name) { return this.attrs[name] ?? null; }
    setAttribute(name, value) { this.attrs[name] = value; }
    getClientRects() { return this.hidden ? [] : [{}]; }
    get ownerDocument() { return { defaultView: { getComputedStyle: () => ({ display: 'block', visibility: this.hidden ? 'hidden' : 'visible', opacity: '1' }) } }; }
    querySelectorAll(selector) { return this.map[selector] || []; }
    querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
    matches(selector) { return this.selectors?.includes(selector) || false; }
    closest(selector) { return selector === 'button' ? this : tile.selectors.includes(selector) ? tile : null; }
    remove() { this.isConnected = false; if (frame === this) frame = null; }
  }
  const link = article => Object.assign(new Element(), { href: `https://www.ikea.com/au/en/p/-${article}` });
  const control = new Element({ 'aria-label': detail ? 'Add to bag' : 'Add "DRAGON Spoon" to cart' });
  const profile = config.cart.profiles[detail ? 1 : 0];
  control.selectors = [profile.addSelector];
  const tile = new Element({ 'data-product-number': fault === 'cardMismatch' ? otherID : id });
  tile.selectors = [profile.containerSelector];
  tile.map[config.cart.linkSelector] = detail ? [] : [link(fault === 'foreignLocale' ? otherID : id)];
  if (fault === 'foreignLocale') tile.map[config.cart.linkSelector][0].href = 'https://www.ikea.com/us/en/p/-40515525';
  tile.map.input = detail ? [Object.assign(new Element({ 'aria-label': 'Quantity input value' }), { value: String(amount) })] : [];
  const makeDocument = () => {
    const doc = new Element(); doc.readyState = 'complete';
    const main = new Element(); doc.map.main = [main];
    const rows = [], inputs = [], c = config.cart.snapshot;
    const render = () => {
      rows.length = 0; inputs.length = 0;
      for (const [article, quantity] of server) {
        const row = new Element();
        row.map[config.cart.linkSelector] = [link(article)];
        const reported = fault === 'articleMismatch' ? '99999999' : article;
        row.map[c.articleSelector] = [new Element({ 'aria-label': `Product article number ${reported.slice(0, 3)}.${reported.slice(3, 6)}.${reported.slice(6)}` })];
        const input = Object.assign(new Element({ value: String(quantity) }), { value: fault === 'invalidQuantity' ? 'NaN' : String(quantity) });
        row.map[c.quantitySelector] = [input]; inputs.push(input);
        const decrease = new Element();
        decrease.click = () => { changes.push(['decrease', article]); server.set(article, server.get(article) - 1); render(); };
        const remove = new Element();
        remove.click = () => { changes.push(['remove', article]); server.delete(article); render(); };
        if (fault === 'disabledDecrement') decrease.disabled = true;
        row.map[c.decrementSelector] = [decrease]; row.map[c.removeSelector] = [remove];
        rows.push(row);
      }
      doc.map[c.rowSelector] = fault === 'duplicateRow' && rows.length ? [...rows, rows[0]] : rows;
      main.map[c.quantitySelector] = inputs;
      doc.map[c.emptySelector] = server.size ? [] : [new Element({}, c.emptyText)];
      const total = [...server.values()].reduce((a, b) => a + b, 0);
      const badge = new Element({ 'aria-label': total ? `Shopping bag, ${total} items` : null }, 'Shopping bag');
      badge.href = 'https://www.ikea.com/au/en/shoppingcart/';
      doc.map['a[data-tracking-label="shopping-cart"]'] = [badge];
      if (fault === 'error') main.map['[aria-busy="true"], [role="alert"]'] = [new Element()];
    };
    render(); return doc;
  };
  const document = new Element(); document.visibilityState = 'visible';
  document.addEventListener = (type, callback) => { listeners[`document:${type}`] = callback; };
  document.createElement = () => {
    const element = new Element(); element.style = {};
    element.contentWindow = { location: new URL('https://www.ikea.com/au/en/shoppingcart/') };
    if (fault === 'frameRedirect') element.contentWindow.location = new URL('https://www.ikea.com/us/en/shoppingcart/');
    element.contentDocument = makeDocument(); loads++; return element;
  };
  document.body = { appendChild: element => { frame = element; activeDocument = element.contentDocument; } };
  const window = { __listRunnerStoreConfig: config, webkit: { messageHandlers: { listRunner: { postMessage: raw => messages.push(raw === 'automationReady' ? raw : JSON.parse(raw)) } } },
    addEventListener: (type, callback) => { listeners[type] = callback; } };
  const clickEvent = trusted => ({ target: control, isTrusted: trusted, preventDefault() {}, stopImmediatePropagation() {} });
  control.click = () => {
    listeners.click(clickEvent(false)); changes.push(['add', id]);
    if (fault !== 'noIncrease') server.set(id, (server.get(id) || 0) + amount);
    if (fault === 'unexpectedOther') server.set(otherID, 3);
  };
  vm.runInNewContext(source, { window, document, location, URL, Element, Date: { now: () => now },
    setTimeout: (callback, ms) => { timers.push({ callback, at: now + ms }); } });
  const context = { sessionID: 'session', interactionID: 'interaction', itemID: '7f715ac5-ce9d-46f5-9476-30f261dc1808', documentGeneration: 1 };
  window.__listRunnerSetContext?.(context);
  const flush = async () => {
    for (let i = 0; i < 1500; i++) {
      for (let j = 0; j < 8; j++) await Promise.resolve();
      if (!timers.length) return;
      timers.sort((a, b) => a.at - b.at); const timer = timers.shift(); now = timer.at; timer.callback();
    }
    throw new Error('Timer loop did not settle');
  };
  const detected = () => messages.find(m => m.type === 'addDetected');
  return { server, messages, changes, window, context, document, control, tile,
    click: (trusted = true) => listeners.click?.(clickEvent(trusted)), flush, detected,
    get loads() { return loads; }, get frameDocument() { return activeDocument; },
    undo: () => window.__listRunnerUndoAdd({ ...context, storeID: 'ikeaAU', ...detected() }) };
}

for (const detail of [false, true]) for (const before of [0, 2]) {
  test(`IKEA ${detail ? 'detail' : 'grid'} verifies ${before}→${before + 1} and reverses only its delta`, async () => {
    const f = fixture({ detail, before }); f.click(); await f.flush();
    assert.equal(f.detected()?.beforeQuantity, before); assert.equal(f.detected()?.resultingQuantity, before + 1);
    assert.equal(f.changes.filter(([type]) => type === 'add').length, 1);
    const promise = f.undo(); await f.flush(); assert.equal(await promise, true);
    assert.equal(f.server.get('40515525') || 0, before); assert.equal(f.server.get('80515528'), 2);
    assert.equal(f.changes.filter(([type]) => type === 'remove').length, before === 0 ? 1 : 0);
    assert.equal(await f.undo(), false);
  });
}
for (const fault of ['articleMismatch', 'invalidQuantity', 'duplicateRow', 'error', 'frameRedirect', 'cardMismatch', 'foreignLocale', 'noIncrease', 'unexpectedOther']) {
  test(`IKEA fails closed for ${fault}`, async () => {
    const f = fixture({ fault }); f.click(); await f.flush();
    assert.equal(f.detected(), undefined); assert.equal(await f.undo(), false);
    if (!['noIncrease', 'unexpectedOther'].includes(fault)) assert.deepEqual(f.changes, []);
  });
}
test('synthetic taps and intended draft changes do not arm snapshot verification', async () => {
  const f = fixture({ detail: true, amount: 4 }); f.click(false); await f.flush();
  assert.equal(f.loads, 0); assert.equal(f.detected(), undefined);
});
test('context changes cancel preflight without replaying Add', async () => {
  const f = fixture(); f.click(); f.window.__listRunnerSetContext({ ...f.context, interactionID: 'new' }); await f.flush();
  assert.deepEqual(f.changes, []); assert.equal(f.detected(), undefined);
});
test('Undo refuses changed target and unrelated product quantities', async () => {
  for (const id of ['40515525', '80515528']) {
    const f = fixture(); f.click(); await f.flush(); f.server.set(id, 8);
    const promise = f.undo(); await f.flush(); assert.equal(await promise, false);
    assert.equal(f.changes.length, 1);
  }
});
test('Undo refuses disabled decrement without removing pre-existing quantity', async () => {
  const f = fixture({ before: 2, fault: 'disabledDecrement' }); f.click(); await f.flush();
  const promise = f.undo(); await f.flush(); assert.equal(await promise, false); assert.equal(f.server.get('40515525'), 3);
});
test('backgrounding cancels pending preflight and all delayed mutations', async () => {
  const f = fixture(); f.click(); f.document.visibilityState = 'hidden'; await f.flush(); assert.deepEqual(f.changes, []);
});
