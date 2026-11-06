# ListRunner iOS

Native SwiftUI app targeting iPhone on iOS 17 or later.

Open `ListRunner.xcodeproj` in Xcode, choose an iPhone simulator, and run the `ListRunner` scheme. This is a native SwiftUI/SwiftData iOS 17 app, not the removed Capacitor app.

Nightly cloud archive configuration, offline gates and first-run caveats are in
`XCODE-CLOUD.md`. The cloud workflow remains disabled until explicitly enabled;
repository scripts alone do not activate a schedule or distribute to testers.

## Keeping the Linux and Mac checkouts aligned

Use Git commits and `git pull --ff-only` to transfer changes, not whole-folder overwrites. Both working checkouts should use `main` at the same commit before further work; commit or otherwise preserve local edits before pulling. The canonical store JSON files are under `ListRunner/Resources`, and the shared Xcode project references these directly. Do not recreate the old duplicate `Resources 2`–`Resources 5` or `*-v2.json` copies. The signing team and app bundle ID remain in the shared project; certificates, provisioning profiles and Xcode user state remain machine-local.

The active Mac checkout is `/Users/adrianzafir/Projects/listrunner`, outside iCloud-managed Documents. Open its `packages/ios/ListRunner.xcodeproj`, not the older project under `Documents/Codex/2026-10-21/set-up-a-mac-local-xcode/listrunner`. The older folder is retained for recovery: iCloud replayed older file contents after a successful Git pull, so it is not a reliable working checkout. The preexisting `~/Projects/listrunner` directory (Finder metadata and an empty `test` folder, not a Git checkout) was preserved intact under `~/listrunner-backups/20261029T013952Z/preexisting-projects-listrunner` before placing the verified checkout here.

The Mac state before reconciliation is preserved on `backup/mac-before-sync-20261029`, including its extra source/resource copies, project layout and launch asset variant. Pre-sync archives were also saved outside each checkout under `listrunner-backups/20261029T013952Z` in the corresponding user's home directory; the Linux backup directory contains both archives.

Keep Xcode Derived Data in its default `~/Library/Developer/Xcode/DerivedData` location, or another build directory outside the checkout and iCloud Drive. A generated compiler-cache file inside `work/DerivedData` previously advertised a 24 GiB logical size and overwhelmed cloud downloads. Git ignore rules prevent generated files from being committed, but **do not stop iCloud from syncing them**. Machine-local Finder/Xcode user state is ignored separately. Git synchronization does not synchronize app lists, cookies or iPhone data.

### Handoff in either direction

One session owns a writable task checkout. For independent simultaneous tasks, use separate task branches/worktrees. The sender reviews the diff, stages explicit files, commits and pushes the task branch, and records its branch, full `git rev-parse HEAD` SHA and validation results. The receiving machine first inspects `git status --short --branch`, `git remote -v` and its current SHA. If dirty, stop and preserve that work. Then `git fetch origin`, check out the agreed task branch, fast-forward only when appropriate, and confirm `git rev-parse HEAD` equals the supplied SHA before building. Divergence requires review, not reset/force-push. A Mac-side fix follows the same commit/push handoff back to Linux before Linux resumes editing that task.

Before significant work or reconciliation, repeat a separate timestamped backup of local commits, uncommitted files and relevant ignored files outside the checkout/cloud. Exclude generated dependencies/build caches, but preserve unique scratch work and local settings privately. The migration archives are verified recovery snapshots, not an automatic ongoing backup service. Never commit secrets, signing credentials or provisioning profiles.

After a Mac build, verify the actual app bundle, not just build success:

```sh
python3 -B packages/ios/tests/test-bundled-resources.py
python3 -B packages/ios/tests/verify-bundled-resources.py /absolute/path/to/ListRunner.app
```

The verifier requires every canonical JSON file (including Bunnings) to be byte-identical in the built app and rejects legacy `*-v2.json` copies. Build output must stay outside the checkout. Run the focused parser/native/DOM checks as appropriate and record the exact committed revision tested. Device installs must preserve existing app data; retailer cart mutations require fresh authorization.

## Current implementation

### IKEA Australia

IKEA (`ikeaAU`) joins the shared store catalogue with Australian discovery,
blue/yellow branding, its own persistent list and website-data IDs ending
`000033`, and the existing enable/settings/diagnostics/reset flow. It starts
disabled. Search uses `https://www.ikea.com/au/en/search/?q={query}`. Only exact
Australian `/au/en/` HTTPS destinations on `www.ikea.com`/`ikea.com` are trusted;
other countries and unreviewed authentication origins are not integrated.

Its schema-5 `verifiedCartSnapshot` engine is bundled separately in
`Resources/CartSnapshotAutomation.js`. Unlike the older passive detectors, this
engine holds an exactly identified real Add tap while it reads a fresh rendered
cart, then sends that same requested control once. It verifies eight-digit article
numbers, linked identities and stable actual basket quantities, not the intended
quantity or IKEA's family-only toast. Complete before/after snapshots must differ
only by the requested article quantity. Cart reads use a sandboxed, off-screen,
same-origin frame; there are no private API calls or background polling. An
unsupported preflight reports that Add was **not sent** and allows subsequent
ordinary website shopping with manual status controls. It never retries an Add.

Undo requires a fresh unchanged basket and single-use confirmation provenance. It
decrements only the exact article and newly added quantity, preserving original
and unrelated quantities. Removing the last unit is permitted only with a proved
zero original baseline. A new cart document must confirm the full restored basket.
The native progress indicator remains visible during reversal; uncertainty uses
the existing cart-Undo warning. Composite/multi-article bundles and unsupported
layouts fall back to manual shopping. Other retailers retain their current engines.

Search, production cart detection and retailer-cart Undo are enabled after
independent native live verification. Both grid and detail cycles automatically
marked the row Added, completed retailer Undo without a warning, and independently
displayed an empty bag afterward; no Mark Added or manual removal was used.
Essential-only consent was selected in isolated guest sessions. Full evidence,
including the earlier test-navigation failures, is recorded in `VALIDATION.md`.
Offline coverage is in `tests/ikea-cart-snapshot.test.mjs` and
`tests/RecoveryTests.swift`; ordinary tests never contact IKEA. The explicit
`testLiveStoreCartIKEAGrid`/`testLiveStoreCartIKEADetail` probes require
`TEST_RUNNER_LISTRUNNER_LIVE_CART_STORE=ikeaAU` plus the separately authorized
`TEST_RUNNER_LISTRUNNER_LIVE_IKEA_ESSENTIAL_COOKIES=1` through xcodebuild and use
isolated guest storage. They reject optional cookies and stop on an unreviewed
consent category. Resource/archive verification audits the JavaScript byte-for-byte
as well as every canonical JSON file.

### Twenty-store expansion (1 November 2026 — partial delivery)

