## ListRunner Build Specification

### Vision
ListRunner automates the tedious process of having to search for items on grocery websites when you already have the items recorded in your digital grocery list. The unique proposition is that it steps you through your whole list, one item at a time, on the store's real site.
ListRunner detects user actions but does not choose products, does not checkout, and does not manipulate payment/account details.

### MVP
The MVP is an app that imports or accepts a grocery list, uses Coles as the only supported store, opens that store in an in-app browser, overlays item cards, searches one item at a time, detects add-to-cart where supported, and allows manual progression when automation fails.

#### Platforms
* Native iPhone app supporting iOS 17 or later in portrait orientation.

#### MVP Architecture
* ListRunner is a native SwiftUI iOS app. The MVP does not use Capacitor or a web-app shell.
* Coles runs inside a persistent `WKWebView`, with the ListRunner overlay implemented as native SwiftUI.
* A generic store-automation engine and its JavaScript are bundled with the app. The engine reads bundled store configuration files and passes detected events to the native app through the `WKWebView` message bridge.
* The MVP bundles one store configuration for Coles. Automation scripts are injected only into domains allowed by the active store configuration. Links to other domains open in Safari and do not receive ListRunner automation scripts.
* Store automation and configuration files are not downloaded remotely in the MVP.
* An automation session is scoped to one store. It has a unique session ID, consecutive failed-item-interaction count, and session-level manual-mode state. In the MVP, the single Coles session begins when the app initializes store automation and ends on app termination or `Reset Coles Session`. It persists through web-view dismissal, navigation, and Coles sign-in/sign-out. Starting a new session resets its failed-item count and manual-mode state.
* Apple Reminders integration uses the native EventKit framework.
* Lists, item state, search terms, source identifiers, and app-level launch metadata are persisted locally with SwiftData.
* A UI-independent native shopping-run state engine owns item status transitions, selected-item history, cooldown decisions, progression, completion, and undo restoration. SwiftUI views and the store-automation bridge send events into this engine rather than changing run state directly.
* The state engine processes shopping-run events serially in arrival order. Each cooldown receives a unique generation token; cancelling, completing, or replacing a cooldown invalidates its token, and callbacks carrying an invalid token are ignored.
* The state engine produces updated state and explicit side-effect requests, such as searching the store or updating a linked reminder. Platform services execute those effects so progression rules can be tested without SwiftUI, `WKWebView`, SwiftData, or EventKit.

#### Accessibility
* ListRunner-owned list, settings, card, and overlay controls support Dynamic Type.
* ListRunner-owned controls expose meaningful VoiceOver labels, values, traits, and navigation order, including item status and selected state.
* ListRunner honors iOS Reduce Motion. Carousel changes move instantly or use a subtle crossfade, and the three-second cooldown uses non-continuous progress updates instead of sweeping animation. Timing and state behavior remain unchanged.
* These requirements apply to ListRunner's native interface; accessibility inside the Coles website remains controlled by Coles.

#### Appearance
* ListRunner's native list/summary and settings screens follow the system light or dark appearance using adaptive semantic colors.
* Overlay cards retain their defined brand gradients in both appearances, while overlay text and control surfaces use adaptive colors where possible.
* The Coles website controls its own appearance.

