import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

// Exercise the exact bundled script without accessing or changing a real cart.
const swift = readFileSync(new URL('../ListRunner/StoreShoppingView.swift', import.meta.url), 'utf8');
const source = swift.match(/private static let automationScript = #"""\n([\s\S]*?)\n    """#/)[1];
const coles = JSON.parse(readFileSync(new URL('../ListRunner/Resources/coles.json', import.meta.url), 'utf8'));
const woolworths = JSON.parse(readFileSync(new URL('../ListRunner/Resources/woolworths.json', import.meta.url), 'utf8'));
const bunnings = JSON.parse(readFileSync(new URL('../ListRunner/Resources/bunnings.json', import.meta.url), 'utf8'));

function bunningsFixture({ before = 0, sticky = false } = {}) {
  const messages = [];
  const scheduled = [];
  let click;
  let quantity = before;
  class FakeElement {
    constructor(tagName, attributes = {}, textContent = '') {
      this.tagName = tagName.toUpperCase(); this.attributes = attributes; this.textContent = textContent;
      this.children = []; this.parentElement = null; this.isConnected = true; this.value = '';
    }
    append(child) { child.parentElement = this; this.children.push(child); return child; }
    closest(selector) {
      for (let current = this; current; current = current.parentElement) if (current.matches(selector)) return current;
      return null;
    }
    matches(selector) {
      return selector.split(',').some(raw => {
        const value = raw.trim();
        return value === 'button' && this.tagName === 'BUTTON' ||
          value === 'h1' && this.tagName === 'H1' ||
          value === '#pdp-footer-container' && this.attributes.id === 'pdp-footer-container' ||
          value === 'input[aria-label="Quantity"]' && this.tagName === 'INPUT' && this.attributes['aria-label'] === 'Quantity' ||
          value === 'input[name="quantity"]' && this.tagName === 'INPUT' && this.attributes.name === 'quantity';
      });
    }
    getAttribute(name) { return this.attributes[name] ?? null; }
    getRootNode() { return document; }
    querySelectorAll(selector) {
      const found = [];
      const visit = parent => { for (const child of parent.children) { if (child.matches(selector)) found.push(child); visit(child); } };
      visit(this); return found;
    }
  }
  const document = {
    body: null, documentElement: null, visibilityState: 'visible',
    addEventListener(type, callback) { if (type === 'click') click = callback; },
    querySelectorAll(selector) { return this.documentElement.querySelectorAll(selector); },
  };
  document.documentElement = new FakeElement('html');
  document.body = document.documentElement.append(new FakeElement('body'));
  const main = document.body.append(new FakeElement('main'));
  const product = main.append(new FakeElement('section'));
  product.append(new FakeElement('h1', {}, 'Esky 26L Chilla Hard Cooler'));
  const stickyControls = document.body.append(new FakeElement('div', { id: 'pdp-footer-container' }));
  const tile = sticky ? stickyControls : product;
  const control = tile.append(new FakeElement('button', {}, before ? 'Increase quantity' : 'Add to Cart'));
  const addInput = () => {
    const input = tile.children.find(child => child.tagName === 'INPUT') || tile.append(new FakeElement('input', { 'aria-label': 'Quantity' }));
    input.value = String(quantity);
  };
  if (before > 0) addInput();
  const context = vm.createContext({
    URL, Element: FakeElement, Date: { now: () => 0 },
    location: { protocol: 'https:', hostname: 'www.bunnings.com.au', pathname: '/esky-26l-chilla-hard-cooler_p0138506', href: 'https://www.bunnings.com.au/esky-26l-chilla-hard-cooler_p0138506' },
    window: { __listRunnerStoreConfig: bunnings, webkit: { messageHandlers: { listRunner: { postMessage: raw => { if (raw !== 'automationReady') messages.push(JSON.parse(raw)); } } } } },
    document,
    setTimeout: (callback, delay) => scheduled.push(() => { callback(); }),
    MutationObserver: class { observe() {} },
  });
  vm.runInContext(source, context);
  context.window.__listRunnerSetContext({ sessionID: 'session', interactionID: 'interaction', itemID: 'item', documentGeneration: 1 });
  return {
    messages,
    click() {
      click?.({ isTrusted: true, target: control });
      quantity++;
      if (control.parentElement) control.parentElement.children = control.parentElement.children.filter(child => child !== control);
      control.parentElement = null;
      tile.append(new FakeElement('button', { 'aria-label': 'Increase quantity' }, 'Increase quantity'));
      addInput();
    },
    tick(count = 1) { for (let i = 0; i < count; i++) scheduled.shift()?.(); },
  };
}

test('Bunnings product detail confirms its URL-identified quantity increase without enabling cart Undo', () => {
  assert.equal(bunnings.capabilities.cartDetection, true);
  assert.equal(bunnings.capabilities.cartUndo, false);
  const page = bunningsFixture();
  page.click();
  assert.equal(page.messages[0].type, 'cartInteractionStarted');
  assert.equal(page.messages[0].productID, '0138506');
  assert.equal(page.messages[0].beforeQuantity, 0);
  page.tick(3);
  assert.equal(page.messages.at(-1).type, 'addDetected');
  assert.equal(page.messages.at(-1).resultingQuantity, 1);
});

test('Bunnings sticky product-page Add to Cart control uses the same scoped quantity signal', () => {
  const page = bunningsFixture({ sticky: true });
  page.click();
  assert.equal(page.messages[0].productID, '0138506');
  assert.equal(page.messages[0].beforeQuantity, 0);
  page.tick(3);
  assert.equal(page.messages.at(-1).type, 'addDetected');
  assert.equal(page.messages.at(-1).resultingQuantity, 1);
});

function fixture({ host = 'www.coles.com.au', config = coles, empty = true, testID = true, deliverContext = true, decrement = true, disabled = false, applyDecrement = true } = {}) {
  const messages = [];
  const installationMessages = [];
  const scheduled = [];
  let click;
  let value = null;
  let currentTile;
  let decrementClicks = 0;
  let now = 0;
  class Element {
    closest(selector) { return selector === '[data-testid="product-tile"]' ? currentTile : this; }
    matches(selector) { return selector.includes(',') || testID; }
    getAttribute(name) {
      return name === 'aria-label' ? 'Add to trolley: Coles Full Cream Milk' : null;
    }
  }
  const control = new Element();
  const decreaseControl = {
    disabled,
    getAttribute(name) { return name === 'aria-label' ? 'Decrease Coles Full Cream Milk quantity by one' : null; },
    click() {
      decrementClicks++;
      // Programmatic controls remain untrusted and must not create new add events.
      click?.({ isTrusted: false, target: control });
      if (applyDecrement) value--;
    },
  };
  const link = { href: 'https://www.coles.com.au/product/coles-full-cream-milk-8150285' };
  const makeTile = (id = '8150285') => ({
    productID: id,
    isConnected: true,
    querySelectorAll(selector) {
      if (selector === 'a[href]') return [{ href: link.href.replace('8150285', this.productID) }];
      if (selector === 'button') return decrement ? [decreaseControl] : [];
      if (selector === '[role="status"]') return empty ? [{ textContent: 'Product is not in your trolley' }] : [];
      if (selector.includes('quantity-input')) return value === null ? [] : [{ value: String(value) }];
      return [];
    },
  });
  currentTile = makeTile();
  const context = vm.createContext({
    URL, Element, Date: { now: () => now },
    location: { protocol: 'https:', hostname: host, href: `https://${host}/search/products?q=milk` },
    window: { __listRunnerStoreConfig: config, webkit: { messageHandlers: { listRunner: { postMessage: raw => {
      if (raw === 'automationReady') installationMessages.push(raw);
      else messages.push(JSON.parse(raw));
    } } } } },
    document: {
      documentElement: {},
      addEventListener(type, callback) { if (type === 'click') click = callback; },
      querySelectorAll() { return [{ ...link, closest: () => currentTile }]; },
    },
    setTimeout: (callback, delay) => scheduled.push(() => { now += delay; callback(); }),
    MutationObserver: class { observe() {} },
  });
  vm.runInContext(source, context);
  const setContext = () => context.window.__listRunnerSetContext?.({ sessionID: 'session', interactionID: 'interaction', itemID: 'item', documentGeneration: 1 });
  if (deliverContext) setContext();
  return {
    messages,
    installationMessages,
    setContext,
    setReorderedContext() { context.window.__listRunnerSetContext?.({ documentGeneration: 1, itemID: 'item', interactionID: 'interaction', sessionID: 'session' }); },
    hideDocument() { context.document.visibilityState = 'hidden'; },
    click(trusted = true) { click?.({ isTrusted: trusted, target: control }); },
    setQuantity(next) { value = next; },
    replaceTile(id) { currentTile.isConnected = false; currentTile = makeTile(id); },
    reuseTileForProduct(id) { currentTile.productID = id; },
    advanceTime(ms) { now += ms; },
    resetContext() { context.window.__listRunnerSetContext?.(null); },
    get decrementClicks() { return decrementClicks; },
    get quantity() { return value; },
    undo(record) { return context.window.__listRunnerUndoAdd(record); },
    cancelUndo() { context.window.__listRunnerCancelUndo(); },
    tick(count = 1) { for (let i = 0; i < count; i++) scheduled.shift()?.(); },
  };
}

function woolworthsFixture({ productIDAttributeOnly = false, noSemanticTile = false, emptyTextMismatch = false, addClassMismatch = false, alternateQuantityMarkup = false } = {}) {
  const messages = [];
  const installationMessages = [];
  const scheduled = [];
  let click;
  let now = 0;
  let quantity = 0;

  class FakeRoot {
    constructor(host = null) { this.host = host; this.children = []; }
    append(child) { child.parentElement = null; child.treeRoot = this; this.children.push(child); return child; }
    querySelectorAll(selector) {
      const found = [];
      const visit = parent => {
        for (const child of parent.children || []) {
          if (selector === '*' || child.matches(selector)) found.push(child);
          visit(child);
        }
      };
      visit(this);
      return found;
    }
  }

  class FakeElement {
    constructor(tagName, attributes = {}, textContent = '') {
      this.tagName = tagName.toUpperCase();
      this.attributes = attributes;
      this.href = attributes.href;
      this.textContent = textContent;
      this.children = [];
      this.parentElement = null;
      this.treeRoot = null;
      this.shadowRoot = null;
      this.disabled = false;
      this.isConnected = true;
      this.value = attributes.value ?? '';
    }
    append(child) { child.parentElement = this; child.treeRoot = this.treeRoot; this.children.push(child); return child; }
    attachShadow() { this.shadowRoot = new FakeRoot(this); return this.shadowRoot; }
    matches(selector) {
      return selector.split(',').some(raw => {
        const value = raw.trim();
        if (value === '*') return true;
        if (value === 'wc-product-tile' || value === 'wc-add-to-cart') return this.tagName.toLowerCase() === value;
        if (value === 'button') return this.tagName === 'BUTTON';
        if (value === 'a[href]') return this.tagName === 'A' && this.attributes.href != null;
        if (value.startsWith('a[href*=')) return this.tagName === 'A' && this.attributes.href?.includes('/shop/productdetails/');
        if (value === 'button.add-to-cart-btn') return this.tagName === 'BUTTON' && this.attributes.class === 'add-to-cart-btn';
        if (value === 'input.quantity-input[aria-valuenow]') return this.tagName === 'INPUT' && this.attributes.class === 'quantity-input' && this.attributes['aria-valuenow'] != null;
        if (value === 'input[type="number"]') return this.tagName === 'INPUT' && this.attributes.type === 'number';
        if (value === '[role="spinbutton"]') return this.attributes.role === 'spinbutton';
        if (value === 'input[type="button"]' || value === 'input[type="submit"]') return this.tagName === 'INPUT' && this.attributes.type === value.match(/\[type="([^"]+)"\]/)?.[1];
        if (value === '[role="button"]') return this.attributes.role === 'button';
        return false;
      });
    }
    getAttribute(name) { return this.attributes[name] ?? null; }
    getRootNode() { return this.treeRoot; }
    querySelectorAll(selector) {
      const found = [];
      const visit = parent => {
        for (const child of parent.children || []) {
          if (child.matches(selector)) found.push(child);
          visit(child);
        }
      };
      visit(this);
      return found;
    }
  }

  const document = new FakeRoot();
  document.documentElement = {};
  document.visibilityState = 'visible';
  document.addEventListener = (type, callback) => { if (type === 'click') click = callback; };
  const tile = document.append(new FakeElement(noSemanticTile ? 'div' : 'wc-product-tile', productIDAttributeOnly ? { 'data-product-id': '83273' } : {}));
  tile.shadowRoot = new FakeRoot(tile);
  tile.shadowRoot.treeRoot = tile.shadowRoot;
  if (!productIDAttributeOnly) {
    tile.shadowRoot.append(new FakeElement('a', { href: '/shop/productdetails/83273/so-good-barista-oat-long-life-milk' }));
    if (noSemanticTile) tile.shadowRoot.append(new FakeElement('a', { href: '/shop/productdetails/83273/so-good-barista-oat-long-life-milk?source=image' }));
  }
  const cartHost = tile.shadowRoot.append(new FakeElement('wc-add-to-cart'));
  const cartRoot = cartHost.attachShadow();
  const rebuildCartControl = () => {
    cartRoot.children = [];
    if (quantity === 0) {
      cartRoot.append(new FakeElement('button', {
        class: addClassMismatch ? 'retailer-button' : 'add-to-cart-btn',
        'aria-label': 'Add So Good Barista Oat Long Life Milk 1L to cart',
      }, emptyTextMismatch ? 'Add' : 'Add to cart'));
    } else {
      cartRoot.append(new FakeElement('input', {
        ...(alternateQuantityMarkup
          ? { class: 'stepper-value', type: 'number', value: String(quantity) }
          : { class: 'quantity-input', 'aria-valuenow': String(quantity) }),
      }));
    }
  };
  rebuildCartControl();

  const context = vm.createContext({
    URL, Element: FakeElement, Date: { now: () => now },
    location: { protocol: 'https:', hostname: 'www.woolworths.com.au', href: 'https://www.woolworths.com.au/shop/search/products?searchTerm=milk' },
    window: { __listRunnerStoreConfig: woolworths, webkit: { messageHandlers: { listRunner: { postMessage: raw => {
      if (raw === 'automationReady') installationMessages.push(raw);
      else messages.push(JSON.parse(raw));
    } } } } },
    document,
    setTimeout: (callback, delay) => scheduled.push(() => { now += delay; callback(); }),
    MutationObserver: class { observe() {} },
  });
  vm.runInContext(source, context);
  context.window.__listRunnerSetContext?.({ sessionID: 'session', interactionID: 'interaction', itemID: 'item', documentGeneration: 1 });

  return {
    messages,
    installationMessages,
    click(trusted = true) {
      const button = cartRoot.children.find(child => child.tagName === 'BUTTON');
      click?.({ isTrusted: trusted, target: tile, composedPath: () => button ? [button, cartHost, tile] : [tile] });
    },
    setQuantity(next) { quantity = next; rebuildCartControl(); },
    advanceTime(ms) { now += ms; },
    tick(count = 1) { for (let i = 0; i < count; i++) scheduled.shift()?.(); },
    undo(record) { return context.window.__listRunnerUndoAdd(record); },
  };
}

test('actual Coles add label arms a window and confirms a stable quantity increase', () => {
  const page = fixture();
  page.click();
  assert.equal(page.messages[0].type, 'cartInteractionStarted');
  assert.equal(page.messages[0].beforeQuantity, 0);
  page.setQuantity(1);
  page.tick(2);
  assert.equal(page.messages.filter(m => m.type === 'addDetected').length, 0);
  page.tick();
  assert.equal(page.messages[1].type, 'addDetected');
  assert.equal(page.messages[1].resultingQuantity, 1);
  page.tick(5);
  assert.equal(page.messages.length, 2);
});

function confirmedAdd(page, before = 0, after = 1) {
  page.setQuantity(before);
  page.click();
  page.setQuantity(after);
  page.tick(3);
  const message = page.messages.at(-1);
  assert.equal(message.type, 'addDetected');
  return message;
}

async function settle(page, promise) {
  // Advance both timer callbacks and the Promise microtasks between observations.
  for (let i = 0; i < 40; i++) {
    page.tick();
    await Promise.resolve();
  }
  return await promise;
}

test('Undo reverses an initial add and does not emit a second add event', async () => {
  const page = fixture();
  const record = confirmedAdd(page);
  assert.equal(await settle(page, page.undo(record)), true);
  assert.equal(page.quantity, 0);
  assert.equal(page.decrementClicks, 1);
  assert.equal(page.messages.length, 2);
});

test('Undo preserves quantity already in the basket and reverses exactly the delta', async () => {
  const page = fixture();
  const record = confirmedAdd(page, 3, 5);
  assert.equal(await settle(page, page.undo(record)), true);
  assert.equal(page.quantity, 3);
  assert.equal(page.decrementClicks, 2);
});

test('Undo after a repeated add reverses only the latest add', async () => {
  const page = fixture();
  confirmedAdd(page);
  const latest = confirmedAdd(page, 1, 2);
  assert.equal(await settle(page, page.undo(latest)), true);
  assert.equal(page.quantity, 1);
  assert.equal(page.decrementClicks, 1);
});

test('changed basket quantity prevents all store clicks', async () => {
  const page = fixture();
  const record = confirmedAdd(page);
  page.setQuantity(2);
  assert.equal(await page.undo(record), false);
  assert.equal(page.quantity, 2);
  assert.equal(page.decrementClicks, 0);
});

test('an unconfirmed or forged add never authorizes store reversal', async () => {
  const page = fixture();
  assert.equal(await page.undo({ confirmationID: '1' }), false);
  const record = confirmedAdd(page);
  assert.equal(await page.undo({ ...record, beforeQuantity: -1 }), false);
  assert.equal(await page.undo({ ...record, productID: '999' }), false);
  assert.equal(await page.undo({ ...record, interactionID: 'old' }), false);
  assert.equal(page.decrementClicks, 0);
});

test('one confirmation can authorize only one Undo', async () => {
  const page = fixture();
  const record = confirmedAdd(page);
  assert.equal(await settle(page, page.undo(record)), true);
  page.setQuantity(1);
  assert.equal(await page.undo(record), false);
  assert.equal(page.decrementClicks, 1);
});

test('missing or disabled decrease controls fail without touching the cart', async () => {
  for (const options of [{ decrement: false }, { disabled: true }]) {
    const page = fixture(options);
    const record = confirmedAdd(page);
    assert.equal(await page.undo(record), false);
    assert.equal(page.decrementClicks, 0);
  }
});

test('an unconfirmed decrease times out without repeatedly clicking', async () => {
  const page = fixture({ applyDecrement: false });
  const record = confirmedAdd(page);
  assert.equal(await settle(page, page.undo(record)), false);
  assert.equal(page.decrementClicks, 1);
  assert.equal(page.quantity, 1);
});

test('new interaction or cancellation prevents further decrements', async () => {
  for (const cancel of [page => page.resetContext(), page => page.cancelUndo(), page => page.click()]) {
    const page = fixture();
    const record = confirmedAdd(page, 0, 3);
    const undo = page.undo(record);
    assert.equal(page.decrementClicks, 1);
    cancel(page);
    assert.equal(await settle(page, undo), false);
    assert.equal(page.decrementClicks, 1);
  }
});

test('rerendering to a different product cannot receive a decrement', async () => {
  const page = fixture();
  const record = confirmedAdd(page);
  page.replaceTile('999');
  assert.equal(await page.undo(record), false);
  assert.equal(page.decrementClicks, 0);
});

test('original final-item Undo refuses reversal after a later quantity increase', async () => {
  const page = fixture();
  const original = confirmedAdd(page);
  confirmedAdd(page, 1, 2);
  assert.equal(await page.undo(original), false);
  assert.equal(page.decrementClicks, 0);
});

test('invalidating context before Undo prevents all cart mutations', async () => {
  const page = fixture();
  const record = confirmedAdd(page);
  page.resetContext();
  assert.equal(await page.undo(record), false);
  assert.equal(page.decrementClicks, 0);
});

test('context JSON key ordering does not invalidate confirmation provenance', async () => {
  const page = fixture();
  const record = confirmedAdd(page);
  page.setReorderedContext();
  assert.equal(await settle(page, page.undo(record)), true);
});

test('an unexpected quantity change during reversal stops remaining clicks', async () => {
  const page = fixture();
  const record = confirmedAdd(page, 1, 3);
  const undo = page.undo(record);
  page.setQuantity(5);
  assert.equal(await settle(page, undo), false);
  assert.equal(page.decrementClicks, 1);
  assert.equal(page.quantity, 5);
});

test('backgrounding the page prevents all cart mutations', async () => {
  const page = fixture();
  const record = confirmedAdd(page);
  page.hideDocument();
  assert.equal(await page.undo(record), false);
  assert.equal(page.decrementClicks, 0);
});

test('Woolworths confirms trusted product-specific adds across nested shadow roots, but never enables cart Undo', async () => {
  assert.equal(woolworths.capabilities.cartDetection, true);
  assert.equal(woolworths.capabilities.cartUndo, false);
  const page = woolworthsFixture();
  page.click();
  assert.equal(page.messages[0].type, 'cartInteractionStarted');
  assert.equal(page.messages[0].productID, '83273');
  assert.equal(page.messages[0].beforeQuantity, 0);
  page.setQuantity(1);
  page.tick(3);
  const detected = page.messages.find(message => message.type === 'addDetected');
  assert.equal(detected.productID, '83273');
  assert.equal(detected.beforeQuantity, 0);
  assert.equal(detected.resultingQuantity, 1);
  assert.equal(await page.undo(detected), false);
  assert.equal(page.messages.filter(message => message.type === 'addDetected').length, 1);
});

test('Woolworths accepts its explicit numeric product-ID attribute before its product link hydrates', () => {
  const page = woolworthsFixture({ productIDAttributeOnly: true });
  page.click();
  assert.equal(page.messages[0].type, 'cartInteractionStarted');
  assert.equal(page.messages[0].productID, '83273');
  page.setQuantity(1);
  page.tick(3);
  assert.equal(page.messages.find(message => message.type === 'addDetected')?.productID, '83273');
});

test('Woolworths finds the nearest ordinary container with one unique product ID', () => {
  const page = woolworthsFixture({ noSemanticTile: true });
  page.click();
  assert.equal(page.messages[0].type, 'cartInteractionStarted');
  assert.equal(page.messages[0].productID, '83273');
  page.setQuantity(1);
  page.tick(3);
  assert.equal(page.messages.find(message => message.type === 'addDetected')?.productID, '83273');
});

test('Woolworths dedicated trusted Add button establishes zero baseline when visible text differs', () => {
  const page = woolworthsFixture({ emptyTextMismatch: true, addClassMismatch: true });
  page.click();
  assert.equal(page.messages[0].type, 'cartInteractionStarted');
  assert.equal(page.messages[0].beforeQuantity, 0);
  page.setQuantity(1);
  page.tick(3);
  assert.equal(page.messages.find(message => message.type === 'addDetected')?.resultingQuantity, 1);
});

test('Woolworths reads a product-scoped numeric stepper when mobile omits the desktop quantity class and ARIA value', () => {
  const page = woolworthsFixture({ alternateQuantityMarkup: true });
  page.click();
  assert.equal(page.messages[0].type, 'cartInteractionStarted');
  assert.equal(page.messages[0].beforeQuantity, 0);
  page.setQuantity(1);
  page.tick(3);
  assert.equal(page.messages.find(message => message.type === 'addDetected')?.resultingQuantity, 1);
});

test('Woolworths rejects untrusted events and does not claim undo support', () => {
  const page = woolworthsFixture();
  page.click(false);
  page.setQuantity(1);
  page.tick(5);
  assert.equal(page.messages.length, 0);
  assert.equal(woolworths.capabilities.cartUndo, false);
});

test('Woolworths cart confirmation remains active for slower web-component updates', () => {
  const page = woolworthsFixture();
  page.click();
  page.advanceTime(5000);
  page.setQuantity(1);
  page.tick(3);
  assert.equal(page.messages.find(message => message.type === 'addDetected')?.resultingQuantity, 1);
});

test('Coles configuration cannot install on Woolworths or an unlisted subdomain', () => {
  for (const host of ['www.woolworths.com.au', 'evil.coles.com.au', 'coles.com.au.evil.test']) {
    const page = fixture({ host });
    page.click();
    assert.equal(page.messages.length, 0);
    assert.equal(page.installationMessages.length, 0);
  }
});

test('cart Undo rejects a record originating from a different store', async () => {
  const page = fixture();
  const record = confirmedAdd(page);
  assert.equal(await page.undo({ ...record, storeID: 'woolworths' }), false);
  assert.equal(page.decrementClicks, 0);
});

test('quantity stabilization requires consecutive matching observations', () => {
  const page = fixture();
  page.click();
  page.setQuantity(1);
  page.tick(2);
  page.setQuantity(0);
  page.tick();
  page.setQuantity(1);
  page.tick();
  assert.equal(page.messages.length, 1);
  page.tick();
  assert.equal(page.messages[1].type, 'addDetected');
});

test('a callback delayed past its confirmation deadline cannot confirm', () => {
  const page = fixture();
  page.click();
  page.tick();
  page.setQuantity(1);
  page.advanceTime(3_001);
  page.tick(4);
  assert.equal(page.messages.length, 1);
});

test('a still-connected tile reused for a different product cannot confirm', () => {
  const page = fixture();
  page.click();
  page.reuseTileForProduct('999');
  page.setQuantity(1);
  page.tick(4);
  assert.equal(page.messages.length, 1);
});

test('product-specific accessible label works independently of test ID', () => {
  const page = fixture({ testID: false });
  page.click();
  assert.equal(page.messages[0].type, 'cartInteractionStarted');
});

test('synthetic clicks and passive quantity updates never arm or confirm', () => {
  const page = fixture();
  page.click(false);
  page.setQuantity(1);
  page.tick(5);
  assert.equal(page.messages.length, 0);
});

test('missing quantity is not assumed zero without the explicit not-in-trolley state', () => {
  const page = fixture({ empty: false });
  page.click();
  assert.equal(page.messages[0].type, 'automationUnavailable');
  assert.equal(page.messages[0].reason, 'quantityUnavailable');
});

test('existing quantity must increase, and one observation is not confirmation', () => {
  const page = fixture({ empty: false });
  page.setQuantity(2);
  page.click();
  page.tick(3);
  assert.equal(page.messages.length, 1);
  page.setQuantity(3);
  page.tick();
  assert.equal(page.messages.length, 1);
  page.tick();
  assert.equal(page.messages[1].resultingQuantity, 3);
});

test('a rerendered tile is reidentified using its own product link', () => {
  const page = fixture();
  page.click();
  page.replaceTile('8150285');
  page.setQuantity(1);
  page.tick(3);
  assert.equal(page.messages[1].type, 'addDetected');
});

test('a different product cannot confirm an earlier candidate', () => {
  const page = fixture();
  page.click();
  page.replaceTile('999999');
  page.setQuantity(1);
  page.tick(4);
  assert.equal(page.messages.length, 1);
});

test('changing interaction invalidates delayed observations', () => {
  const page = fixture();
  page.click();
  page.resetContext();
  page.setQuantity(1);
  page.tick(4);
  assert.equal(page.messages.length, 1);
});

test('automation does not install on an unrelated HTTPS host', () => {
  const page = fixture({ host: 'example.com' });
  page.click();
  assert.equal(page.messages.length, 0);
  assert.equal(page.installationMessages.length, 0);
});

test('installation requests native context without waiting for page-load completion', () => {
  const page = fixture({ deliverContext: false });
  assert.deepEqual(page.installationMessages, ['automationReady']);
  page.click();
  assert.equal(page.messages.length, 0);
  // Native answers the handshake before WebKit's later didFinish callback.
  page.setContext();
  page.click();
  page.setQuantity(1);
  page.tick(3);
  assert.equal(page.messages[1].type, 'addDetected');
});

test('a repeated context from didFinish preserves the active cart confirmation', () => {
  const page = fixture();
  page.click();
  page.setQuantity(1);
  page.tick(2);
  page.setContext();
  page.tick();
  assert.equal(page.messages[1].type, 'addDetected');
});
