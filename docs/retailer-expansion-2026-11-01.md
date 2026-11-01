# Twenty-store expansion — evidence and remaining work

## Scope and authorization

The user requested search and add-to-cart detection for twenty additional popular
retailers and explicitly authorized test cart additions. This is **not** authority
to check out, purchase, sign in, change addresses/fulfilment/account settings, or
bypass retailer verification. Subsequent authorization allows representative
postcodes (AU 3000, NZ 1010, UK SW1A 1AA, US 10001) and delivery/nearby pickup
selection in isolated guest sessions only. Full addresses, booked slots and saved
account-setting changes remain unauthorized. The original twenty must be kept.
Cart Undo is a separate capability and is not part
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

**Final support decision:** search is enabled for sixteen new stores: Chemist
Warehouse, Priceline, Officeworks, JB Hi-Fi, Target Australia, Petbarn, Supercheap
Auto, BCF, Bunnings New Zealand, The Warehouse, Sainsbury’s, Asda, Morrisons, Ocado,
Waitrose and Walgreens. New World, PAK’nSAVE, Boots and CVS remain manual/browsing
registrations with search off. No new cart detection is enabled.

`LiveExpansionSearchTests/testReadOnlySearchRoutes` is opt-in via
`TEST_RUNNER_LISTRUNNER_LIVE_EXPANSION_SEARCH=1` in command-line Xcode runs. It uses
fresh nonpersistent iOS WKWebViews, GET-only exact-host top-level navigation and
no app cookies. Ordinary tests skip it. `_ONLY` selects a comma-separated subset;
`_REQUIRED` makes named failures fail the test. Observational runs otherwise pass
even when individual stores do not return products. Unknown/mismatched selections
are rejected.

Priceline clears its visible search field and labels the heading `All products`.
Its separate opt-in `testPricelineDifferentialSearch` requires at least three
matching products for each of two unrelated queries (shampoo/toothpaste), at least
75% relevance in each complete named-product result set, the correct final query
parameter, and less than 50% overlap between the complete result sets. Merely
filtering a fixed general catalogue in the probe would not satisfy this check.

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
- `~/Library/Logs/ListRunner-Expansion-Final-f15dfe2.log` and `.xcresult`

The stricter `eed5eec` run verified query reflection plus matching products for
Chemist Warehouse (20), Officeworks (21), JB Hi-Fi (30), Target AU (38), Supercheap
Auto (13), Bunnings NZ (36), The Warehouse (32), Sainsbury’s (43), Waitrose (47) and
Walgreens (24). It rejected obsolete Morrisons/Ocado routes rather than certifying
their general catalogue, and left Priceline to its independent differential proof.

At code revision `f15dfe2185b41a595f0b8bd1792a2821da1170c4`, all three focused iOS
tests passed: Priceline differential search (12.188s, 36/36 relevant products for
each query and sufficiently distinct complete result sets), corrected search
routes (28.716s), and offline discovery of every new destination plus separate
Australian/US Target rows (152.960s). Corrected routes returned Petbarn 29, BCF 28,
Asda 3, Morrisons 49, and Ocado 46 matching products, all with reflected queries
and exact trusted hosts. This is simulator search evidence, not cart, login,
fulfilment or physical-device certification.

At that revision, 1,423 native recovery/configuration/encoding/reset/diagnostic
checks passed, and all 34 JSON files in the actual Debug simulator app byte-match
canonical resources. Linux checks: 78 existing DOM/cart regression tests, 90 core
tests plus TypeScript typecheck, 7 resource-verifier regression tests and 3 new
expansion resource/probe/project consistency tests passed. The test screenshot
`Separate Australian and US Target discovery` is retained in the xcresult.

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

## Cart investigation — four certified; sixteen remain

Priceline, Supercheap Auto, Ocado and Chemist Warehouse cart detection are certified and enabled in JSON and native ceilings.
The other sixteen new destinations keep detection disabled; all twenty keep
retailer-cart Undo disabled. The engine now supports schema-4 product-linked
receipt quantities, tightly allowlisted Priceline image identity, bounded captured
URL-component identities, and explicit quantity-free product acknowledgements.
Prospective profiles are not enabled production integrations.
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
   loosening numeric-identity validation. Reviewed schema-4 extensions now have
   focused DOM and native validation tests; live iPhone certification remains separate.
