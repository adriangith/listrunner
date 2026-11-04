import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const source = readFileSync(new URL('../tools/inspect-store.js', import.meta.url), 'utf8');
function inspect({ links = [], reflected = 'milk', dialogs = [], controls = [] } = {}) {
  const node = (text, href, visible = true) => ({
    textContent: text, getClientRects: () => visible ? [{}] : [],
    getAttribute: key => key === 'href' ? href : null,
    tagName: 'BUTTON', closest: () => null
  });
  const context = vm.createContext({ URL, location: new URL('https://shop.example/search?q=milk'),
    getComputedStyle: () => ({ display: 'block', visibility: 'visible', opacity: '1' }),
    document: { querySelectorAll(selector) {
      if (selector === 'products') return links.map(([text, href, visible]) => node(text, href, visible));
      if (selector === 'query') return [node(reflected)];
      if (selector === 'adds') return controls.map(text => node(text));
      return dialogs.map(text => node(text));
    } }
  });
  return JSON.parse(JSON.stringify(vm.runInContext(`(${source})`, context)({
    query: 'milk', productSelector: 'products', querySelector: 'query',
    addSelector: 'adds', containerSelector: 'cards'
  })));
}
test('inspection finds distinct product identities, matching query and blocker categories without raw text', () => {
  const result = inspect({ links: [['Fresh milk', '/p/1?tracking=secret'], ['Milk', '/p/1'], ['Bread', '/p/2']],
    dialogs: ['Cookie consent personal secret'], controls: ['Add private product'] });
  assert.equal(result.productCount, 2);
  assert.equal(result.matchingCount, 1);
  assert.equal(result.queryReflected, true);
  assert.deepEqual(result.blockers, ['consent']);
  assert.equal(result.controls.length, 1);
  assert.equal(JSON.stringify(result).includes('secret'), false);
  assert.equal(JSON.stringify(result).includes('private'), false);
});
test('inspection rejects hidden, foreign, insecure, credentialled and unnamed products', () => {
  const result = inspect({ reflected: 'All products', links: [
    ['Milk', '/p/hidden', false], ['Milk', 'https://evil.example/p/1'],
    ['Milk', 'http://shop.example/p/1'], ['Milk', 'https://user@shop.example/p/1'], ['', '/p/empty']
  ] });
  assert.equal(result.productCount, 0);
  assert.equal(result.queryReflected, false);
});
test('inspection reports overflow rather than certifying a truncated catalogue', () => {
  const result = inspect({ links: Array.from({ length: 501 }, (_, i) => ['Milk', `/p/${i}`]) });
  assert.equal(result.overflow, true);
  assert.equal(result.productCount, 500);
});
test('inspection contains no mutation, credential or storage primitives', () => {
  assert.doesNotMatch(source, /\.click\s*\(|\.submit\s*\(|\bfetch\s*\(|XMLHttpRequest|document\.cookie|localStorage|sessionStorage/);
});