#### Features
* Support for https://www.coles.com.au. This is where we personally do most of our online shopping.
* Support exactly one active ListRunner list at a time.
* Parse raw text list of grocery items and quantities. Items are split on new lines, bullet markers, and commas, including comma-separated input such as `milk, bread, eggs`.
* Quantity parsing supports whole numbers, decimal amounts, multiplier forms, and common grocery units. Supported examples include `2 apples`, `2x apples`, `500g mince`, `1.5L milk`, and `3 cans tomatoes`.
* Parsing is best-effort. If ListRunner cannot recognize a quantity format, it preserves the full input as the item name, treats quantity as unspecified, and allows the user to correct the item from the list/summary screen. Unrecognized input is not rejected or silently discarded.
* Blank entries and entries containing only bullet characters or whitespace are ignored.
* Stored item names preserve the user's or source's capitalization after surrounding whitespace is trimmed and repeated internal whitespace is collapsed. Manual edits preserve the capitalization entered by the user.
* The overlay formats item names in sentence case for display without changing the stored item name. Coles searches use the stored item name rather than the formatted overlay text.
* The overlay formatter uppercases recognized acronyms. The MVP recognized-acronym list includes `BBQ`, so `bbq sauce` is presented as `BBQ sauce`.
* When users type or paste multiple items into a non-empty list, the parsed items are appended as new `Pending` items in their input order. Existing items are not replaced.
* Duplicate-name normalization ignores capitalization, trims surrounding whitespace, and collapses repeated internal whitespace. For example, `Milk`, `milk`, and ` milk ` match the same normalized item name.
* Typed or pasted items with the same normalized item name are automatically merged into one ListRunner item instead of creating duplicate entries.
* When merged duplicate items have quantities with the same normalized quantity unit, their amounts are added together. For example, `2 apples` and `3 apples` become one item displayed as `5 apples`. The MVP does not convert between different units.
* When one duplicate has no specified quantity and the other has a specified quantity, the specified quantity replaces the unspecified value. The display fallback of `1` is not included in the sum. For example, `apples` and `2 apples` become `2 apples`.
* Items with the same normalized name but incompatible quantity units remain separate. For example, `2 cans tomatoes` and `500g tomatoes` are not merged.
* When typed or pasted input merges into an existing item, the merged item has `Pending` status regardless of whether it was previously `Pending`, `Added`, or `Skipped`. For a linked Paprika item, the merged name and quantity update the linked reminder text and the status transition unchecks the reminder. Paprika reminders with duplicate reminder IDs remain ignored instead of being merged.
* Overlay item cards over store website for wizard like navigation.
* Stepping through grocery items
* Ability to skip to a specific item by clicking on the item's card.
* If at least one `Pending` item remains after an item is added to the cart, a three-second cooldown starts, allowing the user to undo adding to cart if they added the wrong item or need to add multiple of the same item. If supported, the undo function will reverse the adding of the item to the store cart. Undo always rolls back ListRunner’s state; store cart rollback is best-effort only. No cooldown starts after the final pending item is handled.
* Another automatic add while cooldown is active restarts the cooldown when pending items remain, replaces the transient `Undo` target with the item's current `Added` state, and leaves the item `Added`. Therefore, `Undo` after a later add reverses only the latest add on a best-effort basis and leaves the ListRunner item `Added`.
* A detected quantity increase above the previous correlated Coles quantity is treated as another automatic add, marking the item `Added` and starting or restarting cooldown when pending items remain.
* A detected removal or quantity decrease is treated as the newest cart event and cancels any active cooldown, discarding the stale `Undo` target. ListRunner tracks the latest confirmed quantity for each store product associated with the selected item during the active run. The item stays `Added` while any associated product has a quantity above zero and returns to `Pending` only when every associated product has a confirmed quantity of zero.
* Selecting another item during cooldown cancels the cooldown, keeps the previously selected item in `Added` status, and immediately searches the newly selected item.
* Clicking a next button to skip the cooldown.
* Marking items as added manually, particularly useful when automation is not available or not working correctly.
* Skipping items
* Ability to import from Reminders on Apple systems from a list called `Paprika`. Paprika exports grocery lists to Apple Reminders. ListRunner reads incomplete reminders from that list and imports each reminder title as grocery-list input. Reminder notes and other fields are ignored.
* Items that do not have any specified quantity will display as a quantity of '1' in the overlay without any quantity unit.
* Item quantity is display guidance only. ListRunner does not automatically set or enforce the quantity in the Coles cart.

###### On supported grocery sites -
* Automatic search triggering and item progression when items are added to cart.
* Observe direct user interaction with the store's add item button, store numerical add-to-cart field, or store add-additional-item button (typically depicted with a plus icon) as a candidate add for the currently selected ListRunner item. The user may manually refine the Coles search or navigate within Coles without editing the ListRunner item or breaking that association. The interaction alone is not confirmation; ListRunner automatically progresses only after a matching confirmed cart quantity change or other supported cart signal within three seconds.
* Observe direct user interaction with the store's remove button, typically depicted with a minus icon, or store quantity field as a candidate removal. A matching stable quantity decrease confirms the removal. When the resulting quantity reaches zero, the Coles product control returns to its red `Add` state, and ListRunner returns the item to `Pending`.

