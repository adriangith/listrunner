import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const swift = readFileSync(new URL('../ListRunner/StoreShoppingView.swift', import.meta.url), 'utf8');
const source = swift.match(/private static let automationScript = #"""\n([\s\S]*?)\n    """#/)[1];
const load = id => JSON.parse(readFileSync(new URL(`../ListRunner/Resources/${id}.json`, import.meta.url), 'utf8'));

// Semantic markup observed live: real cart quantity inputs (not intended
// selectors), Priceline's linkless product-image-identified cart rows, and
// Supercheap's duplicate image/title links and React/jQuery control updates.
function fixture(store = 'priceline', { before = 0, captured = false } = {}) {
  const config = load(store);
  config.capabilities.cartDetection = true; // test only; production ceilings stay off until certified
  const name = store === 'priceline' ? 'PRO:VOKE Touch Of Silver Brightening Shampoo 50mL' : 'SCA Car Wash Concentrate 1 Litre';
  let id = store === 'priceline' ? '39390' : '733022';
  if (captured) {
    id = 'keji-ballpoint-pens-keka1271as';
    config.id = 'officeworks';
    config.allowedHosts = ['www.officeworks.com.au'];
    config.cart.identityStrategy = 'capturedURLComponent';
    config.cart.productURLPattern = '^/shop/officeworks/p/([A-Za-z0-9_-]{1,256})$';
    config.cart.linkSelector = 'a[href]';
  }
  const host = config.allowedHosts[0];
  const path = value => captured ? `/shop/officeworks/p/${value}` : store === 'priceline'
    ? `/product/${value}/pro-voke-touch-of-silver-brightening-shampoo-50ml`
    : `/p/sca-sca-car-wash-concentrate-1-litre/${value}.html`;
  let now = 0, click, mutation;
  const timers = [], messages = [];
  class Element {
    constructor(tag, attrs = {}, text = '') {
      this.tagName = tag.toUpperCase(); this.attrs = attrs; this.ownText = text;
      this.children = []; this.parentElement = null; this.hidden = false;
      this.value = ''; this.isConnected = true; this.disabled = false;
    }
    append(child) { child.parentElement = this; this.children.push(child); return child; }
    get textContent() { return [this.ownText, ...this.children.map(e => e.textContent)].join(' '); }
    set textContent(value) { this.ownText = value; }
    get innerText() { return this.textContent; }
    get href() { return this.attrs.href; }
    getAttribute(key) { return this.attrs[key] ?? null; }
    getRootNode() { return document; }
    getClientRects() {
      for (let p = this; p; p = p.parentElement) if (p.hidden) return [];
      return this.isConnected ? [{}] : [];
    }
    matches(selector) {
      const simple = (node, text) => {
        if (text === '*') return true;
        const attrs = [...text.matchAll(/\[([\w-]+)(\*=|=)['"]([^'"]*)['"]\]/g)];
        const base = text.replace(/\[[^\]]+\]/g, '');
        const tag = base.match(/^[\w-]+/)?.[0];
        const classes = [...base.matchAll(/\.([\w-]+)/g)].map(m => m[1]);
        return (!tag || node.tagName === tag.toUpperCase())
          && classes.every(c => (node.attrs.class || '').split(/\s+/).includes(c))
          && attrs.every(([, key, op, value]) => op === '=' ? node.getAttribute(key) === value : node.getAttribute(key)?.includes(value))
          && (!text.includes('[href]') || node.getAttribute('href') !== null);
      };
      return selector.split(',').some(raw => {
        const parts = raw.trim().split(/\s+(?![^\[]*\])/);
        if (!simple(this, parts.pop())) return false;
        let parent = this.parentElement;
        while (parts.length) {
          const wanted = parts.pop();
          while (parent && !simple(parent, wanted)) parent = parent.parentElement;
          if (!parent) return false;
          parent = parent.parentElement;
        }
        return true;
      });
    }
    querySelectorAll(selector) {
      return this.children.flatMap(child => [...(child.matches(selector) ? [child] : []), ...child.querySelectorAll(selector)]);
    }
  }
  const document = { visibilityState: 'visible', addEventListener(type, fn) { if (type === 'click') click = fn; },
    querySelectorAll(selector) { return this.documentElement.querySelectorAll(selector); } };
  document.documentElement = new Element('html');
  document.body = document.documentElement.append(new Element('body'));
  const main = document.body.append(new Element('main'));
  const tile = main.append(new Element('div', { class: store === 'priceline' ? 'card' : 'product-tile' }));
  const imageLink = tile.append(new Element('a', { href: `https://${host}${path(id)}` }));
  const title = tile.append(new Element('a', { href: `https://${host}${path(id)}`, class: 'name-link' }, name));
  const controls = tile.append(new Element(store === 'priceline' ? 'api-add-to-cart' : 'div'));
  const button = controls.append(new Element('button', { type: 'submit', class: 'atc-button' }, 'Add to cart'));
  const actual = controls.append(new Element('input', { class: 'in-cart-quantity-input' })); actual.value = String(before);
  const intended = controls.append(new Element('select', { name: 'Quantity' })); intended.value = '9';
  const modal = document.body.append(new Element('ngb-modal-window', { class: 'add-product-modal' })); modal.hidden = true;
  const receipt = modal.append(new Element('api-added-to-cart-dialog', {}, 'My Cart'));
  const error = receipt.append(new Element('cx-cart-validation-warnings'));
  const cartRow = receipt.append(new Element('api-cart-item'));
  cartRow.append(new Element('h2', {}, name));
  const media = cartRow.append(new Element('cx-media', { format: 'product' }));
  const cartImage = media.append(new Element('img', { src: `https://api.priceline.com.au/medias/300Wx300H-${id}.jpg` }));
  const cartQuantity = cartRow.append(new Element('input', { 'aria-label': 'Quantity' })); cartQuantity.value = '1';
  const otherButton = document.body.append(new Element('button', {}, 'Open cart'));
  const location = { protocol: 'https:', hostname: host, pathname: '/search', href: `https://${host}/search` };
  const context = vm.createContext({ URL, Element, document, location, Date: { now: () => now },
    getComputedStyle: e => ({ visibility: e.hidden ? 'hidden' : 'visible' }),
    setTimeout(fn, ms) { timers.push(() => { now += ms; fn(); }); },
    MutationObserver: class { constructor(fn) { mutation = fn; } observe() {} },
    window: { __listRunnerStoreConfig: config, webkit: { messageHandlers: { listRunner: { postMessage(raw) {
      if (raw !== 'automationReady') messages.push(JSON.parse(raw));
    } } } } } });
  vm.runInContext(source, context);
  context.window.__listRunnerSetContext({ sessionID: 'session', interactionID: 'interaction', itemID: 'item', documentGeneration: 1 });
  return { messages, config,
    tap(trusted = true) { click({ isTrusted: trusted, target: button, composedPath: () => [button, controls, tile] }); },
    tapOther() { click({ isTrusted: true, target: otherButton, composedPath: () => [otherButton] }); },
    receipt(quantity = 1) { modal.hidden = false; cartQuantity.value = String(quantity); mutation(); },
    quantity(value) { actual.value = String(value); mutation(); },
    intended(value) { intended.value = String(value); mutation(); },
    wrongImage(hostname = 'evil.test', product = id) { cartImage.attrs.src = `https://${hostname}/medias/300Wx300H-${product}.jpg`; },
    wrongName() { cartRow.children[0].ownText = 'Other product'; },
    hideReceipt() { modal.hidden = true; },
    errorReceipt() { receipt.ownText = 'Unable to add item'; },
    cartError() { error.ownText = 'Unable to add this item'; },
    duplicateRow() { const row = receipt.append(new Element('api-cart-item', {}, name));
      row.append(new Element('a', { href: `https://${host}${path(id)}` }));
      const q = row.append(new Element('input', { 'aria-label': 'Quantity' })); q.value = '1'; },
    conflictQuantity() { const q = cartRow.append(new Element('input', { 'aria-label': 'Quantity' })); q.value = '2'; },
    foreignLink() { imageLink.attrs.href = `https://evil.test${path(id)}`; title.attrs.href = imageLink.attrs.href; },
    changeIdentity(value) { imageLink.attrs.href = `https://${host}${path(value)}`; title.attrs.href = imageLink.attrs.href; },
    navigate() { location.href = `https://${host}/cart`; },
    expire() { now += 16000; },
    end() { context.window.__listRunnerSetContext(null); },
    tick(n = 8) { for (let i = 0; i < n; i++) timers.shift()?.(); },
    get additions() { return messages.filter(m => m.type === 'addDetected'); },
  };
}