Native store definitions use retailer JSON schema 7 for one required category per
destination (33 destinations, including IKEA AU). Schemas 2–5 remain readable with
category unknown; schema 6's multi-category arrays remain readable without assigning
a primary category by array order. Categories do not grant automation or alter
discovery. Schema-6/7 definitions preserve their previous automation-rule version
separately so the metadata upgrade does not change detection behavior. The taxonomy and full assignment are in
`../../docs/store-categories.md`. This JSON format version is independent of the
SwiftData shopping-list schema.

The All items scope reads existing store lists without creating a shared basket. It
uses the same `ShoppingListPage`, header/scope picker, toolbar, summary, product-entry
section and item-row components as store lists. Only the top header stays pinned;
counts, entry, grouping and rows scroll together. Shared keyboard reveal keeps the
entry card usable while typing. Its split Add supports remembered grouping/destination/draft, shared manual-add
staging and the existing destination-captured import flow. Shopping sheets retain
store-owned queues and return to All items. UUID-based promotion order is stored in
app preferences, with no shopping database schema change. Disabling or replacing a
store/region with saved items is blocked until they are explicitly moved or cleared;
lookup/save failures and in-flight imports fail closed. Unavailable and unknown-owner
rows remain recoverable. See `VALIDATION.md` for Mac build/native/UI evidence and
remaining manual accessibility/design-reference checks; Linux cannot run the iOS target.

Twenty additional AU/NZ/GB/US destinations are registered, disabled by default,
with independent saved lists, website sessions and diagnostics/reset scopes.
Bunnings has explicitly isolated AU/NZ regional destinations; Target Australia
is separate from unrelated Target US. Existing store identities and lists are
preserved. That expansion introduced 32 destinations and 30 brand rows; IKEA
Australia brings the current catalogue to 33 destinations and 31 brand rows.

Automatic search is enabled only for independently reviewed routes. Unverified
searches remain off. **Priceline, Supercheap Auto, Ocado and Chemist Warehouse cart detection are live-verified and enabled;
the other sixteen new detectors and all twenty retailer-cart Undo capabilities remain off**;
registration is not certification of the user's full search-and-detection request.
Manual controls remain available. Evidence, corrected retailer routes, verification
barriers and remaining cart implementation work are recorded in
`../../docs/retailer-expansion-2026-11-01.md` and `VALIDATION.md`.

`LiveExpansionSearchTests` uses opt-in, nonpersistent iOS WebKit probes. It checks
real matching product links plus visible query reflection; Priceline has a separate
two-query result-set check. Observational test success does not mean every retailer
passed. `testExpansionStoreDiscoveryAndSeparateTargetBrands` is an offline UI check.
Schema-4 profiles cover Priceline, Supercheap Auto, Chemist Warehouse,
JB Hi-Fi, Officeworks, Bunnings NZ, Petbarn, Morrisons and Waitrose; only Priceline,
Supercheap Auto, Ocado, Chemist Warehouse, Waitrose, JB Hi-Fi, Bunnings NZ and Officeworks are production-enabled after native live proof.
User-facing store lists offer only destinations with verified search enabled.
Amazon US, Costco US, New World, PAK’nSAVE, Boots and CVS are temporarily
hidden from discovery/search, the chooser and regional options. Their registration,
implementation, saved lists, website sessions and raw preferences remain intact.
Costco AU stays available; a hidden active US region never silently changes to AU.
An available enabled store is selected instead, or the returning-user no-stores
state is shown. Saved flags can become effective again when support is improved.
Quantity-free acknowledgements never invent before/after totals and
cannot reverse the retailer cart. Opt-in `testLiveStoreCart…` tests require
`TEST_RUNNER_LISTRUNNER_LIVE_CART_STORE=<store>` when launched through xcodebuild.
They use isolated guest storage and must verify cleanup as well as automatic
native status changes. Ordinary tests do not contact retailers.
For the explicit Officeworks storage-compatibility experiment only, a DEBUG
launch may also set `LISTRUNNER_LIVE_PERSISTENT_PROBE=officeworks` alongside
`LISTRUNNER_LIVE_CART_PROBE=officeworks` and a valid `LISTRUNNER_UI_TEST_SESSION`.
Only Officeworks gets a named persistent website store identified by that test
UUID; canonical website/list IDs and the zero UUID are rejected. Probe activation
also verifies the actual store identifier, rejecting the default or any unrelated
persistent store. Other test retailers remain nonpersistent; Release behaviour is
unchanged. This experiment is not evidence that temporary storage caused the bug.
Do not sign in or leave test items behind; retain the isolated identifier for any
later targeted test-store cleanup, never clear normal retailer stores as cleanup.
User-operated sign-in handoffs have a separate browsing-only opt-in:
`TEST_RUNNER_LISTRUNNER_LIVE_LOGIN_STORE=waitrose` (or `sainsburys`) with
`testLiveStoreLoginWaitroseHandoff` / `testLiveStoreLoginSainsburysHandoff`.
These verify a real login form in nonpersistent test storage; XCTest closes the
app afterward. A manual handoff must launch the isolated setup outside XCTest
and independently verify that the form remains visible and the app is running.
The checks never enter credentials, Add products, or certify authentication/detection.
Sainsbury's exact account origin and Waitrose's observed authentication redirect
are allowed for browsing only, never cart automation trust.
Linux-compatible resource/probe/project consistency checks run with:

```sh
python3 -B packages/ios/tests/test-store-expansion.py
```

### US retailer expansion (30 October 2026)

The catalogue now contains the approved Walmart, Amazon US, Costco US, Kroger and Target US set. Amazon, Kroger and Target are new disabled-by-default registrations with independent saved lists, named persistent website-data stores, diagnostics/reset scopes and US country grouping. Costco US retains its existing regional identity and shares only the discovery brand with Costco Australia. Amazon US means Amazon.com, not a verified Amazon Fresh/Whole Foods integration; Kroger's other banners and Australian Target are not included.

Walmart, Kroger and Target US enable automatic item search after read-only live iOS WebKit probes returned matching milk products. Amazon US and Costco US remain browsing/manual-only: Amazon verification blocked results, and Costco did not populate products. All five retain manual progression; cart detection and retailer-cart Undo stay disabled in configuration and native policy pending separately authorized verification. Amazon/Costco search templates are dormant, not active integrations. The exact bare/`www` US domains are registered, not arbitrary login subdomains or third-party delivery services. Existing lists/logins/visibility are unchanged. See `VALIDATION.md` for evidence and remaining work; search evidence does not certify sign-in, all queries, fulfilment or delivery coverage.

`LiveUSSearchTests` is an explicit opt-in, read-only iOS WebKit probe using nonpersistent data stores and GET-only exact-host navigation. Ordinary UI tests skip it. It records visible product links and a matching milk product without touching account settings, sign-in or carts. A recorded probe outcome alone does not certify login, cart detection or cart reversal.

### Import source setup (30 October 2026)