#### Paprika Import
ListRunner requests Apple Reminders permission only when the user first selects the Paprika import action, not on app launch.
After the user selects import, the action is disabled and displays `Importing…` until that attempt finishes; repeated taps do not start additional imports. On completion or failure, the normal import action becomes available again.
ListRunner matches the Reminders list name exactly and case-sensitively as `Paprika`. If more than one accessible list has that exact name, ListRunner imports nothing, shows `Multiple Paprika lists found`, and leaves the current ListRunner list unchanged.
Each incomplete reminder title is processed through the same item-name and quantity parser used for typed input. Blank titles and titles containing only bullet characters or whitespace are ignored. Reminder notes do not affect the imported item.
An imported Paprika reminder is checked when its ListRunner status changes to `Added` after manual `Mark Added` or automatic add detection. The reminder is unchecked when its ListRunner status changes to `Pending` or `Skipped`, including when `Undo`, editing, merging, or detected cart removal causes that transition.
When Paprika is imported into an existing ListRunner list, incomplete reminders whose reminder IDs are already present in the list are ignored. New reminders are sorted by creation date from oldest to newest, with reminder ID as the deterministic tie-breaker, then imported as new `Pending` items and appended to the end of the ListRunner list in that order. Reminders without a creation date sort after dated reminders and use reminder ID ordering among themselves.
Successful imports update the visible ListRunner list without showing a separate success message.
Paprika import is snapshot-based and one-way after import. External edits, completion, or deletion in Apple Reminders do not change the existing ListRunner item. Re-importing adds new incomplete reminder IDs but does not refresh existing items. ListRunner may write the current item name and quantity to a linked reminder and synchronizes its checked state from ListRunner status: `Added` is checked, while `Pending` and `Skipped` are unchecked.
Reminder writeback is best-effort. If a linked reminder no longer exists or an EventKit write fails, ListRunner keeps the local text and status change, does not retry, and does not block or interrupt shopping.

#### Core user flow
Import or type list → review list → `Show Store` → ListRunner searches current item → user adds product → ListRunner detects add → cooldown when another pending item remains → next pending item.
* If automation fails, the user can search manually, mark added manually, or skip.
* On opening ListRunner mobile, the user is presented with a space to type a grocery list of items or add items one by one. They also have the option to add items from Paprika.
* Multiline or pasted raw text is parsed only after the user taps an explicit `Add Items` action. Parsed entries are added directly to the editable list; ListRunner does not show a separate parse-preview step or parse and modify the active list continuously while the user is typing.
* `Add Items` is also used for one-item manual entry. One non-empty item creates one `Pending` item; multiple parsed entries create or merge items in input order. Submitting blank or bullet-only input leaves the active list unchanged. After at least one item is added or merged successfully, the raw-input field is cleared.
* `Show Store` presents the Coles web view and item-card overlay over the list/summary screen. The user returns to the list by pulling down on the presented web view until iOS dismisses it.
* Adding or importing the first items keeps the user on the list/summary screen so they can review the parsed list before showing the store.

#### Persistence and resume
ListRunner persists a non-empty grocery list, item quantities, item statuses, the last item selected in the overlay, search terms, and Paprika reminder identifiers. A separate app-level metadata record persists the optional last-active local calendar date even when no grocery list exists.
The in-app Coles browser uses persistent website storage so Coles cookies, login state, and cart data can survive app launches as supported by the Coles website. ListRunner does not read or manage the user's Coles credentials.

* A secondary settings area remains accessible on the list/summary screen whether the list is empty or non-empty. `Reset Coles Session` is available there. It requires confirmation, then clears Coles cookies and local website storage from the in-app browser, ends the active Coles automation session, starts a new one, and loads `https://www.coles.com.au` without presenting the web view. It preserves the ListRunner list, statuses, and selected item. It signs the user out locally but does not clear Apple Reminders. It does not guarantee deletion of a server-side Coles cart, which may return after the user signs in again. `Show Store` later presents the reset web view.

