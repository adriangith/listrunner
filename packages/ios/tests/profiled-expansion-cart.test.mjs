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
  const petbarn = store === 'petbarn';
  const ocado = store === 'ocado';
  const morrisons = store === 'morrisons' || ocado;
  const detail = store === 'chemistWarehouse' || petbarn;
  const office = store === 'officeworks';
  const bunnings = store === 'bunningsNZ';
  const acknowledged = store === 'jbHiFi' || office;
  const name = store === 'priceline' ? 'PRO:VOKE Touch Of Silver Brightening Shampoo 50mL'
    : ocado ? 'Ocado British Semi Skimmed Milk 2 Pints' : morrisons ? 'Belvita Milk & Cereal Biscuit Snack Bars Multipack' : petbarn ? 'Beef with Kiwi Fruit Dog Treat' : detail ? 'Sukin Natural Balance Shampoo 500ml' : office ? 'Keji Ballpoint Pens 1mm Assorted 10 Pack' : bunnings ? 'Craftright 8oz Steel Claw Hammer' : acknowledged ? 'Belkin Hi Speed USB Cable (1.8 Metres)' : 'SCA Car Wash Concentrate 1 Litre';
  let id = store === 'priceline' ? '39390' : ocado ? '78922011' : morrisons ? '109427121' : petbarn ? '138813' : detail ? '85510' : office ? 'keji-ballpoint-pens-1mm-assorted-10-pack-keka1271as' : bunnings ? '5660292' : acknowledged ? 'belkin-hi-speed-usb-cable-1-8-metres' : '733022';
  if (captured) {
    id = 'keji-ballpoint-pens-keka1271as';
    config.id = 'officeworks';
    config.allowedHosts = ['www.officeworks.com.au'];
    config.cart.identityStrategy = 'capturedURLComponent';
    config.cart.productURLPattern = '^/shop/officeworks/p/([A-Za-z0-9_-]{1,256})$';
    config.cart.linkSelector = 'a[href]';
  }
  const host = config.allowedHosts[0];
  const path = value => captured || office ? `/shop/officeworks/p/${value}` : bunnings ? `/craftright-8oz-steel-claw-hammer_p${value}` : store === 'priceline'
    ? `/product/${value}/pro-voke-touch-of-silver-brightening-shampoo-50ml`
    : ocado ? `/products/ocado-british-semi-skimmed-milk-2-pints/${value}` : morrisons ? `/products/belvita-milk-cereal-biscuit-snack-bars-multipack/${value}` : petbarn ? `/p/providore-beef-with-kiwi-fruit-dog-treat/${value}` : detail ? `/buy/${value}/sukin-natural-balance-shampoo-500ml` : acknowledged ? `/products/${value}` : `/p/sca-sca-car-wash-concentrate-1-litre/${value}.html`;
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
        if (text.includes(':last-child')) {
          if (node.parentElement?.children.at(-1) !== node) return false;
          text = text.replace(':last-child', '');
        }
        const not = text.match(/:not\(([^)]+)\)/);
        if (not) {
          if (node.matches(not[1])) return false;
          text = text.replace(not[0], '');
        }
        const has = text.match(/:has\(([^)]+)\)/);
        if (has) {
          if (!node.querySelectorAll(has[1]).length) return false;
          text = text.replace(has[0], '');
        }
        const attrs = [...text.matchAll(/\[([\w-]+)(\*=|\^=|=)['"]([^'"]*)['"]\]/g)];
        const base = text.replace(/\[[^\]]+\]/g, '');
        const tag = base.match(/^[\w-]+/)?.[0];
        const classes = [...base.matchAll(/\.([\w-]+)/g)].map(m => m[1]);
        return (!tag || node.tagName === tag.toUpperCase())
          && classes.every(c => (node.attrs.class || '').split(/\s+/).includes(c))
          && attrs.every(([, key, op, value]) => op === '=' ? node.getAttribute(key) === value : op === '^=' ? node.getAttribute(key)?.startsWith(value) : node.getAttribute(key)?.includes(value))
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
  const tile = main.append(new Element('div', { class: store === 'priceline' ? 'card' : detail ? 'flex' : 'product-tile', 'data-testid': 'product-card-content', 'data-ref': 'product-tile-KEKA1271AS', 'data-search-product-tile': 'true', 'data-test': 'fop-body' }));
  const imageLink = detail ? null : tile.append(new Element('a', { href: `https://${host}${path(id)}` }));
  const title = tile.append(new Element(detail ? 'h1' : 'a', detail ? {} : { href: `https://${host}${path(id)}`, class: 'name-link', 'data-testid': 'product-card-title', 'data-test': 'fop-product-link' }, name));
  if (morrisons) { title.ownText = ''; title.append(new Element('h3', { 'data-test': 'fop-title' }, name)); }
  if (bunnings) { title.ownText = ''; title.append(new Element('p', {}, name)); }
  const controls = tile.append(new Element(store === 'priceline' ? 'api-add-to-cart' : 'div', { 'data-identifier-id': 'product-add-to-cart' }));
  const petQuantity = petbarn ? controls.append(new Element('div', { 'data-identifier-id': 'quantity-selector' })) : null;
  const petButton = value => value > 0 ? {} : { 'aria-label': 'Submit', 'data-identifier-id': 'product-add-to-cart-button' };
  const morrisonsButton = value => ({ 'data-synthetics': 'add-button', 'data-test': value > 0 ? 'counter:increment' : 'counter-button', 'aria-label': value > 0 ? `Increase quantity of ${name} in trolley` : `Add ${name} to ${ocado ? 'trolley' : 'basket'}` });
  let button = (petQuantity || controls).append(new Element('button', morrisons ? morrisonsButton(before) : petbarn ? petButton(before) : detail || bunnings ? before > 0
    ? { 'aria-label': bunnings ? 'Increase quantity' : 'Increment quantity' } : bunnings ? { 'data-locator': 'atcButton' } : { 'data-cy': 'add-to-cart' }
    : { type: 'submit', class: 'atc-button', 'data-testid': 'product-card-actions', 'data-ref': 'add-to-cart-button-KEKA1271AS' }, morrisons ? before > 0 ? '' : 'Add' : petbarn && before > 0 ? '+' : (detail || bunnings) && before > 0 ? '' : 'Add to cart'));
  if (store === 'jbHiFi') button.append(new Element('span', {}, 'Added')); // static before Add; never success evidence
  const actual = new Element('input', { class: 'in-cart-quantity-input', type: 'number', min: '0', 'aria-label': 'Quantity', 'data-test': 'quantity-in-basket' }); actual.value = String(before);
  if ((!detail && !bunnings && !morrisons) || before > 0) controls.append(actual);
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
  const acknowledgement = document.body.append(new Element('div', { 'data-testid': 'slideout-added-to-cart-alert', 'data-ref': 'confirmation-page' }));
  acknowledgement.hidden = true;
  const successHeading = acknowledgement.append(new Element(office ? 'h3' : 'h5', { 'data-testid': 'slideout-added-to-cart-alert-heading' }, office ? 'We’ve added it to your cart' : 'Item added to your cart!'));
  const acknowledgementRow = office ? acknowledgement.append(new Element('div', { 'data-ref': 'minicart-item-KEKA1271AS' })) : acknowledgement;
  const acknowledgedTitle = acknowledgementRow.append(new Element(office ? 'label' : 'h3', { 'data-testid': 'slideout-product-title' }, name));
  if (office) acknowledgementRow.append(new Element('label', { 'aria-label': 'price' }, '$1.00'));
  const location = { protocol: 'https:', hostname: host, pathname: detail ? path(id) : '/search', href: `https://${host}${detail ? path(id) : '/search'}` };
  const context = vm.createContext({ URL, Element, document, location, Date: { now: () => now },
    getComputedStyle: e => ({ visibility: e.hidden ? 'hidden' : 'visible', opacity: e.opacity ?? '1', display: 'block' }),
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
    acknowledge() { acknowledgement.hidden = false; mutation(); },
    hideAcknowledgement() { acknowledgement.hidden = true; },
    transparentAcknowledgement() { acknowledgement.opacity = '0'; },
    wrongAcknowledgementTitle() { acknowledgedTitle.ownText = 'Other product'; },
    wrongSuccess() { successHeading.ownText = 'Unable to add item'; },
    acknowledgementError() { acknowledgement.append(new Element('div', { role: 'alert' }, 'Failed to add')); },
    duplicateAcknowledgementTitle() { acknowledgementRow.append(new Element(office ? 'label' : 'h3', { 'data-testid': 'slideout-product-title' }, 'Other product')); },
    recommendation() { document.body.append(new Element('h3', { 'data-testid': 'slideout-product-title' }, name)); acknowledgedTitle.ownText = 'Other product'; },
    receipt(quantity = 1) { modal.hidden = false; cartQuantity.value = String(quantity); mutation(); },
    quantity(value) {
      actual.value = String(value);
      if (detail || bunnings || morrisons) {
        controls.children = controls.children.filter(child => child !== button && child !== actual);
        button.isConnected = false;
        if (value > 0) controls.append(actual);
        if (petQuantity) petQuantity.children = [];
        button = (petQuantity || controls).append(new Element('button', morrisons ? morrisonsButton(value) : petbarn ? petButton(value) : value > 0 ? { 'aria-label': bunnings ? 'Increase quantity' : 'Increment quantity' } : bunnings ? { 'data-locator': 'atcButton' } : { 'data-cy': 'add-to-cart' }, morrisons ? value > 0 ? '' : 'Add' : petbarn && value > 0 ? '+' : value > 0 ? '' : 'Add to cart'));
      }
      mutation();
    },
    intended(value) { intended.value = String(value); mutation(); },
    relabel(value) { button.attrs['aria-label'] = value; },
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
    get acknowledgements() { return messages.filter(m => m.type === 'addAcknowledged'); },
  };
}

