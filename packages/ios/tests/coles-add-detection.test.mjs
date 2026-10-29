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
const kmart = JSON.parse(readFileSync(new URL('../ListRunner/Resources/kmart.json', import.meta.url), 'utf8'));

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

function bunningsGridFixture({ before = 0, duplicateLinks = false, ambiguous = false,
  href, detailPage = false, config = bunnings } = {}) {
  const messages = [], scheduled = [];
  let click, mutation, now = 0;
  class FakeElement {
    constructor(tagName, attributes = {}, textContent = '') {
      this.tagName = tagName.toUpperCase(); this.attributes = attributes; this.textContent = textContent;
      this.children = []; this.parentElement = null; this.isConnected = true; this.value = '';
    }
    get href() { return this.attributes.href; }
    append(child) { child.parentElement = this; this.children.push(child); return child; }
    getAttribute(name) { return this.attributes[name] ?? null; }
    getRootNode() { return document; }
    matches(selector) {
      return selector.split(',').some(raw => {
        const s = raw.trim();
        return s === '*' || s === 'button' && this.tagName === 'BUTTON' ||
          s === 'h1' && this.tagName === 'H1' ||
          s === 'a[href]' && this.tagName === 'A' && !!this.attributes.href ||
          s === "a[href*='/product/']" && this.tagName === 'A' && this.attributes.href?.includes('/product/') ||
          s === '#pdp-footer-container' && this.attributes.id === 'pdp-footer-container' ||
          s === 'input[aria-label="Quantity"]' && this.tagName === 'INPUT' && this.attributes['aria-label'] === 'Quantity' ||
          s === 'input[name="quantity"]' && this.tagName === 'INPUT' && this.attributes.name === 'quantity' ||
          s === 'input[type="number"]' && this.tagName === 'INPUT' && this.attributes.type === 'number' ||
          s === '[role="spinbutton"]' && this.attributes.role === 'spinbutton' ||
          s === '[role="status"]' && this.attributes.role === 'status';
      });
    }
    querySelectorAll(selector) {
      const result = [];
      const visit = parent => { for (const child of parent.children) { if (child.matches(selector)) result.push(child); visit(child); } };
      visit(this); return result;
    }
  }
  const document = {
    visibilityState: 'visible',
    addEventListener(type, callback) { if (type === 'click') click = callback; },
    querySelectorAll(selector) { return this.documentElement.querySelectorAll(selector); },
  };
  document.documentElement = new FakeElement('html');
  document.body = document.documentElement.append(new FakeElement('body'));
  const badge = document.body.append(new FakeElement('input', { 'aria-label': 'Quantity' }));
  badge.value = '0';
  const main = document.body.append(new FakeElement('main'));
  main.append(new FakeElement('h1', {}, detailPage ? 'Different detail-page product' : 'Staples'));
  const selectedHref = href === undefined ? (config.id === 'kmart'
    ? 'https://www.kmart.com.au/product/foldaway-pvc-chair-42250333/'
    : 'https://www.bunnings.com.au/trojan-staples_p0217507') : href;
  const otherHref = config.id === 'kmart'
    ? 'https://www.kmart.com.au/product/basic-camp-chair-42200101/'
    : 'https://www.bunnings.com.au/staple-gun_p0217503';
  const makeCard = (url, quantity) => {
    const tile = new FakeElement('div');
    const link = tile.append(new FakeElement('a', { href: url }, 'Trojan staples'));
    if (duplicateLinks) tile.append(new FakeElement('a', { href: url }, 'Same product image'));
    if (ambiguous) tile.append(new FakeElement('a', { href: 'https://www.bunnings.com.au/other_p9999999' }, 'Another product'));
    const controls = tile.append(new FakeElement('div'));
    const control = controls.append(new FakeElement('button', { 'aria-label': quantity ? 'Increase quantity' : config.id === 'kmart' ? 'Add' : 'Add to Cart' }, quantity ? '' : 'Add'));
    const inner = control.append(new FakeElement('span', {}, 'Add'));
    const card = { tile, link, controls, control, inner };
    if (quantity) setCardQuantity(card, quantity);
    return card;
  };
  function setCardQuantity(card, quantity) {
    const input = card.controls.children.find(child => child.tagName === 'INPUT') ||
      card.controls.append(new FakeElement('input', { 'aria-label': 'Quantity', type: 'number' }));
    input.value = String(quantity);
    card.control.attributes['aria-label'] = 'Increase quantity';
    card.control.textContent = '';
    const decrement = card.controls.children.find(child => child.attributes['aria-label'] === 'Decrease quantity') ||
      card.controls.append(new FakeElement('button', { 'aria-label': 'Decrease quantity' }));
    decrement.click = () => { input.value = String(Number(input.value) - 1); mutation?.(); };
  }
  let selected = makeCard(selectedHref, before);
  main.append(selected.tile);
  const other = makeCard(otherHref, 0);
  main.append(other.tile);
  const pathname = detailPage ? '/different-product_p0123456' : config.id === 'kmart' ? '/search/?searchTerm=chair' : '/search/products';
  const host = config.allowedHosts[0];
  const context = vm.createContext({
    URL, Element: FakeElement, Date: { now: () => now }, document,
    location: { protocol: 'https:', hostname: host, pathname, href: 'https://' + host + pathname },
    window: { __listRunnerStoreConfig: config, webkit: { messageHandlers: { listRunner: {
      postMessage: raw => { if (raw !== 'automationReady') messages.push(JSON.parse(raw)); },
    } } } },
    setTimeout(callback, delay) { scheduled.push(() => { now += delay; callback(); }); },
    MutationObserver: class { constructor(callback) { mutation = callback; } observe() {} },
  });
  vm.runInContext(source, context);
  context.window.__listRunnerSetContext({ sessionID: 'session', interactionID: 'interaction', itemID: 'item', documentGeneration: 1 });
  return {
    messages,
    click(trusted = true) { click({ isTrusted: trusted, target: selected.inner, composedPath: () => [selected.inner, selected.control, selected.controls, selected.tile] }); },
    setQuantity(value) { setCardQuantity(selected, value); mutation(); },
    setOtherQuantity(value) { setCardQuantity(other, value); badge.value = String(value); mutation(); },
    reuseForDifferentProduct() { selected.link.attributes.href = 'https://www.bunnings.com.au/reused_p1234567'; setCardQuantity(selected, 1); mutation(); },
    replaceCard(sameProduct = true) {
      selected.tile.isConnected = false;
      main.children = main.children.filter(child => child !== selected.tile);
      selected = makeCard(sameProduct ? selectedHref : config.id === 'kmart'
         ? 'https://www.kmart.com.au/product/replacement-chair-42299999/'
         : 'https://www.bunnings.com.au/replacement_p1234567', 1);
      main.append(selected.tile); mutation();
    },
    clearContext() { context.window.__listRunnerSetContext(null); },
    undo(record) { return context.window.__listRunnerUndoAdd(record); },
    advanceTime(value) { now += value; },
    tick(count = 1) { for (let i = 0; i < count; i++) scheduled.shift()?.(); },
  };
}