* On launch, ListRunner first reads the saved last-active local calendar date and last overlay-selected item ID without updating either value. If a non-empty list has at least one `Pending` item and a saved date matching today's local calendar date, it presents the Coles web view over the list/summary screen and restores the saved selected item. If that item was deleted or no selection was saved, it uses the normal first-item or deletion fallback. If the list is empty, complete, the saved date is missing, or the saved date differs from today, ListRunner keeps the list/summary screen visible and does not present the web view. After choosing the launch destination, ListRunner saves today's local calendar date.
* The list/summary screen remains underneath the presented Coles web view. Pulling down to dismiss the web view reveals the list without changing selection or item status, invalidates the active interaction ID, and causes delayed bridge messages for that interaction to be ignored. Dismissal preserves the Coles page, website storage, and automation session.
* `Show Store` presents the Coles web view, returns to the last item selected in the overlay, creates a fresh interaction ID, and searches it again. If the overlay has not been used for the current list, `Show Store` selects and searches the first item in list order.
* Dismissing and reopening the Coles web view does not reset the active automation session or its session-level manual-mode state. If the session is already in session-level manual mode, automation is retried only when a new Coles session is started, such as after `Reset Coles Session`.
* When the app enters the background, ListRunner cancels any active cooldown, keeps the current item status, suspends automation, invalidates the active interaction ID, and ignores bridge messages while inactive. The current Coles page, website storage, and automation session remain preserved. If the Coles web view is still presented when the app returns to the foreground, ListRunner creates a fresh interaction for the selected item and re-establishes product quantity baselines from the current page without forcing a new search.
* `Show Store` is hidden only while the list is empty and remains available for a completed non-empty list so the user can inspect the Coles cart or store session.
* Tapping an item on the list/summary screen selects that item, opens the shopping website overlay, and immediately searches for it on Coles. The item's status does not change until the user takes a status-changing action.
* The list/summary screen preserves list order rather than grouping items by status. Each row displays its status badge, and summary counts for `Pending`, `Added`, and `Skipped` appear above the list.
* The list/summary screen displays a `Complete` indicator when no items have `Pending` status.
* Users can add items to an existing list, including a completed list. Each new item begins with `Pending` status, causing the `Complete` indicator to disappear and normal overlay progression to resume.
* Users can open an item's inline edit mode from the list/summary screen and edit its name, numeric quantity amount, and optional quantity unit. `Save` validates and applies all fields atomically; `Cancel` discards every change and closes edit mode. A blank item name keeps edit mode open, shows `Item name is required`, and focuses the name field. The quantity amount accepts only valid whole or decimal numbers; an invalid amount keeps edit mode open, shows `Enter a valid quantity`, and focuses the amount field. VoiceOver announces either validation error when it appears. The quantity unit is free text with suggestions including `g`, `kg`, `mL`, `L`, `cans`, and `packs`; it is trimmed but otherwise preserved. Saving with a blank quantity amount also clears the unit, stores the quantity as unspecified, and makes the overlay display the fallback quantity `1` without a unit. A unit without an amount does not create a quantity. A valid save updates the Coles search term when the item name changed, affects only that row, and never automatically merges it with another existing item, so editing may create duplicate normalized names. The successful save changes the item to `Pending` regardless of its previous status, causing the `Complete` indicator to disappear when applicable. For a linked Paprika item, one best-effort reminder writeback applies the saved text and unchecked state after the local save succeeds. Edits apply only inside ListRunner and do not modify the Coles cart.
* Users can delete individual items from the list/summary screen. Individual deletion happens immediately without a confirmation dialog. Deleting an item removes it only from ListRunner and does not change its Apple Reminder or any corresponding item in the Coles cart.
* If the deleted item was selected, ListRunner selects the next `Pending` item after its former position. If none exists after it, selection wraps to the first `Pending` item. If no pending items remain, ListRunner selects the next remaining item in list order, or the previous item if the deleted item was last. If the list becomes empty, no item is selected. References to the deleted item are removed from `Back` selection history.
* Adding an item does not change the last item selected in the overlay. `Show Store` still returns to that item, regardless of status. If that item has been deleted, the deletion fallback selects the next pending or remaining item as described above.
* `Clear List` is available on the list/summary screen whenever the list is non-empty, not only when reopening an older run.
* `Clear List` removes the saved list and shopping-run state from ListRunner only. It does not change Apple Reminders, the Coles cart, or the in-app browser's stored Coles session.
* If at least one item is `Pending`, `Clear List` requires confirmation before removing the list. If no items are `Pending`, the list is already marked `Complete` and `Clear List` proceeds without a confirmation dialog.
* Active cooldown timers, `Back` selection history, manual-mode state, and unconfirmed warnings are transient and are not restored after the app is terminated.

#### Acceptance criteria
* Given a list of 10 items, the user can import it, show Coles, search each item, mark items added manually, skip items, and handle every item without being blocked by automation.
* The bundled Coles configuration automatically searches the selected item and detects supported add and removal/quantity changes on the live Coles website.
* If automatic search, add detection, or removal detection fails, manual fallback still allows the user to navigate the list, use the Coles site directly, mark items added, skip items, and reach `All items handled`.
* With Reminders permission granted and a `Paprika` list present, ListRunner imports new incomplete reminders without duplicates, updates linked reminder text after ListRunner edits, checks the linked reminder when its item becomes `Added`, and unchecks it whenever the item becomes `Pending` or `Skipped`.
* Relaunching on the same local calendar day with `Pending` items restores the persisted list, statuses, edits, Coles web view, and last overlay-selected item. Relaunching on the same day with a completed list, or on a later day, preserves the same run but opens the list/summary screen first. The saved date is compared before it is updated, and today is saved only after the launch destination has been chosen. Cooldown, `Back` history, manual-mode state, and unconfirmed warnings are not restored, while the independent Coles website session remains persistent.