**Simplified controls:** Reminders list and Remove reminders after import now live on **Import from Paprika**, reached through the source chooser (including Settings → Import source → Paprika). Top-level Settings no longer duplicates these controls. The screen shows brief export guidance, both controls, a mode-specific consequence and **Import to [store]**; supplementary guidance/help is collapsed under **More about importing**. Earlier Settings → Reminders list references below describe the old location, not the current UI. Preferences and import safeguards are unchanged.

**Named export lists:** imports now ask which Apple Reminders list to read and remember its calendar identifier, not its title. `Paprika` is suggested but never automatically selected; named grocery lists and custom export names are supported. Settings → Reminders list changes the selection without importing. Duplicate names show their accounts; missing IDs reopen selection without falling back. Instructions and removal results name the selected source. Only that list is read/cleaned up; read-only choices are disabled while removal is enabled. Existing installs must choose once. This supersedes the older exact-name requirements below.

**4 November revision:** Settings → Importing → **Remove reminders after import** defaults on, including existing installs. Import first saves groceries, then removes their readable, unchanged, unchecked source reminders. Existing saved IDs allow removal retries without reimporting those IDs. Removal failures leave saved groceries intact and explain retry. This mode suppresses linked-reminder writeback. Turning it off restores the keep/link/writeback behavior described below. Toggling alone never deletes anything; local-data reset restores the default. Instructions and results adapt to the preference. Paprika re-exports create new IDs and may duplicate groceries in either mode. Removal never deletes the Reminders list or changes Paprika. The export-guide link now targets `#grocerylistactions`.

The list initially offers **Import items...**, which opens **Import items**. Keep this chooser for future verified sources; currently only **Paprika — Via Apple Reminders** is available. Instructions explain **Groceries → Actions → Export to Reminders**, the exact `Paprika` destination name, and the selected store destination. **Import groceries** returns directly to Your list and starts importing, including when opened through Settings. Only that explicit action requests Reminders access. Paprika is remembered app-wide after a successful committed import, not merely visiting instructions or attempting a failed import.

Once remembered, **Import from Paprika** invokes the immediate, store-scoped EventKit import: no preview, selection step or automatic store presentation. There is no nearby Change source button. The preference persists across relaunch/store changes. Settings → **Import source** reopens the chooser/instructions; backing out changes nothing. Instructions include permission purpose and a **How updates work** disclosure explaining snapshot imports and best-effort linked-reminder updates, not Paprika sync. No other sources or speculative integrations are offered.

Success announces the added count and store destination, plus already-imported reminders where applicable. Empty outcomes distinguish no unchecked groceries, already-imported reminder IDs, and unreadable new titles. Recovery offers **View instructions** and **Try again**; denied/write-only Reminders permission also offers **Open Settings**. Generic access failures do not claim that changing permission will fix them. All outcomes preserve existing rows/drafts and do not open the retailer.

Existing grocery rows, statuses, quantities, drafts, reminder links and retailer sessions are unaffected by source setup. There is no database migration: existing installations show setup once unless this new preference is already saved. Unknown source values return to setup rather than silently importing Paprika. Confirmed Reset Local Data clears the source preference; diagnostics clearing, list clearing and retailer session resets do not. Reminders permission and transactional import/deduplication/writeback behaviour remain unchanged.

### Alternate Settings navigation (29 October 2026)

Main Settings now contains Manage Stores and **Country**, with no individual store rows. Manage Stores lists enabled brands first, followed by disabled brands matching the country and other disabled brands. Enabled brands are never repeated in the discovery groups. Empty groups disappear; search still finds every brand and regional name. The native right-hand letter index remains; the ABC toolbar menu is removed.

Each store row opens its complete settings, even when disabled. **Enable store** and (where applicable) **Region** appear first, followed by the selected region's included support, session status, session reset, diagnostics and About. Changing region retains explicit confirmation and refreshes the settings to that region's isolated session; country changes do not switch an enabled region. Earlier descriptions below of inline management switches, a country row in Manage Stores, or enabled-store rows on main Settings are superseded by this alternate hierarchy.

Revision `e5f6d1634f828ba158f9ee4c98b31e90418bd366` passed 287 native checks and a signed Mac/Xcode device build, and was installed in place and launched on the physical iPhone for user review. Automated UI checks and visual/accessibility sign-off remain pending; see `VALIDATION.md`.

- Add one or many items from comma-, newline-, and bullet-separated text.
- Native product-entry focus changes are coalesced onto the next main-queue turn, outside SwiftUI's layout-update animation suppression, so defocusing permits the system keyboard dismissal animation. Queued focus changes read the latest binding and ignore detached/dismantled editors; no custom duration or forced animation overrides system accessibility preferences. Return interception, empty-Return dismissal, Add Items focus retention and draft preservation remain unchanged.
- Parse common counts, multipliers, and grocery units; unrecognized entries are retained as names.
- Merge typed duplicates by normalized name and compatible units; persist one active list locally with SwiftData.
- Review status totals, edit item name/quantity/unit, delete rows, and choose which list items to clear.
- Clear List always presents the native action dialog: **Clear Added** removes only Added rows (hidden when the current store has none), **Clear All** removes every row, and Cancel preserves the list. Pending/Skipped rows and their relative order survive Clear Added; a surviving selection is retained or replaced with a remaining Pending item. Neither option changes another store's list, retailer carts or Apple Reminders.
- Select independent retailer lists using the native Store picker, including Tesco UK; selected store and per-list selected items survive relaunch. Visibility and Shopping country are app-local settings. Newly introduced stores start hidden until enabled in Manage Stores.
- Open the selected retailer in a persistent-data WKWebView sheet with native item cards and manual Mark Added, Skip, Next, Pause, Undo, and Finish controls.
- The overlay's reload button returns to the selected item's original product search instead of refreshing the current product/cart page. It uses the saved search term with current regional naming, retains navigation pacing/verification protections, and does not change local item status. Browsing-only stores return to their trusted homepage rather than enabling unsupported search.

This is an implementation slice, not the release-complete MVP. Selecting an item starts that store's configured URL-template search only when validated configuration enables it. Detection requires a trusted user action and correlated product-specific evidence, and updates only the selected ListRunner item. Native ceilings independently restrict search, detection and retailer-cart Undo. Tesco UK now supports grid detection and normal signed-in cart Undo, plus the acknowledgement-only sign-in continuation described below. Invalid configuration disables automation but keeps trusted-homepage browsing and manual controls. Shopping country is a saved preference, not location detection; no distance, delivery, stock, or postcode coverage is inferred. Remaining release checks and live-certification limits are recorded in `VALIDATION.md`; fixture/XCTest results are not live-retailer certification.

