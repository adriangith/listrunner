import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

// Markup observed live on www.walgreens.com search (16 Nov 2026): the card
// "Add to cart" opens #fulfillmentWidgetContainer; the retailer Add happens on
// "Add for Pickup"; success is the drawer-root "N item(s) added to cart" receipt.
const swift = readFileSync(new URL('../ListRunner/StoreShoppingView.swift', import.meta.url), 'utf8');
const source = swift.match(/private static let automationScript = #"""\n([\s\S]*?)\n    """#/)[1];
const load = () => JSON.parse(readFileSync(new URL('../ListRunner/Resources/walgreens.json', import.meta.url), 'utf8'));

const NAME = 'Crest Pro-Health Advanced Extra White Toothpaste - 5.1 oz';
const PANEL_NAME = 'Crest Pro-Health Advanced Extra White Toothpaste-5.1 oz';
const PATH = '/store/c/crest-pro-health-advanced-extra-white-toothpaste/ID=prod6347302-product';

class Element {
  constructor(tag, attrs = {}, text = '') {
    this.tagName = tag.toUpperCase(); this.attrs = attrs; this.ownText = text;
    this.children = []; this.parentElement = null; this.hidden = false; this.isConnected = true; this.value = '';
  }
  append(child) { child.parentElement = this; this.children.push(child); return child; }
  remove() { if (this.parentElement) this.parentElement.children = this.parentElement.children.filter(c => c !== this); this.parentElement = null; }
  get textContent() { return [this.ownText, ...this.children.map(e => e.textContent)].join(' '); }
  get innerText() { return this.textContent; }
  get href() { return this.attrs.href; }
  getAttribute(key) { return this.attrs[key] ?? null; }
  getRootNode() { return {}; }
  getClientRects() { for (let p = this; p; p = p.parentElement) if (p.hidden) return []; return [{}]; }
  getBoundingClientRect() { return { left: 0, top: 0, right: 100, bottom: 50, width: 100, height: 50 }; }
  matches(selector) {
    const simple = (node, text) => {
      if (text === '*') return true;
      for (const [, key, op, value] of text.matchAll(/\[([\w-]+)(?:(\*=|\^=|=)['"]([^'"]*)['"])?\]/g)) {
        const actual = node.getAttribute(key);
        if (actual === null) return false;
        if (op === '=' && actual !== value) return false;
        if (op === '^=' && !actual.startsWith(value)) return false;
        if (op === '*=' && !actual.includes(value)) return false;
      }
      const tag = text.replace(/\[[^\]]+\]/g, '').match(/^[\w-]+/)?.[0];
      return !tag || node.tagName === tag.toUpperCase();
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

function fixture({ panelName = PANEL_NAME } = {}) {
  const config = load();
  let now = 0, click, mutation;
  const timers = [], messages = [];
  const document = { visibilityState: 'visible', addEventListener(type, fn) { if (type === 'click') click = fn; },
    querySelectorAll(selector) { return this.documentElement.querySelectorAll(selector); } };
  document.documentElement = new Element('html');
  document.body = document.documentElement.append(new Element('body'));
  const host = 'https://www.walgreens.com';
  const card = document.body.append(new Element('div', { id: 'productcardprod6347302', 'data-product-id': 'prod6347302', 'data-sku-id': 'sku6286038' }));
  card.append(new Element('a', { href: host + PATH })).append(new Element('img'));
  card.append(new Element('a', { href: host + '/rebates/' }, 'Spend $50 rebate'));
  const select = card.append(new Element('select', { name: 'legacyQtySelect-prod6347302' })); select.value = '1';
  const add = card.append(new Element('button', { 'data-testid': 'add-to-fulfillment-btn-1', 'aria-label': `Add ${NAME}  to cart` }, 'Add to cart'));
  card.append(new Element('a', { href: host + PATH, 'data-testid': 'product-title-1' }, NAME));
  const other = document.body.append(new Element('div', { id: 'productcardprod1', 'data-product-id': 'prod1' }));
  other.append(new Element('a', { href: host + '/store/c/other/ID=prod1-product', 'data-testid': 'product-title-2' }, 'Colgate Total'));
  const otherAdd = other.append(new Element('button', { 'data-testid': 'add-to-fulfillment-btn-2', 'aria-label': 'Add Colgate Total to cart' }, 'Add to cart'));

  const panel = document.body.append(new Element('div', { id: 'fulfillmentWidgetContainer', role: 'dialog', 'aria-modal': 'true' }));
  panel.hidden = true;
  panel.append(new Element('h2', { id: 'ffoverlayHeading' }, 'How do you want your item?'));
  const close = panel.append(new Element('button', { 'aria-label': 'close dialog', 'data-testid': 'ffoverlay-close-button' }));
  const panelTitle = panel.append(new Element('p', {}, panelName));
  const tabs = panel.append(new Element('ul'));
  const shippingTab = tabs.append(new Element('li', { role: 'tab', 'aria-label': 'Shipping' }));
  const shippingLabel = shippingTab.append(new Element('span', {}, 'Shipping'));
  const pickup = panel.append(new Element('button', { 'data-testid': 'ffoverlay-addforpickup-button', 'aria-label': 'Add for Pickup' }, 'Add for Pickup'));
  const details = panel.append(new Element('a', { id: 'pickup_details_link' }, 'Details'));

  const drawer = document.body.append(new Element('div', { 'data-testid': 'drawer-root', role: 'dialog' }));
  drawer.hidden = true;
  const success = drawer.append(new Element('p', { 'data-testid': 'atc-added-to-cart-success-text' }, '1 item added to cart'));
  const drawerTitle = drawer.append(new Element('p', { 'data-testid': 'pdp-product-title' }, PANEL_NAME));
  const viewCart = drawer.append(new Element('button', { 'aria-label': 'View cart' }, 'View cart'));

  const location = { protocol: 'https:', hostname: 'www.walgreens.com', pathname: '/search/results.jsp', href: `${host}/search/results.jsp?Ntt=toothpaste` };
  const context = vm.createContext({ URL, Element, document, location, Date: { now: () => now },
    getComputedStyle: e => ({ visibility: e.hidden ? 'hidden' : 'visible', opacity: '1', display: 'block', overflowX: 'visible', overflowY: 'visible' }),
    setTimeout(fn, ms) { timers.push(() => { now += ms; fn(); }); },
    MutationObserver: class { constructor(fn) { mutation = fn; } observe() {} },
    window: { __listRunnerStoreConfig: config, webkit: { messageHandlers: { listRunner: { postMessage(raw) {
      if (raw !== 'automationReady') messages.push(JSON.parse(raw));
    } } } } } });
  vm.runInContext(source, context);
  context.window.__listRunnerSetContext({ sessionID: 'session', interactionID: 'interaction', itemID: 'item', documentGeneration: 1 });
  const tapOn = (target, trusted = true) => {
    const path = []; for (let e = target; e; e = e.parentElement) path.push(e);
    click({ isTrusted: trusted, target, composedPath: () => path });
  };
  return { config,
    tapAdd(trusted = true) { tapOn(add, trusted); panel.hidden = false; mutation(); },
    tapAddDirect(trusted = true) { tapOn(add, trusted); mutation(); },
    hidePanel() { panel.hidden = true; mutation(); },
    tapOtherAdd() { tapOn(otherAdd); },
    tapTab() { tapOn(shippingLabel); mutation(); },
    tapContinue(trusted = true) { tapOn(pickup, trusted); panel.hidden = true; mutation(); },
    tapClose() { tapOn(close); panel.hidden = true; mutation(); },
    tapDetails() { tapOn(details); },
    tapViewCart() { tapOn(viewCart); },
    succeed(text = '1 item added to cart') { success.ownText = text; drawer.hidden = false; mutation(); },
    fail() { success.ownText = 'We weren’t able to add the item to your cart'; drawer.hidden = false; mutation(); },
    failureMarker() { drawer.append(new Element('div', { 'data-testid': 'atc-error-message' }, 'Please try again')); },
    drawerTitle(value) { drawerTitle.ownText = value; },
    panelTitle(value) { panelTitle.ownText = value; },
    navigate() { location.href = `${host}/cart`; },
    end() { context.window.__listRunnerSetContext(null); },
    advance(ms) { now += ms; },
    tick(n = 10) { for (let i = 0; i < n; i++) timers.shift()?.(); },
    get acknowledgements() { return messages.filter(m => m.type === 'addAcknowledged'); },
    get additions() { return messages.filter(m => m.type === 'addDetected'); },
  };
}

test('Walgreens two-step card Add confirms only after the panel Add and a matching receipt', () => {
  const p = fixture();
  p.tapAdd(); p.tick(3);
  p.tapTab(); p.tick(3);
  assert.equal(p.acknowledgements.length, 0);
  p.tapContinue(); p.tick(1);
  assert.equal(p.acknowledgements.length, 0);
  p.succeed(); p.tick(1);
  assert.equal(p.acknowledgements.length, 0, 'one observation cannot confirm');
  p.tick();
  assert.equal(p.acknowledgements.length, 1);
  assert.equal(p.acknowledgements[0].productID, 'prod6347302');
  assert.equal(p.acknowledgements[0].profileID, 'product-card');
  assert.equal('resultingQuantity' in p.acknowledgements[0], false);
  assert.equal(p.additions.length, 0);
  assert.equal(p.config.capabilities.cartUndo, false);
});

for (const text of ['2 items added to cart', '12 items added to cart']) {
  test(`Walgreens accepts reviewed receipt count "${text}"`, () => {
    const p = fixture(); p.tapAdd(); p.tapContinue(); p.succeed(text); p.tick();
    assert.equal(p.acknowledgements.length, 1);
  });
}

test('Walgreens keeps the original Add while the user chooses fulfilment, within the reviewed limit', () => {
  const p = fixture(); p.tapAdd(); p.tick(300); // ~54 s with the panel open
  p.tapContinue(); p.succeed(); p.tick();
  assert.equal(p.acknowledgements.length, 1);
});

const failures = {
  noContinue: p => { p.tapAdd(); p.succeed(); p.tick(); },
  syntheticCard: p => { p.tapAdd(false); p.tapContinue(); p.succeed(); p.tick(); },
  syntheticContinue: p => { p.tapAdd(); p.tapContinue(false); p.succeed(); p.tick(); },
  closePanel: p => { p.tapAdd(); p.tapClose(); p.succeed(); p.tick(); },
  otherPanelLink: p => { p.tapAdd(); p.tapDetails(); p.tapContinue(); p.succeed(); p.tick(); },
  otherProductAdd: p => { p.tapOtherAdd(); p.tapContinue(); p.succeed(); p.tick(); },
  differentPanelProduct: p => { p.panelTitle('Colgate Total'); p.tapAdd(); p.tapContinue(); p.succeed(); p.tick(); },
  failedReceipt: p => { p.tapAdd(); p.tapContinue(); p.fail(); p.tick(); },
  failureMarker: p => { p.tapAdd(); p.tapContinue(); p.failureMarker(); p.succeed(); p.tick(); },
  stockLimit: p => { p.tapAdd(); p.tapContinue(); p.succeed('0 items added for pickup'); p.tick(); },
  pickupCount: p => { p.tapAdd(); p.tapContinue(); p.succeed('1 item added for pickup'); p.tick(); },
  zeroCount: p => { p.tapAdd(); p.tapContinue(); p.succeed('0 items added to cart'); p.tick(); },
  uncountedReceipt: p => { p.tapAdd(); p.tapContinue(); p.succeed('item added to cart'); p.tick(); },
  receiptPrefix: p => { p.tapAdd(); p.tapContinue(); p.succeed('not 1 item added to cart'); p.tick(); },
  wrongReceiptProduct: p => { p.tapAdd(); p.tapContinue(); p.drawerTitle('Colgate Total'); p.succeed(); p.tick(); },
  receiptAfterViewCart: p => { p.tapAdd(); p.tapContinue(); p.tapViewCart(); p.succeed(); p.tick(); },
  navigation: p => { p.tapAdd(); p.tapContinue(); p.navigate(); p.succeed(); p.tick(); },
  contextEnded: p => { p.tapAdd(); p.tapContinue(); p.end(); p.succeed(); p.tick(); },
  panelBeyondLimit: p => { p.tapAdd(); p.advance(130000); p.tapContinue(); p.succeed(); p.tick(); },
  receiptExpired: p => { p.tapAdd(); p.tapContinue(); p.advance(16000); p.succeed(); p.tick(); },
};
for (const [name, run] of Object.entries(failures)) {
  test(`Walgreens rejects ${name}`, () => {
    const p = fixture(); run(p);
    assert.equal(p.acknowledgements.length, 0);
    assert.equal(p.additions.length, 0);
  });
}

test('Walgreens remembered fulfilment: a direct card Add confirms from its matching receipt', () => {
  const p = fixture(); p.tapAddDirect(); p.tick(2);
  assert.equal(p.acknowledgements.length, 0);
  p.succeed(); p.tick();
  assert.equal(p.acknowledgements.length, 1);
  assert.equal(p.acknowledgements[0].productID, 'prod6347302');
});

const directFailures = {
  synthetic: p => { p.tapAddDirect(false); p.succeed(); p.tick(); },
  failedReceipt: p => { p.tapAddDirect(); p.fail(); p.tick(); },
  stockLimit: p => { p.tapAddDirect(); p.succeed('0 items added for pickup'); p.tick(); },
  wrongProduct: p => { p.tapAddDirect(); p.drawerTitle('Colgate Total'); p.succeed(); p.tick(); },
  otherProduct: p => { p.tapOtherAdd(); p.succeed(); p.tick(); },
  laterTap: p => { p.tapAddDirect(); p.tapDetails(); p.succeed(); p.tick(); },
  expired: p => { p.tapAddDirect(); p.advance(16000); p.succeed(); p.tick(); },
  panelDismissedWithoutAdd: p => { p.tapAdd(); p.tick(2); p.hidePanel(); p.succeed(); p.tick(); },
};
for (const [name, run] of Object.entries(directFailures)) {
  test(`Walgreens direct Add rejects ${name}`, () => {
    const p = fixture(); run(p);
    assert.equal(p.acknowledgements.length, 0);
  });
}

test('fulfilment continuation is opt-in: without it a panel tap cancels the card Add', () => {
  const p = fixture();
  delete p.config.cart.profiles[0].acknowledgement.fulfillment;
  delete p.config.cart.profiles[0].acknowledgement.successPattern;
  p.drawerTitle(NAME);
  p.tapAdd(); p.tapContinue(); p.succeed(); p.tick();
  assert.equal(p.acknowledgements.length, 0);
});