### Testing
* Parser unit tests cover separators, quantity formats, best-effort fallback, sentence-case presentation, acronym formatting, duplicate normalization, quantity merging, incompatible units, blank input, and Paprika reminder-title parsing.
* State-engine unit tests cover every status/action combination, cooldown timing with a controllable clock, invalidated cooldown callbacks, simultaneous event ordering, final-item behavior, undo restoration, automatic progression, selection history, deletion fallback, completion, and manual-mode scope.
* SwiftData tests use an in-memory store to cover persistence, same-day overlay restoration, later-day list routing, date-comparison-before-update ordering, editing, deletion, clearing, and transient-state exclusion.
* Store-config tests decode and validate every bundled JSON configuration.
* Bridge tests validate accepted automation event payloads and reject malformed or unsupported events.
* UI tests cover the main list-to-store flow, row selection, `Show Store`, pull-down dismissal, background and foreground lifecycle behavior, manual fallback, and returning to the saved run.
* Before release, a manual smoke test against the live Coles website verifies search navigation, add detection, quantity changes, removal detection, cooldown behavior, and manual fallback.
  
### Later Scope
#### Platforms
* iPad-specific support.
* Landscape orientation.
* Android App
* Chrome Extension

#### Features
* Multiple saved ListRunner lists.
* Multi-store support
* Store-scoped automation sessions for each active store, so failure counters and manual-mode state do not cross stores during a multi-store run.
* Binding lists to stores and support for multiple store lists on the overview screen. Items can be moved between lists.
* Reordering items within a list via drag and drop.
* Remember selected stores even when app is closed.
* Multi-store shopping in one run.
* Additional grocery websites through bundled store configuration files.
* Remote or community delivery of updated store configuration files.
* Arbitrary store-specific JavaScript hooks when the generic named strategies are insufficient.
* Quantity-unit normalization and conversion, such as combining `1 kg` with `500 g` into `1.5 kg`.
* Ability to mostly hide the overlay in case the user needs to use site functions that are anchored to the bottom of the screen.

### Privacy
* The MVP has no analytics, remote telemetry, user account, or ListRunner backend.
* Grocery lists, item state, source identifiers, and ListRunner diagnostics remain on-device.
* Store automation messages travel only between the injected script and the native app. ListRunner does not transmit them to its own server.
* Coles website traffic remains between the embedded browser and Coles. ListRunner does not read or store Coles credentials or payment details.

### Out of scope
- Pantry/exclusion list feature.
- User accounts.
- Backend sync.
- Payment or checkout automation.
- Automatic product selection.
- Price comparison.
- Meal planning.

### Fallback & Error Handling
If automation is not available, user can still move through items manually and Mark Added. On mobile, a small manual badge will be present to let the users know that the automation is not available.
The user's Coles login state does not determine whether ListRunner enters manual mode. Automation continues while the store page permits the required search and cart actions.

#### Manual mode scope
* Item-level manual mode applies when search or cart confirmation fails for the current item interaction. Multiple automation failures while handling the same selected item count as one failed item interaction. Item-level manual mode affects only that item interaction, and ListRunner attempts automation again when another item is selected.
* When the user leaves an item interaction that required manual fallback, the session's consecutive failed-item count increments once. Completing an item interaction with automatic search and confirmed cart detection resets the count to zero. Two failed item interactions in succession switch ListRunner to session-level manual mode; an isolated successful bridge event within an otherwise failed interaction does not reset the count.
* A store configuration that fails to load enters session-level manual mode immediately. Automation remains disabled for the rest of that store's session.
* Dismissing and reopening the web view does not end the store session or clear session-level manual mode.

#### Possible failure cases
* Store automation unavailable
  * If automation reaches the two-consecutive-failed-item threshold or the active store configuration fails to load, ListRunner enters session-level manual mode. In overlay view, the user will see an icon that triggers a tooltip explaining that automation is unavailable and that they can still proceed manually with the overlay buttons.
* Search is not loading
  * ListRunner waits up to ten seconds for the Coles results page to become recognizable after starting automatic search. If it does not, the item remains `Pending` and enters item-level manual mode. The overlay shows the manual-mode badge with a tooltip explaining that automatic search is unavailable. The user can search with the Coles search bar, use `Mark Added` after finding the item, or press `Skip`. ListRunner attempts automation again when another item is selected.