A supported automatic-add Undo immediately restores the recorded ListRunner status. Its transient record retains the session, interaction, document generation, item, product, before/after quantities, and isolated-script confirmation ID. For Coles, the script must still retain that exact confirmation, and the current product quantity must equal the recorded after value. Only then can Undo click the product tile's supported `Decrease … quantity by one` button, confirming each decrement twice and preserving the pre-existing quantity. Reversal has a three-second script deadline and a four-second native timeout; it does not retry uncertain clicks. A new user click, changed interaction, navigation, or store dismissal stops further decrements. Repeated adds replace cooldown Undo with the latest add; final confirmation retains its original Undo. Woolworths local Undo never requests store reversal. Manual Mark Added never requests store reversal. Missing controls, stale context, changed quantities, or unconfirmed Coles reversal show a dismissible `Could not undo store cart change` notice without undoing the local restoration. This remains a supported-product-tile strategy, not general cart or product-detail-page automation; live Coles reversal still needs device verification.

Manual Mark Added advances immediately when pending items remain, without a countdown; the final item retains Undo / Finish. A confirmed automatic Coles add shows a three-second Undo cooldown before advancing; final automatic adds retain Undo / Finish. Revisiting an Added item offers Mark Pending in the same card-button position. It restores Pending locally, keeps the item selected, clears any paused confirmation, and never removes products from the Coles cart. After finishing a completed run, Mark Pending can reopen it. Pause is reserved for an active automatic-add countdown.

On Your list, tap Edit to use native iOS row reordering. The row's three-dot menu offers Mark Added for Pending items, Mark Pending for Added items, and Mark Skipped for non-Skipped items. These actions change ListRunner status only and do not edit retailer baskets.

## Ingredient dictionary

`Lemon Tree` is a distinct dictionary entry (including `lemon trees`), so the longer product name wins over the nested `Lemon` match. New typed/imported entries retain `Lemon Tree` in both the saved name and search term, with quantities preserved, and do not merge into ordinary Lemon rows. Already-saved names are not rewritten: the app cannot infer which old Lemon rows originally meant trees.

### Country-based retailer search names

Settings → **Use local ingredient names** defaults on and uses the existing **Country**, not the retailer's country. The bundled `ingredient-regional-names.json` currently covers five reviewed families across AU/NZ/GB/US: zucchini/courgette, eggplant/aubergine, capsicum/bell pepper, rocket/arugula and beetroot/beet. UK uses **bell pepper**, not ambiguous **pepper**. Searches in other countries, with no country, or with the toggle off use the saved search term unchanged.

`RegionalIngredientSearchResolver.swift` changes only an ingredient span in an app-initiated search. Approved surrounding descriptors (fresh/frozen/organic, colours, sizes, baby, whole and gluten-free) retain their exact spelling and spacing. Unknown brands, composite foods, conjunctions and uncertain ingredient combinations are left alone. Coriander/seed distinctions, yam/sweet-potato and pumpkin/squash substitutions are deliberately not included. There is no AI/network lookup or unit conversion.

Saved names/search terms, quantities, item identity, status, duplicate merging and Reminders are never rewritten. Existing items work immediately without a database migration. Existing parser canonicalisation still applies on input: disabling this feature uses the saved query, not the pre-parser recipe text. Country/toggle changes cancel obsolete queued/preloaded searches but do not navigate the visible page or reset the interaction/cart state. The next explicit search uses the new preferences; stale recovery falls back to the trusted store homepage. Browsing-only stores remain browsing-only.

To extend coverage, add an explicit reviewed source/target family tied to an existing ingredient ID; do not blindly copy every parser alias. Each source must have one owner in the dictionary, and every country target must be one of that family's reviewed sources. Add fixtures for every target, qualifiers, compound protection and ambiguity. Unsupported schema/invalid resources disable only rewriting. The Xcode project must bundle the JSON; the built-app resource verifier checks it automatically.

Focused checks (from the repository root):

```sh
sh packages/ios/tests/run-regional-search-tests.sh
sh packages/ios/tests/run-parser-tests.sh
bash packages/ios/tests/run-recovery-tests.sh  # Mac: SwiftData/WebKit
python3 -B packages/ios/tests/test-bundled-resources.py
```

The UI tests `testRegionalSearchBrowserChecks`, `testRegionalSearchTogglePersistsAndLeavesExistingItemUnchanged` and `testRegionalSearchCountryChangeUpdatesCachedBrowser` use isolated preferences/nonpersistent WebKit and local HTML fixtures only. The browser test checks actual deferred requests, localized preloads/promotion, context cancellation, stale recovery and browsing-only capability gates, without retailer access. The UI flows verify the same cached browser uses changed Country/toggle preferences without restarting, and that the toggle persists across relaunch.

The bundled `ListRunner/Resources/ingredients.json` recognises 69 named pasta shapes/varieties as well as generic pasta. Coverage includes long and ribbon pasta, tubes, spirals, bows, shells, small soup pasta, lasagne sheets, filled pasta and gnocchi. Alternate names/spellings resolve consistently, such as orzo → Risoni, bow-tie pasta → Farfalle, and fettuccini → Fettuccine. Specific fillings, egg tagliatelle, and common gluten-free/wholemeal qualifiers stay distinguishable rather than all becoming generic pasta.

The parser checks ingredient identity as well as quantities, so `500 g penne pasta` resolves to Penne rather than an ambiguous Penne + Pasta match. Alternatives such as `penne or rigatoni` remain ambiguous. `tests/pasta-parser-fixtures.json` covers the pasta cases, and the parser runner also checks every name/alias for those fixture ingredients. Dictionary updates affect newly parsed text/imports; they do not rewrite existing saved items or select retailer products.

## Store configuration and list ownership

### Page-specific cart detection profiles (schema 3)

Schema 2 store files retain the legacy detector unchanged. Schema 3 opts into `cart.strategy: "profiled"` and a nonempty `cart.profiles` array. Each profile declares a stable `id`, `scope` (`productCard` or `productPage`), `identity` (`cardLink` or `pageURL`), `containerSelector`, `titleSelector`, `addSelector`, anchored `addLabelPatterns`, `confirmation` (`productReceipt` or `quantityIncrease`), and `confirmationWindowMS` (500–15000). A receipt profile requires `receipt: {selector, successText, quantityPattern}` with exactly one numeric capture and no `quantitySelector`; a quantity profile requires its own `quantitySelector` and no receipt. A quantity profile may declare `emptyStatusText` for a reviewed dedicated Add state as explicit zero evidence when no input exists. React-replaced controls are reacquired by the same product/profile; duplicated main/sticky quantities must agree. Existing top-level cart selectors remain required as shared link/URL rules and legacy/Undo configuration; they are not a fallback when a profile fails.

Profile-based retailer Undo requires native permission, quantity confirmation (never receipt-only), an explicit zero state, and `undo: {decrementSelector, decrementLabelPattern}` on every profile. Reversal uses the single-use confirmation, exact product/profile/session/item/document/page URL, checks current quantity against the confirmed result, clicks only one matching enabled decrement at a time, and verifies each decrement twice. It preserves pre-existing quantity and stops on uncertainty, hidden/inconsistent controls, navigation or context changes. BIG W is the only profiled retailer permitted to use this path; Kmart remains detection-only with local Undo.

