# Add a website product to the current store list

## Agreed interaction

The expanded shopping overlay exposes an **Add store item to list** control at
either end of the card rail. Cards cover the controls while browsing the middle
of the rail. The action is also available without horizontal scrolling through
an accessibility action and the collapsed bar. Existing card selection, collapse,
Back/Skip/Undo and retailer cart behavior remain unchanged.

On a recognised product page, read its explicit product heading. On a grid,
temporarily hide the cards and place ListRunner-owned selection shields over
recognised product tiles. Tapping a shield selects that product, never clicks or
replays the website link/Add button. A native Cancel/manual-entry bar stays visible.
Scrolling remains possible. Reposition shields as the layout changes and re-read
the exact tile at selection time; reject ambiguous links/names and stale tiles.

Show a native review sheet with editable product name and quantity (default 1),
the destination store, Add and Cancel. Only Add saves a Pending ListRunner item.
Preserve the current card, page, history and scroll position. Reuse store-local
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