* Add-to-cart cannot be detected
  * ListRunner cannot know with certainty that add-to-cart detection has failed. If a likely add-to-cart interaction does not produce a confirmable cart signal within three seconds, the current item enters item-level manual mode.
  * In overlay view, the user will see a manual-mode or unconfirmed badge explaining that ListRunner could not confirm the cart change. The user can still add the product on the store website and tap `Mark Added` in the overlay. Manual marking updates the ListRunner item status and triggers cooldown only if another pending item remains, but does not modify the store cart. ListRunner attempts automation again when another item is selected.
* Reminders permission denied.
  * ListRunner shows `Could not access Paprika reminders` and leaves the current list unchanged. The message does not include an `Open Settings` action. The import action becomes available again so access can be retried after the user changes permission externally. Typed, pasted, and manually added grocery lists remain fully available.
* Reminders access restricted, revoked, or read failed.
  * ListRunner shows `Could not access Paprika reminders`, leaves the current list unchanged, and makes the import action available again. The failure does not block typed, pasted, or manually added grocery lists.
* Paprika list not found.
  * ListRunner shows `Paprika list not found` and leaves the current ListRunner list unchanged.
* Multiple Paprika lists found.
  * If more than one accessible Reminders list is named exactly `Paprika`, ListRunner shows `Multiple Paprika lists found` and leaves the current ListRunner list unchanged.
* No new Paprika items.
  * If the Paprika list contains no new incomplete reminder IDs to import, ListRunner shows `No new Paprika items` and leaves the current ListRunner list unchanged.
* Reminder writeback fails.
  * ListRunner keeps the local change and continues without retrying or interrupting the shopping session.

### Store Website Overlay

ListRunner displays a native wizard overlay on top of the grocery store website, anchored to the bottom of the screen. The store remains fully visible and interactive behind it, while the overlay provides navigation through the user's grocery list.

The overlay contains a horizontal carousel of item cards. The item whose `Selected Flag` is `Yes` is centered and visually emphasized with a colored gradient card showing the item name and quantity. If the selected item has `Pending` or `Skipped` status, its action is `Mark Added`. If the selected item has `Added` status, its action is `Add Another`. Every skipped item displays a small `Skipped` badge in the top-left corner of its card. Non-selected added items appear as smaller green cards with an `Added` label and quantity badge. Upcoming pending items appear as neutral white gradient cards.

Below the card carousel are large navigation controls:
- `Back` returns to the last selected item without changing item status. It remains visible but is disabled with reduced contrast when selection history is empty.
- `Skip` is shown when the selected item is `Pending` and skips that item.
- `Next` is shown when the selected item is `Added` or `Skipped` and at least one `Pending` item remains. It advances to the next pending item.
- The user can also tap any visible item card to jump directly to that item and immediately search it on Coles.

During an active cooldown, `Back` is unavailable and `Undo` is shown as a temporary action. `Next` remains available to skip the cooldown. When cooldown ends or is cancelled, `Undo` disappears and `Back` returns.
Tapping another visible item card during cooldown remains allowed. It cancels the cooldown, keeps the previously added item in `Added` status, selects the tapped item, and immediately searches it on Coles.

The shopping-session overlay does not have a separate start or end screen. When no items have `Pending` status, the right-hand `Skip`/`Next` control is replaced by the message `All items handled` with the supporting text `Continue to checkout when ready.` The carousel and `Back` control remain available so the user can select earlier items and make changes. If an item returns to `Pending` status, the normal progression control returns.

The overlay should feel like a lightweight shopping assistant, not a replacement for the store website. The user still selects products and interacts with the real store page; ListRunner only guides the sequence of searches, tracks progress, and provides manual fallback controls when automation fails.

### Store Automation Configs
The MVP uses a generic bundled automation engine with one bundled Coles configuration. The configuration schema is designed so additional grocery websites can use the same engine without changing the core shopping workflow.

Each store configuration defines:
- Schema version.
- Store identifier and display name.
- Supported domains and navigation policy.
- Search URL pattern.
- CSS selectors and strategies for add-to-cart detection.
- CSS selectors and strategies for quantity and removal detection, when available.
- Optional selector and attribute rules for extracting a stable store product identifier from a search result.
- Manual fallback behavior.

The MVP automation engine supports these named strategies:
- URL-template search, which percent-encodes the selected item's search term into a configured URL.
- Selector-based add detection, which recognizes interaction with configured add buttons or quantity inputs.
- Quantity-value observation, which watches configured quantity controls and classifies a stable committed value as an add, remaining-added quantity, or removal to zero. The initial observed value establishes a baseline without emitting an event, repeated reports of the same resulting value are ignored, and one physical cart change produces at most one ListRunner transition.

