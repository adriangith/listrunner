import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const swift = readFileSync(new URL('../ListRunner/StoreShoppingView.swift', import.meta.url), 'utf8');
const source = swift.match(/private static let loginReplayObserver = #"""\n([\s\S]*?)\n    """#/)[1];
const id = '254656543';
const operation = () => ({ mutation: { kind: 'Document', definitions: [{ kind: 'OperationDefinition', operation: 'mutation',
  name: { value: 'UpdateBasket' }, selectionSet: { selections: [{ kind: 'Field', name: { value: 'basket' } }] } }] },
  variables: { items: [{ id, newValue: 4 }] } });
const result = () => ({ data: { basket: { updates: { items: [{ id, successful: true }] }, items: [{ product: { id }, quantity: 4 }] } } });

function fixture({ auth = false, delayedClient = false } = {}) {
  const messages = [], calls = [];
  let resolve, reject, now = 0;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  const client = { mutate(...args) { calls.push({ receiver: this, args }); return promise; } };
  const orchestrator = { resolveProps() { return { client }; } };
  const location = { protocol: 'https:', hostname: 'www.tesco.com', pathname: auth ? '/account/auth/en-GB/login' : '/shop/en-GB/search', search: '?query=milk' };
  const window = { __listRunnerReplayRule: { productID: id, nonce: 'intent-nonce', host: 'www.tesco.com', path: '/shop/en-GB/search', search: '?query=milk' },
    webkit: { messageHandlers: { listRunnerLoginReplay: { postMessage: value => messages.push(JSON.parse(JSON.stringify(value))) } } } };
  if (!delayedClient) window.Orchestrator = orchestrator;
  const context = vm.createContext({ window, location, Date: { now: () => now } });
  vm.runInContext(source, context);
  return { messages, calls, client, promise, location,
    resolve, reject, installClient() { window.Orchestrator = orchestrator; }, expire() { now = 300001; },
    reinject() { vm.runInContext(source, context); },
    async settle(value = result()) { resolve(value); await promise; await Promise.resolve(); },
  };
}

test('observes actual mutation promise, never the optimistic result, preserving original call/return', async () => {
  const page = fixture();
  const options = operation(); options.optimisticResponse = result();
  assert.equal(page.client.mutate(options), page.promise);
  assert.equal(page.messages.length, 0);
  assert.equal(page.calls.length, 1);
  assert.equal(page.calls[0].receiver, page.client);
  assert.equal(page.calls[0].args[0], options);
  await page.settle();
  assert.deepEqual(page.messages, [{ nonce: 'intent-nonce', productID: id, successful: true, requestedQuantity: 4, resultingQuantity: 4 }]);
});
test('attaches at document start when Orchestrator becomes available later', async () => {
  const page = fixture({ delayedClient: true }); page.installClient(); page.client.mutate(operation()); await page.settle();
  assert.equal(page.messages.length, 1);
});
test('never attaches on authentication forms', async () => {
  const page = fixture({ auth: true }); page.client.mutate(operation()); await page.settle();
  assert.equal(page.messages.length, 0);
});
test('does not multiply wrappers on repeated installation or emit repeated receipts', async () => {
  const page = fixture(); page.reinject(); page.client.mutate(operation()); page.client.mutate(operation()); await page.settle();
  assert.equal(page.calls.length, 2); assert.equal(page.messages.length, 1);
});
for (const mode of ['other-product', 'other-operation', 'query', 'duplicate-item', 'zero', 'fraction', 'string', 'coercible-object']) {
  test(`ignores unrelated or malformed request: ${mode}`, async () => {
    const page = fixture(), options = operation();
    if (mode === 'other-product') options.variables.items[0].id = '999999';
    if (mode === 'other-operation') options.mutation.definitions[0].name.value = 'Login';
    if (mode === 'query') options.mutation.definitions[0].operation = 'query';
    if (mode === 'duplicate-item') options.variables.items.push({ id, newValue: 4 });
    if (mode === 'zero') options.variables.items[0].newValue = 0;
    if (mode === 'fraction') options.variables.items[0].newValue = 1.5;
    if (mode === 'string') options.variables.items[0].newValue = '4';
    if (mode === 'coercible-object') options.variables.items[0].id = { toString: () => id };
    page.client.mutate(options); await page.settle(); assert.equal(page.messages.length, 0);
  });
}
for (const mode of ['failed', 'string-success', 'duplicate-ack', 'missing-ack', 'missing-quantity', 'different-quantity', 'conflicting-quantity', 'errors', 'error', 'expiry', 'navigation']) {
  test(`refuses unconfirmed, stale or ambiguous completion: ${mode}`, async () => {
    const page = fixture(), response = result(); page.client.mutate(operation());
    if (mode === 'failed') response.data.basket.updates.items[0].successful = false;
    if (mode === 'string-success') response.data.basket.updates.items[0].successful = 'true';
    if (mode === 'duplicate-ack') response.data.basket.updates.items.push({ id, successful: true });
    if (mode === 'missing-ack') response.data.basket.updates.items = [];
    if (mode === 'missing-quantity') response.data.basket.items = [];
    if (mode === 'different-quantity') response.data.basket.items[0].quantity = 3;
    if (mode === 'conflicting-quantity') response.data.basket.splitView = [{ items: [{ product: { id }, quantity: 5 }] }];
    if (mode === 'errors') response.errors = [{}];
    if (mode === 'error') response.error = {};
    if (mode === 'expiry') page.expire();
    if (mode === 'navigation') page.location.pathname = '/shop/en-GB/trolley';
    await page.settle(response); assert.equal(page.messages.length, 0);
  });
}
test('rejected network promise is returned unchanged and cannot emit a success', async () => {
  const page = fixture(); const promise = page.client.mutate(operation());
  page.reject(new Error('network')); await assert.rejects(promise, /network/);
  assert.equal(page.messages.length, 0);
});
test('can read a matching split basket without exposing unrelated product/account data', async () => {
  const page = fixture(), response = result(); delete response.data.basket.items;
  response.data.basket.splitView = [{ items: [{ product: { id: 'other' }, quantity: 50 }, { product: { id }, quantity: 4 }] }];
  response.data.account = { private: 'must not be forwarded' };
  page.client.mutate(operation()); await page.settle(response);
  assert.equal(page.messages.length, 1);
  assert.deepEqual(Object.keys(page.messages[0]).sort(), ['nonce', 'productID', 'requestedQuantity', 'resultingQuantity', 'successful']);
});