test('Bunnings search grid identifies the tapped card and confirms only its quantity', () => {
  const page = bunningsGridFixture();
  page.click();
  assert.equal(page.messages[0].type, 'cartInteractionStarted');
  assert.equal(page.messages[0].productID, '0217507');
  assert.equal(page.messages[0].beforeQuantity, 0);
  page.setQuantity(1); page.tick(5);
  assert.equal(page.messages.at(-1).type, 'addDetected');
  assert.equal(page.messages.at(-1).resultingQuantity, 1);
});

test('Kmart search grid confirms a real Add only in its URL-identified product card and reverses only that add', async () => {
  assert.equal(kmart.capabilities.search, true);
  assert.equal(kmart.capabilities.cartDetection, true);
  assert.equal(kmart.capabilities.cartUndo, true);
  const page = bunningsGridFixture({ config: kmart });
  page.click();
  assert.equal(page.messages[0].type, 'cartInteractionStarted');
  assert.equal(page.messages[0].productID, '42250333');
  page.setQuantity(1); page.tick(5);
  assert.equal(page.messages.at(-1).type, 'addDetected');
  assert.equal(page.messages.at(-1).resultingQuantity, 1);
  const undo = page.undo({
    ...page.messages.at(-1), storeID: 'kmart', sessionID: 'session', interactionID: 'interaction',
    itemID: 'item', documentGeneration: 1,
  });
  for (let index = 0; index < 3; index++) {
    await Promise.resolve();
    page.tick();
  }
  assert.equal(await undo, true);
});