test('Priceline confirms only a new, stable product-image-identified quantity receipt', () => {
  const p = fixture(); p.tap(); p.receipt(); p.tick(1);
  assert.equal(p.additions.length, 0);
  p.tick(); assert.equal(p.additions.length, 1);
  assert.equal(p.additions[0].productID, '39390');
  assert.equal(p.additions[0].resultingQuantity, 1);
});

for (const scenario of ['passive', 'synthetic', 'unrelatedClick', 'foreignImage', 'wrongID', 'wrongName', 'hidden', 'error', 'cartError', 'duplicate', 'conflict', 'stale', 'navigation', 'expired', 'ended']) {
  test(`schema-4 receipt rejects ${scenario}`, () => {
    const p = fixture();
    if (scenario === 'stale') p.receipt();
    if (scenario !== 'passive') p.tap(scenario !== 'synthetic');
    if (scenario === 'foreignImage') p.wrongImage();
    if (scenario === 'wrongID') p.wrongImage('api.priceline.com.au', '99999');
    if (scenario === 'wrongName') p.wrongName();
    if (scenario === 'error') p.errorReceipt();
    if (scenario === 'cartError') p.cartError();
    if (scenario === 'duplicate') p.duplicateRow();
    if (scenario === 'conflict') p.conflictQuantity();
    if (scenario === 'navigation') p.navigate();
    if (scenario === 'expired') p.expire();
    if (scenario === 'ended') p.end();
    if (scenario === 'unrelatedClick') p.tapOther();
    p.receipt(); if (scenario === 'hidden') p.hideReceipt();
    p.tick(); assert.equal(p.additions.length, 0);
  });
}