- Add reviewed profiles and native ceilings independently, then verify native
  ListRunner status changes, stale/foreign/passive-event rejection and manual
  fallback. Retailer-cart Undo remains off.
- Complete Manage Stores/region/enable/manual-flow UI checks and physical-device
  sign-off. Do not install a build to a physical phone merely to claim testing.

### Follow-up implementation and live evidence

- Waitrose native certification completed on the simulator build of `0ca7f554ce2b72296483c35ca0acaf2412b1e544`.
  Read-only isolated-world preflight confirmed schema 4, active cart detection,
  context receiver and unapplied-Update guard. Starting exact milk card had Add,
  no quantity field and trolley 0 items/£0.00. User tapped Add once: the observed
  product quantity became 1 with no draft Update, trolley 1 item/£1.75. Native
  isolated-session diagnostics recorded `automation/cartDetection/succeeded`
  (sequence 5), and a read-only query of that session's SwiftData store independently
  confirmed Waitrose's `Milk` item persisted as `Added`. No manual Mark Added was
  requested. User removed the single test quantity; inspection verified Add,
  no quantity field, no draft Update and trolley 0 items/£0.00. App was not restarted
  during this cycle. Production detection is now enabled; retailer-cart Undo stays
  off. This brings certified expansion detectors to five of twenty, not completion
  of the remaining retailers. Earlier research-only entries below are historical.

- Signed-in Waitrose research was performed in the existing nonpersistent app
  without rebuilding or restarting it. A bounded, read-only own-app debugger
  inspection emitted only the exact public milk card's DOM metadata, not account
  forms, credentials, cookies, storage, addresses, payments or API data. Debugger
  detached/resumed the app after every inspection. User's trusted tap added one
  Essential British Free Range Semi-Skimmed Milk 4 Pints (£1.75), composite product
  identity `053457-26759-26760`; observed actual card field value 1 with no unapplied
  Update and trolley 1 item/£1.75. User's minus tap restored Add, no quantity field,
  and trolley 0 items/£0.00. Cleanup verified, but **not native detector proof**.
- Prospective Waitrose profile uses observed `article[data-testid='product-pod']`,
  `h2[data-testid='product-pod-name']`, exact Add/plus test IDs and
  `input[data-testid='inputProductAmount']`. Its composite identity requires three
  bounded numeric components. Visible `trolleyUpdateButton` means an unapplied
  draft and blocks both arming and confirmation. Favourites, intended quantities,
  invalid identities and drafts have explicit negative fixtures. Production
  detection and retailer-cart Undo remain off until real native proof.

- Waitrose login-route check **passed** at `59cb76e`: reached a secure password
  field with no credential entry or cart action. However XCTest closed the app
  after completion even when explicit teardown was skipped. Its historical
  `LOGIN_HANDOFF_READY` marker is therefore **not a ready manual handoff**.
  Mac `~/Library/Logs/ListRunner-Login-Handoff-waitrose-59cb76e.*`.
  Future checks emit `LOGIN_ROUTE_VERIFIED` with `manualHandoffReady=false`.
  The actual user handoff must launch outside XCTest in valid-UUID nonpersistent
  browsing mode, then independently verify a visible form and a running app.

- Waitrose handoff `19a7079` did not reach login: native recovery alert appeared;
  isolated diagnostics recorded a network failure on the Waitrose host (domain
  classified `other`, no retained HTTP code). No credentials/cart mutation.
  Independent guest browser document trace then established the necessary flow:
  `/ecom/login` → `/api/token-client-prod/v1/auth` → exact
  `auth.waitrose.com/oauth2/authorize` → `/ecom/sign-in`.
  At `59cb76e`, that exact authentication host is allowed for browsing only;
  automation trust remains unchanged. Six native positive/refusal checks added;
  Mac recovery 1,461 + synthetic proof pass. A rerun must still verify that this
  resolves the live handoff; the observed missing hop is not itself a login pass.

- User authorized preparing Waitrose/Sainsbury's sign-in handoffs and confirmed
  access to the Mac Simulator. Separate DEBUG browsing-only opt-in uses a valid
  UI-test UUID and nonpersistent WebKit; it does not enable unverified detectors.
  Sainsbury's exact `account.sainsburys.co.uk` origin is browsing-only and is not
  trusted by the cart bridge (six native allow/refusal checks).
