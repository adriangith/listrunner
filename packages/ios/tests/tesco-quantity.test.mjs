import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const swift = readFileSync(new URL('../ListRunner/StoreShoppingView.swift', import.meta.url), 'utf8');
const source = swift.match(/const profileQuantity = \(tile, profile\) => \{([\s\S]*?)\n      \};/)[0];
const config = JSON.parse(readFileSync(new URL('../ListRunner/Resources/tesco.json', import.meta.url), 'utf8'));
const profile = config.cart.profiles[0];

function quantity(nodes, overrides = {}, add = false) {
  const context = vm.createContext({
    config, supportsSchema4Features: (config.automationSchemaVersion ?? config.schemaVersion) === 4,
    getComputedStyle: node => ({ visibility: node.hidden ? 'hidden' : 'visible' }),
    deepQueryAll: (_tile, selector) => selector === profile.quantitySelector ? nodes : add ? [{ textContent: 'Add', getAttribute: () => 'add 1 Milk' }] : [],
    profileControlMatches: () => true, normalize: text => text.trim().toLowerCase(),
  });
  vm.runInContext(source + '\nglobalThis.read = profileQuantity;', context);
  return context.read({ isConnected: true }, { ...profile, ...overrides });
}
function label(text, options = {}) {
  return {
    tagName: 'SPAN', textContent: text, value: '',
    getAttribute: () => null, getClientRects: () => [{}], ...options,
  };
}

test('Tesco profile enables verified detection and normal signed-in Undo', () => {
  assert.equal(config.capabilities.cartDetection, true);
  assert.equal(config.capabilities.cartUndo, true);
  assert.equal(profile.quantityText, true);
});
for (const value of ['0', '1', '2', '9999']) {
  test(`reads product-scoped text quantity ${value}`, () => assert.equal(quantity([label(value)]), Number(value)));
}
for (const value of ['', ' ', '-1', '1.5', '1e2', '0x10', '01', '10000', '1 in basket', 'NaN', 'Infinity']) {
  test(`rejects invalid text quantity ${JSON.stringify(value)}`, () => assert.equal(quantity([label(value)]), null));
}
test('rejects hidden, editable and input intended quantities', () => {
  assert.equal(quantity([label('1', { getClientRects: () => [] })]), null);
  assert.equal(quantity([label('1', { hidden: true })]), null);
  assert.equal(quantity([label('1', { getAttribute: () => 'true' })]), null);
  assert.equal(quantity([label('1', { tagName: 'INPUT', value: '1' })]), null);
});
test('rejects conflicting product quantities', () => assert.equal(quantity([label('1'), label('2')]), null));
test('present invalid quantity never falls back to Add zero', () => assert.equal(quantity([label('invalid')], {}, true), null));
test('dedicated Add is explicit zero only without quantity', () => assert.equal(quantity([], {}, true), 0));
test('missing quantity and Add is unknown, not zero', () => assert.equal(quantity([]), null));
test('old input-value profiles never read text labels implicitly', () => assert.equal(quantity([label('1')], { quantityText: undefined }), null));
test('numeric identity accepts current and legacy Tesco UK routes only', () => {
  const pattern = new RegExp(config.cart.productURLPattern);
  assert.equal(pattern.exec('/shop/en-GB/products/254656543')?.[1], '254656543');
  assert.equal(pattern.exec('/groceries/en-GB/products/254656543')?.[1], '254656543');
  assert.equal(pattern.test('/shop/en-IE/products/254656543'), false);
});