Injected JavaScript communicates with native Swift through versioned JSON bridge messages. Each message contains:
- Message schema version.
- Event type.
- Store identifier.
- Store automation session ID.
- Interaction ID generated when ListRunner selects and searches an item.
- ListRunner item ID associated with that interaction.
- Current page URL.
- Store product ID when the page exposes one.
- Resulting quantity when available.

The MVP bridge accepts only these event types:
- `addDetected`
- `quantityChanged`
- `removalDetected`
- `searchReady`
- `automationUnavailable`

Every ListRunner item selection and ListRunner-triggered search creates a new interaction ID. Manual Coles search refinement and same-domain navigation retain the active interaction and selected ListRunner item. Multiple Coles product results can report events for the same ListRunner item and interaction while retaining distinct store product IDs. Confirmed product associations and their latest quantities are retained for that ListRunner item for the active run, including after a new interaction is created. A direct user action on a specific product control arms a three-second confirmation window for that product. Only a matching stable cart change during that window can update the selected ListRunner item. Quantity changes caused by cart restoration, page rendering, synchronization, or another source without an armed direct interaction update the observed quantity baseline but do not change ListRunner status. Native code validates each message against the supported message schema, active store configuration, current `WKWebView` domain, allowed event types, active session ID, active interaction ID, associated item ID, armed store product ID, and confirmation window before forwarding it to the shopping-run state engine. Delayed, duplicate, passive, or otherwise stale messages are ignored and logged locally. Bridge messages do not contain store credentials, payment details, or arbitrary page content.

Each undo record stores whether its cooldown originated from a confirmed Coles cart change or from a ListRunner-only action. Store-cart reversal is allowed only when that exact undo record originated from a confirmed cart change and contains the matching session ID, interaction ID, store product ID, before quantity, after quantity, and detected delta. Manual `Mark Added` and `Add Another` create ListRunner-only undo records and never request a Coles cart change. For an undo following a confirmed quantity increase, the strategy attempts to decrement exactly the detected quantity delta rather than remove the entire product, preserving any pre-existing quantity, but only when the current cart quantity still matches the recorded after quantity. If the cart changed again, or if any required correlation value or supported reversal strategy is unavailable, ListRunner still restores its own state, does not attempt product-specific cart reversal, and shows a non-blocking inline shopping-overlay banner reading `Could not undo store cart change` with an explicit close action. The banner is informational only and has no retry action. VoiceOver announces the banner, and the close control is labeled `Dismiss cart undo warning`. The banner remains until dismissed or the user navigates away, and is not persisted across relaunches.
Removal events without a valid active session, interaction, item, or correlated store product ID are ignored and do not change ListRunner item status. The Coles website remains the source of truth for the uncorrelated cart change.

Store configurations are data-only JSON files bundled with the app and decoded into typed Swift models using `Codable`. They may select only named detection strategies implemented by the generic bundled engine and cannot include executable JavaScript. Supported domains must use HTTPS and match an explicit host allowlist. Automated validation tests decode every bundled configuration and fail for unsupported schema versions, missing required fields, non-HTTPS domains, domains outside the host allowlist, or unsupported detection strategies. The engine and configurations are versioned and shipped with the app. Additional store configurations, remote configuration delivery, and arbitrary store-specific JavaScript hooks are later scope.

If the active store configuration unexpectedly fails to decode at runtime, ListRunner opens the store without injecting automation scripts and enters session-level manual mode. Native overlay navigation and `Mark Added` remain available, the manual-mode badge explains that automation is unavailable, and the decoding error is logged locally. Configuration failure must not crash or block the shopping session.

### App metadata model
The app-level metadata record contains:
- Last active local calendar date
  - Optional until the first launch destination has been chosen.
  - Stored independently of the grocery list and used to choose same-day overlay restoration or later-day list/summary routing.

### Core list model
The single active list contains:
- List ID
  - Required stable UUID generated by ListRunner.
- Items
  - Ordered relationship to the list's grocery items.
- Last overlay-selected item ID
  - Optional until the list first opens in the overlay.
  - References an item in the list and drives `Show Store` restoration.

### Core item model
For each grocery item, the following fields exist:
- Item ID
  - Required stable UUID generated by ListRunner.
  - Used for persistence, selection history, and deletion without relying on item text.
- List position
  - Required integer defining the item's order in the list and overlay carousel.
- Item name
  - Required
- Search term
  - Required
  - Derived from the item name and updated whenever the item name changes.
