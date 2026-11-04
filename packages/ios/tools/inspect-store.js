// Read-only DOM inspection. This function never clicks, submits, fetches, reads
// cookies/storage, or returns page HTML/account fields. Used by native XCTest.
options => {
  const visible = element => {
    if (!element || !element.getClientRects().length) return false;
    const style = getComputedStyle(element);
    return style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity) !== 0;
  };
  const query = options.query.toLocaleLowerCase().trim();
  const terms = query.split(/\s+/).filter(Boolean);
  const matches = text => terms.every(term => text.toLocaleLowerCase().includes(term));
  const pick = selector => [...document.querySelectorAll(selector)].filter(visible);
  const all = pick(options.productSelector);
  // Do not silently truncate a catalogue and then claim a relevance percentage.
  const overflow = all.length > 500;
  const products = new Map();
  for (const link of all.slice(0, 500)) {
    const name = (link.textContent || link.getAttribute('aria-label') || '').trim();
    const raw = link.getAttribute('href');
    if (!raw || !name) continue;
    const url = new URL(raw, location.href);
    if (url.protocol !== 'https:' || url.origin !== location.origin || url.username || url.password) continue;
    const path = url.pathname; // never return tracking queries or fragments
    products.set(path, (products.get(path) || false) || matches(name));
  }
  const paths = [...products.keys()].sort();
  const matching = [...products].filter(([, match]) => match).map(([path]) => path).sort();
  const reflected = pick(options.querySelector).some(element => matches(element.value || element.textContent || ''));
  const controls = pick(options.addSelector).slice(0, 40).map(element => ({
    tag: element.tagName.toLowerCase(), disabled: Boolean(element.disabled),
    hasProductContainer: Boolean(element.closest(options.containerSelector))
  }));
  const blockers = pick('[role="dialog"],[aria-modal="true"]').slice(0, 10).map(element => {
    const text = (element.textContent || '').toLocaleLowerCase();
    if (/cookie|consent/.test(text)) return 'consent';
    if (/captcha|verify|verification|robot/.test(text)) return 'verification';
    if (/postcode|zip code|location|delivery/.test(text)) return 'location';
    return 'dialog';
  });
  return {origin: location.origin, path: location.pathname, queryReflected: reflected,
    productCount: paths.length, matchingCount: matching.length, paths, matching,
    overflow, controls, blockers, strategyFit: 'requires-review', cartVerification: 'not-performed'};
}
