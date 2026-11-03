// Bundled, isolated-world engine. Only the reviewed IKEA AU contract opts in.
// No retailer APIs, credentials, checkout, storage scraping or page-world bridge.
(() => {
  'use strict';
  const config = window.__listRunnerStoreConfig;
  const rules = config?.cart;
  const bridge = window.webkit?.messageHandlers?.listRunner;
  const allowed = value => {
    try {
      const url = new URL(value, location.href);
      return url.protocol === 'https:' && config.allowedHosts.includes(url.hostname.toLowerCase()) &&
        !url.username && !url.password && (!url.port || url.port === '443') &&
        url.pathname.startsWith('/au/en/') && !/%25|%2e|%2f|%5c|\\/i.test(url.pathname);
    } catch (_) { return false; }
  };
  if (!bridge || config?.id !== 'ikeaAU' || config.schemaVersion !== 5 ||
      !config.capabilities.cartDetection || rules?.strategy !== 'verifiedCartSnapshot' || !allowed(location.href)) return;
  const contract = rules.snapshot;
  const normalize = value => String(value || '').replace(/\s+/g, ' ').trim();
  const key = value => value ? JSON.stringify([value.sessionID, value.interactionID, value.itemID, value.documentGeneration]) : 'null';
  const pattern = new RegExp(rules.productURLPattern);
  const idFromURL = value => {
    if (!allowed(value)) return null;
    const match = new URL(value, location.href).pathname.match(pattern);
    return match && /^\d{8}$/.test(match[1]) ? match[1] : null;
  };
  const idsIn = root => new Set([...root.querySelectorAll(rules.linkSelector)].map(a => idFromURL(a.href)).filter(Boolean));
  const enabled = element => element?.isConnected && !element.disabled && element.getAttribute('aria-disabled') !== 'true';
  const visible = element => {
    if (!element?.getClientRects().length) return false;
    for (let current = element; current; current = current.parentElement) {
      const style = element.ownerDocument.defaultView.getComputedStyle(current);
      if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity) === 0) return false;
    }
    return true;
  };
  const resolve = control => {
    if (!enabled(control) || !visible(control)) return null;
    const matches = [];
    for (const profile of rules.profiles) {
      if (!control.matches(profile.addSelector) || !profile.addLabelPatterns.some(p => new RegExp(p).test(
          normalize(control.getAttribute('aria-label') || control.textContent).toLowerCase()))) continue;
      const tile = control.closest(profile.containerSelector);
      if (!tile || ['BODY', 'HTML', 'MAIN'].includes(tile.tagName)) continue;
      let id;
      if (profile.identity === 'cardLink') {
        const ids = idsIn(tile);
        if (ids.size !== 1) continue;
        id = [...ids][0];
        // The explicit card article must agree with its product links.
        if (tile.getAttribute('data-product-number') !== id) continue;
      } else {
        id = idFromURL(location.href);
        if (!id || idsIn(tile).size) continue;
      }
      const inputs = [...tile.querySelectorAll('input')];
      const draft = profile.identity === 'pageURL' ? inputs.filter(x => /quantity/i.test(x.getAttribute('aria-label') || '')) : [];
      if (draft.length > 1) continue;
      const amount = draft.length ? Number(draft[0].value) : 1;
      if (!Number.isInteger(amount) || amount < 1 || amount > 99) continue;
      matches.push({ id, amount, profileID: profile.id, draft: inputs.map(x => x.value).join('|') });
    }
    return matches.length === 1 ? matches[0] : null;
  };
  let context = null;
  let operation = null;
  let frame = null;
  let bypass = null;
  let disabled = false;
  let sequence = 0;
  const confirmations = new Map();
  const post = (type, fields) => {
    if (context) bridge.postMessage(JSON.stringify({ schemaVersion: 1, type, storeID: config.id,
      sessionID: context.sessionID, interactionID: context.interactionID, itemID: context.itemID,
      documentGeneration: context.documentGeneration, pageURL: location.href, ...fields }));
  };
  const discardFrame = () => { frame?.remove(); frame = null; };
  const cancel = () => { operation = null; bypass = null; discardFrame(); };
  const valid = op => operation === op && context && key(context) === op.context &&
    location.href === op.pageURL && allowed(location.href) && document.visibilityState !== 'hidden' && Date.now() < op.deadline;
  const pause = () => new Promise(resolve => setTimeout(resolve, 200));
  const fingerprint = snapshot => JSON.stringify([...snapshot.quantities].sort(([a], [b]) => a.localeCompare(b)));
  const sameOthers = (a, b, id) => {
    const without = snapshot => JSON.stringify([...snapshot.quantities].filter(([key]) => key !== id).sort(([a], [b]) => a.localeCompare(b)));
    return without(a) === without(b);
  };
  const read = () => {
    try {
      const doc = frame?.contentDocument;
      const url = frame?.contentWindow.location;
      if (!doc || !url || url.origin !== location.origin || url.pathname !== contract.path ||
          url.search || url.hash || doc.readyState !== 'complete') return null;
      const main = doc.querySelector('main');
      if (!main || main.querySelector('[aria-busy="true"], [role="alert"]')) return null;
      const rows = [...doc.querySelectorAll(contract.rowSelector)];
      const quantities = new Map(), products = new Map();
      const allInputs = [...main.querySelectorAll(contract.quantitySelector)];
      // Completeness: every cart quantity belongs to exactly one semantic row.
      if (rows.length !== allInputs.length) return null;
      for (const row of rows) {
        if (!visible(row)) return null;
        const articles = [...row.querySelectorAll(contract.articleSelector)];
        const inputs = [...row.querySelectorAll(contract.quantitySelector)];
        if (articles.length !== 1 || inputs.length !== 1 || !visible(inputs[0]) || !enabled(inputs[0])) return null;
        const article = normalize(articles[0].getAttribute('aria-label')).match(/^Product article number (\d{3})\.(\d{3})\.(\d{2})$/);
        const id = article ? article.slice(1).join('') : null;
        const ids = idsIn(row);
        const raw = String(inputs[0].value);
        if (!id || ids.size !== 1 || !ids.has(id) || quantities.has(id) || !/^[1-9]\d{0,2}$/.test(raw)) return null;
        // An edited input is a draft until the rendered value agrees. A fresh
        // document plus a stable reread is required again before confirming it.
        if (inputs[0].getAttribute('value') !== raw) return null;
        quantities.set(id, Number(raw)); products.set(id, row);
      }
      const empty = [...doc.querySelectorAll(contract.emptySelector)].filter(visible)
        .some(e => normalize(e.textContent) === contract.emptyText);
      if (empty !== (rows.length === 0)) return null;
      // Cart badge is a completeness check, NEVER the product quantity proof.
      const badges = [...doc.querySelectorAll('a[data-tracking-label="shopping-cart"]')];
      if (badges.length !== 1 || new URL(badges[0].href).pathname !== contract.path) return null;
      const badge = badges[0];
      const label = normalize(badge.getAttribute('aria-label') || badge.textContent);
      const count = label.match(/^Shopping bag, (\d+) items?$/);
      const total = [...quantities.values()].reduce((a, b) => a + b, 0);
      if (rows.length ? !count || Number(count[1]) !== total : label !== 'Shopping bag') return null;
      return { quantities, products };
    } catch (_) { return null; }
  };
  const load = () => {
    discardFrame();
    frame = document.createElement('iframe');
    frame.setAttribute('aria-hidden', 'true'); frame.tabIndex = -1;
    frame.setAttribute('sandbox', 'allow-scripts allow-same-origin');
    frame.style.cssText = 'position:fixed;left:-10000px;top:0;width:390px;height:844px;border:0;pointer-events:none';
    frame.src = new URL(contract.path, location.origin).href;
    document.body.appendChild(frame);
  };
  const stable = async (op, accept) => {
    let previous = null, consecutive = 0;
    const deadline = Math.min(op.deadline, Date.now() + 12000);
    while (valid(op) && Date.now() < deadline) {
      await pause();
      if (!valid(op)) return null;
      const snapshot = read();
      const signature = snapshot && fingerprint(snapshot);
      if (snapshot && accept(snapshot)) {
        consecutive = signature === previous ? consecutive + 1 : 1;
        previous = signature;
        if (consecutive >= 3) return snapshot;
      } else { previous = null; consecutive = 0; }
    }
    return null;
  };
  window.__listRunnerSetContext = next => {
    if (key(context) === key(next)) return;
    cancel(); confirmations.clear(); context = next;
  };
  window.__listRunnerCancelUndo = cancel;
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') cancel(); });
  window.addEventListener('pagehide', cancel);
  // Any later real website interaction invalidates an in-flight operation and
  // its Undo provenance. Our one permitted replay is never a new trusted intent.
  for (const type of ['input', 'change', 'keydown']) window.addEventListener(type, event => {
    if (event.isTrusted) { cancel(); confirmations.clear(); }
  }, true);
  window.addEventListener('click', event => {
    const control = event.target instanceof Element ? event.target.closest('button') : null;
    if (!event.isTrusted) {
      if (bypass === control) bypass = null;
      return;
    }
    cancel(); confirmations.clear();
    if (disabled || !context || !control || !allowed(location.href)) return;
    const product = resolve(control);
    if (!product) return;
    // Hold this exact user-requested Add until a fresh server-rendered cart has
    // established the baseline. No preload, guessed zero, or stale cached cart.
    event.preventDefault(); event.stopImmediatePropagation();
    const op = { context: key(context), pageURL: location.href, deadline: Date.now() + 45000 };
    operation = op;
    (async () => {
      let replayed = false;
      try {
        load();
        const before = await stable(op, () => true);
        if (!before || !valid(op)) throw new Error('baseline');
        const current = resolve(control);
        if (!current || JSON.stringify(current) !== JSON.stringify(product)) throw new Error('changed product');
        // Exact same still-connected control, exactly once. Never retry Add.
        discardFrame();
        bypass = control; replayed = true; control.click(); bypass = null;
        if (!valid(op)) return;
        // Let the retailer complete its Add before taking a new cart document.
        // Repeated reads below never repeat the retailer mutation.
        await pause();
        load();
        let after = null;
        for (let attempt = 0; attempt < 4 && valid(op); attempt++) {
          const observed = await stable(op, () => true);
          if (!observed) break;
          if (sameOthers(before, observed, product.id) &&
              observed.quantities.get(product.id) === (before.quantities.get(product.id) || 0) + product.amount) {
            after = observed; break;
          }
          // Only an unchanged basket can be waiting for the retailer request.
          if (fingerprint(observed) !== fingerprint(before)) break;
          for (let i = 0; i < 5 && valid(op); i++) await pause();
          if (valid(op)) load();
        }
        if (!after || !valid(op)) throw new Error('confirmation');
        const fields = { confirmationID: String(++sequence), productID: product.id,
          beforeQuantity: before.quantities.get(product.id) || 0, resultingQuantity: after.quantities.get(product.id) };
        confirmations.set(fields.confirmationID, { ...fields, context: op.context, pageURL: op.pageURL, before, after });
        post('cartInteractionStarted', { productID: product.id, beforeQuantity: fields.beforeQuantity,
          intent: fields.beforeQuantity === 0 ? 'add' : 'increment' });
        post('addDetected', fields);
      } catch (_) {
        if (operation === op && key(context) === op.context && location.href === op.pageURL && document.visibilityState !== 'hidden') {
          // Preserve ordinary website shopping after an unsupported preflight.
          // Do not replay an unverified or already-attempted Add as a fallback.
          disabled = true;
          post('automationUnavailable', { capability: 'cartDetection',
            reason: replayed ? 'quantityUnavailable' : 'cartPreflightUnavailable', scope: 'interaction' });
        }
      } finally {
        if (operation === op) { operation = null; discardFrame(); }
      }
    })();
  }, true);
  window.__listRunnerUndoAdd = async record => {
    const saved = confirmations.get(record.confirmationID);
    if (!config.capabilities.cartUndo || !saved || operation || !context || key(context) !== saved.context ||
        location.href !== saved.pageURL || record.storeID !== config.id ||
        record.sessionID !== context.sessionID || record.interactionID !== context.interactionID ||
        record.itemID !== context.itemID || record.documentGeneration !== context.documentGeneration ||
        record.productID !== saved.productID || record.beforeQuantity !== saved.beforeQuantity ||
        record.resultingQuantity !== saved.resultingQuantity) return false;
    confirmations.delete(record.confirmationID); // Single-use, including failure.
    const op = { context: key(context), pageURL: location.href, deadline: Date.now() + 45000 };
    operation = op;
    try {
      load();
      let state = await stable(op, () => true);
      if (!state || fingerprint(state) !== fingerprint(saved.after)) return false;
      let expected = saved.resultingQuantity;
      while (expected > saved.beforeQuantity && valid(op)) {
        // Recheck the whole basket immediately before every single decrement.
        const fresh = read();
        if (!fresh || fingerprint(fresh) !== fingerprint(state)) return false;
        const row = fresh.products.get(saved.productID);
        if (!row || fresh.quantities.get(saved.productID) !== expected) return false;
        const selector = expected === 1 ? contract.removeSelector : contract.decrementSelector;
        // Remove-all is permitted ONLY when exact live quantity is one and the
        // independently observed original baseline was zero.
        if (expected === 1 && saved.beforeQuantity !== 0) return false;
        const controls = [...row.querySelectorAll(selector)];
        if (controls.length !== 1 || !visible(controls[0]) || !enabled(controls[0])) return false;
        controls[0].click();
        const next = await stable(op, s => sameOthers(state, s, saved.productID) &&
          (s.quantities.get(saved.productID) || 0) === expected - 1);
        if (!next) return false;
        state = next; expected--;
      }
      if (!valid(op) || fingerprint(state) !== fingerprint(saved.before)) return false;
      // Verify persistence in a fresh cart, not just an optimistic local stepper.
      load();
      const verified = await stable(op, s => fingerprint(s) === fingerprint(saved.before));
      return !!verified && valid(op);
    } catch (_) { return false; }
    finally { if (operation === op) { operation = null; discardFrame(); } }
  };
  bridge.postMessage('automationReady');
})();
