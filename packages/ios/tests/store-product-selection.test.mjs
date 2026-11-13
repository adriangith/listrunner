import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const swift = readFileSync(new URL('../ListRunner/StoreProductSelection.swift', import.meta.url), 'utf8');
const source = swift.match(/static let script = #"""\n([\s\S]*?)\n    """#/)[1];
const config = {
  productURLPattern: '_p(\\d+)$',
  grid: {containerSelector: '.tile', titleSelector: '.title', linkSelector: 'a'},
  detail: {containerSelector: 'main', titleSelector: 'h1'},
};

function fixture({detail = false, origin = {left: 0, top: 0}} = {}) {
  const timers = new Map(), frames = new Map(), listeners = new Map(), roots = [], created = [], observers = [];
  let serial = 0;
  function listen(name, fn) { if (!listeners.has(name)) listeners.set(name, new Set()); listeners.get(name).add(fn); }
  function unlisten(name, fn) { listeners.get(name)?.delete(fn); }
  const window = {scrollX: 0, scrollY: 0, addEventListener: listen, removeEventListener: unlisten};
  class Observer {
    constructor(callback) { this.callback = callback; this.active = true; this.nodes = new Set(); observers.push(this); }
    observe(node) { this.nodes.add(node); }
    unobserve(node) { this.nodes.delete(node); }
    disconnect() { this.active = false; this.nodes.clear(); }
  }
  class Mutations extends Observer {}
  class Sizes extends Observer {}
  class Node {
    constructor(text = '') {
      this.textContent = text; this.isConnected = true; this.nodes = {};
      this.style = {setProperty() {}, removeProperty() {}};
      this.box = {left: 10, top: 100, width: 180, height: 300, right: 190, bottom: 400};
      this.events = {}; this.children = [];
    }
    querySelectorAll(selector) { if (selector === '[') throw Error('CSS'); return this.nodes[selector] || []; }
    getClientRects() { return this.isConnected && !this.hidden ? [this.box] : []; }
    get innerText() { return this.textContent; }
    getBoundingClientRect() {
      const left = this.box.left - window.scrollX, top = this.box.top - window.scrollY;
      return {...this.box, left, top, right: left + this.box.width, bottom: top + this.box.height};
    }
    closest() { return this.hidden ? this : null; }
    contains(node) { return node === this || this.children.includes(node); }
    remove() { this.isConnected = false; }
    attachShadow() { return this; }
    appendChild(node) { this.children.push(node); return node; }
    setAttribute() {}
    addEventListener(name, fn) { this.events[name] = fn; }
  }
  const tile = new Node(), title = new Node('2x LED lights, 75 mm'), link = new Node('link');
  link.href = 'https://www.bunnings.com.au/lights_p0123456';
  tile.nodes = {'.title': [title], a: [link]};
  const main = new Node(), heading = new Node('2x LED lights, 75 mm');
  main.nodes = {h1: [heading]};
  const document = {
    visibilityState: 'visible', documentElement: new Node(),
    body: Object.assign(new Node(), {appendChild(node) { roots.push(node); }}),
    nodes: {'.tile': [tile], main: [main]},
    querySelectorAll(selector) { if (selector === '[') throw Error('CSS'); return this.nodes[selector] || []; },
    createElement(tag) {
      const node = new Node(); node.tag = tag;
      if (tag === 'div') node.box = {...origin, width: 0, height: 0};
      created.push(node); return node;
    },
    addEventListener: listen, removeEventListener: unlisten,
    elementFromPoint() { return tile; },
  };
  const location = {href: detail ? link.href : 'https://www.bunnings.com.au/search/products?q=lights'};
  const context = vm.createContext({config: structuredClone(config), hosts: ['www.bunnings.com.au'],
    pathPrefix: '', requestID: 'test-request', chooseLabel: 'Choose product', allowGrid: true,
    window, document, location, URL, innerWidth: 402, innerHeight: 874,
    getComputedStyle: () => ({display: 'block', visibility: 'visible', opacity: '1'}),
    MutationObserver: Mutations, ResizeObserver: Sizes,
    requestAnimationFrame(fn) { const id = ++serial; frames.set(id, fn); return id; },
    cancelAnimationFrame(id) { frames.delete(id); },
    setTimeout(fn) { const id = ++serial; timers.set(id, fn); return id; }, clearTimeout(id) { timers.delete(id); },
  });
  return {context, document, window, location, tile, title, link, heading, main, roots, timers, frames, Node,
    start() { return vm.runInContext(`(async () => {${source}\n})()`, context); },
    tick() { const pending = [...frames.values()]; frames.clear(); for (const fn of pending) fn(); },
    mutate(target = tile) { for (const o of observers) if (o.active && o instanceof Mutations) o.callback([{target}]); },
    resize() { for (const o of observers) if (o.active && o instanceof Sizes) o.callback([]); },
    expire() { for (const fn of [...timers.values()]) fn(); },
    event(name) { for (const fn of [...(listeners.get(name) || [])]) fn(); },
    buttons() { return created.filter(n => n.tag === 'button' && n.isConnected); },
    tap(button = this.buttons()[0]) {
      let prevented = false, stopped = false;
      button.events.click({isTrusted: true, detail: 1, clientX: 50, clientY: 150,
        preventDefault() { prevented = true; }, stopImmediatePropagation() { stopped = true; }});
      assert.ok(prevented && stopped, 'selection tap is consumed');
    },
    assertClean() {
      assert.equal(timers.size, 0);
      assert.equal(frames.size, 0);
      assert.ok(observers.every(o => !o.active));
      assert.ok(roots.every(root => !root.isConnected));
      assert.equal([...listeners.values()].reduce((sum, set) => sum + set.size, 0), 0);
      assert.equal(window.__listRunnerCancelProductSelection, undefined);
      assert.equal(window.__listRunnerProductSelectionID, undefined);
    },
  };
}

test('product page reads its exact heading without adding selection DOM', async () => {
  const f = fixture({detail: true});
  const value = await f.start();
  assert.equal(value.name, '2x LED lights, 75 mm');
  assert.equal(value.productID, '0123456');
  assert.equal(f.roots.length, 0); f.assertClean();
});

test('assistive grid activation uses native fallback without exposing website shields', async () => {
  const grid = fixture(); grid.context.allowGrid = false;
  assert.equal(await grid.start(), null);
  assert.equal(grid.roots.length, 0); grid.assertClean();
  const detail = fixture({detail: true}); detail.context.allowGrid = false;
  assert.equal((await detail.start()).name, '2x LED lights, 75 mm'); detail.assertClean();
});

test('grid installs shields outside the tiles and consumes selection without website click', async () => {
  const f = fixture();
  let websiteClicks = 0;
  f.link.click = () => { websiteClicks++; };
  const pending = f.start();
  assert.equal(f.buttons().length, 1);
  assert.equal(f.tile.children.length, 0);
  f.tap();
  assert.equal((await pending).name, '2x LED lights, 75 mm');
  assert.equal(websiteClicks, 0); f.assertClean();
});

test('layout updates retain the same tappable shield and update its position', async () => {
  const f = fixture(), pending = f.start(), button = f.buttons()[0];
  f.tile.box.top = 50;
  f.mutate();
  f.tick();
  assert.equal(f.buttons()[0], button);
  assert.equal(button.style.top, '50px');
  f.tap(); assert.ok(await pending); f.assertClean();
});

test('window scrolling needs no JavaScript position update or timer tick', async () => {
  const f = fixture(), pending = f.start(), button = f.buttons()[0];
  assert.match(f.roots[0].style.cssText, /position:absolute/);
  assert.match(button.style.cssText, /position:absolute/);
  assert.equal(button.style.top, '100px');
  f.window.scrollY = 80; f.window.scrollX = 7;
  assert.equal(f.tile.getBoundingClientRect().top, 20);
  assert.equal(button.style.top, '100px', 'document-relative geometry never chases viewport scrolling');
  assert.equal(f.frames.size, 0, 'normal scrolling stays correct before any JS callback runs');
  f.tap(); assert.equal((await pending).name, '2x LED lights, 75 mm'); f.assertClean();
});

test('positioned body origins are measured instead of assumed to be zero', async () => {
  const f = fixture({origin: {left: 5, top: 40}}), pending = f.start();
  assert.equal(f.buttons()[0].style.left, '5px');
  assert.equal(f.buttons()[0].style.top, '60px');
  f.window.scrollY = 50;
  f.tap(); assert.ok(await pending); f.assertClean();
});

test('nested scroll geometry is coalesced into one frame without recreating controls', async () => {
  const f = fixture(), pending = f.start(), button = f.buttons()[0];
  f.tile.box.top = 30;
  for (let i = 0; i < 10; i++) f.event('scroll');
  assert.equal(f.frames.size, 1);
  f.tick(); assert.equal(f.buttons()[0], button); assert.equal(button.style.top, '30px');
  f.tap(); assert.ok(await pending); f.assertClean();
});

test('resize and mutation callbacks share one frame and discover newly rendered/offscreen tiles', async () => {
  const f = fixture(), pending = f.start(), button = f.buttons()[0];
  const tile = new f.Node(), title = new f.Node('New product'), link = new f.Node();
  link.href = 'https://www.bunnings.com.au/new_p2222222';
  tile.box.top = 1200; tile.nodes = {'.title': [title], a: [link]};
  f.document.nodes['.tile'].push(tile);
  f.tile.box.width = 200;
  f.resize(); f.mutate(); f.event('resize');
  assert.equal(f.frames.size, 1);
  f.tick(); assert.equal(f.buttons().length, 2); assert.equal(button.style.width, '200px');
  const other = f.buttons()[1]; assert.equal(other.style.top, '1200px');
  f.window.scrollY = 1100; f.document.elementFromPoint = () => tile;
  f.tap(other); assert.equal((await pending).name, 'New product'); f.assertClean();
});

test('own layer mutations do not start a geometry feedback loop; pending frames cancel on exit', async () => {
  const f = fixture(), pending = f.start();
  f.mutate(f.roots[0]); assert.equal(f.frames.size, 0);
  f.mutate(); assert.equal(f.frames.size, 1);
  f.window.__listRunnerCancelProductSelection();
  assert.equal(await pending, null); f.assertClean();
  f.resize(); f.event('scroll'); f.tick(); f.assertClean();
});

test('missing observer support falls back without adding document controls', async () => {
  const f = fixture(); f.context.ResizeObserver = undefined;
  assert.equal(await f.start(), null); assert.equal(f.roots.length, 0); f.assertClean();
});

for (const [name, change] of [
  ['recycled ID', f => { f.link.href = 'https://www.bunnings.com.au/other_p9999999'; }],
  ['changed title', f => { f.title.textContent = 'Other product'; }],
  ['detached tile', f => { f.tile.isConnected = false; }],
  ['unrefreshed geometry', f => { f.tile.box.top = 200; }],
  ['occluded tile', f => { f.document.elementFromPoint = () => null; }],
  ['same-document navigation', f => { f.location.href += '&page=2'; }],
]) {
  test(`selection rejects ${name}`, async () => {
    const f = fixture(), pending = f.start(); change(f); f.tap();
    assert.equal(await pending, null); f.assertClean();
  });
}

for (const [name, change] of [
  ['explicit cancel', f => f.window.__listRunnerCancelProductSelection()],
  ['navigation', f => f.event('pagehide')],
  ['background', f => { f.document.visibilityState = 'hidden'; f.event('visibilitychange'); }],
  ['timeout', f => f.expire()],
  ['root removed by site', f => { f.roots[0].remove(); f.mutate(f.document.body); f.tick(); }],
]) {
  test(`${name} removes all shields and listeners`, async () => {
    const f = fixture(), pending = f.start(); change(f);
    assert.equal(await pending, null); f.assertClean();
  });
}

for (const raw of ['http://www.bunnings.com.au/x_p1', 'https://user:pass@www.bunnings.com.au/x_p1',
  'https://www.bunnings.com.au:444/x_p1', 'https://www.bunnings.com.au.attacker.test/x_p1']) {
  test(`rejects untrusted link ${raw}`, async () => {
    const f = fixture(); f.link.href = raw;
    assert.equal(await f.start(), null); f.assertClean();
  });
}

test('two different product links in one tile fail closed', async () => {
  const f = fixture(); f.tile.nodes.a.push({...f.link, href: 'https://www.bunnings.com.au/other_p2',
    isConnected: true, getClientRects: () => [1], getBoundingClientRect: () => f.link.box, closest: () => null});
  assert.equal(await f.start(), null); f.assertClean();
});

test('conflicting or hidden headings never choose a recommendation on a detail page', async () => {
  const f = fixture({detail: true}); f.heading.hidden = true;
  assert.equal(await f.start(), null); f.assertClean();
});

test('invalid CSS and missing profiles fall back without leftover page changes', async () => {
  const f = fixture(); f.context.config.grid.containerSelector = '[';
  assert.equal(await f.start(), null); f.assertClean();
  const missing = fixture(); missing.context.config = null;
  assert.equal(await missing.start(), null); missing.assertClean();
});

test('native source confines reads and cancellation to the request and isolated world', () => {
  const source = readFileSync(new URL('../ListRunner/StoreShoppingView.swift', import.meta.url), 'utf8');
  assert.match(source, /let url = webView.url, store.allows\(url\)/);
  assert.match(source, /productSelectionRequest == request/);
  assert.match(source, /documentGeneration == generation, view.url == url/);
  assert.match(source, /contentWorld: automationWorld/);
  assert.match(source, /func endInteraction\(\) \{\s*cancelStoreProductSelection\(\)/);
  const resume = source.split('func resumeAfterStoreProductSelection(itemID: UUID)')[1].split('func chooseStoreProduct')[0];
  assert.doesNotMatch(resume, /beginInteraction|search\(for:|loadStoreURL/);
  assert.doesNotMatch(swift.match(/static let script[\s\S]*/)[0], /fetch\(|\.click\(|localStorage|sessionStorage|document.cookie/);
  assert.doesNotMatch(swift.match(/static let script[\s\S]*/)[0], /setInterval/);
});

test('rail control wording and fade follow uncovered width without a delayed animation', () => {
  assert.match(swift, /Text\("Add item to your list"\)/);
  assert.match(swift, /accessibilityLabel\("Add item to your list"\)/);
  assert.match(swift, /StoreProductRailEndControl\(uncoveredWidth: leadingWidth/);
  assert.match(swift, /StoreProductRailEndControl\(uncoveredWidth: trailingWidth/);
  assert.match(swift, /opacity\(Double\(uncoveredWidth \/ 88\)\)/);
  assert.match(swift, /if uncoveredWidth >= 44/);
  assert.match(swift, /else if uncoveredWidth > 0/);
  assert.doesNotMatch(swift, /Add store item to list/);
});

test('rail sides capture insertion position through review, manual entry and persistence', () => {
  assert.match(swift, /insertion: \.start\) \{ action\(\.start\) \}/);
  assert.match(swift, /insertion: \.end\) \{ action\(\.end\) \}/);
  assert.match(swift, /let insertion: ShoppingLists\.AdditionPosition/);
  assert.match(swift, /LabeledContent\("Position"\)/);
  const view = readFileSync(new URL('../ListRunner/StoreShoppingView.swift', import.meta.url), 'utf8');
  assert.match(view, /onAddStoreProduct\(name, quantity, draft\.insertion\)/);
  assert.match(view, /StoreProductDraft\(name: name, insertion: insertion\)/);
  assert.match(view, /StoreProductDraft\(name: "", insertion: storeProductInsertion\)/);
  assert.match(view, /Button \{ beginStoreProductSelection\(at: \.start\) \} label:/);
  const lists = readFileSync(new URL('../ListRunner/GroceryListScreen.swift', import.meta.url), 'utf8');
  assert.match(lists, /to: store, allItems: allItems, context: modelContext, insertion: insertion/);
  assert.match(lists, /to: storeID, allItems: allItems, context: modelContext, insertion: insertion/);
});
