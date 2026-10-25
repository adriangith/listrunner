# ListRunner iOS

Native SwiftUI app targeting iPhone on iOS 17 or later.

Open `ListRunner.xcodeproj` in Xcode, choose an iPhone simulator, and run the `ListRunner` scheme. This is a native SwiftUI/SwiftData iOS 17 app, not the removed Capacitor app.

## Current implementation

- Add one or many items from comma-, newline-, and bullet-separated text.
- Parse common counts, multipliers, and grocery units; unrecognized entries are retained as names.
- Merge typed duplicates by normalized name and compatible units; persist one active list locally with SwiftData.
- Review status totals, edit item name/quantity/unit, delete rows, and clear a list with pending-item confirmation.
- Select independent Coles and Woolworths lists using the native Store picker; selected store and per-list selected items survive relaunch.
- Open the selected retailer in a persistent-data WKWebView sheet with native item cards and manual Mark Added, Skip, Next, Pause, Undo, and Finish controls.

This is an implementation slice, not the release-complete MVP. Selecting an item starts the selected store's configured URL-template search. Coles cart detection listens in an isolated WebKit content world for trusted taps on supported add controls, correlates a numeric product ID, and confirms an increase only after the product quantity is observed stable twice within three seconds. Woolworths add detection now uses the visible numeric stockcode in the product URL and quantity control inside its nested open shadow roots; it requires a trusted add action and two matching quantity observations. Confirmed adds update only that store's selected ListRunner item and start its undo cooldown, or final-item confirmation. Detection itself is observational. Explicit Undo of a confirmed Coles add can request a best-effort cart reversal as described below. Woolworths cart Undo remains intentionally disabled; its Undo restores only ListRunner status and does not change the retailer basket. Paprika import and best-effort Reminder writeback are implemented as described below. Search readiness recognition, general cart removal detection, broader product-page/DOM coverage, session-scoped failure thresholds, fully revisioned persistence, full persistent final-confirmation lifecycle behavior, and full accessibility/release verification remain to be implemented.

A supported automatic-add Undo immediately restores the recorded ListRunner status. Its transient record retains the session, interaction, document generation, item, product, before/after quantities, and isolated-script confirmation ID. For Coles, the script must still retain that exact confirmation, and the current product quantity must equal the recorded after value. Only then can Undo click the product tile's supported `Decrease … quantity by one` button, confirming each decrement twice and preserving the pre-existing quantity. Reversal has a three-second script deadline and a four-second native timeout; it does not retry uncertain clicks. A new user click, changed interaction, navigation, or store dismissal stops further decrements. Repeated adds replace cooldown Undo with the latest add; final confirmation retains its original Undo. Woolworths local Undo never requests store reversal. Manual Mark Added never requests store reversal. Missing controls, stale context, changed quantities, or unconfirmed Coles reversal show a dismissible `Could not undo store cart change` notice without undoing the local restoration. This remains a supported-product-tile strategy, not general cart or product-detail-page automation; live Coles reversal still needs device verification.

Manual Mark Added advances immediately when pending items remain, without a countdown; the final item retains Undo / Finish. A confirmed automatic Coles add shows a three-second Undo cooldown before advancing; final automatic adds retain Undo / Finish. Revisiting an Added item offers Mark Pending in the same card-button position. It restores Pending locally, keeps the item selected, clears any paused confirmation, and never removes products from the Coles cart. After finishing a completed run, Mark Pending can reopen it. Pause is reserved for an active automatic-add countdown.

On Your list, tap Edit to use native iOS row reordering. The row's three-dot menu offers Mark Added for Pending items, Mark Pending for Added items, and Mark Skipped for non-Skipped items. These actions change ListRunner status only and do not edit retailer baskets.

## Store configuration and list ownership

- `StoreConfiguration.swift` defines a typed registry and validates bundled `Resources/coles.json` and `Resources/woolworths.json`: schema version, exact HTTPS hosts/ports, homepage, encoded search template, named strategies, selectors, and capabilities. Definitions contain data only, never executable scripts. Invalid/missing definitions fall back to trusted-homepage browsing with automation disabled. Adding an arbitrary website from inside the app is not implemented.
- `StoreBrowser` is the shared runtime. It injects the same bundled engine with the selected store's validated data into a store-named isolated content world. The engine traverses open shadow roots and composed event paths for Woolworths' `wc-product-tile` / `wc-add-to-cart` controls, while keeping each product's ID and quantity scoped to its tile. Native validation checks the current WebView, main frame, exact security origin, store/session/interaction/document identity, strict message fields/types/bounds, and quantity confirmation before notifying the overlay. Cross-store messages and Undo records are rejected.
- Coles retains its existing default persistent website-data store, preserving the prior login. Woolworths gets its own stable named persistent store. Store switching cancels pending interactions and does not change either basket. Non-allowlisted top-level HTTP(S) links open outside the app; they do not receive automation. Live sign-in/redirect flows still need retailer-specific smoke testing.
- `ShoppingSchemaV1` matches the previous unversioned item model. `ShoppingMigration` adds store-owned list metadata and an optional item list ID via lightweight migration; startup backfills old rows into Coles in one local save before exposing the app. Legacy UUIDs, names, search terms, amounts, units, statuses, order and selection are retained. Open/migration/backfill failures go to local recovery without silent replacement.
- One list per supported retailer is created idempotently. Counts, typed-item merging, ordering, clearing, selection and item actions are scoped to the active list. Each list keeps its own selected item and last-active date. A same-day relaunch resumes the selected list's store only when that list still has Pending items; the date is compared before updating it. Transient automation/Undo records are not restored after termination.
- Paprika import uses native EventKit access to the exactly named, case-sensitive `Paprika` Apple Reminders list. Full Reminders access is requested only after the user taps Import from Paprika. The import reads one complete snapshot of incomplete reminders, rejects missing or duplicate-named Paprika lists without changing the active list, parses titles through `GroceryParser`, ignores blank titles, and stages new source IDs in creation-date/ID order. Existing reminder IDs are deduplicated within the selected store list. Imported rows are committed together in one SwiftData transaction; import errors leave the existing list unchanged and show the specified inline notice. Successful imports add rows quietly.
- Imported `GroceryItem` records persist their reminder identifier. The schema migrates from the previous multi-store schema by adding this optional field. After a linked item edit, merge, status change or confirmed store move, the desired reminder title and completion flag are held until the corresponding SwiftData save succeeds. Per-reminder writes serialize and coalesce to the latest not-yet-started state; a failed EventKit save is best-effort and is not retried for that revision. `Added` checks the reminder; `Pending` and `Skipped` uncheck it. Deleting an item cancels queued writeback without deleting the Apple Reminder. List clear and local-data reset do not delete Reminders.
- If one reminder title parses into multiple grocery rows, its reminder ID is linked only to the first row to avoid competing writes to the same source reminder. Additional parsed rows remain local ListRunner items.
- Move to Another Store asks for confirmation, transfers the existing row (same UUID and quantity), appends it to the destination, and marks it Pending. It does not implicitly merge destination duplicates or modify retailer baskets. Typed/pasted duplicate merging continues within the selected list. Input drafts are kept separately in memory while switching stores.
- Live Chrome DevTools verification inspected 43 product tiles: each had a unique numeric stockcode and product-details URL. With an initially empty cart, a trusted add of `So Good Barista Oat Long Life Milk 1L` (`83273`) changed the cart to one item and exposed a quantity input of `1`; the cart remove control then returned the product and cart count to zero. This verifies the current website add signal for detection, not the embedded iOS WebKit path or all product families. Woolworths cart Undo remains disabled because its product-tile decrement/reversal path has not been separately verified.