test('JB confirms a fresh product-specific acknowledgement without inventing quantities', () => {
  const p = fixture('jbHiFi'); p.tap(); p.tick(2);
  assert.equal(p.acknowledgements.length, 0, 'static Added span is not evidence');
  p.acknowledge(); p.tick(1); assert.equal(p.acknowledgements.length, 0);
  p.tick(); assert.equal(p.acknowledgements.length, 1);
  assert.equal(p.acknowledgements[0].productID, 'belkin-hi-speed-usb-cable-1-8-metres');
  assert.equal(p.acknowledgements[0].profileID, 'product-card');
  assert.equal('beforeQuantity' in p.acknowledgements[0], false);
  assert.equal('resultingQuantity' in p.acknowledgements[0], false);
  assert.equal(p.additions.length, 0);
});

test('Officeworks observes the exact confirmation title and excludes price labels', () => {
  const p = fixture('officeworks'); p.tap(); p.acknowledge(); p.tick();
  assert.equal(p.acknowledgements.length, 1);
  assert.equal(p.acknowledgements[0].productID, 'keji-ballpoint-pens-1mm-assorted-10-pack-keka1271as');
  assert.equal('resultingQuantity' in p.acknowledgements[0], false);
});

for (const before of [0, 2]) {
  test(`Bunnings NZ confirms product-card stepper ${before}→${before + 1}`, () => {
    const p = fixture('bunningsNZ', { before }); p.tap(); p.quantity(before + 1); p.tick();
    assert.equal(p.additions.length, 1);
    assert.equal(p.additions[0].productID, '5660292');
    assert.equal(p.additions[0].beforeQuantity, before);
    assert.equal(p.additions[0].resultingQuantity, before + 1);
  });
}

