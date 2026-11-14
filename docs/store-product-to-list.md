# Add a website product to the current store list

## Agreed interaction

The expanded shopping overlay exposes an **Add item to your list** control at
either end of the card rail. Cards cover the controls while browsing the middle
of the rail; each control fades with the square of its uncovered fraction as cards
cover it (half uncovered means 25% opacity, rather than the earlier 50%),
without a delayed opacity animation or a tappable area over the cards.
Both end labels have 24 points of top padding, weighting the icon/text lower in
their slots while keeping the slot bottom clear of the Back/Skip navigation row.
The action is also available without horizontal scrolling through
an accessibility action and the collapsed bar. Existing card selection, collapse,
Back/Skip/Undo and retailer cart behavior remain unchanged.

The left/leading control captures **Start of list**; the right/trailing control
captures **End of list**. Preserve that choice through grid selection, direct
detail reads, manual/assistive fallback, review and save retries. The native review
shows its Position and the controls announce their destination edge. The collapsed
shortcut and generic accessibility action retain the existing add-to-start default.
An existing matching item still merges/reactivates, but moves to the chosen edge
without creating a duplicate. Untouched items retain their relative order. The
position applies to the browsed store's list/card queue in either list scope;
All items grouping/category recency rules are otherwise unchanged. Typed input
and imports retain their existing ordering defaults.

After a successful save, reveal the saved product as the middle card without
making it active. Use the persisted UUID returned by saving (including a merged
row), not a name match or guessed index. Keep the active item, selection history,
website search/cart attribution and shopping controls unchanged. A collapsed
shortcut expands back to the cards to show the result. Cancelled or failed saves
do not reveal a new product. Explicitly selecting/tapping a card resumes normal
centring; tapping the still-active card also recentres it without changing history.
Keep distinct edge padding for 160-point active and 145-point inactive cards so a
new card can be exactly centred even at the start/end. Do not reorder saved items
just to centre a card; left/start and right/end persistence still apply.

Entering highlighted-product selection hides the existing rail without destroying
its ScrollView. Cancel (including manual-review Cancel) reveals the same horizontal
offset, not the active-card centre, and preserves collapsed/expanded state. Clearing
an old saved-product reveal on entry must not issue a scroll. Only successful saves
reveal the saved card; cancelling after a previous reveal keeps the user's current
rail position. Active item, website page and list data remain unchanged.

On a recognised product page, read its explicit product heading. On a grid,
temporarily hide the cards and place ListRunner-owned selection shields over
recognised product tiles. Tapping a shield selects that product, never clicks or
replays the website link/Add button. A native Cancel/manual-entry bar stays visible.
Scrolling remains possible. Shields use document-plane absolute positioning,
outside retailer tile/link subtrees, so ordinary page scrolling moves products
and shields together without JavaScript chasing viewport coordinates. A separate
transparent fixed blocker prevents unrelated website taps. Coalesce mutation,
resize, image/font-load and nested-scroll geometry updates into animation frames;
do not poll positions on a timer. A single 60-second deadline still bounds the mode.
Reposition shields as the layout changes and re-read
the exact tile at selection time; reject ambiguous links/names and stale tiles.
For VoiceOver or Switch Control, grid selection falls back to the native manual
composer: assistive activation can target an underlying website element without
visual hit testing. Product-page reads still prefill the native review. Enabling
either assistive technology during grid selection cancels the shields safely.

Show a native review sheet with editable product name and quantity (default 1),
the destination store, Add and Cancel. Only Add saves a Pending ListRunner item.
Preserve the active card, page, history and website scroll position; only the card
rail reveals the successfully saved product. Reuse store-local
duplicate merging, save-before-side-effects and store-promotion behavior. Do not
split or ingredient-parse product names containing commas or quantities. Do not
persist website URLs, prices, account data or image data in the shopping schema.

## Data and safety

Schema 8 adds optional `productSelection` data, independent of cart capability:
`productURLPattern`, `grid {containerSelector, titleSelector, linkSelector}` and
`detail {containerSelector, titleSelector}`. Old schemas 2–7 remain readable;
automationSchemaVersion keeps its existing meaning. Definitions opt in only with
explicit selectors; absent or unusable selectors offer manual entry, not broad DOM
or metadata guesses. The initial profile covers Bunnings AU with public rendered
grid and detail selector evidence. Coles returned an empty document and Woolworths
returned Access Denied during read-only inspection; do not guess their selectors.
IKEA's grid was readable but needs separate detail/profile review. Other stores
offer manual entry until individually reviewed. Live native verification remains
a release gate.

Read public rendered DOM only, in the existing isolated WebKit world, on the active
trusted main-frame store document. No retailer APIs, credentials, storage reads,
cart mutations, checkout actions or synthetic retailer clicks. Bound nodes, text,
time and configuration size. Abort on navigation (including same-document URL
changes), backgrounding, dismissal, verification/recovery or reset. Keep old async
results from affecting a newer request. Clear shields/listeners/timers on every
exit. Pause automatic card progression and cart attribution while choosing/reviewing.

## Implementation and validation plan

1. Extend and test the strict configuration contract and initial profiles.
2. Add bounded isolated-world product reading and temporary grid shields, with
   offline DOM tests for identity, scrolling/layout changes, cancellation and no
   website click-through.
3. Add rail-end controls, selection-mode chrome and the native review sheet.
4. Wire both store-list and All items shopping flows into safe local persistence.
5. Run offline regression checks, commit/push the isolated branch, then build/test
   that exact revision in a separate Mac worktree without touching another agent's
   checkout or simulator. Record any unverified native/live behavior honestly.

Design reference: `docs/openpencil-screen-audit.md`, Shopping Flow card dimensions,
material/card overlap and existing adaptive native controls; user-provided Bunnings
screenshots establish the new rail-end placement. No existing OpenPencil document
is modified as part of implementation.