One engine resolves the clicked control to exactly one profile. Card profiles climb only within the smallest unambiguous product-linked/title-bearing container. Page profiles require an explicit detail-control container, numeric page URL, and consistent configured headings; recommendation cards retain their own linked identity. Multiple matching profiles fail closed, not by array order. Product-receipt profiles arm only after a trusted tap and require a new, matching receipt observed twice before posting confirmation. Quantity profiles require a measured baseline and stable same-product increase. Navigation, changed item/context, or expiry cancels observation; passive receipts, stale receipts, unrelated products and synthetic clicks cannot mark an item Added. Exact-host/main-frame/isolated-world bridge validation and native capability ceilings remain unchanged. Unknown profile/receipt keys, duplicate profile IDs, invalid enums/regexes and unsupported version/strategy combinations fail configuration validation.

Kmart's `product-card` profile uses its mobile `quick-product-button`, product-link title paragraph and linked numeric ID; `product-page` uses `product-button` inside `.product-button-container`, the numeric URL and `h1[data-testid="product-title"]`. Both currently use the same product-specific receipt confirmation—not separate engines. Other stores have not been migrated or gained new capabilities.

### Bunnings website authentication and cart

Bunnings uses a silent frame at `https://authorisation.api.bunnings.com.au/connect/authorize` to establish its website session. Native navigation permits this exact authentication host for Bunnings only, using HTTPS, without URL credentials or nonstandard ports. This is browsing-only: the host is not in the bundled automation allowlist, does not receive ListRunner cart automation and cannot establish native bridge trust. Other retailers do not inherit the exception. Bunnings' existing website-data/reset scope includes this Bunnings-owned subdomain; no login reset or list migration is required.

Physical iPhone verification reproduced the blocked frame and failing cart, then confirmed cart loading and one test staples pack added and removed (0→1→0) after the navigation fix. Bunnings cart Undo remains disabled. This verifies website cart functionality, not a new trusted-tap automatic-detection certification. Temporary diagnostic code/build flags were removed before reinstalling the normal app; see `VALIDATION.md` for evidence.

The subsequent grid-detection fix resolves trusted Add/increment taps to the smallest card containing one unique exact-host numeric product link and its own cart control. Duplicate image/title links to the same product are accepted; ambiguous or unsafe identities fail closed. Confirmation requires a stable increase in that same card's quantity, never the page-wide cart badge or another product's quantity. React replacements are reacquired by the same product ID. Product-detail/sticky controls retain their URL-based identity, while recommendation cards use their own links rather than inheriting the detail-page product. The existing detection timeout and cart-Undo restriction are unchanged. A real finger tap on the iPhone grid was confirmed by native diagnostics and automatically marked Staples Added; the user explicitly chose to keep the added pack and that status. This is scoped live detection evidence, not a full retailer/release certification.

### No enabled stores

When every store is disabled, the list screen is neutral: no retailer colours, grocery rows, grocery input, Edit, Show Store action or store chooser. A native “No stores enabled” message explains that saved lists/logins are kept, with a Manage Stores action; Settings also remains available. The chooser returns after a store is enabled.

When returning to the list, select the most recently newly enabled store that is still enabled, even if the previous active store remains enabled. Multiple enable actions retain their order; disabling the newest before returning falls back to the preceding pending enable. The preference is persisted until return and consumed once, so later manual picker choices are not overridden. Reassigning an already-enabled value is not a new enable. With no pending enable, retain an enabled current store, otherwise choose the alphabetically first enabled store (or show no-stores state). Selection waits for the list screen: toggling does not dismiss Manage Stores/Settings or change activeStoreID early. It does not move/delete items or drafts, clear cookies, reset sessions or open a retailer website. Country/filter changes alone never switch the active store. Confirmed Reset Local Data clears pending enable selection too.

### Regional brand discovery — Costco first

Manage Stores groups only explicitly reviewed native brand identities, never matching website/name strings heuristically. Costco Australia (existing `costco` ID) and browsing-only Costco United States (`costcoUS`) have **one Costco visibility switch** and a separate **Website: [country]** button. This regional destination control intentionally adds a clear country label to the formerly names-only row; users must be able to see which website is selected. Kmart remains its own Australian entry, not grouped with unrelated US businesses. Eight regional definitions now appear as seven brand rows.

Shopping country only suggests the regional website for a disabled brand without a saved choice. A saved choice or an already enabled region always wins. Changing Shopping country can regroup the brand based on its available valid service areas, but never changes the selected regional website, enabled store IDs, active list, login or session. The visible Website label continues to identify the actual selected destination even when another region matches Shopping country. Brand and regional-country names are searchable; the native letter index lists each brand once.

Use the Website button to choose a regional site. A native confirmation explains that changing an enabled brand replaces which regional ID is visible in the main chooser/Settings. It never moves, rewrites or deletes old lists or website data. The newly enabled regional destination follows the pending newest-enable selection rule on return; a disabled region cannot remain active. Choosing a region for a disabled brand does not enable it or queue selection. Turning the single switch off hides the brand's regional destinations; turning it back on restores only the selected region and queues it as the newest enable. Region choices persist locally and clear only with confirmed Reset Local Data, not country changes, Clear Diagnostics or retailer-session reset.

Costco US uses exact `www.costco.com`/`costco.com` hosts, US service area, and unique list/website-data IDs ending `000008`. Its configuration has all automation off and `cart: null`, reinforced by native policy; a dormant search template satisfies the schema but is not enabled or verified. Australia retains its existing ID, data IDs, hosts, search capability and website session. Regional data and diagnostics/reset scopes never mix. The main chooser labels the new destination **Costco US**; the existing Australian entry keeps its legacy **Costco** label. No US login/search/cart compatibility or live website verification is claimed. Canonical resource: `Resources/costcoUS.json`; the Mac project bundles equivalent `costcoUS-v2.json`.

### Kmart Australia — search, detection and cart Undo

Kmart is bundled with AU coverage and exact `www.kmart.com.au`/`kmart.com.au` browsing hosts. Enable it in Manage Stores; it starts disabled and has its own permanent list/website-data IDs ending `000007`. It appears alphabetically between Costco and Woolworths in the Australian group. Search uses Kmart's `searchTerm` URL parameter. Schema 3 profiles support trusted Add taps on both the search grid (product-card link identity) and individual product page (URL and heading identity), then wait for the product-specific “Added to your bag” receipt and stable quantity before confirming. Both flows passed live iPhone 17 / iOS 27.0 Foldaway PVC Chair 0→1→0 checks at `f54314d`; no native Mark Added was used. Search cards and the detail page do not expose a resulting quantity field themselves. Cart Undo remains disabled until a safe, product-scoped reversal from Kmart's bag page is implemented and verified. Manual browsing/status controls and per-store Settings/reset remain available. Canonical source: `Resources/kmart.json`.