for (const store of ['jbHiFi', 'officeworks']) for (const scenario of ['passive', 'synthetic', 'unrelatedClick', 'wrongTitle', 'wrongSuccess', 'hidden', 'transparent', 'error', 'ambiguous', 'stale', 'recommendation', 'navigation', 'expired', 'ended']) {
  test(`${store} acknowledgement rejects ${scenario}`, () => {
    const p = fixture(store);
    if (scenario === 'stale') p.acknowledge();
    if (scenario !== 'passive') p.tap(scenario !== 'synthetic');
    if (scenario === 'unrelatedClick') p.tapOther();
    if (scenario === 'wrongTitle') p.wrongAcknowledgementTitle();
    if (scenario === 'wrongSuccess') p.wrongSuccess();
    if (scenario === 'error') p.acknowledgementError();
    if (scenario === 'ambiguous') p.duplicateAcknowledgementTitle();
    if (scenario === 'recommendation') p.recommendation();
    if (scenario === 'navigation') p.navigate();
    if (scenario === 'expired') p.expire();
    if (scenario === 'ended') p.end();
    p.acknowledge();
    if (scenario === 'hidden') p.hideAcknowledgement();
    if (scenario === 'transparent') p.transparentAcknowledgement();
    p.tick(); assert.equal(p.acknowledgements.length, 0);
  });
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

for (const before of [0, 2]) {
  test(`Chemist Warehouse detail confirms actual cart stepper ${before}→${before + 1} after Add replacement`, () => {
    const p = fixture('chemistWarehouse', { before });
    p.tap(); p.quantity(before + 1); p.tick();
    assert.equal(p.additions.length, 1);
    assert.equal(p.additions[0].productID, '85510');
    assert.equal(p.additions[0].beforeQuantity, before);
    assert.equal(p.additions[0].resultingQuantity, before + 1);
  });
  test(`Petbarn numeric PDP confirms its actual cart stepper ${before}→${before + 1}`, () => {
    const p = fixture('petbarn', { before }); p.tap(); p.quantity(before + 1); p.tick();
    assert.equal(p.additions.length, 1);
    assert.equal(p.additions[0].productID, '138813');
    assert.equal(p.additions[0].beforeQuantity, before);
    assert.equal(p.additions[0].resultingQuantity, before + 1);
  });
  test(`Morrisons card confirms actual quantity ${before}→${before + 1} with product-specific accessible Add label`, () => {
    const p = fixture('morrisons', { before }); p.tap(); p.quantity(before + 1); p.tick();
    assert.equal(p.additions.length, 1);
    assert.equal(p.additions[0].productID, '109427121');
    assert.equal(p.additions[0].beforeQuantity, before);
    assert.equal(p.additions[0].resultingQuantity, before + 1);
  });
  test(`Ocado card confirms independently observed quantity ${before}→${before + 1}`, () => {
    const p = fixture('ocado', { before }); p.tap(); p.quantity(before + 1); p.tick();
    assert.equal(p.additions.length, 1);
    assert.equal(p.additions[0].productID, '78922011');
    assert.equal(p.additions[0].beforeQuantity, before);
    assert.equal(p.additions[0].resultingQuantity, before + 1);
  });
}

test('Morrisons visible Add text does not override a mismatched accessible action label', () => {
  const p = fixture('morrisons'); p.relabel('Remove item'); p.tap(); p.quantity(1); p.tick();
  assert.equal(p.additions.length, 0);
});

for (const scenario of ['passive', 'synthetic', 'unrelatedClick', 'unchanged', 'navigation', 'expired', 'ended']) {
  test(`Petbarn rejects ${scenario}`, () => {
    const p = fixture('petbarn');
    if (scenario !== 'passive') p.tap(scenario !== 'synthetic');
    if (scenario === 'unrelatedClick') p.tapOther();
    if (scenario === 'navigation') p.navigate();
    if (scenario === 'expired') p.expire();
    if (scenario === 'ended') p.end();
    if (scenario !== 'unchanged') p.quantity(1);
    p.tick(); assert.equal(p.additions.length, 0);
  });
}

for (const store of ['supercheapAuto', 'bunningsNZ', 'morrisons', 'ocado']) for (const scenario of ['synthetic', 'foreign', 'recycled', 'unchanged', 'unrelatedClick', 'navigation']) {
  test(`${store} schema-4 quantity rejects ${scenario}`, () => {
    const p = fixture(store);
    if (scenario === 'foreign') p.foreignLink();
    p.tap(scenario !== 'synthetic');
    if (scenario === 'recycled') p.changeIdentity('99999');
    if (scenario === 'navigation') p.navigate();
    if (scenario === 'unrelatedClick') p.tapOther();
    if (scenario !== 'unchanged') p.quantity(1);
    p.tick(); assert.equal(p.additions.length, 0);
  });
}

for (const store of ['supercheapAuto', 'chemistWarehouse', 'bunningsNZ', 'petbarn', 'morrisons', 'ocado']) {
  for (const value of ['invalid', '', -1, 10000, 1.5, 1]) {
    test(`${store} rejects invalid or non-increasing actual quantity ${JSON.stringify(value)}`, () => {
      const p = fixture(store, { before: 2 }); p.tap(); p.quantity(value); p.tick();
      assert.equal(p.additions.length, 0);
    });
  }
  test(`${store} does not treat intended quantity as an actual cart increase`, () => {
    const p = fixture(store); p.tap(); p.intended(9); p.tick();
    assert.equal(p.additions.length, 0);
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