- Quantity amount
  - Optional numeric value; supports whole numbers and decimals.
  - Display guidance only; it does not control the Coles cart quantity.
- Quantity unit
  - Optional text or recognized unit such as `g`, `kg`, `L`, `cans`, or `packs`.
  - Display guidance only; it does not control the Coles cart quantity.
- Paprika reminder ID
  - Optional
  - Present only for items imported from Apple Reminders and used to synchronize completion and prevent duplicate imports.
- Selected Flag
  - Derived rather than persisted.
  - `Yes` when the item ID matches the list's last overlay-selected item ID and `No` for all other items.
  - Before the overlay has a recorded selection, the first item in list order is treated as `Yes`.
- Status
  - Required
  - New items default to `Pending`.
  - Enumerations
    - Skipped
    - Pending
    - Added

### Progression Rules
The selected card action and right-hand navigation control are determined by the following table when at least one `Pending` item remains:

| Selected item status | Card action | Right-hand control |
|---|---|---|
| `Pending` | `Mark Added` | `Skip` |
| `Added` | `Add Another` | `Next` |
| `Skipped` | `Mark Added` | `Next` |

When no `Pending` items remain, `All items handled` replaces the right-hand control regardless of the selected item's status.

- The selected card displays the status label `Added` for an `Added` item and `Skipped` for a `Skipped` item. A `Pending` card does not display a `Pending` label; its pending state is conveyed by the available actions and surrounding context.

- Before an add starts cooldown, ListRunner temporarily records the item's current status for `Undo`. This pre-action status is transient and is discarded when cooldown ends or is cancelled. If another automatic add arrives during cooldown, the current `Added` status replaces the previous undo target so `Undo` applies to the latest add without returning the item to `Pending` or `Skipped`.
- Selecting `Mark Added` on a skipped item records `Skipped` as the pre-action status, changes the item to `Added`, and starts cooldown only if at least one `Pending` item remains.
- Manual `Mark Added` records the current status, changes the item to `Added`, and starts cooldown only if at least one `Pending` item remains. Its undo record is ListRunner-only and never requests store-cart reversal.
- Tapping `Add Another` does not modify the Coles cart, and the item remains `Added`. If at least one `Pending` item remains, ListRunner records `Added` as the pre-action status, creates a ListRunner-only undo record, and starts or restarts the three-second cooldown. Otherwise, no undo state or cooldown is created and `All items handled` remains visible.
- When an add handles the final `Pending` item, no cooldown starts. That item remains selected and the right-hand navigation area immediately displays `All items handled`.
- `Undo` during cooldown cancels the timer and restores the recorded pre-action status. Undoing the first add therefore restores `Pending` or `Skipped`, while undoing `Add Another` leaves the item `Added`. Reversing the store cart change remains best-effort.
- Selecting another item during cooldown cancels the timer without changing the previous item's `Added` status, then selects and searches the chosen item.
- Pulling down to dismiss the Coles web view during cooldown cancels the timer, keeps the current item in `Added` status, invalidates the active interaction ID, and ignores delayed bridge messages for that interaction.
- When cooldown completes or the user skips the cooldown with `Next`, ListRunner advances to the next item with `Pending` status. Items that are already `Added` or `Skipped` are passed over.
- Automatic advancement caused by cooldown completion, `Next`, or `Skip` is added to selection history. `Back` therefore returns to the item that was selected immediately before the automatic advancement.
- `Skip` is used when an item is unavailable at the store or not applicable to the current shopping run. Skipping changes the item status to `Skipped`. If another `Pending` item remains, ListRunner advances to it immediately. If the skipped item was the final pending item, it remains selected and `All items handled` appears immediately. Skipped items are not automatically revisited at the end of the run.
- `Back` only moves focus to the last selected item. It does not change the status of the current item or the destination item. This is based on selection history rather than list order, because users can tap item cards several items backward or forward.
- `Back` removes the destination entry from selection history and does not add the item being left back into history. Repeated taps therefore continue walking backward instead of alternating between two items.
- Tapping the already-selected item does not add a duplicate entry to selection history.
- Selecting a different item by tapping a card or list row pushes the previously selected item ID onto selection history before changing selection. This also applies when card selection cancels an active cooldown.
- Tapping an item card makes that item the current focus and immediately searches for it on Coles.
- Tapping an item on the list/summary screen follows the same selection and search behavior as tapping an item card, then opens the overlay. Selection alone does not change item status.
- Completion is derived from item statuses rather than represented by a separate state: when no items are `Pending`, the overlay displays `All items handled` in place of `Skip`/`Next` while keeping item navigation available.