- Waitrose handoff `f94d743` failed before Sign in; no credentials or cart action.
  Its hidden/off-screen header link is not proof of a login-ready form. At
  `19a7079`, the isolated handoff can enter independently verified
  `https://www.waitrose.com/ecom/login` directly, still enforcing navigation trust.
  Mac recovery 1,455 checks + synthetic proof pass. Login readiness is pending;
  do not ask the user to type credentials until the live form is verified.
- `e0009b2` corrects remaining test navigation: Bunnings explicitly selects NZ;
  Officeworks recognizes its icon-only location/cart labels; JB anchors its real
  title text and excludes numeric price/rating links from product-contamination
  guards. These fixes are not retailer detection certification.

- **Chemist Warehouse native live PASS** at `101badc`: detected=true,
  cleanupVerified=true, exact authorized Sukin PDP Add and product decrement.
  Mac `~/Library/Logs/ListRunner-Finish-Cart-chemistWarehouse-101badc.*`.
  Four-store runtime follow-up: Chemist passed; JB/Bunnings NZ/Officeworks failed
  before any Add due to test navigation. All 34 actual bundled resources matched.
  Chemist production detection enabled afterward; retailer-cart Undo stays off.

- **Ocado native live PASS** at `38496f2`: automatic native confirmation and
  cleanupVerified=true, not skipped, 244.267s. Exact Ocado milk test card restored
  to Add by its decrement. Mac `~/Library/Logs/ListRunner-Finish-Cart-ocado-38496f2.*`.
  Production detection enabled afterward; retailer-cart Undo stays off.

- Additional fixture checks reject invalid/fractional/negative/out-of-range or
  decreasing actual quantities, and intended-quantity-only changes across all
  six quantity profiles. Full DOM suite: 216 passing tests.
- Ocado guest verification: Ocado British Semi Skimmed Milk 2 Pints (`78922011`,
  £1.20), actual card quantity 0→1→0, final Add and £0.00 trolley verified.
  No location selection/sign-in required. Independent prospective Ocado profile
  records its `to trolley` action text, not Morrisons' `to basket` label.
- Target AU hand-towel retry: initial Add disabled during stock loading, later
  enabled without overriding attributes. A trusted Add did not establish success;
  basket page explicitly reported 0 items. No product removal/checkout required;
  browser closed. Stock panels still said unable to check stock.
- Boots retry explicitly returned `Sorry, your access to this site is not possible
  at this time`; browser closed. No search/detector capability raised.
- JB native `b305bcf` stopped before Add after generic Close hit invalid geometry
  and dismissed the store sheet. Consent handling is now store-specific and
  rejects empty/infinite/out-of-safe-bounds frames.
- Chemist native `38496f2` stopped before Add while waiting for PDP navigation.
  A DEBUG-only direct-detail entry now lets a dual-gated, nonpersistent live probe
  verify the exact authorized product separately from already-reviewed search.
  Host trust is enforced; ordinary sessions and Release builds cannot use it.

- **Supercheap Auto native live PASS** at `b305bcf`: detected=true and
  cleanupVerified=true; XCTest passed (not skipped), 173.609s. A trusted Add for
  SCA Car Wash Concentrate 1 Litre (`733022`, $7.99) triggered native confirmation.
  View Cart → Remove restored `Shopping Cart is Empty` after cleanup scrolling.
  Mac logs/results: `~/Library/Logs/ListRunner-Finish-Cart-supercheapAuto-b305bcf.*`.
  Enabled production detection afterward; retailer-cart Undo remains disabled.
- Chemist Warehouse `b305bcf` stopped before Add: initial product link was not
  visibly navigated to the detail page. No mutation. Test now reveals and validates
  that link and waits for the product page's Add before looking for its control.
- Morrisons later retry **supersedes the address-selection blocker below**:
  explicitly scrolled exact authorized suggestion into view, selected it, checked
  the exact address in the location summary, and confirmed guest Home Delivery.
  No name, sign-in, slot booking or checkout. Belvita Milk & Cereal multipack
  (`109427121`, £1.25) added once; `input[data-test='quantity-in-basket']` was 1
  in that exact card, then its decrement restored Add and £0.00 trolley.
  Browser closed. Prospective numeric card profile awaits native proof. Its Add
  has product-specific ARIA text and visible `Add`; schema-4 baseline accepts the
  reviewed visible text only when the configured accessible action also matches.
- Correctly scrolled Add attempts: Sainsbury's and Waitrose redirect to sign-in;
  ASDA blocks access. No confirmed additions, no authentication/security bypass.

