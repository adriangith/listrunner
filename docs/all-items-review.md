# All items implementation review

Reviewed against the approved All items plan and the pre-feature baseline
`18347796fef55944e6e7708f89217c5fba3240be`. Application revision:
`429a58f93edd75c67ab5dd7760cafe833bae249e` on `feature/all-items-screen`.

## Scope and invariants

- All items is a projection over existing `GroceryItem` records, not a new store,
  database list, mixed-store shopping queue, basket or browser session.
- Store/list/website-data identifiers, retailer trust rules and automation ceilings
  are unchanged. The category fingerprint test checks non-metadata resource content.
- Manual entry uses shared destination-specific staging. Imports use the existing
  Paprika transaction/removal safeguards, hosted with an immutable destination.
- Grouping reads category metadata without reassigning items. Historical rows use
  deterministic list order; successful additions/imports alone record new promotion
  order in UUID-keyed preferences. No new SwiftData schema or migration was needed.
- Nonempty-list protection runs at the shared visibility mutation boundary, using
  fresh saved-row counts. Lookup errors, unsaved local mutations and active imports
  block replacement rather than pretending a list is empty.
- Hidden, unavailable and unknown-owner rows remain visible with local recovery
  actions. They are excluded from add/shopping destinations, not deleted or enabled.

## Findings fixed during implementation/review

1. **Runtime schema-7 rejection:** the strict JSON-key allowlist initially omitted
   `category`, leaving the app with no available stores. Both native decoding paths,
   round-trip coverage and onboarding validation now accept the correct versioned
   contract.
2. **Regional replacement bypass:** enabling another regional destination could
   implicitly disable a populated hidden sibling. Every actually removed visible
   ID is now checked, including brand enabling and region changes. Reselecting the
   current region remains harmless.
3. **Stale/failing empty-list checks:** view-local snapshots could be empty or stale.
   The root supplies the main-context lookup to shared preferences; read failures,
   pending saves and in-flight imports fail closed. Settings and regional View List
   routes now return to the affected list (or recoverable All items view).
4. **Composer and control reachability:** scrolling previously hid the composer;
   modifiers outside Button labels did not provide real 44-point hit targets.
   Entry is pinned independently of grouped rows, controls have explicit label hit
   areas, and accessible group-heading rows can be revealed with the new item.
5. **Scope/draft loss:** shopping and import handoffs previously replaced All items
   with a store screen. They now use scoped sheets and return to the aggregate;
   scope, grouping, destination and draft have independent persisted preferences.
6. **Cross-store ordering:** store-local positions cannot represent actual recent
   additions across a category. UUID-based sidecar order preserves batch order,
   duplicate reactivation and cross-store recency without changing old records.
7. **Quantity-unit loss:** merging a parsed measured quantity into an unspecified
   existing item now retains its unit, using the same staging code in both screens.
8. **Version/generator drift:** native schema 6 now retains its original vocabulary;
   schema 7 rejects legacy-only category types. Disabled schema-2 onboarding drafts
   receive an explicit unknown compatibility category, keeping generated Swift
   exhaustive without guessing a new retailer category.
9. **Save/reset recovery:** failed additions keep the draft and do not promote rows;
   reminder writeback remains save-gated. Confirmed local reset clears new aggregate
   preferences together with the database, while diagnostics clearing does not.
10. **Visual keyboard overlap:** an exported passing-test screenshot revealed the
    shopping footer covering the newest row, despite it being above the keyboard.
    The secondary footer now compacts while typing; the viewport test asserts its
    absence. The final screenshot confirms the new row and its heading are clear.

No unresolved high-severity correctness finding remains from this source review.
Validation results and any test-infrastructure limitations are recorded separately
in `packages/ios/VALIDATION.md`; a source review is not release certification.

Final combined simulator run: **11/11 focused UI tests passed, zero failures/skips**
on the revision above. The complete Mac offline gate passed with **1,881 native**,
**449 parser**, **195 regional-search** checks and all schema/onboarding/JavaScript
gates; shared offline-tested sources are unchanged since that gate. The actual app
bundle's 35 JSON + 1 JavaScript resources match canonical source. A final real-keyboard
screenshot was visually inspected at `/tmp/opencode/all-items-final-keyboard.png`.

## Remaining validation boundaries

- iOS 17 runtime, manual VoiceOver/Switch Control, the largest accessibility text
  sizes, smaller iPhones and a complete light/dark/Reduce Motion visual audit still
  require manual/device coverage. The deployment target remains iOS 17.
- The OpenPencil MCP document-list request repeatedly timed out. The approved plan
  and repository specification were used, but the external design document has not
  been updated or claimed as reviewed against the final implementation.
- No live Paprika permission/removal operation or retailer-cart mutation was part of
  this task. Fixture tests cannot certify those live environments.
- No merge, physical-device installation, TestFlight delivery or release is included.