BIG W is a separate AU retailer with exact `www.bigw.com.au`/`bigw.com.au` hosts and isolated list/session IDs ending `000009`; it starts disabled until enabled. Search uses `/search?text={query}`. Schema 3 quantity profiles cover product cards/recommendations and normal/sticky product-page controls, using exact `/product/<slug>/p/<numeric-id>` identity. A trusted Add/increment and stable same-product quantity increase are required; cart badges, intended quantity, wishlists and success modal recommendations cannot confirm an add. Retailer Undo reverses only the confirmed quantity delta through product-specific decrement controls; manual Mark Added still has local-only Undo. BIG W may require a postcode/availability choice before Add; prompts are retailer-owned and a prompt is not a successful addition. Automatic search, grid/detail detection and native cart Undo passed live iPhone 17 / iOS 27 simulator checks using Contempo 2 Slice Toaster – White (6060359), with explicit empty cart before/after each cycle and temporary-list cleanup. See `VALIDATION.md` for evidence and exclusions: marketplace/variant/login and physical-device flows are not certified by this test. Canonical source: `Resources/bigW.json`.

BIG W profiles also declare `setupPrompt: {selector, textPattern, maximumWaitMS}` for first-use postcode/store selection. A visible matching dialog extends observation up to five minutes plus the ordinary confirmation window; unrelated/hidden dialogs cannot extend it. The original trusted product ID, baseline, page and item context are retained. Native confirmation is armed only when stable product-specific quantity evidence is ready, so time spent entering availability does not trigger the native eight-second failure. Cancellation/expiry still fails safely; navigation, changed item/context and backgrounding cancel observation. This path passed fresh-session grid and detail tests with deliberate 25–42-second prompt waits, followed by automatic Added and native Undo to an explicitly empty cart. It never supplies a postcode or picks a store automatically.

- `StoreConfiguration.swift` defines the trusted typed registry and validates schema-v2 retailer JSON: retailer identity, country service areas, strict known/unique keys, exact HTTPS hosts/ports, homepage, encoded search template, named strategies, bounded selectors/patterns/colors, and native capability ceilings/dependencies. Canonical source resources are `Resources/{coles,woolworths,bunnings,costco,tesco,walmart}.json`; the loader prefers `<id>-v2.json` when present in the Mac app bundle. Definitions contain data only, never executable scripts. Invalid/missing definitions fall back to trusted-homepage browsing with all automation disabled. Adding an arbitrary website from inside the app is not implemented.
- `StoreBrowser` is the shared runtime. It injects the same bundled engine with the selected store's validated data into a store-named isolated content world. The engine traverses open shadow roots and composed event paths for Woolworths' `wc-product-tile` / `wc-add-to-cart` controls, while keeping each product's ID and quantity scoped to its tile. Native validation checks the current WebView, main frame, exact security origin, store/session/interaction/document identity, strict message fields/types/bounds, and quantity confirmation before notifying the overlay. Cross-store messages and Undo records are rejected.
- Coles retains its existing default persistent website-data store, preserving the prior login. Woolworths gets its own stable named persistent store. Store switching cancels pending interactions and does not change either basket. Non-allowlisted top-level HTTP(S) links open outside the app; they do not receive automation. Live sign-in/redirect flows still need retailer-specific smoke testing.
- `ShoppingSchemaV1` matches the previous unversioned item model. `ShoppingMigration` adds store-owned list metadata and an optional item list ID via lightweight migration; startup backfills old rows into Coles in one local save before exposing the app. Legacy UUIDs, names, search terms, amounts, units, statuses, order and selection are retained. Open/migration/backfill failures go to local recovery without silent replacement.
- One list per supported retailer is created idempotently. Counts, typed-item merging, ordering, clearing, selection and item actions are scoped to the active list. Each list keeps its own selected item and last-active date. A same-day relaunch resumes the selected list's store only when that list still has Pending items; the date is compared before updating it. Transient automation/Undo records are not restored after termination.
- Paprika import uses native EventKit access to the exactly named, case-sensitive `Paprika` Apple Reminders list. Full Reminders access is requested only after the user taps Import groceries or the remembered Import from Paprika action. The import reads one complete snapshot of incomplete reminders, rejects missing or duplicate-named Paprika lists without changing the active list, parses titles through `GroceryParser`, ignores blank titles, and stages new source IDs in creation-date/ID order. Existing reminder IDs are deduplicated within the selected store list. Imported rows are committed together in one SwiftData transaction; import errors leave the existing list unchanged and show an actionable inline notice. Successful imports confirm the added count and store destination.
- Imported `GroceryItem` records persist their reminder identifier. The schema migrates from the previous multi-store schema by adding this optional field. After a linked item edit, merge, status change or confirmed store move, the desired reminder title and completion flag are held until the corresponding SwiftData save succeeds. Per-reminder writes serialize and coalesce to the latest not-yet-started state; a failed EventKit save is best-effort and is not retried for that revision. `Added` checks the reminder; `Pending` and `Skipped` uncheck it. Deleting an item cancels queued writeback without deleting the Apple Reminder. List clear and local-data reset do not delete Reminders.
- If one reminder title parses into multiple grocery rows, its reminder ID is linked only to the first row to avoid competing writes to the same source reminder. Additional parsed rows remain local ListRunner items.
- Move to Another Store asks for confirmation, transfers the existing row (same UUID and quantity), appends it to the destination, and marks it Pending. It does not implicitly merge destination duplicates or modify retailer baskets. Typed/pasted duplicate merging continues within the selected list. Input drafts are kept separately in memory while switching stores.
- Live Chrome DevTools verification inspected 43 product tiles: each had a unique numeric stockcode and product-details URL. With an initially empty cart, a trusted add of `So Good Barista Oat Long Life Milk 1L` (`83273`) changed the cart to one item and exposed a quantity input of `1`; the cart remove control then returned the product and cart count to zero. This verifies the current website add signal for detection, not the embedded iOS WebKit path or all product families. Woolworths cart Undo remains disabled because its product-tile decrement/reversal path has not been separately verified.

## Settings and recovery