- **Priceline native live PASS** at `b01ff2835732d0940f1c8024b1cf74b1cfe7a832`:
  `LIVE_CART_NATIVE_PROBE store=priceline, detected=true, cleanupVerified=true`.
  On existing iPhone 17/iOS 27 simulator, trusted Add for PRO:VOKE Touch Of Silver
  Brightening Shampoo 50mL (`39390`) triggered native ListRunner Undo without
  tapping Mark Added. Test removed that guest item and verified removal.
  XCTest passed (not skipped), 533.694 seconds. Evidence:
  `~/Library/Logs/ListRunner-Finish-Cart-priceline-b01ff28.{log,xcresult}` on Mac.
  Production detector enabled afterward; retailer-cart Undo remains disabled.

- `3ef44f8c59c9068980c73037b7249493bbcdfa31`: prospective Priceline and
  Supercheap profiles, schema-4 foundations and isolated live-test gate. The gate
  requires a valid UI-test UUID, an explicit single-store opt-in and nonpersistent
  WebKit storage. Ordinary tests remain offline; production ceilings remain off.
- `94650b0`: Chemist Warehouse PDP quantity profile and JB Hi-Fi explicit
  acknowledgement, with no fabricated quantities and no retailer-cart Undo.
  Mac recovery passed 1,453 checks and synthetic store proof. Focused DOM tests
  include hidden/stale/error/ambiguous receipts, recommendations outside the
  confirmation, unrelated clicks and unsafe captured identities.
- First native Priceline/Supercheap tests at `3ef44f8` compiled but failed before
  any Add: Priceline query became `PRO`; Supercheap default gestures hit the native
  overlay. Corrected query and unobscured-coordinate gestures are in `94650b0`.
  Priceline rerun launched on existing iPhone 17; no result recorded yet.
- Linux guest Priceline and Supercheap test carts were restored to zero and closed.
  Chemist Warehouse test cart returned to $0.00 with its PDP Add state restored.
- JB Hi-Fi: Belkin Hi Speed USB Cable (1.8 Metres), $8, explicit
  `Item added to your cart!` plus product title in `slideout-added-to-cart-alert`.
  Its static pre-existing `Added` button span is not success evidence. Removed
  through Review cart → Remove; `Your cart is empty...` verified; browser closed.
- Officeworks: the pending $1 Keji pen-pack Add resumed after guest postcode 3000
  setup. `confirmation-page` showed `We’ve added it to your cart` and exact product
  title. No duplicate Add was performed. View Cart → Delete returned header to
  zero; browser closed. Prospective acknowledgement profile awaits native proof.
- Bunnings NZ: Craftright 8oz Steel Claw Hammer (`5660292`, NZ$4.98), actual
  per-card quantity input changed to 1 following Add. Product-specific decrement
  restored Add state and quantity zero; browser closed. Prospective quantity
  profile awaits native proof and is not borrowed from Bunnings AU certification.
- Morrisons retry: Add opened location search. Entering approved postcode
  SW1A 1AA returned only complete-address choices, not postcode-only choices.
  None selected, no Confirm location, no Add completed. Modal and browser closed.
  A specific full-address authorization/login handoff is needed to go further.
- User subsequently supplied a specific UK address and authorized its guest
  location selection. Exact address was found in Morrisons' postcode suggestions,
  but choosing it left the location summary on an unrelated default postcode
  (`AL10 9BW`). That mismatched location was not accepted as verified setup; no
  delivery-method confirmation, slot, checkout or purchase followed. Closed modal
  and browser. Do not record the supplied person's name/address in tracked code.
- BCF: Gillies Split Shot Sinker dial pack (`109293`, $10.99), one guest Add
  produced only a generic `Item successfully added to cart` dialog; requested PDP
  quantity remained 1 and was not treated as actual cart quantity. Cart page
  verified exact product quantity 1. Remove restored `Your Shopping Cart is Empty`;
  browser closed. No BCF detector enabled from that generic receipt.
- Native Priceline `94650b0` and `1cd63da` reruns failed before any Add. First
  still encountered cookie controls under native overlay; second dismissed consent
  but re-expanded cards before dragging, again covering gesture origin. `fa4ba64`
  keeps cards collapsed for website interaction and expands only to inspect native
  confirmation. Its rerun is pending. None of these failures certifies detection.
- Linux full DOM suite: 148 tests passed; core: 90 tests and typecheck passed.

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
