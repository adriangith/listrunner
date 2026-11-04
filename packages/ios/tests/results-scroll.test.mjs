import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

// Test the exact isolated-world script bundled in the native app; no network.
const swift = readFileSync(new URL('../ListRunner/StoreShoppingView.swift', import.meta.url), 'utf8');
const source = swift.match(/private static let resultsScrollScript = #"""\n([\s\S]*?)\n    """#/)[1];
const url = 'https://www.coles.com.au/search?q=milk';

function fixture() {
  let now = 0, serial = 0;
  const timers = new Map(), listeners = new Map(), scrolls = [];
  const listen = (name, fn) => {
    if (!listeners.has(name)) listeners.set(name, new Set());
    listeners.get(name).add(fn);
  };
  const unlisten = (name, fn) => listeners.get(name)?.delete(fn);
  const window = {
    scrollX: 0, scrollY: 0, innerHeight: 800,
    addEventListener: listen, removeEventListener: unlisten,
    scrollTo(value) { scrolls.push(value); this.scrollY = value.top; },
  };
  const node = {
    isConnected: true, textContent: 'Milk', top: 900, height: 500, width: 360,
    visibility: 'visible', display: 'block', opacity: '1', busy: null,
    getBoundingClientRect() { return {top: this.top - window.scrollY, height: this.height, width: this.width}; },
    getClientRects() { return this.display === 'none' ? [] : [1]; },
    getAttribute() { return this.busy; },
  };
  const document = {
    readyState: 'complete', visibilityState: 'visible', nodes: [node],
    scrollingElement: {scrollHeight: 3000},
    addEventListener: listen, removeEventListener: unlisten,
    querySelectorAll(selector) {
      if (selector === '[') throw new Error('Invalid CSS');
      if (this.expectedSelector && selector !== this.expectedSelector) return [];
      return this.nodes;
    },
  };
  const location = {href: url};
  const schedule = (fn, delay, repeat = false) => {
    const id = ++serial;
    timers.set(id, {fn, at: now + delay, delay, repeat});
    return id;
  };
  const context = vm.createContext({
    window, document, location, getComputedStyle: value => value,
    setTimeout: (fn, delay) => schedule(fn, delay), clearTimeout: id => timers.delete(id),
    setInterval: (fn, delay) => schedule(fn, delay, true), clearInterval: id => timers.delete(id),
  });
  vm.runInContext(source, context);
  return {
    window, document, node, location, timers, scrolls,
    start(selector = '.grid', offset = 12, expected = url, preload = false) { window.__listRunnerScrollResults(selector, offset, expected, preload); },
    prepare() { window.__listRunnerScrollResults('.grid', 12, url, true); },
    cancel() { window.__listRunnerCancelResultsScroll(); },
    event(name) { for (const fn of [...(listeners.get(name) || [])]) fn(); },
    tick(duration) {
      const end = now + duration;
      while (true) {
        const next = [...timers].filter(([, value]) => value.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
        if (!next) break;
        const [id, timer] = next;
        now = timer.at;
        if (timer.repeat) timer.at += timer.delay;
        else timers.delete(id);
        timer.fn();
      }
      now = end;
    },
    assertClean() {
      assert.equal(timers.size, 0);
      assert.equal([...listeners.values()].reduce((sum, values) => sum + values.size, 0), 0);
    },
  };
}

test('waits for stable results, applies header gap and scrolls only once', () => {
  const f = fixture();
  f.start('.grid', 120);
  f.tick(200);
  assert.equal(f.scrolls.length, 0);
  f.node.top = 1000; // layout shift resets the stability window
  f.tick(300);
  assert.equal(f.scrolls.length, 0);
  f.tick(100);
  assert.equal(f.scrolls.length, 1);
  assert.equal(f.scrolls[0].top, 880);
  assert.equal(f.scrolls[0].behavior, 'instant');
  f.start(); f.tick(10000);
  assert.equal(f.scrolls.length, 1);
  f.assertClean();
});

test('client-rendered grid can appear after document finishes', () => {
  const f = fixture(); f.document.nodes = [];
  f.start(); f.tick(1500);
  assert.equal(f.scrolls.length, 0);
  f.document.nodes = [f.node]; f.tick(500);
  assert.equal(f.scrolls[0].top, 888);
  f.assertClean();
});

test('Woolworths targets its current results grid, not the removed custom tile element', () => {
  const woolworths = JSON.parse(readFileSync(new URL('../ListRunner/Resources/woolworths.json', import.meta.url), 'utf8'));
  const f = fixture();
  f.document.expectedSelector = '[data-testid="search-results-product-scrollable-content"]';
  assert.equal(f.document.querySelectorAll('wc-product-tile').length, 0);
  f.start(woolworths.search.resultsSelector, woolworths.search.resultsTopOffset);
  f.tick(500);
  assert.equal(f.window.__listRunnerResultsScrollState, 'scrolled');
  assert.equal(f.scrolls[0].top, 780);
  f.assertClean();
});

for (const event of ['touchstart', 'pointerdown', 'wheel', 'keydown', 'pagehide']) {
  for (const early of [true, false]) {
    test(`${event} ${early ? 'before' : 'after'} arming cancels pending scroll`, () => {
      const f = fixture();
      if (early) f.event(event);
      f.start();
      if (!early) f.event(event);
      f.tick(10000);
      assert.equal(f.scrolls.length, 0);
      f.assertClean();
    });
  }
}

test('retailer-owned scroll restoration before or during hydration is not user input', () => {
  const f = fixture();
  f.window.scrollY = 100;
  f.event('scroll');
  f.start(); f.tick(100);
  f.window.scrollY = 0;
  f.event('scroll');
  f.tick(500);
  assert.equal(f.scrolls.length, 1);
  assert.equal(f.scrolls[0].top, 888);
  f.assertClean();
});

test('a real user scroll still cancels despite page-owned scroll events', () => {
  const f = fixture(); f.start(); f.event('scroll');
  f.event('touchstart'); f.event('scroll'); f.tick(1000);
  assert.equal(f.scrolls.length, 0); f.assertClean();
});

for (const mutation of [
  f => { f.document.nodes = []; },
  f => { f.node.height = 0; },
  f => { f.node.width = 0; },
  f => { f.node.visibility = 'hidden'; },
  f => { f.node.display = 'none'; },
  f => { f.node.opacity = '0'; },
  f => { f.node.isConnected = false; },
  f => { f.node.textContent = ' '; },
  f => { f.node.busy = 'true'; },
  f => { f.document.readyState = 'loading'; },
]) {
  test(`missing/unusable results time out without moving the page (${mutation.toString()})`, () => {
    const f = fixture(); mutation(f); f.start(); f.tick(9000);
    assert.equal(f.scrolls.length, 0); f.assertClean();
  });
}

test('invalid CSS fails harmlessly', () => {
  const f = fixture(); f.start('['); f.tick(500);
  assert.equal(f.scrolls.length, 0); f.assertClean();
});

test('exact search URL prevents old grids, redirected product pages and SPA navigation', () => {
  const f = fixture(); f.start();
  f.location.href = 'https://www.coles.com.au/product/milk-123';
  f.tick(1000); assert.equal(f.scrolls.length, 0); f.assertClean();
  const stale = fixture(); stale.start('.grid', 12, url.replace('milk', 'bread'));
  stale.tick(1000); assert.equal(stale.scrolls.length, 0); stale.assertClean();
});

test('native cancellation covers disabled preference, supersession, dismissal and recovery', () => {
  const f = fixture(); f.start(); f.tick(100); f.cancel();
  f.tick(10000); f.start();
  assert.equal(f.scrolls.length, 0); f.assertClean();
});

test('hiding an active page cancels pending scroll', () => {
  const f = fixture(); f.start(); f.document.visibilityState = 'hidden'; f.event('visibilitychange');
  f.tick(10000); assert.equal(f.scrolls.length, 0); f.assertClean();
});

test('an unarmed hidden preload does not scroll', () => {
  const f = fixture(); f.document.visibilityState = 'hidden';
  f.tick(60000); assert.equal(f.scrolls.length, 0);
  f.document.visibilityState = 'visible'; f.start(); f.tick(500);
  assert.equal(f.scrolls.length, 1); f.assertClean();
});

test('hidden preload positions stable results before promotion; promotion does not scroll twice', () => {
  const f = fixture(); f.document.visibilityState = 'hidden'; f.prepare();
  f.tick(500);
  assert.equal(f.scrolls.length, 1);
  assert.equal(f.window.__listRunnerResultsScrollState, 'preloadScrolled');
  assert.equal(f.timers.size, 0);
  f.tick(60000);
  f.document.visibilityState = 'visible'; f.event('visibilitychange'); f.start(); f.tick(500);
  assert.equal(f.scrolls.length, 1);
  assert.equal(f.window.__listRunnerResultsScrollState, 'scrolled');
  f.assertClean();
});

for (const change of [f => { f.node.top += 200; }, f => { f.window.scrollY = 0; }]) {
  test(`promotion repairs background layout or scroll restoration (${change})`, () => {
    const f = fixture(); f.prepare(); f.tick(500); change(f);
    f.start(); f.tick(500);
    assert.equal(f.scrolls.length, 2);
    assert.equal(f.window.scrollY, f.node.top - 12); f.assertClean();
  });
}

test('promotion takes over an unfinished background stability check', () => {
  const f = fixture(); f.document.visibilityState = 'hidden'; f.prepare(); f.tick(100);
  f.document.visibilityState = 'visible'; f.start(); f.tick(500);
  assert.equal(f.scrolls.length, 1); f.assertClean();
});

test('background timeout permits visible fallback when the grid finally arrives', () => {
  const f = fixture(); f.document.nodes = []; f.prepare(); f.tick(9000);
  assert.equal(f.window.__listRunnerResultsScrollState, 'preloadTimedOut');
  assert.equal(f.timers.size, 0);
  f.document.nodes = [f.node]; f.start(); f.tick(500);
  assert.equal(f.scrolls.length, 1); f.assertClean();
});

for (const event of ['touchstart', 'pointerdown', 'wheel', 'keydown', 'pagehide']) {
  test(`input or navigation after background positioning prevents promotion correction: ${event}`, () => {
    const f = fixture(); f.prepare(); f.tick(500); f.node.top += 200;
    f.event(event); f.start(); f.tick(1000);
    assert.equal(f.scrolls.length, 1); f.assertClean();
  });
}

test('native cancellation of a prepared preload is permanent', () => {
  const f = fixture(); f.prepare(); f.tick(500); f.cancel();
  f.window.scrollY = 0; f.start(); f.tick(1000);
  assert.equal(f.scrolls.length, 1); f.assertClean();
});

test('background phase still rejects stale search URLs', () => {
  const f = fixture(); f.prepare(); f.location.href += '&changed=true'; f.tick(500);
  f.start(); f.tick(500); assert.equal(f.scrolls.length, 0); f.assertClean();
});

test('visible fallback waits for the promoted document to become visible', () => {
  const f = fixture(); f.document.visibilityState = 'hidden'; f.prepare(); f.tick(100);
  f.start(); f.tick(500); assert.equal(f.scrolls.length, 0);
  f.document.visibilityState = 'visible'; f.event('visibilitychange'); f.tick(500);
  assert.equal(f.scrolls.length, 1); f.assertClean();
});

test('visible attempt that stays hidden times out without moving the page', () => {
  const f = fixture(); f.document.visibilityState = 'hidden'; f.start(); f.tick(9000);
  assert.equal(f.scrolls.length, 0); f.assertClean();
});

for (const [top, height, expected] of [[40, 3000, 0], [5000, 3000, 2200], [900, 500, 0]]) {
  test(`clamps target ${top} in document ${height}`, () => {
    const f = fixture(); f.node.top = top; f.document.scrollingElement.scrollHeight = height;
    f.start('.grid', 120); f.tick(500);
    assert.equal(f.window.scrollY, expected); f.assertClean();
  });
}

test('chooses first visible match rather than a hidden duplicate', () => {
  const f = fixture();
  f.document.nodes = [{...f.node, visibility: 'hidden'}, f.node];
  f.start(); f.tick(500); assert.equal(f.scrolls.length, 1); f.assertClean();
});

for (const offset of [-1, 501, NaN, Infinity, '120']) {
  test(`rejects invalid offset ${offset}`, () => {
    const f = fixture(); f.start('.grid', offset); f.tick(500);
    assert.equal(f.scrolls.length, 0); f.assertClean();
  });
}
