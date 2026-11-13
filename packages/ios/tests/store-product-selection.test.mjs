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

function fixture({detail = false} = {}) {
  const timers = new Map(), listeners = new Map(), roots = [], created = [];
  let now = 0;
  function listen(name, fn) { if (!listeners.has(name)) listeners.set(name, new Set()); listeners.get(name).add(fn); }
  function unlisten(name, fn) { listeners.get(name)?.delete(fn); }
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
    getBoundingClientRect() { return {...this.box}; }
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
    visibilityState: 'visible', body: {appendChild(node) { roots.push(node); }},
    nodes: {'.tile': [tile], main: [main]},
    querySelectorAll(selector) { if (selector === '[') throw Error('CSS'); return this.nodes[selector] || []; },
    createElement(tag) { const node = new Node(); node.tag = tag; created.push(node); return node; },
    addEventListener: listen, removeEventListener: unlisten,
    elementFromPoint() { return tile; },
  };
  const location = {href: detail ? link.href : 'https://www.bunnings.com.au/search/products?q=lights'};
  const window = {addEventListener: listen, removeEventListener: unlisten};
  const context = vm.createContext({config: structuredClone(config), hosts: ['www.bunnings.com.au'],
    pathPrefix: '', requestID: 'test-request', chooseLabel: 'Choose product', allowGrid: true,
    window, document, location, URL, innerWidth: 402, innerHeight: 874,
    getComputedStyle: () => ({display: 'block', visibility: 'visible', opacity: '1'}),
    setInterval(fn) { timers.set(1, fn); return 1; }, clearInterval(id) { timers.delete(id); },
  });
  return {context, document, window, location, tile, title, link, heading, main, roots, timers,
    start() { return vm.runInContext(`(async () => {${source}\n})()`, context); },
    tick() { now++; for (const fn of [...timers.values()]) fn(); },
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
      assert.ok(roots.every(root => !root.isConnected));
      assert.equal([...listeners.values()].reduce((sum, set) => sum + set.size, 0), 0);
      assert.equal(window.__listRunnerCancelProductSelection, undefined);
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
  f.tick();
  assert.equal(f.buttons()[0], button);
  assert.equal(button.style.top, '50px');
  f.tap(); assert.ok(await pending); f.assertClean();
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
  ['timeout', f => { for (let n = 0; n < 600; n++) f.tick(); }],
  ['root removed by site', f => { f.roots[0].remove(); f.tick(); }],
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
});
