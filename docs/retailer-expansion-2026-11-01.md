# Twenty-store expansion — evidence and remaining work

## Scope and authorization

The user requested search and add-to-cart detection for twenty additional popular
retailers and explicitly authorized test cart additions. This is **not** authority
to check out, purchase, sign in, change addresses/fulfilment/account settings, or
bypass retailer verification. Cart Undo is a separate capability and is not part
of this expansion.

**The complete search-and-detection request is not yet delivered.** Registration,
search and cart detection are separate milestones. Do not count a registered store,
a passing observational test, an Add button, an intended quantity, or a page-wide
cart badge as working automatic cart detection.

## Registration

The new permanent IDs occupy suffixes `000013`–`000032`, in the order below.
Existing IDs are unchanged. Each destination has its own saved list, persistent
website-data store and diagnostics/reset scope. New destinations start disabled.
All use the existing shopping/management flow and manual Mark Added/Skip controls.

| ID | Store | Country | Stable ID suffix |
| --- | --- | --- | --- |
| chemistWarehouse | Chemist Warehouse | AU | 000013 |
| priceline | Priceline | AU | 000014 |
| officeworks | Officeworks | AU | 000015 |
| jbHiFi | JB Hi-Fi | AU | 000016 |
| targetAU | Target Australia | AU | 000017 |
| petbarn | Petbarn | AU | 000018 |
| supercheapAuto | Supercheap Auto | AU | 000019 |
| bcf | BCF | AU | 000020 |
| bunningsNZ | Bunnings New Zealand | NZ | 000021 |
| theWarehouse | The Warehouse | NZ | 000022 |
| newWorld | New World | NZ | 000023 |
| paknsave | PAK’nSAVE | NZ | 000024 |
| sainsburys | Sainsbury’s | GB | 000025 |
| asda | Asda | GB | 000026 |
| morrisons | Morrisons | GB | 000027 |
| ocado | Ocado | GB | 000028 |
| waitrose | Waitrose | GB | 000029 |
| boots | Boots | GB | 000030 |
| walgreens | Walgreens | US | 000031 |
| cvs | CVS | US | 000032 |

Bunnings is one reviewed brand with isolated Australian and New Zealand regional
destinations, using the existing explicit region-confirmation mechanism. Australian
Target and US Target remain separate brands: their shared name does not establish
common ownership or shared accounts. There are 32 destinations and 30 brand rows.

Asda's old groceries host redirects to `www.asda.com/groceries`; both are explicitly
registered, with no wildcard hosts. Morrisons browsing is restricted to its
`groceries.morrisons.com` host, while website-data reset owns `morrisons.com` so
root-domain cookies are not missed. Data ownership is not navigation permission.

## Search verification

`LiveExpansionSearchTests/testReadOnlySearchRoutes` is opt-in via
`TEST_RUNNER_LISTRUNNER_LIVE_EXPANSION_SEARCH=1` in command-line Xcode runs. It uses
fresh nonpersistent iOS WKWebViews, GET-only exact-host top-level navigation and
no app cookies. Ordinary tests skip it. `_ONLY` selects a comma-separated subset;
`_REQUIRED` makes named failures fail the test. Observational runs otherwise pass
even when individual stores do not return products. Unknown/mismatched selections
are rejected.

At revision `a7c4a91df39d9ee66a94112a2ccfc39fea6c4f52`, iPhone 17/iOS 27.0
returned matching product links for Priceline (43), Officeworks (21), JB Hi-Fi (33),
Target AU (38), Supercheap Auto (28), Bunnings NZ (36), The Warehouse (32),
Sainsbury’s (43), Morrisons (3), Ocado (5), Waitrose (47), and Walgreens (24).
The other eight returned no matching links within the observation window.

**Superseded evidence:** the first Morrisons/Ocado probes used obsolete `entry=`
parameters. Desktop inspection showed Morrisons redirecting to its general
catalogue; matching milk products there did not prove a search worked. Their
corrected routes use `q=`. Subsequent probes must additionally require the query
in a visible heading or search input, not just matching product links.

At revision `d92df86339980d96fbe15b11df5f11db37cc6cec`, the corrected Chemist
Warehouse `/search?query=...&contexts=default` route returned 20 matching shampoo
product links. The seven other previously unverified candidates still returned
none. Both runs built and passed observationally, not as all-retailer certification.

Evidence lives on the Mac outside the checkout:

- `~/Library/Logs/ListRunner-Expansion-Search-a7c4a91.log` and `.xcresult`
- `~/Library/Logs/ListRunner-Expansion-Search-d92df86.log` and `.xcresult`
- `~/Library/Logs/ListRunner-Expansion-Search-eed5eec.log` and `.xcresult`