test('Bunnings duplicate image/title links to one product are not ambiguous', () => {
  const page = bunningsGridFixture({ duplicateLinks: true });
  page.click(); page.setQuantity(1); page.tick(5);
  assert.equal(page.messages.at(-1).type, 'addDetected');
  assert.equal(page.messages.at(-1).productID, '0217507');
});

test('Bunnings grid increment retains the existing product-specific quantity baseline', () => {
  const page = bunningsGridFixture({ before: 2 });
  page.click();
  assert.equal(page.messages[0].beforeQuantity, 2);
  page.setQuantity(3); page.tick(5);
  assert.equal(page.messages.at(-1).resultingQuantity, 3);
});

test('Bunnings another card or page-wide cart badge cannot confirm the tapped product', () => {
  const page = bunningsGridFixture();
  page.click(); page.setOtherQuantity(3); page.tick(10);
  assert.equal(page.messages.filter(message => message.type === 'addDetected').length, 0);
});

test('Bunnings missing, foreign, insecure and deceptive product links cannot arm grid detection', () => {
  for (const href of ['', 'https://other.example/staples_p0217507',
    'http://www.bunnings.com.au/staples_p0217507', 'https://user:secret@www.bunnings.com.au/staples_p0217507',
    'https://www.bunnings.com.au:444/staples_p0217507', 'https://www.bunnings.com.au.attacker.example/staples_p0217507']) {
    const page = bunningsGridFixture({ href });
    page.click(); page.setQuantity(1); page.tick(5);
    assert.equal(page.messages[0].type, 'automationUnavailable', href);
    assert.equal(page.messages[0].reason, 'productIdUnavailable', href);
    assert.equal(page.messages.some(message => message.type === 'addDetected'), false, href);
  }
});

test('Bunnings cards containing two product identities fail closed', () => {
  const page = bunningsGridFixture({ ambiguous: true });
  page.click(); page.setQuantity(1); page.tick(5);
  assert.equal(page.messages[0].reason, 'productIdUnavailable');
  assert.equal(page.messages.some(message => message.type === 'cartInteractionStarted'), false);
});

test('Bunnings grid synthetic clicks and passive changes never confirm an add', () => {
  const page = bunningsGridFixture();
  page.click(false); page.setQuantity(1); page.tick(5);
  assert.equal(page.messages.length, 0);
});

test('Bunnings same-product card replacement retains product-specific confirmation', () => {
  const page = bunningsGridFixture();
  page.click(); page.replaceCard(); page.tick(5);
  assert.equal(page.messages.at(-1).type, 'addDetected');
  assert.equal(page.messages.at(-1).productID, '0217507');
});

test('Bunnings replaced or recycled cards for a different product never confirm the old product', () => {
  for (const replace of [true, false]) {
    const page = bunningsGridFixture();
    page.click();
    if (replace) page.replaceCard(false); else page.reuseForDifferentProduct();
    page.tick(7);
    assert.equal(page.messages.some(message => message.type === 'addDetected'), false);
  }
});

test('Bunnings unchanged quantities, expired windows and ended interactions cannot confirm', () => {
  const unchanged = bunningsGridFixture({ before: 1 });
  unchanged.click(); unchanged.setQuantity(1); unchanged.tick(7);
  assert.equal(unchanged.messages.some(message => message.type === 'addDetected'), false);
  const expired = bunningsGridFixture();
  expired.click(); expired.advanceTime(4000); expired.setQuantity(1); expired.tick(5);
  assert.equal(expired.messages.some(message => message.type === 'addDetected'), false);
  const ended = bunningsGridFixture();
  ended.click(); ended.clearContext(); ended.setQuantity(1); ended.tick(5);
  assert.equal(ended.messages.some(message => message.type === 'addDetected'), false);
});

test('Bunnings recommendation cards use their own ID instead of the detail-page URL', () => {
  const page = bunningsGridFixture({ detailPage: true });
  page.click(); page.setQuantity(1); page.tick(5);
  assert.equal(page.messages[0].productID, '0217507');
  assert.equal(page.messages.at(-1).type, 'addDetected');
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
