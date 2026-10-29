import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const swift = readFileSync(new URL('../ListRunner/StoreShoppingView.swift', import.meta.url), 'utf8');
const source = swift.match(/private static let automationScript = #"""\n([\s\S]*?)\n    """#/)[1];
const config = JSON.parse(readFileSync(new URL('../ListRunner/Resources/bigW.json', import.meta.url), 'utf8'));

// Semantic DOM captured from BIG W mobile: article/product links on the grid,
// scoped main/sticky detail controls, React Add→quantity-control replacement.
function fixture({ detail = false, sticky = false, before = 0, foreign = false } = {}) {
  const messages = [], timers = [];
  let click, mutation, now = 0, decrementClicks = 0;
  class Element {
    constructor(tag, attributes = {}, text = '') {
      this.tagName = tag.toUpperCase(); this.attributes = attributes; this.textContent = text;
      this.children = []; this.parentElement = null; this.isConnected = true; this.value = '';
      this.hidden = false; this.disabled = false;
    }
    append(node) { node.parentElement = this; this.children.push(node); return node; }
    getAttribute(name) { return this.attributes[name] ?? null; }
    get href() { return this.attributes.href; }
    getRootNode() { return document; }
    getClientRects() { return this.hidden ? [] : [{}]; }
    matches(selector) {
      return selector.split(',').some(raw => {
        const s = raw.trim();
        if (s === '*') return true;
        const m = s.match(/^(\w+)?(?:#([\w-]+))?(?:\[([\w-]+)(\*=|=)["']([^"']*)["']\])?$/);
        return !!m && (!m[1] || this.tagName === m[1].toUpperCase()) &&
          (!m[2] || this.attributes.id === m[2]) && (!m[3] ||
            (m[4] === '*=' ? this.getAttribute(m[3])?.includes(m[5]) : this.getAttribute(m[3]) === m[5]));
      });
    }
    querySelectorAll(selector) {
      const results = [];
      for (const child of this.children) {
        if (child.matches(selector)) results.push(child);
        results.push(...child.querySelectorAll(selector));
      }
      return results;
    }
  }
  const document = {
    visibilityState: 'visible',
    addEventListener(type, fn) { if (type === 'click') click = fn; },
    querySelectorAll(selector) { return this.documentElement.querySelectorAll(selector); },
  };
  document.documentElement = new Element('html');
  document.body = document.documentElement.append(new Element('body'));
  const main = document.body.append(new Element('main'));
  const heading = main.append(new Element('h1', { id: detail ? 'product-title' : 'search-title' }, detail ? 'Contempo 2 Slice Toaster - White' : 'toaster'));
  const name = 'Contempo 2 Slice Toaster - White';
  function makeTile(id, page, hidden = false) {
    const tile = main.append(new Element(page ? 'div' : 'article', page
      ? { class: 'ProductActionButtons_ButtonsGrid__oQTcr' } : { 'data-testid': 'product-tile' }));
    tile.hidden = hidden;
    if (!page) {
      const href = `${foreign ? 'https://evil.test' : 'https://www.bigw.com.au'}/product/toaster/p/${id}`;
      tile.append(new Element('a', { href })); // image link
      tile.append(new Element('a', { href })).append(new Element('p', { 'data-optly-product-tile-name': 'true' }, name));
    }
    const controls = tile.append(new Element('div'));
    return { tile, controls, id, page, value: 0 };
  }
  function setState(state, value) {
    state.value = value;
    for (const child of state.controls.children) child.isConnected = false;
    state.controls.children = [];
    if (value === 0) {
      state.control = state.controls.append(new Element('button', {
        'data-di-id': state.page ? 'pdp--add-to-cart' : 'plp--add-to-cart',
        'data-optly-add-to-cart-button': 'true',
      }, 'Add to cart'));
    } else {
      const decrease = state.controls.append(new Element('button', {
        'aria-label': 'decrease quantity by 1', 'data-optly-decrease-quantity-button': 'true',
      }));
      decrease.click = () => { decrementClicks++; setState(state, state.value - 1); mutation(); };
      const input = state.controls.append(new Element('input', { 'aria-label': 'update quantity', type: 'number' }));
      input.value = String(value);
      state.control = state.controls.append(new Element('button', {
        'aria-label': 'increase quantity by 1', 'data-optly-increase-quantity-button': 'true',
      }));
    }
  }
  let selected = makeTile('6060359', detail);
  const duplicate = detail && sticky ? makeTile('6060359', true, true) : null;
  const other = makeTile('6072804', false);
  setState(selected, before); if (duplicate) setState(duplicate, before); setState(other, 0);
  const path = detail ? '/product/contempo-2-slice-toaster-white/p/6060359' : '/search';
  const location = { protocol: 'https:', hostname: 'www.bigw.com.au', pathname: path, href: 'https://www.bigw.com.au' + path };
  const context = vm.createContext({
    URL, Element, Date: { now: () => now }, document, location,
    getComputedStyle: element => ({ visibility: element.hidden ? 'hidden' : 'visible' }),
    window: { __listRunnerStoreConfig: config, webkit: { messageHandlers: { listRunner: {
      postMessage: value => { if (value !== 'automationReady') messages.push(JSON.parse(value)); },
    } } } },
    setTimeout(fn, ms) { timers.push(() => { now += ms; fn(); }); },
    MutationObserver: class { constructor(fn) { mutation = fn; } observe() {} },
  });
  vm.runInContext(source, context);
  const nativeContext = { sessionID: 'session', interactionID: 'interaction', itemID: 'item', documentGeneration: 1 };
  context.window.__listRunnerSetContext(nativeContext);
  const tap = (state, trusted = true) => click({ isTrusted: trusted, target: state.control, composedPath: () => [state.control, state.controls, state.tile] });
  return {
    messages,
    click: trusted => tap(selected, trusted),
    clickRecommendation: () => tap(other),
    setQuantity(value) { setState(selected, value); if (duplicate) setState(duplicate, value); mutation(); },
    setOtherQuantity(value) { setState(other, value); mutation(); },
    setDuplicateQuantity(value) { setState(duplicate, value); mutation(); },
    replaceCard(value = 1, id = '6060359') {
      selected.tile.isConnected = false;
      main.children = main.children.filter(child => child !== selected.tile);
      selected = makeTile(id, false); setState(selected, value); mutation();
    },
    disableDecrease() { selected.controls.children[0].disabled = true; },
    removeDecrease() { selected.controls.children.shift(); },
    changeHeading() { heading.textContent = 'A different product'; },
    clearContext() { context.window.__listRunnerSetContext(null); },
    navigate() { location.href = 'https://www.bigw.com.au/cart'; location.pathname = '/cart'; },
    tick(count = 1) { for (let i = 0; i < count; i++) timers.shift()?.(); },
    expire() { now += 8100; },
    get clicks() { return decrementClicks; },
    record() { const result = messages.findLast(message => message.type === 'addDetected'); return { ...result }; },
    undo(record) { return context.window.__listRunnerUndoAdd(record); },
    async settle(promise) {
      let settled = false, result;
      promise.then(value => { result = value; settled = true; });
      for (let i = 0; i < 40 && !settled; i++) { this.tick(); await Promise.resolve(); }
      assert.ok(settled, 'Undo must terminate');
      return result;
    },
  };
}

for (const options of [{}, { detail: true }, { detail: true, sticky: true }]) {
  test(`BIG W confirms a trusted product quantity increase after control replacement ${JSON.stringify(options)}`, () => {
    const page = fixture(options);
    page.click();
    assert.equal(page.messages[0].type, 'cartInteractionStarted');
    assert.equal(page.messages[0].beforeQuantity, 0);
    assert.equal(page.messages.some(message => message.type === 'addDetected'), false);
    page.setQuantity(1); page.tick(8);
    assert.equal(page.record().productID, '6060359');
    assert.equal(page.record().resultingQuantity, 1);
  });
}

test('BIG W confirms existing-quantity increment without assuming zero', () => {
  const page = fixture({ detail: true, before: 2 });
  page.click(); page.setQuantity(3); page.tick(8);
  assert.equal(page.record().beforeQuantity, 2);
  assert.equal(page.record().resultingQuantity, 3);
});

test('BIG W recommendation on a detail page retains its own ID', () => {
  const page = fixture({ detail: true });
  page.clickRecommendation(); page.setOtherQuantity(1); page.tick(8);
  assert.equal(page.record().productID, '6072804');
});

test('BIG W reacquires React-replaced cards but rejects recycled product identities', () => {
  const page = fixture(); page.click(); page.replaceCard(); page.tick(8);
  assert.equal(page.record().productID, '6060359');
  const recycled = fixture(); recycled.click(); recycled.replaceCard(1, '9999999'); recycled.tick(8);
  assert.equal(recycled.record().productID, undefined);
});

test('BIG W passive, synthetic, foreign, unrelated, expired and navigated changes never confirm', () => {
  for (const mode of ['passive', 'synthetic', 'foreign', 'unrelated', 'expiry', 'navigation', 'context']) {
    const page = fixture({ foreign: mode === 'foreign' });
    if (mode !== 'passive') page.click(mode !== 'synthetic');
    if (mode === 'unrelated') page.setOtherQuantity(1); else page.setQuantity(1);
    if (mode === 'expiry') page.expire();
    if (mode === 'navigation') page.navigate();
    if (mode === 'context') page.clearContext();
    page.tick(8);
    assert.equal(page.record().productID, undefined, mode);
  }
});

test('BIG W conflicting main/sticky quantities cannot confirm an addition', () => {
  const page = fixture({ detail: true, sticky: true });
  page.click(); page.setQuantity(1); page.setDuplicateQuantity(2); page.tick(8);
  assert.equal(page.record().productID, undefined);
});

for (const options of [{}, { detail: true }, { detail: true, before: 2 }]) {
  test(`BIG W Undo reverses only the confirmed delta ${JSON.stringify(options)}`, async () => {
    const page = fixture(options);
    page.click(); page.setQuantity((options.before || 0) + 1); page.tick(8);
    const record = page.record();
    assert.equal(await page.settle(page.undo(record)), true);
    assert.equal(page.clicks, 1);
    assert.equal(await page.undo(record), false, 'confirmation is single use');
    assert.equal(page.messages.filter(message => message.type === 'addDetected').length, 1, 'Undo cannot recursively confirm an add');
  });
}

test('BIG W Undo refuses changed quantities, disabled/missing controls, stale/forged records', async () => {
  for (const mode of ['quantity', 'disabled', 'missing', 'context', 'forged', 'navigation']) {
    const page = fixture({ detail: true });
    page.click(); page.setQuantity(1); page.tick(8);
    const record = page.record();
    if (mode === 'quantity') page.setQuantity(2);
    if (mode === 'disabled') page.disableDecrease();
    if (mode === 'missing') page.removeDecrease();
    if (mode === 'context') page.clearContext();
    if (mode === 'forged') record.productID = '9999999';
    if (mode === 'navigation') page.navigate();
    assert.equal(await page.settle(page.undo(record)), false, mode);
    assert.equal(page.clicks, 0, mode);
  }
});