Desktop research established the following limitations/corrections; desktop
observations alone do not enable iOS capabilities:

- Petbarn's `/search?q=` is a not-found page. Its own search navigates to
  `/catalogsearch/result/q/{query}` and returns dog-food products.
- BCF searching `camping` redirects to a category whose products need not contain
  the word camping. Use a specific `camping chair` probe instead.
- New World and PAK’nSAVE showed security-verification challenges. No bypass was
  attempted and no automatic retry loop was used.
- Asda redirects its legacy grocery host to `www.asda.com/groceries/search/...`.
- Morrisons and Ocado display explicit milk results/headings using `/search?q=milk`.
- Boots returned no usable document in this environment; cause unconfirmed.
- CVS explicitly reports that the site is unavailable outside US/US territories.
  No geographic bypass was attempted.

## Cart investigation — no new detection certified

All twenty new destinations currently keep cart detection and cart Undo disabled
in both JSON and native ceilings. The existing detector engine is unchanged.
New store registration does not inherit another region's cart evidence.

Linux browser investigations used isolated, signed-out guest sessions:

- Chemist Warehouse: Sukin Natural Balance Shampoo 500ml (`85510`), quantity one
  was observed in its product-specific cart drawer and decremented to zero;
  `Your cart is empty` was observed. Its quantity is an input value rather than
  textual receipt quantity. No ListRunner trusted-tap detection was certified.
- Supercheap Auto: SCA Car Wash Concentrate 1 Litre (`733022`, $7.99), quantity one
  was added. The website displayed `Item successfully added to cart`, a product
  scoped `Added to cart (1)` state, and a cart line at quantity one. Removed only
  that test item; `Your Shopping Cart is Empty` was observed. No purchase or
  fulfilment choice was made. This is website functionality, not native detection.
- Priceline: PRO:VOKE Touch Of Silver Brightening Shampoo 50mL (`39390`, $2.99)
  was added and observed at quantity one in `My Cart`, then removed; the header
  returned to zero. Its modal exposes a product-specific numeric quantity input,
  not text matching the current receipt strategy. A subsequent retry did not
  establish an additional confirmed cart state; do not infer cleanup for an
  unconfirmed request. The isolated guest browser session was closed.
- Morrisons: attempting an inexpensive cucumber Add opened a delivery-location
  prompt, with login/registration needed for current availability. No location,
  login or cart addition was completed.
- Target AU: the towel product's Add To Basket controls were aria-disabled while
  stock checks failed. No attempt to override disabled controls was made.

A device-interaction verification attempt on two separate iPhone 18 Pro
simulators failed to connect/boot. SSH temporarily became unresponsive. Both
interaction sessions were closed, and only those two agent-started simulators
were shut down after SSH recovered. The existing iPhone 17 test simulator and
physical phone were not shut down/reset. No screenshot/UI assertion or live cart
certification follows from the failed sessions.

### Remaining acceptance work

- Certify search only with reflected query plus actual matching product results
  at the corrected, approved route; leave blocked capabilities off.
- For each retailer, record actual trusted-tap product-specific cart evidence in
  embedded iPhone WebKit. Preserve existing cart quantities and remove only our
  test additions. Never infer success from an intended quantity or global badge.
- Some stores have nonnumeric/slug product identities and some expose receipt
  quantity only in product-linked input values. These need explicitly reviewed
  shared strategies and negative DOM tests, not guessed per-store selectors or
  loosening numeric-identity validation. No such speculative extension was shipped.
- Add reviewed profiles and native ceilings independently, then verify native
  ListRunner status changes, stale/foreign/passive-event rejection and manual
  fallback. Retailer-cart Undo remains off.
- Complete Manage Stores/region/enable/manual-flow UI checks and physical-device
  sign-off. Do not install a build to a physical phone merely to claim testing.

## Mac reconciliation

The user approved preserving/reconciling the Mac's pre-existing project change.
Commit `8b0a640` preserves Xcode formatting and app bundle identifier
`com.adrianzafir.listrunner` (formerly `com.AdrianZ.ListRunner`). It was transferred
through Git and pushed from Linux because the Mac's HTTPS Git credential helper
was unavailable. No app was uninstalled or physical app data migrated/reset.
The identifier change can identify a different physical installation: confirm
the intended installed identifier before any future phone deployment.

Subsequent committed revisions were pushed to the shared GitHub remote and to a
Mac Git remote-tracking ref over SSH, then cleanly fast-forwarded. No folder
copying, scp, reset, clean, credential change or force push was used.