- Settings is available from the list's gear button, including with an empty list. Its Stores section lists enabled stores only; when all stores are disabled, the section is omitted. Manage Stores always remains available and lists every bundled store so disabled stores can be re-enabled. Each enabled store has its own Reset Session and Clear Diagnostics actions, plus an app-wide Clear All Diagnostics action. Hiding a store preserves its list and website session.
- Manage Stores has a visible **Shopping country** preference. The device region supplies a one-time suggestion, not physical-location detection; users can choose another country and it is remembered locally. With no valid suggestion the row offers Choose Country and stores remain alphabetical. Both old Alphabetical/Nearby preferences migrate without requesting location or changing store switches. An explicit country choice survives a later device-region change.
- Country-matching stores appear first under **STORES IN [COUNTRY]**. Other stores follow an inset divider and subtle **OTHER STORES** caption in rounded alphabetical groups. Empty groups/index entries are hidden. With Australia selected, the four Australian stores come first, followed by Tesco UK under T and Walmart US under W, with native T/W index targets. With no local matches, all other stores remain available with an explanatory note. Invalid configurations remain accessible in Setup unavailable, never claiming a validated country match.
- A small UIKit bridge uses a real inset-grouped `UITableView` and its native right-hand section index on iOS 17+, not drawn letters or horizontal jump buttons. The index targets only actual letter sections and does not duplicate the local-country stores. A standard **Jump to store letter** toolbar menu provides the same navigation with a 44-point target and accessible menu items; it honors Reduce Motion. Native search stays below the title, matches enabled and disabled stores, and hides letter groups/index/menu while filtering; clearing restores the country groups. Country choice never selects a store, changes visibility, or guarantees stock/delivery/postcode coverage.
- Confirmed Reset Store Session gates that store, invalidates its automation and Undo operations, detaches the old WebView, removes only the retailer's website-data records and cookies, and verifies that none remain. Success creates a new session and loads that retailer's homepage without presenting it. Other store sessions, all lists, statuses, selections, diagnostics and Reminders are not cleared. Failed verification offers Retry / Cancel; Cancel uses whatever website data remains and does not claim a successful clear. In-flight WebKit deletion cannot be cancelled; failure choices appear only after deletion and verification finish.
- Clear Diagnostics immediately removes only ListRunner's diagnostics file and shows a dismissible confirmation. Failure to delete does not falsely report success. Diagnostic storage uses closed event/reason/outcome/host enums, omits item/quantity/identifier/URL/error-body content, expires records after 168 hours, throttles identical events for 60 seconds, and caps entries at 2,000 and their sorted-key JSON byte total at 2 MiB. Store failures additionally retain a closed error-domain category, a reviewed native error-code enum, numeric HTTP status and whether browsing was active; older files remain readable. Unreviewed error codes remain console-only. Different failure metadata is not throttled together. Failures and idle-browser rebuilds also appear in the Xcode console under `ListRunner` / `StoreRecovery`, without error descriptions, URLs, queries, cookies or userInfo. Records are purged at startup, foreground, and insertion.
- Initial or later main-frame navigation failures, HTTP error responses, and active web-content process termination preserve item status and present a native Retry / Return to List alert. Recovery invalidates the interaction and cancels transient cooldown. Retry uses the intended URL; process-termination Retry rebuilds the WebView while retaining the same per-store website-data store. Callbacks from replaced WebViews and retired navigation objects are ignored.
- A web-content process that terminates while its store is dismissed or the app is inactive is marked for deferred rebuilding, not a latched failure alert or hidden reload. On explicit reopen/foreground resume, rebuild the WebView with the same website-data store and a fresh automation context, then navigate to the selected item's current search (or the trusted homepage for browsing-only/no-selection flows). Do not replay the previous product/cart/checkout URL or form submission. There is no age-based refresh, automatic network/HTTP retry or cookie/session reset. Existing site-verification blocks retain explicit recovery rather than being bypassed. A failure during the resumed load still requires Retry.
- SwiftData open/migration failures show a blocking local-data recovery screen instead of creating a replacement store. Retry attempts the same store. Confirmed Reset Local Data deletes only the configured database and SQLite sidecars, known app-selection/date/visibility/country preferences, and diagnostics. Retailer website data and Reminders are untouched. The reset API refuses to delete a healthy open database.
- Save errors retain in-memory changes and show a non-dismissible Changes may not be saved notice in the list/store UI. The next mutation or foreground transition retries saving; a successful save clears the warning. This is synchronous save recovery, not the complete revisioned persistence coordinator from the release spec.

## Build and test

Detector regression tests (no live cart changes):

```sh
node --test packages/ios/tests/coles-add-detection.test.mjs
```

These run the bundled JavaScript against controlled DOM fixtures using Coles' product-specific Add label, `product-tile` container, not-in-trolley status, quantity field, and decrease control, plus nested open-shadow-root Woolworths fixtures with the real add label, stockcode URL, and quantity input. They cover confirmation, early script readiness, repeated context delivery, rerendered tiles, composed trusted-event handling, synthetic-event rejection, missing quantities, stale interactions, product/host isolation, and Undo safety: initial/repeated adds, exact deltas, pre-existing quantities, changed baskets, replayed/forged provenance, missing/disabled controls, confirmation timeouts, and cancellation. Woolworths cart Undo remains intentionally disabled; live WKWebView add detection and Coles reversal still need device verification.

On the Mac, run native recovery-service checks:

```sh
bash packages/ios/tests/run-recovery-tests.sh
bash packages/ios/tests/run-parser-tests.sh
bash packages/ios/tests/run-store-proof.sh
```

These compile the actual Foundation, SwiftData, configuration, bridge, EventKit and WebKit services. They cover invalid configurations, encoded search, exact hosts, strict bridge fields/types, cross-store rejection, reset generations, diagnostics, local-data recovery, per-store reset domains, item moves/selection, Paprika parsing/order/deduplication, per-reminder write serialization/coalescing/cancellation, and migration from both the original unversioned database and the previous multi-store schema. All test data uses temporary files, isolated UserDefaults or a nonpersistent WebKit store; real app lists, Reminders and logins are never reset. On Linux this runner cannot execute because `xcrun` and the Apple SDK are unavailable; use the Mac command above.

The shared Xcode scheme also includes `ListRunnerUITests`. Run Product → Test, or:

```sh
cd packages/ios
xcodebuild -project ListRunner.xcodeproj -scheme ListRunner \
  -destination 'platform=iOS Simulator,name=<installed iPhone simulator>' test
```

The UI tests exercise store/list/status isolation, all-hidden and hidden-active chooser states, country suggestion/selection/persistence, unset-country fallback, native index/search/menu behavior, enabled-only Settings, explicit item transfer, retailer-specific reset confirmation, same-day/hidden-store relaunch, Paprika fixture import/deduplication/list ownership, first-item scrolling, and existing shopping flows. Debug-only test sessions use unique temporary databases/preferences, injected device-region suggestions, nonpersistent WebViews and deterministic local fixtures for both visible and preloaded navigation; tests never mutate a retailer cart or access the user's Reminders. One isolated mixed-country presentation fixture changes Bunnings' displayed service area to NZ to exercise both groups; it never changes the registry/browser or production AU metadata. Fixture results do not certify real sign-in or embedded WebKit cart behavior. Earlier physical-device results predate the country-first revision; the iPhone is currently unavailable and this revision uses simulator validation only. iOS 17 runtime coverage remains unavailable on this Mac. See `VALIDATION.md` for current results, the native-index hit-area limitation, and outstanding release checks.

The Mac Xcode project is the build/signing baseline. Review both checkouts before synchronizing source changes: uncommitted work can exist in each, and Mac asset/project changes must not be overwritten by a blind folder copy. For committed work, on the Mac:

```sh
cd packages/ios
xcodebuild -project ListRunner.xcodeproj -scheme ListRunner \
  -destination 'generic/platform=iOS Simulator' build
```

Then open `ListRunner.xcodeproj` in Xcode, choose an iOS 17+ iPhone simulator, and run the app. The native service runner uses macOS 14+ frameworks; UIKit/UI tests use the chosen iPhone simulator. This Linux host does not have `xcodebuild` or the iOS SDK.

## Adding a compatible bundled store (developer workflow)

1. Add a stable `StoreID` case in `StoreConfiguration.swift`. Review exact HTTPS automation hosts and any browsing-only login exceptions in native code; keep the trusted host set narrower than a registrable domain. Assign permanent, unique list and WebKit website-data UUIDs. Do not reuse another store's IDs.
2. Add a schema-v2 data-only JSON resource named `<store-id>-v2.json`, including `serviceArea.countryCodes` with canonical ISO 3166-1 alpha-2 codes. Keep `displayName`, `id`, and hosts consistent with the trusted native registration. Use only the existing named strategies; JSON may not carry JavaScript or widen native capability ceilings.
3. Add the JSON resource to the app bundle and add contract fixtures for identity, required/unknown keys (including nested keys), schema version, country codes, URL encoding, HTTPS/host/port/userinfo rejection, bounded colors/selectors/regexes, and capability dependencies. Verify invalid setup retains safe browsing but closes every automation capability.
4. Add DOM fixtures only for reviewed retailer DOM and trusted user-action signals. Test product identity, stable quantity changes, rerenders, stale context, cross-store isolation, and every failure path. Keep cart Undo off until its separate product-specific reversal path is proven; selector presence alone is never approval.
5. Confirm migration visibility policy (existing stores stay visible; a newly registered store starts hidden), persistent data isolation, reset boundaries, and chooser/settings behavior. Do not add a retailer-specific branch to unrelated shopping progression or reset code.
6. Treat fixture and UI tests as simulated evidence. Validate search, login redirects, detection, and Undo independently in the live embedded WebView before enabling each capability. Any real cart mutation needs explicit user authorization, a narrowly agreed product/delta, and a no-checkout workflow.

This workflow is for extending the bundled trusted catalogue, not user-defined sites, remote configuration, downloaded scripts, or a production integration beyond the retailers explicitly approved for ListRunner.

`run-store-proof.sh` compiles a synthetic `.example` registration only under `STORE_REGISTRY_PROOF`. It demonstrates shared configuration validation, multi-country ordering, query encoding, stable isolated IDs, and hidden-by-default/persistent visibility without changes to shopping progression or reset code. The normal app and release build do not define this flag or include the synthetic retailer.

### Walmart US — browsing-only country-grouping preview

Walmart uses the United States (`US`) service area and exact `www.walmart.com`/`walmart.com` browsing hosts. It starts disabled and has its own permanent list/website-data UUIDs ending `000006`, diagnostics/reset scope, and blue/yellow branding. Selecting United States as Shopping country puts Walmart in the local group, without enabling it or hiding the other stores. For Australia it appears under OTHER STORES → W alongside Tesco's T group. Search, cart detection and retailer-cart Undo are disabled in configuration and native policy; the schema-required search template is dormant. No Walmart website/login/cart automation or live compatibility has been implemented or verified. Other Walmart country domains and unreviewed login subdomains are not included.

### Tesco UK — search, grid detection, Undo and sign-in continuation

Tesco is available with GB coverage and remains disabled until explicitly enabled. It keeps its original list/website-data IDs ending `000005` and exact UK browsing hosts; Irish Tesco domains are not included. Its reviewed search route redirects from `/groceries/en-GB/search?query=…` to `/shop/en-GB/search?query=…`. Schema-4 grid detection correlates a trusted product-specific Add with a stable read-only basket quantity. Normal signed-in Add and native cart Undo were live-verified in the simulator. Undo decrements only a confirmed delta and refuses changed quantities or missing/disabled controls.

An Add interrupted by sign-in retains one in-memory trusted product intent for at most five minutes across the reviewed first-party `/account/auth/en-GB` and `/account/login/en-GB` route families, returning only to the original search/product URL. A scoped adapter observes Tesco's existing `UpdateBasket` promise without initiating requests or reading authentication data. Native detection requires a matching product-success acknowledgement, matching requested/returned quantity, and stable exact-product quantity in the isolated automation world. Unknown routes, changed item/session, recovery and expiry invalidate the continuation. No repeated Add or user confirmation is required. This path was live-verified on `56e73d3`; no account baseline is inferred from the guest cart. Its acknowledgement record has no reversible quantity delta, so local Undo cannot remove Tesco cart items and instead warns the user to check the cart. Subsequent signed-in additions retain normal verified cart Undo. This proof covers the observed milk grid/login flow, not all product/detail/fulfilment or physical-device flows.

### Costco Australia

Costco's reviewed automation/browsing hosts are exactly `www.costco.com.au` and `costco.com.au`. Search uses `https://www.costco.com.au/search?text={query}`. Canonical source is `ListRunner/Resources/costco.json`; the Mac project bundles the equivalent `costco-v2.json`. Costco has permanent, unique list and named WebKit store IDs ending `000004`, its own diagnostics/reset scope, AU service area, and blue/red branding. Existing stores retain their IDs, enabled state and sessions; Costco starts disabled and can be enabled in Manage Stores.

Read-only live browser checks on 27 October 2026 verified rendered search results for coffee and laundry detergent and an on-host login form. Costco itself redirects the observed `milk` query to `/content/sameday`, whose links advertise a separate DoorDash service. DoorDash and non-Australian Costco domains are not added to the allowlist or integrated; external links follow the existing Safari policy. The integration does not promise the warehouse assortment, groceries or delivery in every postcode, or bypass membership/login requirements.

Product pages expose SKUs and intended add quantities, but these are not proof of successful cart addition. Business Delivery product IDs can also contain `_BD` suffixes, so the existing numeric-only cart identity strategy is not appropriate without further review. The configuration has `cart: null`; both cart detection and retailer-cart Undo remain off in configuration and native policy. Use Mark Added/Skip and local status Undo after shopping manually. No Costco cart mutations, purchases or account/payment changes are authorized or performed by adding this integration. Embedded login/cart capability validation remains separate from public browser and fixture evidence.

### Country and privacy policy

Store discovery does not use CoreLocation, reverse geocoding or IP lookup and needs no location permission or network service. Shopping country is a local preference, not a claim about the user's physical location. The initial device-region suggestion is used only once and never overwrites a saved choice. Country selection, grouping and search work offline. The obsolete discovery-only location usage description and resolver have been removed. Clear Diagnostics and retailer-session resets preserve country/visibility preferences; confirmed Reset Local Data clears them. Country-specific ingredient naming is a separate backlog feature and is not implemented by this preference.