## Settings and recovery

- Settings is available from the list's gear button, including with an empty list. It lists both stores, each with its own Reset Session and Clear Diagnostics actions, plus an app-wide Clear All Diagnostics action.
- Confirmed Reset Store Session gates that store, invalidates its automation and Undo operations, detaches the old WebView, removes only the retailer's website-data records and cookies, and verifies that none remain. Success creates a new session and loads that retailer's homepage without presenting it. Other store sessions, all lists, statuses, selections, diagnostics and Reminders are not cleared. Failed verification offers Retry / Cancel; Cancel uses whatever website data remains and does not claim a successful clear. In-flight WebKit deletion cannot be cancelled; failure choices appear only after deletion and verification finish.
- Clear Diagnostics immediately removes only ListRunner's diagnostics file and shows a dismissible confirmation. Failure to delete does not falsely report success. Diagnostic storage uses closed event/reason/outcome/host enums, omits item/quantity/identifier/URL/error-body content, expires records after 168 hours, throttles identical events for 60 seconds, and caps entries at 2,000 and their sorted-key JSON byte total at 2 MiB. Records are purged at startup, foreground, and insertion.
- Initial or later main-frame navigation failures, HTTP error responses, and web-content process termination preserve item status and present a native Retry / Return to List alert. Recovery invalidates the interaction and cancels transient cooldown. Retry uses the intended URL; process-termination Retry rebuilds the WebView while retaining the default website-data store. Callbacks from replaced WebViews and retired navigation objects are ignored.
- SwiftData open/migration failures show a blocking local-data recovery screen instead of creating a replacement store. Retry attempts the same store. Confirmed Reset Local Data deletes only the configured database and SQLite sidecars, known app-selection/date preferences, and diagnostics. Coles and Reminders are untouched. The reset API refuses to delete a healthy open database.
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
```

These compile the actual Foundation, SwiftData, configuration, bridge, EventKit and WebKit services. They cover invalid configurations, encoded search, exact hosts, strict bridge fields/types, cross-store rejection, reset generations, diagnostics, local-data recovery, per-store reset domains, item moves/selection, Paprika parsing/order/deduplication, per-reminder write serialization/coalescing/cancellation, and migration from both the original unversioned database and the previous multi-store schema. All test data uses temporary files, isolated UserDefaults or a nonpersistent WebKit store; real app lists, Reminders and logins are never reset.

The shared Xcode scheme also includes `ListRunnerUITests`. Run Product → Test, or:

```sh
cd packages/ios
xcodebuild -project ListRunner.xcodeproj -scheme ListRunner \
  -destination 'platform=iOS Simulator,name=<installed iPhone simulator>' test
```

The UI tests exercise store/list/status isolation, explicit item transfer, retailer-specific reset confirmation, Woolworths' manual status and local-only Undo, same-day relaunch into the remembered store, Paprika import/deduplication/list ownership, and permission/list-error fallback. Debug-only test sessions use unique temporary databases/preferences, nonpersistent WebViews and deterministic local fixtures; tests never contact a retailer or access the user's Reminders. Those fixtures do not certify a user's real EventKit permission flow or Paprika calendar, real sign-in, Coles live add/Undo, or Woolworths' embedded WKWebView live add detection. Physical-device accessibility, baseline/current iOS coverage, and live retailer smoke checks remain release gates.

The source is authored on the Linux development system and synchronized to the Mac through Git. On the Mac:

```sh
cd packages/ios
xcodebuild -project ListRunner.xcodeproj -scheme ListRunner \
  -destination 'generic/platform=iOS Simulator' build
```

Then open `ListRunner.xcodeproj` in Xcode, choose an iOS 17+ iPhone simulator, and run the app. The native service runner uses macOS 14+ frameworks; UIKit/UI tests use the chosen iPhone simulator. This Linux host does not have `xcodebuild` or the iOS SDK.