for (const before of [0, 2]) {
  test(`Supercheap confirms actual same-product quantity ${before}→${before + 1}, not intended quantity`, () => {
    const p = fixture('supercheapAuto', { before }); p.tap(); p.intended(9); p.tick(2);
    assert.equal(p.additions.length, 0);
    p.quantity(before + 1); p.tick(); assert.equal(p.additions.length, 1);
    assert.equal(p.additions[0].beforeQuantity, before);
    assert.equal(p.additions[0].resultingQuantity, before + 1);
  });
}

for (const scenario of ['synthetic', 'foreign', 'recycled', 'unchanged', 'unrelatedClick', 'navigation']) {
  test(`schema-4 quantity rejects ${scenario}`, () => {
    const p = fixture('supercheapAuto');
    if (scenario === 'foreign') p.foreignLink();
    p.tap(scenario !== 'synthetic');
    if (scenario === 'recycled') p.changeIdentity('99999');
    if (scenario === 'navigation') p.navigate();
    if (scenario === 'unrelatedClick') p.tapOther();
    if (scenario !== 'unchanged') p.quantity(1);
    p.tick(); assert.equal(p.additions.length, 0);
  });
}

test('reviewed schema-4 captured URL component identifies bounded nonnumeric SKU', () => {
  const p = fixture('supercheapAuto', { captured: true });
  p.tap(); p.quantity(1); p.tick();
  assert.equal(p.additions.length, 1);
  assert.equal(p.additions[0].productID, 'keji-ballpoint-pens-keka1271as');
});

for (const value of ['../other', 'x'.repeat(257), 'evil%2Fpath', '<script>', 'café']) {
  test(`captured identity rejects unsafe token ${value.slice(0, 24)}`, () => {
    const p = fixture('supercheapAuto', { captured: true }); p.changeIdentity(value);
    p.tap(); p.quantity(1); p.tick(); assert.equal(p.additions.length, 0);
  });
}
