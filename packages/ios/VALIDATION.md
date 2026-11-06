# Reusable store framework validation

## All items per-group Clear List (6 November 2026)

Revision `2b09bf24acdca5575293db6ac809a99a80c661c8` adds a shared `ClearListButton`
to each displayed All items group and reuses that exact component on store-list
pages. The existing red label, trash icon and 56-point minimum content target are
preserved. Confirmation offers Clear Added (only for Added rows in that group),
Clear All and Cancel. The user explicitly chose to include category groups:
category confirmation states that its scope spans the category's store lists.

Clearing snapshots the confirmed IDs and intersects them with the current group,
so new imports and moved rows cannot expand the deletion. It ends interactions only
for affected known owners, repairs affected selections and positions, cancels queued
writeback for removed rows, clears their transient highlights and saves once.
Retailer carts and Apple Reminders are not changed. Unavailable and unknown-owner
groups remain independently clearable, with no invented owner or reassignment.

- Final Xcode build-for-testing passed, zero errors.
- Final three group-clear regressions: **3/3 passed**, zero failures/skips, on
  iPhone 17 / iOS 27.2: store Cancel/Clear Added/Clear All with other owners retained;
  cross-store category Clear Added/Clear All preserving Pending/Skipped and another
  category; independent unavailable/unknown-owner clears. Persistence is checked
  after relaunch. Tests require the entire action to scroll above Show Store.
- Final Mac result bundle:
  `/Users/adrianzafir/Library/Developer/Xcode/DerivedData/ListRunner-epzzinbppcxqwyevzuqhzfuvrvzc/Logs/Test/Test-ListRunner-2026.11.06_13-21-34-+1100.xcresult`.
  The Xcode MCP reader reported an incomplete bundle; direct `xcresulttool` reading
  of the completed canonical bundle confirmed Passed, 3 passed, 0 failed/skipped.
- Six other regressions passed in the preceding combined run at `218bfc6`: the
  four standard-store clear tests (wide target, Added-only, mixed statuses, Cancel/
  Clear All), aggregate reorder/persistence and repeated keyboard entry. Application
  source is unchanged since `003421e`; later revisions refine test setup/scrolling.
  That preceding run was **6 passed / 3 failed**, not a clean 9/9: full swipes skipped
  virtualized groups. Slow bounded drags and scrolling lazy rows into view fixed the
  group-test navigation. Earlier initial failures also assumed Coles rather than
  explicitly selecting it after first-store setup; clear tests now choose it.
- Final screenshot exported and visually reviewed:
  `/tmp/opencode/all-items-clear-list-final.png`, confirming the shared button is
  fully visible above the glass shopping footer, not merely hittable through it.

No physical-iPhone installation, live shopping/reminder mutation or release occurred.

## All items Settings and Edit controls (6 November 2026)

Revision `ec36945ee7a82d2c503821fc47169e18697eb1c5` adds the shared Settings
overview and native leading Edit/Done button to All items. Settings retains the
aggregate draft, destination and grouping; its import/source and View List routes
reuse existing flows. Edit dismisses the keyboard and temporarily displays store
groups, without overwriting the remembered grouping. Native reorder handles update
positions only within the same store-owned list. Unknown-owner rows retain local
recovery actions but are not assigned a fabricated reorder owner. Emptying all lists
exits edit mode. Settings remains available even when lists are empty.

- Xcode build-for-testing: passed, zero errors.
- Final iPhone 17 / iOS 27.2 combined UI run: **6/6 passed**, zero failures/skips:
  Settings return preserving scope/draft/destination/grouping; real native reorder
  followed by relaunch and verification in the owning store's list (other ownership
  unchanged); populated-only shopping chooser; repeated entry/preferences; Paprika
  handoff; unavailable/unknown-owner recovery.
- The first reorder test used an inherited destination and a drag ending at the
  adjacent handle's centre. It failed its order assertion. The corrected regression
  chooses Coles explicitly, drags above the previous row, waits for settled geometry
  and verifies saved order after relaunch; both its focused retry and final combined
  run passed.
- Mac result bundle:
  `/Users/adrianzafir/Library/Developer/Xcode/DerivedData/ListRunner-epzzinbppcxqwyevzuqhzfuvrvzc/Logs/Test/Test-ListRunner-2026.11.06_12-09-52-+1100.xcresult`.
- Exported screenshot visually reviewed:
  `/tmp/opencode/all-items-settings-edit.png` (standard Settings gear, native Done,
  per-store reorder handles, and reordered Coles rows).

No physical-iPhone installation, live retailer mutation or release was performed.

## All items Show Store chooser (6 November 2026)

Application revision `c1982a5eb982de580267aaddf30416d001b74810` reuses the standard
`StoreLaunchButtonStyle` for the All items footer, labelled **Show Store...**. The
shopping chooser intersects available stores with current nonempty list IDs,
including all item statuses. Scope and add-destination choices are unchanged. The
footer remains hidden while typing; unavailable/unknown-owner recovery is preserved.

- Xcode build-for-testing passed, zero errors.
- iPhone 17 / iOS 27.2 focused UI run: **4/4 passed**, zero failures/skips: new
  populated-list chooser regression (enabled empty Costco excluded, Coles and
  Woolworths offered, chosen store opens and dismisses back to All items), existing
  item-row shopping return, repeated keyboard entry, unavailable/unknown recovery.
- Mac result bundle:
  `/Users/adrianzafir/Library/Developer/Xcode/DerivedData/ListRunner-epzzinbppcxqwyevzuqhzfuvrvzc/Logs/Test/Test-ListRunner-2026.11.06_11-50-24-+1100.xcresult`.

Not installed on the physical iPhone; no live retailer actions, data reset or release.

## All items standard composer styling (6 November 2026)

Application revision `1a5b8d27173907dd4e73e45f3ff146520633f8a9` on
`feature/all-items-screen` reuses the standard `ProductEntryEditor` and shared
`ProductEntryFieldStyle` for All items. The subdued external Add products heading,
rounded card, outlined input and checklist Import action match the standard entry
area, retaining the destination-specific split Add button. Layout priority and a
single-line label prevent the destination button wrapping at standard text size.

- Xcode build-for-testing passed with zero errors.
- Focused iPhone 17 / iOS 27.2 simulator run: **4/4 passed**, zero failures/skips:
  aggregate add/grouping, repeated entry/preferences, Paprika scope/draft/destination
  handoff, and standard empty-Return keyboard dismissal.
- Tests verify the split Add remains 44–48 points high at standard text size, its
  arrow retains a 44-point hit target, and the shopping footer is absent while typing.
- Result bundle on the Mac:
  `/Users/adrianzafir/Library/Developer/Xcode/DerivedData/ListRunner-epzzinbppcxqwyevzuqhzfuvrvzc/Logs/Test/Test-ListRunner-2026.11.06_11-41-16-+1100.xcresult`.
- Exported screenshot inspected on Linux:
  `/tmp/opencode/all-items-standard-composer-final.png`. It confirms the outlined
  standard input, one-line destination button, visible keyboard and unobstructed
  newest row; UIKit's AutoFill popover partly covers Import in that captured frame.

This styling revision has **not** been installed on the physical iPhone; the phone
still has reviewed revision `cd2c319`. No reset, live import or retailer action was
performed. Broader accessibility/appearance certification remains as noted below.

## All items scope and category schema 7 (5–6 November 2026)

Application revision `429a58f93edd75c67ab5dd7760cafe833bae249e` is pushed on
`feature/all-items-screen` and checked out on the canonical Mac. Linux checkout:
`/home/claude-svc/listrunner-main`; Mac: `/Users/adrianzafir/Projects/listrunner`.
The Mac's unrelated untracked `xcshareddata/xcodecloud/` directory is preserved.

All items aggregates existing store-owned rows with a pinned composer, independent
scope/grouping/destination/draft preferences, UUID-based cross-store promotion order,
and scoped shopping/import sheets. Existing SwiftData schemas/migrations, retailer
identities, trust rules and capability ceilings are unchanged. Disabled/unavailable
and unknown-owner records remain visible and locally recoverable. Visibility changes
read current saved rows and fail closed on unreadable/unsaved changes or active
imports. See `docs/all-items-review.md` for the final source review and fixed findings.

Validation on the Mac:

- Complete `run-cloud-checks.sh` passed at `a4301dd` (shared core, schema, generator
  and recovery sources are unchanged in the final application revision): Python and
  JavaScript offline gates, **449 parser checks**, **195 regional-search checks**,
  synthetic registration proof and **1,881 native recovery/reset/diagnostic checks**.
  SSH required `/opt/homebrew/bin` in PATH; no dependencies were installed.
- Xcode 27.2 Debug simulator build-for-testing passed on the final UI revision,
  with no build errors.
- Actual Debug app bundle verified byte-for-byte: **35 JSON + 1 JavaScript** resources,
  with no duplicate legacy `-v2` resources.
- **Final combined simulator UI run: 11/11 passed, zero failures/skips**, on
  `429a58f93edd75c67ab5dd7760cafe833bae249e`, iPhone 17 / iOS 27.2. Coverage includes
  destination add/grouping, repeated real-keyboard entry and preference/draft
  restoration, Paprika destination/scope/draft retention, Pending/Added-only disable
  recovery, all-hidden stores, regional replacement protection, shopping-sheet return,
  Grocery versus Groceries & Home promotion, and unavailable/unknown-owner recovery.
  Result bundle on the Mac:
  `/Users/adrianzafir/Library/Developer/Xcode/DerivedData/ListRunner-epzzinbppcxqwyevzuqhzfuvrvzc/Logs/Test/Test-ListRunner-2026.11.06_10-51-08-+1100.xcresult`.
- Final screenshot reviewed: `/tmp/opencode/all-items-final-keyboard.png` on Linux,
  exported from that result bundle. It confirms the pinned composer, visible category
  heading and unobstructed newest row above the real keyboard. Visual review caught
  the old shopping footer overlapping the row; `429a58f` compacts that footer while
  typing and tests assert it is absent. Broader manual accessibility/appearance
  certification remains separate.
- Earlier direct command-line attempts at `/tmp/listrunner-all-items-final-a4301dd.xcresult`
  and `/tmp/listrunner-all-items-retry-a4301dd.xcresult` were killed before assertions.
  Xcode still held an interrupted test session; stopping it and returning to the Xcode
  testing API restored execution. Do not count those runner failures as passes. The
  simulator was restarted without erasing state. An intermediate 10/11 run exposed
  a native menu hit-point flake; the test now taps the menu item's centre explicitly.

Fresh Linux checks: all **431 JavaScript tests** passed; category **2**, onboarding
**20**, expansion **3**, bundled-resource **9** Python tests passed; `git diff --check`
passed. Mac-only registration compilation is covered by the full Mac offline gate.

Earlier test failures exposed and fixed the omitted runtime `category` allowlist,
stale fixture/navigation assumptions, insufficient actual Button hit areas and
inaccessible first-section headings during scroll reveal. Final-review fixes also
covered implicit hidden-sibling replacement, version-specific category vocabularies,
draft-generator exhaustiveness, unspecified-quantity units, import promotion and
local preference reset boundaries.

Storage interruptions were infrastructure problems, not passing test evidence.
With user approval, regenerable Xcode builds/index/compiler caches, the older
`iPhone14,5 27.2 (24B115)` symbol cache, non-Chrome updater/package/Spotify caches
were removed. Newer device symbols, simulator/preview state, signing data, archives,
source and Chrome were preserved. Old task test bundles were transferred to Linux
and SHA-256 verified before removing their Mac copies:
`/tmp/opencode/all-items-mac-test-evidence-20261105.tar.gz` and
`/tmp/opencode/all-items-mac-test-evidence-20261106-pre-review.tar.gz`.

Remaining boundaries: iOS 17 runtime and manual large-text/small-device,
VoiceOver/Switch Control, light/dark and Reduce Motion review are not certified.
OpenPencil document access repeatedly timed out, so that external reference has not
been updated; the approved plan and repository specifications remain authoritative.
No physical-device install, live retailer/cart or live Reminders operation, merge,
TestFlight delivery or release was performed.

### Authorized iPhone deployment (6 November 2026)

At the user's explicit request, revision
`cd2c3198a6cd07c44e5f313abbeb412aad1bab14` from `feature/all-items-screen` was
built, installed in place and launched on **Adrian’s iPhone / iOS 27.2** through
Xcode's `RunProject` action. No build errors; launch succeeded (PID **18513**).
The scheme had no enabled launch arguments or environment overrides. Actual
Debug-iphoneos bundle verification passed for all **35 JSON + 1 JavaScript** resources.
No reset, test fixture, import/reminder operation or retailer/cart interaction was
performed; existing app data and sessions were left intact. This is a development
installation, not a merge, TestFlight delivery or release.

Mac evidence:
`/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261106-112309.txt`.

## Native retailer categories — schema 6 (5 November 2026, historical validation)

Review reconciled this change with main at `a39376ff184769349c711824d9399067754f97f4`.
Schema 5 was already used by IKEA's snapshot engine, so category metadata now uses
schema 6. All **33 destinations** have typed categories and preserve their prior
`automationSchemaVersion` (2–5). Schemas 2–5 retain their original wire format.
The review also fixed encoding of the required null cart field and added all-store
round-trip coverage. The taxonomy and assignment are in `docs/store-categories.md`.

The exhaustive category test fingerprints each current-main resource after removing
only schema/category/compatibility metadata. No host, capability, cart rule, result
target, or search route differs from that baseline. Existing Tesco sign-in/quantity
and IKEA snapshot behavior remain version-gated by the preserved automation version.
Inherited marketing-site commits were excluded from the task-only integration.

Validation of application revision `63b8e08` on an isolated Mac checkout passed:

- Complete `run-cloud-checks.sh`: Python and Node gates, 449 parser checks,
  195 regional search checks, synthetic-store proof and **1,862 native checks**.
- Xcode 27.2 Debug simulator `build-for-testing` and Release simulator build.
- Actual Debug and Release app bundles: all **35 JSON and 1 JavaScript** resources byte-match
  canonical source, with no legacy `-v2` resources.
- Subsequent Linux run: all **431 JavaScript tests** passed, including added
  schema-5/6 IKEA parity; onboarding suite **20 tests**, category suite **2 tests**.

Application source and project in task-only integration `3ab9a2a`
are identical to validated `63b8e08`; subsequent differences are tests/docs only.
The full Mac offline gate passed again at integration revision `4c6d7a3`, including
the expanded IKEA/Tesco JavaScript allowlist and 20 onboarding tests.
Mac logs and result bundles remain outside the checkout under
`/tmp/listrunner-categories-*`. Focused fixture UI results are recorded below when
complete. The first three UI cases failed on stale main-branch fixture assumptions:
discovery expected intentionally hidden New World, and two cases assumed Coles was
active after setup selected Woolworths. Test-only follow-up explicitly selects Coles
for those cases and asserts unverified-search destinations remain hidden.
No physical-device install, live retailer/cart operation, user-data reset,
distribution, or SwiftData migration was performed.

At `f007162`, the corrected focused fixture UI rerun passed **3/3 tests, zero
failures**, on a dedicated iPhone 17 / iOS 27.2 simulator: expansion discovery and
separate Target brands, store-list/status isolation, and hide/re-enable list
preservation. Result bundle: `/tmp/listrunner-categories-ui-rerun.xcresult`;
console: `/tmp/listrunner-categories-ui-rerun.log`. The initial failed run is retained
at `/tmp/listrunner-categories-ui.xcresult`; it is not counted as a pass.
## Change-gated nightly beta pipeline — 4 November 2026

Implementation `02f6c54` plus queued-source-metadata safeguard `2ee3ac492571f0db09b32dd8587231f0a2034209` provides the user-approved policy: **beta prereleases and app-related changes only**. GitHub owns the approximately 02:07 Melbourne decision; a net diff against the last published automated prerelease determines whether to build. Bootstrap is uploaded/processed 1.0 (5), source `28baa28`. Annotated daily request tags pin source, baseline and generated notes; successful releases—not requests or archive results—advance the baseline. Retries/reconciliation survive failed jobs, invalid uploads, pending metadata and runner cancellation; same-date requests never start twice. App Markdown, website and tester-notes-only updates skip new builds. No release-note commits are pushed to main.

**23 offline automation tests passed** locally and in the final GitHub Actions read-only preview. The existing **10 Python cloud-hook/archive tests passed**. Full Mac `ci_post_clone.sh`/cloud offline gates passed at `02f6c54` (22 automation tests before the additional queued-metadata test, 449 parser, 195 regional, synthetic registry proof, 1,789 native checks and the existing Node/Python suites). The first raw SSH gate attempt lacked Node on PATH and stopped; rerunning the actual bootstrap hook with the installed Homebrew Node path passed. Final read-only GitHub job: https://github.com/adriangith/listrunner/actions/runs/41827823249 . Earlier preview `41827033911` also passed. These previews did not start Cloud builds, create request tags or publish releases.

Live App Store Connect API verification succeeded using a dedicated team API key stored only as the encrypted GitHub Actions secret `ASC_PRIVATE_KEY`, with non-secret ID variables. The **Default** Cloud workflow remains enabled/clean, its scheduled start was removed, other automatic starts are null, and manual starts for `nightly/request-` tags are enabled. Existing archive and external TestFlight post-action settings were not replaced. GitHub workflow state is active; live preflight verified repository/app identity and manual-only conditions. Backup of the former workflow response is `/tmp/opencode/listrunner-workflow-before-nightly-automation.json` on Linux. Source of truth/configuration and pause/recovery guidance: `packages/ios/XCODE-CLOUD.md` and `packages/ios/nightly-beta.json`.

User approved declaring no non-exempt encryption after the source check found no custom cryptography/library. Canonical metadata now has `ITSAppUsesNonExemptEncryption=false`, set through Xcode at `1e8d173`; 9 resource checks passed after Xcode's comment-only project normalisation. Build 5 originally archived/uploaded/processed but its external-testing post-action failed with “Missing encryption compliance declaration”. A later API read already showed its answer as false; an attempted identical update was rejected with 409 and was not forced. That historical Cloud run remains failed; it is not a successful automated prerelease. Future builds include the approved declaration; reassess if cryptography/dependencies change.

**First live nightly start, dynamic cloud-side note discovery, TestFlight distribution and GitHub prerelease publication have not yet run end-to-end.** At setup completion Apple still had only runs 3, 4 and 5, and GitHub had no published releases. No extra app build, phone install/reset, retailer/cart/reminder action or public App Store release was performed. GitHub scheduling may be delayed; external beta review can still gate tester access. First-live-run verification remains required rather than claiming upload/publication from a passing dry run.

## Paprika feature merged to main — 4 November 2026

Merge `fd12fc02949c969b455aba41cc41910b759e0916` combines the Paprika branch with main's results-scrolling changes. Two conflicts were resolved by preserving both reset preference domains and both UI-test store-selection cases. On the merged revision, **1,789 native checks passed** and simulator **build-for-testing succeeded with zero errors** (`BuildProject-Log-20261104-221228.txt`). The earlier focused 2/2 Paprika UI run was on feature revision `720e499`; it was not rerun after merge. Phone remains at feature build `4cf8093`, with no new reset/install/import/removal. Mac main was fast-forwarded while preserving its existing untracked Xcode Cloud directory. Task worktrees and feature branch can now be removed without discarding user work. No TestFlight or public release.

## Simplified Paprika options screen — 4 November 2026

At application revision `720e49910f94e4bd82c014cb8ea70a0f081d03af`, Reminders-list selection and remove-after-import are colocated on **Import from Paprika**, not top-level Settings. Short export guidance, both controls, a concise mode-specific footer, **Import to [store]**, and collapsed **More about importing** replace the longer instruction screen. Preference keys/defaults, transactional imports, source-identity restrictions and the immediate repeat-import shortcut are unchanged.

**1,768 native checks passed** and **2/2 focused iPhone 17 / iOS 27.2 simulator UI tests passed**, covering named-list selection/persistence/change and removal-mode controls/instructions after relocation. Result bundle: `Test-ListRunner-2026.11.04_21-57-53-+1100.xcresult`; console: `test-console-log-2026-11-04T21-57-53+11-00.txt` under Mac temporary `ActionArtifacts/default/RunSomeTests`. Independent visual inspection with isolated fixture preferences/reminders confirmed all main controls fit at default text size, no observed clipping/overlap, and immediate footer change when toggled. Screenshot `/tmp/opencode/paprika-720e499-options.png`; interaction session closed. This is not larger-text, VoiceOver, physical-device or real EventKit validation. No real reminders/cart operations or phone install; phone remains at `f38b629`.

## Phone install and import-only reset — 4 November 2026

At user request, revision `f38b629` was built/signed/installed/launched on Adrian’s iPhone 17e / iOS 27.2 with zero build errors (PID 8427; `RunProject-Log-20261104-215208.txt`). All **1,768 native checks passed**, including targeted reset boundaries. A one-time debug launch using `--reset-import-setup` on the current bundle `com.adrianzafir.listrunner` succeeded. This removes only source preference, Reminders-list ID/name and removal-mode override; the default-on mode returns. It does not reset groceries, store preferences, retailer sessions, EventKit permissions or Apple reminders. No import or reminder deletion was performed. The first launch attempt used the obsolete `com.AdrianZ.ListRunner` identifier and correctly failed as not installed; the current canonical identifier was then used. No broad reset/uninstall, scheme argument change or TestFlight operation. Native hierarchy/visual confirmation of the phone's reset state was not obtained; the explicit reset launch succeeded. The iOS permission prompt is not reset by this action.

## Named Paprika export list selection — 4 November 2026

Application implementation `01473bc` replaces fixed-name `Paprika` matching with explicit Reminders-list selection. First import requests permission and offers accessible lists with account labels, suggesting but never auto-selecting `Paprika`. Settings changes the remembered calendar ID/name without importing; missing IDs reopen selection with no title-based fallback. Snapshot and post-save removal use the same captured calendar ID, including duplicate-name accounts. Read-only lists are disabled when removal is enabled. Display names refresh on successful reads. Instructions distinguish default, named and customised Paprika exports and name the affected source list. Local reset clears list selection. No database schema or existing source-link migration is needed.

**1,766 native checks passed**, including cleanup identity/title/completion boundaries. The simulator app and UI targets compiled with no errors (`BuildProject-Log-20261104-210916.txt`). At final test revision **`b5202d8`, both focused iPhone 17 / iOS 27.2 simulator tests passed (2/2, zero failures)**: `testPaprikaNamedRemindersListSelectionPersistsAndCanChange` and `testPaprikaRemovalDefaultsOnAndInstructionsFollowSetting`. They cover cancellation, named-list-only fixture import, remembered source across relaunch, Settings source change, default-on removal and disabled-mode instruction/preference persistence.

Initial focused runs failed on test assumptions: long-string identifier limits, an offscreen lazy instruction action, implicit Woolworths selection while asserting Coles, and a toggle-label tap instead of the native switch. Test-only follow-ups use label predicates, bounded scrolling, explicit starting store, navigation waits and the existing native-switch hit-area pattern. Final result bundle: Mac `ActionArtifacts/default/RunSomeTests/Test-ListRunner-2026.11.04_21-42-25-+1100.xcresult` under the temporary artifacts directory; console `test-console-log-2026-11-04T21-42-25+11-00.txt`. This is focused fixture verification, not a full UI regression, live EventKit removal, or manual accessibility sign-off. No real reminders, retailer carts, physical-device installs or TestFlight operations were performed. Phone remains at `d719603`, predating named-list selection.

## Reminders handoff setting — 4 November 2026

Implementation `d76aa9e` on `feat/improve-paprika-importing-experience` adds default-on **Remove reminders after import**. It captures the mode per attempt, commits groceries first, preserves reminder IDs for deduplication/retry, then removes only saved/readable source reminders after rechecking exact calendar, title and unchecked state. Partial cleanup failure leaves groceries saved and explains retry. With the toggle off, linked-reminder behavior remains. Instructions, permission purpose and results reflect the mode; the export guide anchor is corrected to `#grocerylistactions`. Toggling alone performs no deletion; confirmed local reset restores the default.

On the clean isolated Mac task checkout, **1,762 native checks passed**, including cleanup selection without saved IDs and unique/readable/saved-only selection. **Simulator build-for-testing succeeded with no errors**, compiling app and updated UI scenarios (log `BuildProject-Log-20261104-204932.txt`). UI scenarios have **not been executed** for this revision. The earlier device build-for-testing failed on test-runner signing (`No Accounts`, missing `com.adriangith.ListRunnerUITests.xctrunner` profile); simulator compilation bypassed no device permission or signing settings. No physical app installation, real reminder deletion/import, retailer/cart change or TestFlight upload occurred for this revision. Prior phone remains at `dd481da`. Live EventKit removal, partial failure, VoiceOver/large text and runtime UI verification remain outstanding. Debug reminder fixtures bypass all real deletion.

## Guided Paprika import — implementation awaiting Mac validation, 4 November 2026

Branch `feat/improve-paprika-importing-experience` replaces setup-only confirmation with **Import groceries**, including from Settings. The chooser is retained as **Import items**, with **Paprika — Via Apple Reminders**; no nearby Change source action is added. The last-used source is saved only after committed rows. Repeat imports remain immediate. Instructions explain the export path, exact list name, selected store, permission purpose and snapshot/best-effort writeback limits. Success confirms count/destination; failures distinguish permission denial, generic access, missing/ambiguous lists, no unchecked groceries, already-imported identities, unreadable titles and local-save failure. Recovery has instructions/retry and permission-specific Open Settings.

The existing OpenPencil audit/flow documentation was consulted; no live design service was available, so the saved boards were not edited or visually revalidated. Paprika's published iOS guide search result confirms Groceries → Actions → Export to Reminders and per-list export-name customisation: https://www.paprikaapp.com/help/ios/ . No third-party screen artwork was invented.

Added native empty-outcome classification checks and updated fixture UI scenarios for immediate import, remembered-source persistence, cancellation/draft preservation, Settings import/help, store-local deduplication, no automatic retailer presentation and actionable failures. **These Swift changes/tests have not been compiled or run.** Linux recovery runner stops with `xcrun: command not found`; no local Swift compiler is installed. Mac SSH `adrianzafir@192.168.4.94` failed with `No route to host`. `git diff --check` passed. No real Reminders, retailer sessions, carts, physical devices or TestFlight builds were touched. This implementation is prepared for Git-based handoff on the task branch; pushing it does not establish Mac build or runtime validation.

Next: preserve/recheck Mac status and fetch the exact pushed task revision into an isolated task checkout. Run `packages/ios/tests/run-recovery-tests.sh`, build-for-testing, focused Paprika UI tests (including error fixtures) and a Release simulator build. Review light/dark, larger text and VoiceOver on instructions/recovery before claiming runtime completion. Preserve existing Mac work and app data; do not mirror files or test against real reminders.

## Your list scrolling — phone preview installed, 3 November 2026

Application revision `cf0c17d3ec588542b4054e70f254d4a72448d7a2` removes repeated store-configuration validation from list rendering, tracks row geometry only for the active added-row reveal, tracks entry/action geometry only while focused, cancels positioning once per manual drag, and avoids unchanged native-editor intrinsic-size/placeholder invalidation. The session-owned availability snapshot retains full validation at the immutable registry boundary and reflects enabled-ID changes without revalidating every definition. Details and benchmark limitations: `docs/your-list-scroll-performance.md`.

All **1,701 native checks**, **313 DOM tests**, **3 expansion consistency tests** and **2 release-metadata tests** passed. On the isolated iPhone 17e / iOS 27.2 simulator, the first run attempted nine UI scenarios: four passed, five failed. Test-only revision `61958c3005c4f5ee104c8c6f8e09e2b8b3eef42d` corrected stale import/action selectors and made the selected Coles fixture explicit. Three of the five rerun cases passed, giving **seven passing scenarios across runs, not a clean 9/9**. Passed coverage includes ordinary manual scrolling (`target=none`, `trackedRows=0`, no pending reveal), first-item Add/Return, six repeated additions, growing drafts, empty Return and outside-tap keyboard animation.

Two positioning assertions remain open: the already-visible-row test reports a 3.33-point input shift against its 2-point tolerance; the focused-entry test reports 15 points of movement, while the recorded unfocused action row extends 15 points below the future keyboard-open Show Store boundary. Both show a fully visible resulting target/card; the second test's no-movement precondition may be invalid. Neither is dismissed as a clean pass. Evidence: Mac `~/Library/Logs/ListRunner-scroll-cf0c17d.xcresult` and `ListRunner-scroll-61958c3.xcresult`; Linux `/tmp/opencode/scroll-61958c3-evidence/`. No on-phone FPS/hitch profile was obtained because Instruments could not attach.

At the user's request, Xcode built/signed/installed in place and launched revision `61958c3` on the connected **physical iPhone 17e**, UDID `00008150-001402660A9BC01C`, iOS 27.2, PID **1729**. No simulator test flags, data reset, retailer/cart action or TestFlight upload. All **34 JSON resources** in the actual built device app match canonical files. Build/run log: `RunProject-Log-20261103-223352.txt`. User assessment of the scrolling improvement and the two positioning checks remain follow-up work; the install alone is not performance sign-off.

## Tesco UK — native sign-in continuation verified, 3 November 2026

User-assisted simulator verification at `56e73d3ee102ff438eddf8c433215f5237692fb1` passed the previously missed signed-out Add → sign-in → automatic Added flow. The exact test product was Tesco British Semi Skimmed Milk 2.272L, 4 Pints (`254656543`). On the dedicated **Tesco Login Replay**, iPhone 18 Pro / iOS 27.2 (`036F8BCA-64AD-4F25-BA5C-FF226EE083A0`), native `loginReplayState=confirmed`, `detectedAddSequence=1`, and isolated diagnostics sequence 8 recorded `cartDetection/succeeded`. The local Milk row showed Added. The record retained `before=nil` / `after=nil`, correctly refusing to infer an account-cart baseline from the signed-out display. No temporary investigation observer was present.

The initial `52f8b95` test failed: the observed first-party flow also crossed `/account/login/en-GB/…`, which the narrower auth-only guard rejected. The corrected route policy accepts only the reviewed auth/login route families on the same exact host, binds one trusted product/item/session intent for five minutes, and requires return to the original URL. A filtered page-world adapter observes the normal resolved `UpdateBasket` promise; native acceptance additionally requires a successful exact-product acknowledgement, matching requested/returned quantity and stable isolated-world DOM evidence. It never repeats Add or reads credentials, cookies, account configuration, raw network bodies or headers. Recovery, verification, changed context, unreviewed navigation and expiry invalidate tracking.

Earlier signed-in Add and native Undo were independently confirmed by `cartDetection/succeeded` and `cartUndo/succeeded` in the original isolated test namespace, with user removal back to an empty basket. The subsequent login investigation accumulated additional test quantities; the final successful screenshot showed quantity 6 and a generic estimated total of £8.75, which is inconsistent. Treat that header as non-authoritative; the product-specific returned quantity is the acknowledgement evidence. **Cart cleanup remains outstanding and must preserve any pre-existing account items.** No checkout, purchase, fulfilment change or physical-device deployment occurred. The original and replay simulators share the signed-in Tesco account, despite isolated local/WebKit data.

Evidence on Linux: `/tmp/opencode/tesco-login-native-success.png`, `/tmp/opencode/tesco-login-native-success.md`; investigation sequence `/tmp/opencode/tesco-v3-after-replay.json`; failure report `/tmp/opencode/tesco-native-login-failure.md`. The verified runtime was PID 54145, left running. On `56e73d3`, all **313 DOM tests**, **1,694 native checks**, and the simulator build passed. Production configuration is enabled in the follow-up commit, separately from the DEBUG-only verification flags. Broader UI/physical-device, product-detail, variant and fulfilment paths are not certified by this one grid test. First post-login acknowledgement permits local Undo only, with a check-cart warning; ordinary signed-in quantity-confirmed additions retain retailer Undo.

Production configuration revision `857052944fca4993173981e29fd304dd866ddd70` was pushed and checked out on the Mac. All **313 DOM tests**, **1,694 native checks**, **3 expansion consistency tests** and **2 release-metadata tests** passed. Xcode's simulator build-for-testing succeeded, compiling the updated UI tests; those UI tests were not rerun. All **34 JSON resources** in the actual built Debug simulator app byte-match canonical source files, with no legacy `-v2` resources. The existing live test process was not replaced or restarted after success; no merge, phone deployment or TestFlight upload was performed.

## Twenty-store expansion — 1 November 2026 (partial delivery)

Twenty additional destinations are registered, disabled by default, with stable
independent list/session identities. **Sixteen new searches are verified;
Priceline, Supercheap Auto, Ocado and Chemist Warehouse automatic cart detection are live-verified and enabled. The other
sixteen new detectors and all twenty retailer-cart Undo capabilities remain disabled.** The full
search-and-detection request is not complete. New World, PAK’nSAVE, Boots and CVS
remain browsing/manual-only after unverified/blocked search observations.

Live read-only iPhone 17/iOS 27.0 probes validate actual matching product links
plus reflected query; Priceline instead passed an independent two-query relevance
and distinct-result-set check. Corrected routes cover Petbarn's path search,
Asda's new www grocery site and Morrisons/Ocado's `q=` parameter. The obsolete
Morrisons/Ocado `entry=` observations are explicitly superseded, not certification.

At `f15dfe2185b41a595f0b8bd1792a2821da1170c4`: **1,423 native checks, 3/3 focused
iOS tests**, and byte-verification of **34 actual bundled JSON files** passed.
The UI test found every new destination and independently exposed Target Australia
and Target US; no retailer site was opened by that discovery test. Linux: 78 DOM
regressions, 90 core tests plus typecheck, 7 verifier tests and 3 expansion contract
tests passed. Evidence: Mac `~/Library/Logs/ListRunner-Expansion-Final-f15dfe2.log`
and `.xcresult`, plus earlier search logs identified in the full evidence ledger.

Isolated guest cart investigations confirmed website additions for Chemist
Warehouse, Priceline and Supercheap Auto, not native automatic detection. Confirmed
test quantities were removed; an unconfirmed Priceline retry is not evidence of
either addition or cleanup. No checkout, purchase, credentials, address/fulfilment
changes, security bypass or physical-phone installation occurred. Initial extra
simulator interaction sessions failed to connect; their failures are not app UI
evidence. The subsequent XCTest discovery run succeeded on the existing test sim.

Full retailer list, exact capability decisions, cart observations, environment
limitations, Mac identifier reconciliation and remaining work:
`docs/retailer-expansion-2026-11-01.md` from the repository root.

### Detector follow-up — 2 November 2026

- Chemist Warehouse native PASS at `101badcf143fcfb5bdcc3fd11e206cdf5f250134`:
  detected=true, cleanupVerified=true. Direct PDP verification of the exact
  authorized Sukin shampoo automatically triggered native confirmation, followed
  by product decrement and restored Add state. Mac logs/results:
  `~/Library/Logs/ListRunner-Finish-Cart-chemistWarehouse-101badc.*`.
  All 34 built JSON resources byte-match sources at that revision. Production
  detection enabled afterward; retailer-cart Undo remains off.
- JB, Bunnings NZ and Officeworks at `101badc` failed before Add, not skipped:
  JB flattened/duplicated link scoping; Bunnings selected AU fixture instead of NZ;
  Officeworks location AX label `LocationIconRgbOl` lacks `Shopping method` text.
  No cart changes in those three tests. Their detectors remain disabled.

- Ocado native PASS at `38496f2`: detected=true, cleanupVerified=true,
  244.267s, not skipped. Exact test milk card automatically triggered native Undo;
  retailer decrement restored Add. Mac logs/results:
  `~/Library/Logs/ListRunner-Finish-Cart-ocado-38496f2.*`. Production detection
  enabled afterward; retailer-cart Undo remains off.

- Supercheap Auto passed at `b305bcf`: detected=true and cleanupVerified=true,
  173.609s. Retest fixes the earlier off-screen Remove failure below and verifies
  empty-cart cleanup. Mac `~/Library/Logs/ListRunner-Finish-Cart-supercheapAuto-b305bcf.*`.
  Its production detector is enabled afterward; retailer-cart Undo remains off.
- Morrisons' authorized guest address was successfully selected after corrected
  browser scrolling, superseding its earlier location blocker. One Belvita pack
  showed actual per-card quantity 1, then decrement restored 0/Add and £0.00.
  Prospective profile is fixture-tested but not yet native-certified/enabled.

- Priceline passed `StoreSelectionTests/testLiveStoreCartPriceline` at
  `b01ff2835732d0940f1c8024b1cf74b1cfe7a832` on existing iPhone 17/iOS 27 simulator:
  trusted product Add automatically exposed native Undo, without Mark Added;
  guest test product removal was verified. Not skipped; 533.694s.
  Mac logs/results: `~/Library/Logs/ListRunner-Finish-Cart-priceline-b01ff28.*`.
  Enabled production capability at `85cb068`; retailer-cart Undo stays off.
- At `b305bcf`: 1,452 native checks and synthetic store proof pass. Count is one
  lower after removing the refusal test for Priceline's now-authorized capability.
  Schema-4 prospective profiles also cover Supercheap Auto, Chemist Warehouse,
  JB Hi-Fi, Officeworks, Bunnings NZ and Petbarn's numeric product-detail routes.
  Paired quantities and explicit acknowledgements are separate; quantity-free
  confirmations never fabricate before/after totals or enable cart reversal.
- Supercheap at `85cb068`: native detection confirmed (retained screenshot
  `Live cart detector supercheapAuto confirmed` and failure-time hierarchy show
  Added), but cleanup assertion failed because Remove was below the viewport.
  Removal was not attempted; disposable nonpersistent guest store was released
  when XCTest terminated the app. This is **not** a clean end-to-end pass.
  `b305bcf` adds measured cleanup scrolling; sequential rerun pending.
- Guest Linux Petbarn actual PDP cart stepper observed at 1 for Providore Beef
  with Kiwi Fruit Dog Treat (`138813`); decrement restored Add and both header
  controls explicitly said `Shopping cart is empty`. Browser closed.
- Corrected Linux Add checks: Sainsbury's and Waitrose redirect to sign-in;
  ASDA returns a security block. No confirmed additions. Do not enable detectors
  from these gates or attempt to bypass them.
- User authorized representative guest postcodes and subsequently a specific
  Morrisons UK test address; no personal name/address is tracked. Morrisons
  selection failed to replace its unrelated default location, so no slot or
  checkout followed. Physical phone remains untouched.

## US retailer expansion — 30 October 2026

**Phone deployed:** after Xcode MCP approval, Xcode built/signed/installed in place and launched `480e75ebebfcdcb09a8d34450fb57a8f3a965f78` on **Adrian’s iPhone / iOS 27.2**, with no build errors, PID `15521`, launch reference `80fdf5e00`. All 14 JSON resources in the actual `Debug-iphoneos/ListRunner.app` byte-match canonical sources; no legacy resource copies. No data reset, fixture launch, list/login/visibility change or retailer/cart interaction was performed. Phone UI was not directly inspected. Log: Mac `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261030-180458.txt`. This supersedes the pending-phone-deployment status recorded below.

Approved set: Walmart, Amazon US, Costco US, Kroger and Target US. New `amazon`, `kroger` and `target` registrations have independent permanent list and named website-data UUIDs, exact US bare/`www` hosts, closed diagnostic host entries, disabled-by-default visibility, shared native settings/manual progression and isolated reset scopes. Costco regional grouping and every preexisting identity remain unchanged. No Australian Target, Kroger sister-banner, Amazon Fresh/Whole Foods or third-party same-day integration is implied.

**Live read-only search evidence:** `LiveUSSearchTests/testReadOnlySearchRoutes` at app/test revision `e28eb6799fca187feb5c35ce78214ca3924e9fd7` ran on iPhone 17/iOS 27.0 simulator using fresh nonpersistent `WKWebView` stores, no app cookies, and GET-only exact-host navigation. Visible same-host product links with matching milk text were returned for Walmart (4 links), Kroger (60) and Target (249). Amazon returned no product links and did not establish a matching same-host result; desktop inspection separately showed its verification checkpoint. Costco US stayed on-host but returned no product links within the 30-second window; desktop inspection showed loading placeholders and a location-data timeout. No verification bypass, sign-in, delivery-location change or cart action occurred. These observations do not establish the cause of every blocked flow or certify all queries/regions/accounts.

The search-probe test is observational unless `LISTRUNNER_LIVE_US_REQUIRED` names required retailers: a passing observational test does **not** mean all five passed search. The first attempted run skipped because an unprefixed shell environment variable was not forwarded; the subsequent explicit `TEST_RUNNER_LISTRUNNER_LIVE_US_SEARCH=1` run executed all probes (103.854s, no skip). Evidence: Mac `~/Library/Logs/ListRunner-US-Stores-live.log` and `~/Library/Developer/Xcode/DerivedData/ListRunner-US-Stores/Logs/Test/Test-ListRunner-2026.10.30_17-54-45-+1100.xcresult`. The probe attaches only safe counts/booleans/store IDs, not page content or account data.

**Capability decision:** code revision `74e9810` enables URL-template searches for Walmart `/search?q=`, Kroger `/search?query=` and Target `/s?searchTerm=` based on this live embedded-WebKit evidence. Amazon and Costco US remain browsing/manual-only, with dormant search candidates `/s?k=` and `/s?keyword=`. This supersedes historical Walmart browsing-only search descriptions below. All five retain cart detection and retailer-cart Undo disabled in JSON and native policy. Manual status Undo remains local; no live US cart mutation was performed or certified.

**Initial validation:** at `e28eb67`, 474 native recovery/configuration/reset/diagnostics checks and the synthetic-registry extensibility proof passed. New checks cover all US URL parameter encodings, exact host/protocol/port/userinfo policy, forbidden cart capabilities, unique identities, five-brand country grouping, legacy visibility persistence and actual nonpersistent WebKit cookie-reset isolation. All 61 existing DOM detector regressions and 7 bundled-resource-verifier regressions passed on Linux. At `b4934c1`, 449 parser checks, unsigned generic-iOS Release build, and new-store Settings UI test on iPhone 18 Pro/iOS 27.0 passed; all 14 built JSON files matched canonical sources in both simulator and Release app bundles. The Settings test verifies hidden new retailers, support labels and own reset confirmation/cancellation, using isolated fixtures only. Evidence: Mac `~/Library/Logs/ListRunner-US-{Settings,Release}.log`, `~/Library/Developer/Xcode/DerivedData/ListRunner-US-Settings/Logs/Test/Test-ListRunner-2026.10.30_17-55-40-+1100.xcresult`.

**Remaining boundaries:** separately authorized product/delta live tests are needed before cart detection or reversal work; login/fulfilment, physical-device and broader release/accessibility sign-off are not established by these probes. No phone installation was performed for this expansion. OpenPencil discovery timed out; this change reuses the existing catalogue/settings UI with no layout redesign.

**Final search-enabled revision validation:** `74e9810f2dfdcb1ca5ed68ed9b260234a2fbea65` passed 479 native checks, the synthetic registry proof, unsigned generic-iOS Release build and all 14 Release bundle JSON comparisons. All 78 DOM tests (61 shared + 17 BIG W) passed on Linux. The final iPhone 17/iOS 27.0 run passed 3/3 UI tests, no skips: opt-in live search with Walmart/Kroger/Target explicitly required, new-retailer support/reset settings, and Walmart enabled-search settings. Live probe returned Walmart 4, Kroger 60 and Target 249 visible matching product links. Amazon also returned 59 matching links on this rerun, unlike its unsuccessful first probe; its search remains disabled pending consistent verification rather than silently claiming stable support. Costco US still returned none. Mac log: `~/Library/Logs/ListRunner-US-final.log`; Release log `~/Library/Logs/ListRunner-US-Release-final.log`. The requested phone deployment is pending Xcode MCP agent/project approval; nothing has been installed on the phone by this task yet.

## Welcome-only store setup and completion crossfade — 30 October 2026

Final app revision `2e0ee3ff7cc8a16badcd5b851b48045dba241b7e` adds welcome-only Enable Store/Included Support, direct selection of the enabled store's list, and a 0.3-second completion crossfade with native success sensory feedback. Normal management retains full settings. A scene-local window snapshot fades while the new root navigation stack lays out with animations disabled; no snapshot is written to disk by the app. Reduce Motion skips snapshot/animation. Earlier live-stack animation at `cfac320` passed settled UI tests but visibly mislaid the incoming Woolworths screen; it is superseded, not visual sign-off.

**Passed:** 340 native checks, 2 focused final-revision UI tests covering welcome cancellation, enabling a nondefault store, preview completion, no residual Back/setup stack and unchanged full settings, plus unsigned generic-iOS Release build. The prior 3-test suite passed at `cfac320` and `a8b430d`, not rerun in full on the final revision. Final result bundle: Mac `/tmp/listrunner-welcome-completion-tests/Logs/Test/Test-ListRunner-2026.10.30_17-40-45-+1100.xcresult`; Release log `/tmp/listrunner-welcome-completion-release.log`.

**Recorded simulator visual checks passed** on the final revision for both default/same-store Coles and different-store Woolworths: genuine fade, stable full-width incoming list with store picker present, no white margins/title overlap/layout snap/intermediate Manage Stores pop, correct final selected store and no website or Back button. Isolated preferences/lists only, no real store or Reminders access. Evidence: Linux `/tmp/opencode/listrunner-snapshot-{woolworths,coles}.mp4`, `snapshot-wool-transition.png`, `snapshot-coles-transition.png`, `snapshot-wool-final.png`. Reduce Motion runtime and physical haptic sensation remain unverified.

**Phone deployed:** Xcode built/signed/installed/launched final app revision on Adrian's iPhone/iOS 27.2 with no build errors, PID15386, then devicectl relaunched with `--preview-store-welcome`. No app-data reset, fixture environment or store/list/login changes. Log: Mac `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261030-174531.txt`. Phone UI was not directly inspected.

## Manage Stores background, interactive Back and appearance — 30 October 2026

App revision `8754e8c52720b81231d884f2b3feb02d75601f3b` fixes the grouped-background safe-area bands, stabilises welcome navigation-bar ownership during interactive Back, and uses a standard inline Manage Stores title. Keep the table controller attached under empty search results. Earlier candidates `0fcfb95` and `3f1c3d7` fixed the jump but still failed live appearance-switch title checks; their passing settled UI tests were not proof of title rendering.

**Passed at the final app revision:** 340 native checks; 5 focused iPhone 17/iOS 27.0 simulator UI tests covering repeated Back/background pixel comparisons, cancelled/completed interactive Back, large text, search/clear/empty results, and native section index; unsigned generic-iOS Release build. UI results: Mac `/tmp/listrunner-store-glitches-tests/Logs/Test/Test-ListRunner-2026.10.30_17-06-26-+1100.xcresult`; Release log `/tmp/listrunner-store-inline-release.log`.

**Visual verification on iPhone 18 Pro/iOS 27.0 simulator:** title visible after light→dark and dark→light while unmatched search was active, then closing search; fresh dark launch also passed. Recorded completed and cancelled interactive Back show the exposed welcome CTA remaining at rendered y658–709, with no previous 54-point upward snap. Settled CTA y657.7/height52 and heading y421.2 match baseline. Header, table surround and bottom safe area match RGB(242,242,247) in light and RGB(0,0,0) in dark. Evidence: Linux `/tmp/opencode/inline-{dark,light,fresh-dark}-title-screenshot.png`, `listrunner-inline-swipes.mp4`, `inline-{completed,cancelled}-frames.png`, and `inline-button-video-geometry.json`. Appearance restored to light; interaction session closed. No retailer, Reminders, list or store-visibility changes. These are targeted simulator checks, not exhaustive OS/device/accessibility certification.

## Simplified Paprika import-source setup — 30 October 2026

**Merged and deployed to the phone:** At the user's request, merged with the newer main-branch keyboard/card fixes and pushed `main` at `84d82f810149544c923d922bb00189b235704bcf`. The only conflict was the validation-document introduction; both histories were retained. The unrelated dirty Linux OpenPencil audit file remained byte-identical. The clean active Mac checkout fast-forwarded to the exact merged revision; all 336 native checks passed again. Xcode built/signed, installed in place and launched successfully on **Adrian’s iPhone / iOS 27.2**, PID `13191`, launch reference `947653c00`, with no build errors. All 11 JSON files in the actual `Debug-iphoneos/ListRunner.app` byte-match canonical resources. No app-data reset, fixture launch environment, Reminders import or retailer/cart interaction was performed. Build/run log: Mac `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261030-142917.txt`. This supersedes the historical not-merged/not-phone-installed status below; six UI tests were run on the feature revision before the merge, not rerun on the merged build. Physical-phone interaction/accessibility review remains separate from successful installation/launch.

App/test implementation `5ed3b621329b41e687b24d0caafb574f89bfbf57` is pushed on `feat/import-source-setup`. It follows the simplified OpenPencil Import sources page: first-use Import → source chooser (Paprika only) → instructions → Use Paprika → Your list, without importing/requesting permission during setup. Later Import from Paprika retains the existing immediate, store-scoped import. Settings reopens source setup/instructions and confirmation returns all the way to the list. A new app-wide preference persists selection; unknown values return to setup, and confirmed local-data reset clears it. No database schema or reminder-link migration.

**Passed:** 336 native recovery/reset/diagnostics checks and 449 parser checks on the clean Mac task worktree; 7 bundled-resource verifier regression checks on Linux. Native coverage adds unset/unknown/persisted source selection, diagnostics preservation and reset clearing. Mac logs: `/tmp/listrunner-import-recovery-tests.log`, `/tmp/listrunner-import-parser-tests.log`.

**Focused simulator UI validation passed: 6/6, no failures/skips or runtime warnings in XCResult summary.** On dedicated iPhone 17 / iOS 27.0 simulator `C26F6191-664A-4C14-A113-6B1324650BE0` (ListRunner Import Setup), tests verify setup returns without importing, cross-store/relaunch preference persistence, actual import targeting the selected store, cancellation preserving the draft/unset preference, Settings instructions and return all the way to the list, empty-list setup, existing import deduplication/status ownership/failures, and the compact action-row hit area/height. All 11 JSON resources in the actual built app byte-match canonical files, with no legacy `-v2` resources.

The initial run compiled both app and UI test target but the runner aborted during bootstrap before any feature tests ran, followed by a 600-second diagnostic-collection timeout. It is not counted as a feature-test pass. Evidence: `/tmp/listrunner-import-ui-tests-1.log`, `~/Library/Developer/Xcode/DerivedData/ListRunnerImportSourceSetup-results-1.xcresult`. After Mac reconnection and shutting down only the task's separate visual simulator (preserving its data), a serial `test-without-building` retry with diagnostic collection disabled passed all six tests at the same app/test revision. Passing evidence: `/tmp/listrunner-import-ui-tests-2.log`, `~/Library/Developer/Xcode/DerivedData/ListRunnerImportSourceSetup-results-2.xcresult`.

A separate visual reviewer created simulator `A6A36E73-B725-47AB-8FA2-D68819BBC342` (ListRunner Import Visual), installed the existing task-built app (`com.AdrianZ.ListRunner`), then encountered a launch timeout/connectivity loss. No screenshot/hierarchy evidence or UI success was obtained. **Cleanup outstanding:** close standalone device-interaction session `Paprika Import Visual Verification` when Xcode tools reconnect. Preserve simulator/test evidence; do not delete simulator state as generic cleanup.

Mac task checkout: `/Users/adrianzafir/Projects/listrunner-worktrees/import-source-setup`, detached at the exact app/test revision above; main checkout and physical devices were not switched/installed. All UI runs use isolated test preferences/lists and Paprika fixtures, not real Reminders or retailer carts. The task is not merged to main or installed on the user's phone. Runtime checks for iOS 17, manual accessibility/large-text visual sign-off and physical-device validation remain unverified; the passing simulator app/test build is not a signed physical-device build claim.

## Whole Add products card focus reveal — 30 October 2026

**Phone deployment:** At the user's request, Xcode built and launched revision `ee2cc7c78264fac1b0cf43d8139dcaadc4270ea1` (same app code as tested `f0cbeec`) on Adrian’s iPhone on 30 October at 14:25. No build errors; PID `13148`, launch reference `947650f00`. Installed in place without app-data reset or test-fixture launch configuration. Mac log: `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261030-142549.txt`. This supersedes the historical “phone unchanged/not deployed” status below; behavior verification remains simulator evidence, not a physical-phone interaction test.

**Final visual check on `f0cbeeca65227e88674233772c9e4daaf60d2939`: passed normal focus, growing-draft correction, and submitted-row reveal with software keys visibly onscreen at y590–816.** The normal native card stays y322–464 without moving; Show Store starts at y464. A long draft moves the card up only 57.3 pt to y264.7–464, leaving both actions unobscured and the editor below the fixed header. Add Items then reveals the complete wrapping grocery cell at y234.33–456 within viewport y178–456 while retaining the keyboard. Local screenshots: `/tmp/opencode/measured-card-before.png`, `measured-card-focused.png`, `measured-card-growing.png`, and `measured-card-submitted.png`. An optional tall-draft dismiss/refocus check showed corrected frames but received SIGTERM before its final capture; no recent crash report was found, and the cause is unknown. Do not claim that optional visual refocus check as a completed pass. All device sessions closed; only the simulator was used, and the phone remains unchanged.

**Growing-draft follow-up:** The final visual check of `128f830` confirmed the normal focused card stays at y322–464, touching but not overlapping Show Store at y464. It also exposed a long wrapping draft pushing the actions to y469.3–521.3 behind Show Store. The new growing-draft regression failed on `32788ec` and diagnostic revision `c52085f` (the other four checks passed on `32788ec`). Diagnostics confirmed `scrollTo` was requested but did not move the static action cell. Registering it with a data-driven identity on `4fb7377` moved the list too far, clipping the top of the editor, so that experiment was removed. Moving the editor's enclosing collection view by only the measured clipping distance passed the growing-draft test on `73c3e7c`.

**18/18 repeated UI test runs passed** on `f0cbeeca65227e88674233772c9e4daaf60d2939`: three runs each of growing-draft visibility, normal card visibility/no movement on initial focus or refocus, already-visible new-item positioning, empty-list Return reveal, six repeated additions, and compact action-row height. The fix uses the actual Show Store boundary (not its clear top spacing) to avoid moving already-visible cards. Confirmed with `xcresulttool get test-results summary`: result Passed, 18 passed runs, zero failed/skipped, iPhone 17 / iOS 27.0 simulator. Final visual evidence is recorded above. Evidence bundles: `ListRunner-card-c52085f.xcresult`, `ListRunner-card-4fb7377.xcresult`, `ListRunner-card-73c3e7c.xcresult`, and `ListRunner-card-f0cbeec.xcresult` under the Mac DerivedData directory. No phone deployment of these follow-ups has occurred.

Revision `128f830690f42491ff660028e58e583f3e4a9468` conditionally reveals the complete editor/action card when focused and its bottom is clipped. It checks the adjusted List viewport after focus/viewport changes and keyboard presentation, includes the action row's 4 pt vertical padding inside its scroll identity, and skips scrolling when the card fits. New-item reveal takes precedence after submission. Interactive keyboard dismissal is temporarily disabled during the programmatic card reveal, not during ordinary manual scrolling.

**5/5 focused iPhone 17 / iOS 27 simulator UI tests passed**, with software keyboard enabled: whole entry card above Show Store plus no reposition on refocus; already-visible new row unchanged; empty-list Return reveal; repeated Add Items/Return including wrapping names; compact action row still 52 pt. Evidence: Mac `~/Library/Developer/Xcode/DerivedData/ListRunner-entry-card-128f830.xcresult`.

Earlier runs on `91af873`, `5c9db65`, and `f5b5a10` failed while simulator hardware-keyboard simulation left an accessibility Keyboard below the physical screen. A visual device-interaction check confirmed this state. With user permission, Device Hub's **Toggle Software Keyboard** made the keyboard visible; hardware-keyboard simulation itself was left unchanged. Before the padding fix, the visible native card ended at y464, touching Show Store at y464, and extending 8 pt past the List viewport bottom456. Touching Show Store without overlap is acceptable; the growing-draft follow-up above is a separate visual failure. No phone installation of this revision has been performed; the phone remains on `26df57a`. Tests use isolated fixtures only.

## New-item reveal investigation — 30 October 2026 (in progress)

**Follow-up:** Mac connectivity recovered. App-code revision `36c734c8506907014664f9735c29dae301e9850e` (checkout `572d0d557287aa60ffda3480908f0469685ff090`, documentation-only difference) passed **10/10 repeated runs**: five empty-list Return reveals and five six-submission existing-list sequences. Evidence: Mac `~/Library/Developer/Xcode/DerivedData/ListRunner-reveal-36c734c-retry.xcresult`. This supersedes the connectivity blocker below, not the recorded failures on the older revision. Subsequent revision `91af873d814f7ea1944bda7645f15e4929006d87` adds conditional whole-entry-card reveal on focus/keyboard viewport changes; its five focused checks are running. Neither follow-up is installed on the phone yet.

The repeated existing-list full-cell reveal test reproduced the reported intermittent scrolling failure in all three baseline runs (`e7f8cbd`). The reveal identity now includes vertical cell padding without increasing native row heights (78 pt for the fixture); requests are coalesced and rechecked after insertion layout. Diagnostics found a double subtraction of safe-area insets producing a zero-height viewport while the keyboard was open; use the already-adjusted List layout frame instead. Keyboard callbacks and stale typing changes can also retire a submitted target.

App revision `26df57ae230561828ffcf6691d3030f5556ce0eb` passed three consecutive repeated-addition runs at the same app-code revision (`74a9d8e`, 18 additions total) and the no-reposition test using software-key taps. However, the wider **9-test run passed only 7/9**: empty-list Return reveal and repeated existing-list reveal failed. Do not treat this revision as a reliable final fix. Evidence: Mac `~/Library/Developer/Xcode/DerivedData/ListRunner-reveal-regressions-26df57a.xcresult`. The other seven checks covered Add Items focus retention, already-visible row positioning, first-item Add Items reveal, first long-item reveal, both keyboard dismissal animation cases, and the compact 52 pt action row.

At the user's request, Xcode built, installed in place and launched `26df57a` on Adrian’s iPhone (PID 12297, launch `95aa06b80`), without resetting app data. Log: Mac `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261030-130706.txt`. Follow-up app revision `36c734c8506907014664f9735c29dae301e9850e` guards stale typing callbacks and defers keyboard-hide retirement until focus settles. Its five-iteration checks of both failing scenarios **did not start**: SSH to the Mac timed out during banner exchange (exit 255), before checkout synchronization. It is **not installed on the phone**. Resume by verifying Mac connectivity and clean checkout, syncing the exact app revision, and running both repeated scenarios plus the wider regression set. All tests use isolated local fixtures, not real retailer carts or Reminders. Unrelated design-audit edits remain untouched.

## Compact import/Add Items row — 30 October 2026

Revision `815864efab3f52510630c2b351b8d03caae2332e` reduces only the existing product-action List row's vertical insets to 4 pt top/bottom, retaining 16 pt horizontal insets and the import action's 44 pt minimum tap area. Measured row height is **52 pt**, down from the previous 74 pt native row. Button styling, input geometry, import behavior and Add Items focus retention are unchanged. OpenPencil inspection timed out; no custom redesign or design-document edits were attempted.

**4/4 focused iPhone 17 / iOS 27 simulator UI tests passed**: compact-row geometry/hit area, repeated Add Items with keyboard retained, first-item visibility above the keyboard, and isolated Paprika import/deduplication/store ownership. Evidence: Mac `~/Library/Developer/Xcode/DerivedData/ListRunner-compact-actions-815864e.xcresult`, including the compact-row screenshot attachment and measured 52.0 pt log. Tests used local fixtures only, not real Reminders or retailer carts.

At the user's request, Xcode built, installed in place and launched this revision on **Adrian’s iPhone / iOS 27.2** (PID 11967, launch `968073300`), preserving existing app data; no list/session reset or retailer interaction was performed. Device build/launch log: Mac `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261030-121957.txt`. Unrelated Linux design-audit edits remain untouched.

## Preserve Lemon Tree — 30 October 2026

Revision `30ef292e3b49e4e9dafff5cce61853cf8fd2c320` adds a distinct `lemon-tree` dictionary entry with canonical name/search term `Lemon Tree` and plural alias `lemon trees`. The existing longest-overlapping-match rule now chooses the complete product name instead of the nested Lemon entry, without changing parser algorithms or globally changing compound-name handling. Case variants and counted trees retain the full name; ordinary Lemon and Lemon juice remain separate. Existing saved names are untouched because lost source wording cannot be inferred safely.

**449 parser checks, 195 regional-name checks, 7 resource-verifier checks and the focused iPhone 17 / iOS 27 UI test passed.** The UI test enters `lemon, Lemon tree` together, verifies separate exact-named rows (no incorrect merge), and verifies both names persist after relaunch. All 11 JSON resources in the built simulator app byte-match canonical sources. Linux has no Swift compiler; native suites ran on the clean Git-synchronized Mac checkout. Xcode MCP device-target build succeeded with no errors; Mac log `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261030-105450.txt`. UI evidence: Mac `~/Library/Developer/Xcode/DerivedData/ListRunner-lemon-tree-30ef292.xcresult`. Isolated local fixtures only; no physical-device install, real grocery-list edit, Reminders write or retailer/cart action.

## Product-entry keyboard dismissal animation — 30 October 2026

The native text view previously changed first responder synchronously inside `UIViewRepresentable.updateUIView`, inheriting SwiftUI's UIKit animation suppression. Implementation `2c28574dbb08e89f303d2397e013ed7200445dad` coalesces those requests onto the next main-queue turn, reads the latest focus binding rather than a captured desired value, and ignores detached/dismantled editors. It does not force animation enablement, invent a keyboard duration, or override Reduce Motion. Final code `b474abf7582ad1595f2971309e5ddcb296163866` also uses an editor-scoped weak handle to resign from explicit Show Store/item-row/Clear List actions before presentation, outside layout updates. This prevents a sheet from capturing the prior first responder and restoring the keyboard on return; no global application/other-scene responder action is used.

At `b474abf`, **9/9 focused iPhone 17 / iOS 27.0 simulator UI tests passed**: outside-tap and empty-Return animation guards, existing header/section/empty-list dismissal paths, blank/whitespace Return dismissal, repeated Return submission, repeated Add Items focus retention, Show Store defocus/draft preservation/no refocus on return, and Clear List popup cancellation. The two debug-only guards captured `update-animations-disabled; resign-animations-enabled` at actual focus scheduling/resignation, confirming the transaction-boundary fix rather than merely eventual keyboard disappearance. The intermediate `2c28574` run passed 7/8 but failed the Show Store return-focus check; the explicit pre-presentation resignation fixed that before the clean final run. No test failure was suppressed. Tests use isolated local lists/WebKit fixtures, not retailer or Reminders traffic.

Evidence: Mac `~/Library/Developer/Xcode/DerivedData/ListRunner-keyboard-animation-b474abf.xcresult` (intermediate `ListRunner-keyboard-animation-2c28574.xcresult`); Xcode MCP device-target build succeeded with no errors, log `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261030-105114.txt`. These checks verify animation eligibility and focus behavior, not frame-by-frame animation on the user's phone or accessibility-runtime sign-off. No physical-device installation was performed. Unrelated Linux OpenPencil audit edits remain untouched.

## Clear Added / Clear All — 30 October 2026

Implementation `5aec59f916804695de5d7a34ebfb302784422146` keeps the existing button-anchored native Clear List dialog and always opens it, including completed lists. Clear Added is offered only when the current store has Added rows; it deletes just those rows, cancels only their pending reminder writeback, preserves other statuses/order and any surviving selection, and chooses a remaining Pending item if the selected row was removed. Clear All deletes only the current store's rows. Neither choice mutates another store's list, retailer baskets or Apple Reminders. The unrelated uncommitted OpenPencil audit notes are untouched; OpenPencil was disconnected and the user explicitly approved using the existing native dialog without a design review.

At `31e10cd16cf2719c3929c1ae80590a6c4b67a791`, **4/4 focused iPhone 17 / iOS 27.0 UI tests passed**, with no failed/skipped tests or runtime warnings in the result summary: mixed Pending/Added/Skipped selective clearing, hiding Clear Added afterward, all-clear/cancellation with no Added items even when another store has Added rows, cross-store preservation, relaunch persistence, completed/Added-only list choices, and the wide Clear List hit target. The first test run assumed a visible Cancel button and failed at cancellation; the OS renders a native popover which omits that cancel-role row. The test-only follow-up uses a visible Cancel where available or taps outside the popup and verifies dismissal. No app workaround or custom Cancel control was added. Evidence: Mac `~/Library/Developer/Xcode/DerivedData/ListRunner-clear-options-31e10cd.xcresult` (initial run `ListRunner-clear-options-5aec59f.xcresult`). Verbose simulator diagnostics collection disabled for these runs to avoid the earlier collection timeout; XCTest assertions/results remain enabled.

Xcode MCP built the physical-device target successfully with no errors at the same app-code revision; log: Mac `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261030-103115.txt`. UI tests use isolated local fixtures, not real grocery lists/Reminders or retailer traffic. No phone install or live cart change was performed.

## Idle browser recovery and failure diagnostics — 30 October 2026

Fast-forwarded `main` through `88f181b9e17601ba9de002b8a96cbe08408063d9` (the Kmart branch and its subsequent fixes). Recovery implementation is `37cc788893a0d08f4f36ec7ac7cfb0096727637e`; final code revision `8b9d8865c740faaf2c963d45ff6eef19d4739cef` restricts persisted error codes to a closed native enum. Linux and Mac use Git for the handoff; unrelated uncommitted design-audit notes on Linux are preserved and excluded.

Idle/dismissed/inactive web-content process exits invalidate transient automation and set a deferred rebuild flag rather than latching an alert. Reopening/foreground resumption rebuilds using the same per-store website-data store, retains cookies/session identity, creates fresh bridge context and uses the selected search/current naming or safe homepage, never the last product/cart/checkout URL or form. Hidden SwiftUI updates cannot reload a marked browser. Active exits, HTTP/network failures and existing verification blocks retain explicit recovery. Diagnostics and OSLog now distinguish idle/active exits, browser rebuilds, timeout/error codes and HTTP status, without URLs/searches/error descriptions/cookies. No age timer or general automatic retry was added.

At `37cc788`, **3/3 focused iPhone 17 / iOS 27.0 UI tests passed**: `testIdleRecoveryBrowserChecks`, `testPreloadSearchIsPromotedAfterCooldown`, and `testRegionalSearchBrowserChecks`. The idle fixture injects the actual delegate callback into nonpersistent Coles, Woolworths, Bunnings and Tesco browsers; it exercises both reopen and foreground resume, real fixture-cookie retention, data-store identity, bridge invalidation, safe destinations, old-view/retired-navigation rejection, active Retry, timeout/HTTP diagnostics, no-selection recovery and verification protection. All WebKit requests use local HTML fixtures, never retailer/cart traffic. Console inspection confirmed Bunnings process-exit, timeout (-1001) and HTTP 503 records with active/inactive state; these are injected fixture events, not diagnoses of the user's live Bunnings failure.

At final code revision `8b9d886`, **331 native recovery/reset/diagnostic checks passed**. The parser and regional-name suites also passed (439 and 195 checks at `37cc788`, with no subsequent parser/naming changes). Linux: **78 detector/DOM tests and 7 resource-verifier tests passed**. The generic iOS device build compiles successfully with signing disabled, and all 11 bundled JSON files byte-match canonical resources. SSH-driven signing failed with `errSecInternalComponent`, but **building through Xcode MCP succeeded**, including Apple Development signing of the actual `Debug-iphoneos` app, with no build errors. No keychain settings/credentials were changed and no phone installation was attempted. Xcode evidence: Mac `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261030-101309.txt`. Simulator test results are kept outside the checkout under Mac `~/Library/Developer/Xcode/DerivedData/ListRunner-idle-recovery-checks-{37cc788,8b9d886}.xcresult`.

These deterministic fixtures verify the recovery path, not the exact cause of an unpredictable live idle failure. Physical-device installation and observation of the original intermittent issue remain unverified; further genuine navigation failures should now carry actionable safe metadata.

Final rerun at `8b9d886`: **idle-recovery and regional browser checks passed; preload promotion failed** (2/3, not a clean 3/3). XCResult's failure snapshot shows `preload-debug-status: Cancelling unused preload` after progression to Pears, followed by a 600-second simulator diagnostic-collection timeout. Cause remains unconfirmed; timing of the debug fixture's fixed 900ms automatic confirmation versus cold preload readiness is a candidate, not a proven diagnosis. Tracked separately for investigation; no recovery code was changed to mask this failure.

## Product Return intercepted before layout — 29 October 2026

Replaced the vertical SwiftUI TextField with a small native UITextView wrapper retaining the outlined entry, placeholder, one-to-four-line wrapping/overflow scrolling, accessibility input identity and paste behavior. Its editing delegate returns false for a single keyboard newline and submits before UIKit inserts/layouts it, eliminating the prior insert-then-onChange-submit flash. IME marked text is not intercepted; multiline paste remains a normal edit and uses existing parsing. Native first-responder state is mirrored via a binding; Add Items/Return retain focus, empty Return dismisses, outside taps/Show Store still defocus with draft retention. Initial wrapper run revealed FocusState had no SwiftUI focus target, causing focus loss; changed that local flag to native-backed State before passing checks.

At `df07cd310387de5eb0a13054ff059768c2db1643`, **6/6 focused iPhone 17 / iOS 27 UI tests passed**: stable one-line geometry after Return, empty/whitespace Return dismissal, continued Return entry, repeated Add Items retention, long-item wrapping/visibility and full-field padded activation. At `c9003bfc93cb845150d2cbbc4b728a1bebf0b1d9` (same implementation, extra tests), **3/3 additional UI tests passed**: real clipboard multiline paste via native Paste creates toaster/chair rows, outside dismissal/draft preservation, and Show Store defocus. Test pasteboard payload is isolated simulator test data. Evidence: Mac `RunSomeTests/Test-ListRunner-2026.10.29_23-45-15-+1100.xcresult` and `Test-ListRunner-2026.10.29_23-48-09-+1100.xcresult`.

Normal-app simulator verification PID40305 used actual software Return on temporary Entry verification row: input cleared, exactly one Pending row, keyboard retained, editor remained310×22pt; empty Return then dismissed. Local row deleted, initial empty BIG W list restored; no retailer/cart/settings interactions. Evidence `/tmp/opencode/return-editor-before.png`, `return-editor-after-settled.png`, `return-editor-cleanup.png` and accompanying hierarchies. Interaction session ended.

## Add Items focus exception — 29 October 2026

At the user's request, Add Items is now explicitly exempt from outside-tap keyboard dismissal. The list tracks the button's global bounds alongside the outlined editor, excludes both from spatial-tap defocus, and submits with `keepingInputFocused: true`. This supersedes earlier button-submit/dismiss behavior, without changing outside-header/heading dismissal, Show Store defocus or empty/whitespace Return dismissal. Return with products still submits and retains focus.

At `c1e1fd61ab287e8cd3bcb2d487ffc01f3a32b826`, **5/5 focused iPhone 17 / iOS 27 UI tests passed** together: repeated Add Items taps followed by continued typing without refocus, outside dismissal/draft preservation, empty Return dismissal, long-item visibility above the retained keyboard, and Show Store defocus/draft preservation. Evidence: Mac `RunSomeTests/Test-ListRunner-2026.10.29_23-29-14-+1100.xcresult`. Isolated local UI fixtures only; no retailer/cart changes.

## BIG W first-use availability timeout — 29 October 2026

User reported a real add after postcode/store setup while ListRunner timed out and showed detection unavailable. Both previous script/native eight-second deadlines started at Add, so human setup outlasted them. Revision `822356923747960c03ea997c4b4ec4cddfd554d4` introduces optional validated quantity-profile `setupPrompt` (selector, text regex, max wait); BIG W matches visible postcode/store dialogs with a 300000ms maximum. Matching setup extends the original candidate without rebaselining or treating setup completion as success. Native start/confirmation messages are deferred until the same product's stable quantity increase is observed. Nonmatching dialogs do not extend observation; cancellation/expiry produces a typed confirmation timeout, while page/context/background changes cancel without a false success. Native cancelled timeout tasks also now check cancellation before touching state.

**78 DOM/cart tests, 326 native checks and 7 resource-verifier tests pass**, covering >60-second fake-clock setup, grid/detail detection+Undo, cancelled setup, hidden/unrelated dialogs, bounded waits and navigation/context invalidation. Xcode built/launched without errors on iPhone 17 / iOS 27 simulator, PID37855, launch ref `95a9f4000`. User explicitly approved resetting ONLY BIG W simulator website data to reproduce first use and reusing Melbourne3000. Physical phone/store cart untouched during verification.

**Both fresh-session live flows passed.** Before each reset actual retailer cart explicitly empty; only BIG W session reset via its named confirmation. Approved toaster Contempo2 Slice Toaster White6060359 $7.50, one Add only per cycle: detail postcode prompt stayed open ~42seconds, still Pending/no detection-unavailable at23.5sec; Save at23:17:39 produced Qty1/nativeAdded by23:17:42. Grid prompt remained open25seconds, still Pending/no warning; Save completed original Add and nativeAdded in next5-second observation. No second Add or native MarkAdded. Each nativeUndo restored Pending and retailer0, actual cart explicitly empty; no manual retailer removal needed. Temporary local test row deleted after final cycle, local BIG W list empty. Availability3000/QueenVictoriaVillage retained, other store sessions untouched, all interaction sessions ended. Current simulator app left running; minor expected two-line title truncation observed for long product name, full name in receipt/hierarchy.

Evidence: `/tmp/opencode/bigw-first-use-tests.tap`; detail `/tmp/opencode/bigw-firstuse-08-empty-before-reset.png`, `bigw-firstuse-13-reset-confirm.txt`, `bigw-firstuse-26-prompt-after24s.png`/`.txt`, `bigw-firstuse-30-autoadded-qty1.png`, `bigw-firstuse-32-after-undo.txt`, `bigw-firstuse-36-final-empty.png`/`.txt`; grid `/tmp/opencode/bigw-firstuse-grid-{before-empty,before-add,postcode-wait,autoadded,after-undo-empty,final-local-empty}.png` and corresponding fetched hierarchy files. These extend earlier simulator certification to first-use setup, not all marketplace/variant/account flows.

## Most recently enabled store selection — 29 October 2026

Visibility saves record actual disabled→enabled transitions in persisted `pendingEnabledStoreSelection.v1`, in order; disabled candidates are removed. On return to the list, reconciliation consumes the newest still-enabled available candidate once, before the existing enabled-current/alphabetical fallback. Manage Stores remains open while toggling, repeated on-values do not requeue selection, country/filter changes do not record transitions, and manual selections after consumption remain intact. Confirmed regional switches on enabled brands queue the new destination; disabled-brand region choice alone does not. Reset Local Data clears pending selection; no saved grocery/list/session data is moved or deleted.

**321 native checks passed**, including ordered enables, relaunch-before-return, one-shot consumption, reassignments, disabling the pending candidate and reset. At `e14e21dfbb3870b3e459d7aacad8375b878702fe`, **3/3 focused iPhone 17 / iOS 27 UI tests passed** together: newest-store activation/multiple enables/re-enable/manual choice/relaunch, disabled-active fallback with saved item statuses intact, and all-disabled recovery. An older assertion deliberately encoded the superseded keep-current-on-reenable behavior; updated before the clean run. Evidence: Mac `RunSomeTests/Test-ListRunner-2026.10.29_23-01-21-+1100.xcresult`. Isolated fixture lists only, no retailer/cart actions.

## BIG W search/detection/Undo implementation — 29 October 2026

**Live simulator verification PASSED after reconnecting Xcode**, at installed revision `86ba4edf3270c1f258126a1c14566dd465adbd56` (automation implementation `9aa03ce73e36b0e866f1919b6b3026f3df5c3c79`). Xcode opened the canonical Mac project as `windowtab-qngDTWB2L3`, confirmed iPhone 17 / iOS 27 destination and built/launched with no errors, PID 35641 (launch ref `95aa07180`). Show Store automatically searched the saved Toaster row; the retailer search was then narrowed manually to the approved exact product. Initial cart explicitly empty. One grid Add for Contempo 2 Slice Toaster – White, article 6060359, $7.50, produced native Added without Mark Added. Native Undo restored Pending and the product's Add control; actual retailer cart explicitly empty afterward. A second baseline-empty cycle repeated this successfully from the individual product page, again with native Undo and explicit final empty cart, no manual retailer removal. Console recorded two quantity-increase confirmations and successful store-cart Undo notifications. Grid transition captured between 22:40:40 and 22:40:55; detail between 22:43:33 and 22:43:50 (tool/capture bounds, not detector latency). Melbourne 3000 availability retained as explicitly approved. No checkout/login/payment/account or unrelated product action, no phone deployment. The sole temporary Toaster row was deleted afterward using local Actions → Delete Item; BIG W list is empty, 0 pending/added/skipped, and remains enabled. All interaction sessions ended; normal simulator app left running.

Evidence on Linux: `/tmp/opencode/bigw-live-05.png` (initial empty), `bigw-live-18.png` (grid before), `bigw-live-20.png` (grid Added/receipt), `bigw-live-21.png` (grid Undo/Pending), `bigw-live-26.png` (between-cycle empty), `bigw-live-28.txt` (article identity), `bigw-live-29.png` (detail before/postcode), `bigw-live-31.png` (detail Added/receipt), `bigw-live-32.png` (detail Undo/Pending), `bigw-live-35.png` (final empty), plus matching hierarchy files and `/tmp/opencode/bigw-cleanup-final.png` / `.txt` (local cleanup). This certifies the reviewed BIG W-sold simple product grid/detail flow and quantity reversal, not all marketplace sellers, variants, login/redirect flows or physical-device behavior. Preservation of pre-existing quantities and guarded/refused Undo remain fixture-tested rather than live-tested.

Simulator-only deployment requested. Reviewed live mobile DOM: `/search?text=toaster`; Contempo 2 Slice Toaster – White, article 6060359, $7.50, sold/shipped BIG W. Grid articles have linked numeric IDs, title paragraphs and scoped Add/quantity controls; product pages use `h1#product-title` and duplicated main/sticky button grids. Add replaces the button with `update quantity` input and increment/decrement controls. BIG W required a postcode before adding; user explicitly approved Melbourne 3000, which selected Queen Victoria Village for availability. User approved exact-product +1→0 cycles, not checkout/login/payment changes. First pending Add completed after postcode selection, yielding product receipt Qty1; no duplicate Add. One product-specific decrement restored zero without dialog/navigation; cart explicitly confirmed empty. No detection was claimed for this browsing-only build.

Implementation opts BIG W into schema3 card/detail quantity profiles, exact-host search/detection/Undo native ceilings, explicit dedicated-Add zero state, stable same-ID/profile quantity observation and React control reacquisition. Shared profile Undo requires one-use provenance, unchanged page/context/quantity and one scoped enabled decrement with two stable observations per step. Responsive duplicates must agree; only a visible container can supply a reversal control. Success-modal recommendation controls lacking exact card links/container cannot inherit the page product. Receipt-only Kmart Undo stays disabled and legacy stores retain their engine. Added semantic DOM fixtures cover grid/detail/sticky, increments, replacements, recommendation attribution, zero-state transitions, unsafe identities, passive/synthetic/unrelated changes, cancellation and guarded Undo. Mac native/build/UI and final live grid/detail/Undo validation pending at implementation handoff. Existing temporary local Toaster row and simulator availability setting retained for testing; iPhone untouched.

Implementation revision `9aa03ce73e36b0e866f1919b6b3026f3df5c3c79` pushed and checked out cleanly on Mac: **73 DOM/cart tests, 316 native checks and 7 resource-verifier regression tests pass**. Xcode MCP process exited during the first UI-test request and requires user reconnection via `/mcps`; live post-implementation grid/detail/Undo cycles remain blocked, not certified. Command-line `xcodebuild test` on iPhone 17 / iOS 27 nonetheless built successfully and passed **2/2 isolated UI tests** (BIG W capability/enable/reset-cancel and Kmart's unchanged Undo restriction). Evidence: Mac `/tmp/listrunner-bigw-profiles-20261029.log` and `.xcresult`; Linux `/tmp/opencode/bigw-dom-tests.tap`. All **11 installed simulator JSON resources byte-match** canonical files. Normal app launched with no fixture environment through simctl (PID 32973). The earlier read-only/approved test cart was restored empty before implementation; no further retailer mutations were attempted while MCP was unavailable. Simulator-only target throughout; physical iPhone unchanged.

## Manage Stores gesture isolation — 29 October 2026

The list-screen keyboard-dismiss spatial gesture now participates only while the product field is focused and its source list is visible (`GestureMask.all`); otherwise `.subviews` removes the parent recognizer from arbitration while retaining child gestures. List disappearance clears focus/visibility. This addresses the suspected interference with UIKit Manage Stores row selection; callback early-return alone had left a navigation-container recognizer active. No store-row size, store preferences, list contents or retailer sessions are changed.

At `af81d47a82b2c56706bdae9d5c8f4e078c59029f`, **4/4 focused iPhone 17 / iOS 27 tests passed**. New regression enters Settings/Manage Stores from both unfocused and focused list states, opens Coles/Woolworths/Kmart/Coles via single row taps (eight successful openings total), and verifies returning preserves draft without keyboard reactivation. Outside-header/heading dismissal, full padded-field activation/submission, and Show Store dismissal/draft retention also pass. Evidence: Mac `RunSomeTests/Test-ListRunner-2026.10.29_20-19-50-+1100.xcresult`. Tests used isolated local data and did not toggle stores or touch retailer carts. This verifies the changed interaction path on simulator, not yet user sign-off for the physical-device symptom.

## Comma-separated non-grocery entry — 29 October 2026

Direct item entry now uses `IngredientParser.parseProductEntry`, treating comma/newline/semicolon/tab as explicit separators regardless of ingredient-dictionary recognition. Previously `toaster, chair` remained one unknown ingredient because recipe-oriented `parseList` only split commas when every segment matched the dictionary. Existing per-segment parsing, quantities, ordering/merging and empty-segment rejection remain; Paprika/recipe parsing retains its original preparation-comma behavior. Add Items enablement and submission use the same entry parser.

At `e80759d17fb8520e575977fb3a7f922445428a4c`, all parser fixtures passed (runner reports 439 existing fixture/alias checks, plus added explicit-entry regressions covering unknowns, absent dictionary, mixed known/unknown entries, quantities, whitespace and separators). Linux lacks swiftc; executed on the clean exact-revision Mac checkout. **3/3 focused iPhone 17 / iOS 27 tests passed**: `toaster, chair` produces two independent rows, existing new-item ordering remains, and empty/whitespace Return dismisses focus without inserting a line. Empty Return had also passed alongside nonempty Return at `5625048`. Evidence: `/tmp/opencode/comma-mac-parser-tests.log`; Mac `RunSomeTests/Test-ListRunner-2026.10.29_19-48-55-+1100.xcresult`. Isolated UI fixtures only; no existing user row was silently split or renamed.

## Defocus product entry on outside taps — 29 October 2026

List-screen simultaneous spatial tap handling compares tap location against the outlined field's global frame, clearing focus only outside it. Padding taps retain focus and native text editing remains intact. Header, section heading and empty-state taps now dismiss the keyboard without losing draft text or consuming normal control actions. Add Items submits with focus disabled, while keyboard Return retains focus for continued entry; this supersedes earlier Add Items focus-retention behavior. A separate submit focus parameter avoids the animated insertion reactivating the editor after a button tap.

At `b83efb246c72df13fca5555820725a40e0b2c4ad`, **6/6 focused iPhone 17 / iOS 27 tests passed** together: outside header/heading taps with draft preservation, empty-state dismissal, both padded corners activating the field, Return submission/continued typing, Add Items submission/dismissal, and long first-item visibility with dismissed keyboard. Initial run exposed refocus during animated Add Items insertion; fixed before the clean rerun. Evidence: Mac `RunSomeTests/Test-ListRunner-2026.10.29_19-28-00-+1100.xcresult`. Tests used isolated lists/nonpersistent fixtures and no retailer actions.

## Simplified full-field product entry — 29 October 2026

Removed the plus focus button and helper/example line at the user's request. Retained `Tap to add products…`, store-coloured outline and focused styling. The padded field has a rectangular tap region with a simultaneous focus gesture, including the empty space inside its border, without replacing native text editing/selection. Existing submit/parser/draft behavior is unchanged.

At `dc625d0ac5039fdfe11068dcfc574c360c2fd5fe`, **4/4 focused iPhone 17 / iOS 27 tests passed**: tapping lower-right and upper-left visual padding opens the keyboard, no plus/helper remains, submission works; Return submission, Show Store keyboard dismissal/draft retention and long first-item scrolling also pass. XCTest exposes the inner 22pt editor rather than the padded 52pt field, so the padding regression taps 10pt outside the native editor bounds, within its 14pt visual padding. Initial test incorrectly measured only the editor; corrected before clean rerun. Evidence: Mac `RunSomeTests/Test-ListRunner-2026.10.29_18-56-38-+1100.xcresult`. Tests use isolated local lists and no retailer actions.

## List-item swipe deletion and store-launch focus — 29 October 2026

List rows expose a native trailing red Delete action on a left swipe; full-swipe deletion is disabled so a separate tap is required. The action reuses the existing local `delete(item)` handler and never changes retailer carts. Existing menu deletion and edit-mode reordering remain. Both Show Store and item-row store launch now explicitly clear grocery-input focus before presentation without discarding draft text.

At `8e52f9df517c8ebb05752a48c5824d9cd7ec01e1`, **2/2 focused iPhone 17 / iOS 27 UI tests passed** together: swipe reveal/separate delete tap/empty-state/store isolation/deletion persistence across relaunch, and Show Store keyboard dismissal/draft retention/no refocus after return. Store-launch focus previously also passed alongside Add Items keyboard-retention regression at `00b8196`. All test lists/sessions use isolated fixtures; no user list or retailer-cart mutations were performed by these tests. Evidence: Mac `RunSomeTests/Test-ListRunner-2026.10.29_18-43-49-+1100.xcresult`.

## Prominent inline product entry — 29 October 2026

User approved the inline-entry proposal: Add products heading, store-coloured outline/plus icon, `Tap to add products…` placeholder, and examples in a helper line below. Input remains one-to-four lines, using the existing parser/submit/paste behavior; import and Add Items remain separate. Plus is a 44pt keyboard-focus button, not a submit action. Focus strengthens the outline/background. Existing accessibility input identifier/label retained. OpenPencil inspection was attempted but timed out; implementation follows the user's approved inline mockup and current native/store colour tokens.

At `54364920c9c9c5d7b5a98c1521e39e6bc75c602b`, **4/4 focused iPhone 17 / iOS 27 UI tests passed**: new `testAddProductsEntryOpensKeyboardAndSubmitsFromEmptyList()`, Return submission, Add Items focus retention, and long first-item auto-scroll. Earlier run failed only the stale `Add grocery items` heading assertion, updated to the new wording before the clean four-test run. Mac evidence: `RunSomeTests/Test-ListRunner-2026.10.29_18-33-15-+1100.xcresult`. Normal app built/launched without errors (PID 24432). Visual device check confirmed clear store-tinted entry, full helper text, no clipping/overlap, and caret/stronger focus outline after plus tap. Software keyboard did not display in that manual session (likely hardware-keyboard simulator state); keyboard presence is proven by the focused XCTest, not the manual screenshot. Empty list/counts preserved; no retailer actions, data entry or submissions during manual check. Evidence `/tmp/opencode/prominent-entry-empty.png`, `prominent-entry-focused.png` and matching hierarchy artifacts. Existing `shop though them` copy was left exactly as previously requested, not silently edited as part of this task.

## Card-progress collapse chevron — 29 October 2026

Active cards now display a small down chevron immediately after the progress count. Count and chevron share an independently accessible `Collapse overlay` button with a 44pt minimum target, outside the item-selection button to avoid nested controls. It invokes the existing collapse path (including cooldown cancellation), with no new status/cart mutations; the existing compact bar expands it again. Card dimensions, progress/status colours and swipe/drag support are retained. OpenPencil document inspection was attempted but the connection timed out; the change follows the current native card layout.

At `fb93430e1322208ea0bd8082bea00958f393a93d`, all three focused iPhone 17 / iOS 27 UI tests passed together: `testProgressChevronCollapsesOverlayAndPreservesStatus()`, `testSlowOverlayDragCollapsesAndCanExpandAgain()`, and `testReloadControlRemainsVisibleAcrossNavigationActions()`. The new test checks Pending and Added preservation and the 44pt accessible target (with 0.01pt floating-point tolerance; initial strict equality failed at 43.999999999999886). The 61 detector fixtures passed after the UI implementation. Xcode normal-app build/launch succeeded, PID 22621. Device-interaction visual check confirmed the chevron's alignment/~5pt gap, 44×44 target, collapse/expand behavior and unchanged selected item/quantity/Pending state. Temporary local Overlay test row was deleted afterward, restoring the initially empty list. No retailer cart/account/payment/checkout control was used; the existing retailer trolley badge was left untouched. Evidence: `/tmp/opencode/card-collapse-expanded.png`, `card-collapse-compact.png`, and `card-collapse-cleanup.png` with hierarchy files. UI-test evidence: Mac `RunSomeTests/Test-ListRunner-2026.10.29_18-00-21-+1100.xcresult`. Interaction sessions ended.

## Reload selected product search — 29 October 2026

Overlay Reload now reissues the selected item's saved search term through the existing regional naming, coalescing and navigation-pacing path, rather than calling `WKWebView.reload()` on the currently browsed product/cart page. Item status and interaction identity are unchanged. Verification cooldown protections remain; browsing-only stores return to their trusted homepage without enabling search. Accessibility label is `Reload product search`.

At `56d3432bfaa4b04bee70adf099d0523add650383`, both focused iPhone 17 / iOS 27 UI tests passed in one run: `testRegionalSearchBrowserChecks()` and `testReloadControlRemainsVisibleAcrossNavigationActions()`. Browser fixture checks include returning from a product URL to the original query, regional naming, preserved interaction and latest-selected-query coalescing; all navigation is isolated fixture HTML, not retailer access. Initial run exposed the fixture's cold-WebKit two-second preload assumption and an incorrect NZ eggplant expectation; completion polling and an unambiguous milk query corrected the checks before the clean 2/2 rerun. Evidence: Mac `RunSomeTests/Test-ListRunner-2026.10.29_17-50-42-+1100.xcresult` and `F583CD92-78F6-4553-8E4B-8EEF395690B3.txt` under the Xcode ActionArtifacts directory. Normal app then built/launched successfully on the simulator (PID 22200), without fixture launch settings. No retailer cart actions occurred for this change. The 61 detector fixtures also passed after the initial reload implementation.

## Page-specific detection profiles — 29 October 2026

Introduced opt-in schema 3 `profiled` detection while retaining schema 2/legacy stores unchanged. Kmart has card-link and page-URL profiles sharing a product-receipt observer; the live detail DOM contains `product-button` / `.product-button-container`, duplicated responsive `h1[data-testid="product-title"]` headings and no quantity field. Read-only resolution against the running simulator returned profile `product-page`, product ID `42250333`, name `foldaway pvc chair`. Config validation rejects unknown profile/receipt keys, incompatible version/strategy/scope/identity combinations, duplicate IDs, invalid/bounded observation windows and invalid capture regexes. Profiled Undo stays disabled. Fixtures cover detail success, responsive headings, recommendation identity, trusted taps, stale/unrelated/expired receipts, navigation/context cancellation, overlapping rules and scoped quantity-profile baselines. Mac native checks, build/resource audit and live detail/grid cycles pending at implementation handoff; earlier grid certification below predates this profile engine.

**Handoff and live verification passed at `f54314ddc8812ece4dfa01760bca118cfecfc651`.** Clean Mac checkout received this exact pushed revision; **311 native checks, 61 DOM/cart fixtures and 7 resource-verifier tests passed**. Xcode built/launched on iPhone 17 / iOS 27.0 without errors, PID 20782; all **11 bundled JSON resources byte-match** canonical files and no legacy `-v2` copies are bundled. Two separately baseline-empty cycles passed: detail `Add to bag` on Foldaway PVC Chair / P_42250333 and grid named Add each automatically changed the user's existing Chair / quantity 1 row Pending→Added without native Mark Added. Detail captures bound the transition between 17:26:00.397 and 17:26:14.993; grid between 17:29:35.006 and 17:29:48.728 (capture bounds, not measured detector latency). Console launch ref `c05d94d80` contains two quantity-confirmation notifications. Each bag then showed only that exact chair, quantity 1, $9; product-specific Remove restored `Your shopping bag is empty!` after each cycle. No checkout/account/payment/unrelated product or retailer Undo action occurred. Existing local Chair row preserved and restored Pending, final totals 1 pending/0 added/0 skipped. Interaction session ended; physical device unchanged. Evidence on Linux: `/tmp/opencode/kmart-profiles-detail-{before,early,after,bag,empty}.png`, `/tmp/opencode/kmart-profiles-grid-{empty-before,before,early,after,bag,empty-after}.png` with matching `.txt` hierarchies, and `/tmp/opencode/kmart-profiles-final.png`. Known Close/native Dismiss strip overlap remains separately tracked and was safely worked around; not fixed or certified here. Recommendation isolation and the alternative quantity confirmation strategy are fixture-tested, not live retailer-certified.

## Kmart mobile Add label regression — 29 October 2026

**Live verification passed at `970d7accc49c19391920b920b1f48ea62ed71ee3`** on iPhone 17 / iOS 27.0. After the user authorized further controlled chair cycles, the actual retailer bag was confirmed empty, then exactly one retailer Add tap for Foldaway PVC Chair changed the native row from Pending to Added without tapping Mark Added. The first post-tap capture (~15.5 seconds later) showed Added; the exact transition time within that interval was not measured. Xcode console for unchanged PID 19781 recorded `Trusted cart tap armed quantity confirmation` and `Quantity increase confirmed; notifying overlay`. The retailer bag contained the exact chair, quantity 1, $9.00. Only `Remove Foldaway PVC Chair` was used to reverse it; the bag body displayed `Your shopping bag is empty!` with no product row (the retailer header retained a stale count). The sole temporary local test row was subsequently removed via Actions → Delete Item; final list is empty with 0 pending/added/skipped. No checkout/account/payment or unrelated product changes occurred. Device interaction sessions ended. Evidence: `/tmp/opencode/kmart-latest-before-add.png`, `kmart-latest-after-15s.png`, `kmart-latest-bag-one.txt`, `kmart-latest-empty-after.png`, `kmart-latest-console.txt`, and `local-cleanup-empty.png` on Linux. Kmart retailer-cart Undo remains disabled. Separate UI issue observed: retailer Close overlaps the native Dismiss-store hit strip, dismissing the entire sheet; not resolved by this detector fix.

Follow-up: the single approved post-label-fix cycle at `07d3cb3` also remained Pending despite a retailer receipt; the exact chair was removed and the bag body confirmed empty. Read-only debugger inspection of the actual simulator DOM found that the accessible label is on the nested SVG, not the button: button `textContent` is `Add Foldaway PVC Chair - Black colour to bagAdd` (no separating whitespace). The smallest linked container contains the image/Bestseller badge, while the title paragraph is in a sibling link at the next ancestor. The initial fixture had not represented either detail, so its success was insufficient evidence of a fix.

The follow-up accepts the observed no-space suffix, requires a title-bearing container, and reads title paragraphs rather than polluted whole-link seller/price text. The fixture now reproduces the nested image link/control and sibling title link with duplicated seller text. Read-only execution of the updated identification helpers against the live simulator DOM returned `accepted: true`, `productID: 42250333`, and `name: foldaway pvc chair`. **55 DOM/cart fixtures and 7 bundle-verifier tests pass.** No additional retailer Add was performed during diagnosis. End-to-end post-fix receipt confirmation remains unverified pending a newly approved live cycle. Raw read-only DOM evidence is `/tmp/opencode/kmart-dom-debug.json`; prior live-cycle evidence and timing are `/tmp/opencode/kmart-fixed-report.md`.

Live iPhone 17 / iOS 27 verification at `b75056de968d3c51bfa05e4b8f94442f282f17d0` reproduced a failure: one authorized tap on `Add Foldaway PVC Chair - Black colour to bag Add` produced Kmart's product-specific receipt (`Qty 1`, $9), but the native overlay remained Pending. The chair was removed using `Remove Foldaway PVC Chair`; the bag body then explicitly displayed `Your shopping bag is empty!` (its header briefly retained a stale 1-item count). No checkout/account/payment changes occurred. Evidence is under `/tmp/opencode/kmart-after5.png`, `kmart-after15-hierarchy.txt`, and `kmart-empty-hierarchy.txt` on Linux. The local temporary test row remains pending.

Cause: the configured Add-label patterns accepted only generic short labels, while mobile Kmart supplies a product-named accessible label. The capture listener therefore ignored the trusted tap before arming receipt observation. Updated only Kmart's patterns to accept anchored `Add <product> to bag` labels (including the combined accessibility `Add` suffix). The DOM fixture now uses the observed mobile label; regressions prove old rules ignore it, updated rules confirm the product-specific receipt, and unrelated receipts, synthetic taps, in-progress labels and Remove controls do not confirm adds. **54 DOM/cart fixtures and 7 bundle-verifier tests pass.** Cart Undo remains disabled. A live post-fix cart mutation has not been performed; do not count fixture success as device verification.

## Kmart Australia capability enablement — 29 October 2026 (Linux implementation)

Kmart's reviewed configuration enables retailer search and product-scoped cart detection; retailer-cart Undo is disabled pending a safe bag-page reversal path. The search URL uses the live site's observed `searchTerm` parameter. A controlled browser check confirmed exact Australian product URLs of the form `/product/<slug>-<numeric-id>/` and the live search-card behavior: after Add, the card returns to “Add” and exposes no quantity input, while Kmart displays a product-specific “Added to your bag” receipt with name and `Qty 1`. One approved browser test added Foldaway PVC Chair (product 42250333) from 0→1, verified the receipt and checkout bag quantity 1, then used Kmart's product-specific Remove control to restore an empty bag (1→0). No checkout or account/payment action occurred.

The detector now waits for that exact-product success receipt to appear after a trusted tap, checks the linked numeric ID and product-name tokens, and requires two stable receipt observations. It then supplies the native bridge with the resulting quantity from the receipt rather than assuming the search card can report it. Embedded WebKit/device verification remains pending. Kmart Cart Undo remains Not included until its page transition and exact product-level decrement/removal can be implemented and tested without broad cart mutations.

Linux verification after the receipt-specific update: **52 DOM/cart fixtures passed**, including tap-alone rejection and confirmation only after the stable product-specific receipt; all **7 bundled-resource verifier tests passed**, and `git diff --check` is clean. The Linux host lacks Xcode (`xcrun` unavailable); native recovery checks, built-app resource audit and embedded WebKit/device validation remain pending.

Xcode follow-up: after the iOS 27 simulator became available, Xcode selected the **iPhone 17 simulator (iOS 27.0)**. `testKmartAustraliaStartsHiddenWithReviewedAutomation()` passed on it (1/1), verifying the Kmart Settings capability presentation. Initial device interaction was blocked because Apple’s bundled `device-interaction` skill had not been exported into OpenCode. The skill has since been exported from the active Xcode toolchain and installed globally; device verification is now unblocked. The Mac checkout must first receive this exact fix revision through the Git handoff before the embedded retailer WebView and live cart receipt flow can be meaningfully tested. No simulator cart changes have been made.

## Alternate Settings UI execution — 29 October 2026

On the iPhone 17 Pro simulator running iOS 26.5, revision `ad95e58b06d206e6c77e32a07e152c038964a0c3` passed **291 native checks** and **47 of 48 UI tests**. The Walmart settings test failed; a focused unchanged rerun reproduced it. The exported XCTest hierarchy showed Walmart's 52-point row at y=834.7 while the table ended at y=840: XCTest considered the clipped sliver hittable, but tapping did not open settings. Revision `db5ee0a34c3d3a20d39e0a8ede69afc72063147e` changes only the UI helper to require the complete row inside the table before tapping. The focused Walmart test then **passed (1/1, 28.354 seconds)**. This is 47 passing tests in the full run plus the remaining test passing after a helper fix, **not a single clean 48/48 run on the final revision**. Manual VoiceOver, Switch Control, text-size, light/dark and iOS 17 runtime review remain separate release gates.

Evidence on Mac: `/tmp/listrunner-uitest-run3.log` and `.xcresult` (full run); `/tmp/listrunner-walmart-recheck.log` and `.xcresult` (reproduced failure); `/tmp/listrunner-walmart-all/` (exported hierarchy); `/tmp/listrunner-walmart-visible.log` and `.xcresult` (passing focused rerun). Earlier Button-only test queries were corrected in `f68c977`; BIG W grouping-fixture integration was corrected through `ad95e58`. No retailer interactions or physical-device changes were performed during these simulator runs.

## Alternate Settings hierarchy — 29 October 2026 (installed for device review)

Main Settings no longer lists stores; Country moves there from Manage Stores. Management now has enabled-first, nonduplicated brand grouping and navigation-only store rows. Full per-store settings contain the enable switch and optional region control before support/session/reset/diagnostics/About. The ABC menu is removed while UIKit's native section index remains. The index retains its known narrow-hit-region limitation; the former toolbar menu alternative is no longer present by design, and ordinary store rows remain directly accessible.

Linux validation: **6 bundle-verifier regression tests**, **51 DOM fixtures**, and `git diff --check` pass. Added native grouping assertions across AU/US/GB/NZ/unset countries, all-enabled and search cases; revised UI tests for the new navigation, regrouping, disabled-store settings and regional settings refresh. OpenPencil document inspection was attempted but its connection timed out; the implementation retains the existing native Settings visual style.

Device handoff superseding the pending native/build status above: implementation revision `e5f6d1634f828ba158f9ee4c98b31e90418bd366` was pushed on `main` and received by a clean fast-forward in `/Users/adrianzafir/Projects/listrunner`. **287 native checks passed**. SSH `xcodebuild` compiled successfully but signing failed with `errSecInternalComponent`; building through the existing Xcode GUI session succeeded without changing credentials or signing configuration. The signed Debug app under `~/Library/Developer/Xcode/DerivedData/ListRunner-epzzinbppcxqwyevzuqhzfuvrvzc/Build/Products/Debug-iphoneos/ListRunner.app` passed signature verification and all **9 bundled JSON files byte-match canonical resources**. Installed in place and launched `com.AdrianZ.ListRunner` on the connected physical iPhone 13 using `devicectl`; no uninstall, reset, test-fixture launch or retailer interaction was performed. This proves build/sign/install/launch, not visual or UI-test sign-off; the user is now reviewing the alternate layout. Automated UI checks and accessibility review remain pending.

Code review of `e5f6d16` + `24b4a90` (both re-read in full) found and fixed in `099c14a31c0d4ecdb1079982ffc8b54320b6d150`: the no-local-stores message above OTHER STORES had been lost for countries with no supported stores (restored, with tests re-covering it); the per-store enable toggle announced only "Enable store" to VoiceOver (now "Enable <brand>"); a mixed-country UI assertion compared a full-width disclosure row against the UIKit index frame and would have failed (rows legitimately extend under the index; both controls are now checked for hittability); the Country row was queried as a button (now any element type); and the disabled-brand filter was simplified to one pass. Post-fix validation: **287 native checks**, **6 bundle-verifier tests**, **51 DOM fixtures**, `git diff --check`, and a first compile of the revised **ListRunnerUITests** target (unsigned simulator `build-for-testing`; the only warnings are the toolchain's routine no-AppIntents notices) all pass on Mac/Linux. The UI tests remain unrun; executing them and manual accessibility/visual review are the remaining gates.

## Migration completion audit and bundle regression — 29 October 2026

Refreshed status, remotes, branches, ignored files and local-only commits for both active checkouts and the retained legacy Mac copy. The pre-sync archives were fully read to verify integrity; the Mac archive includes machine-local Xcode user state. Linux's only non-generated ignored files were `.superpowers` scratch/review files; these were additionally archived and verified as `~/listrunner-backups/20261029T013952Z/linux-ignored-scratch.tar.gz`. Generated dependencies/build outputs were excluded. No secrets were printed or added to Git. The legacy folder's replayed older files remain preserved and were not forcibly reset.

The active Mac path resolves directly to `/Users/adrianzafir/Projects/listrunner`, outside cloud-managed Documents/Desktop, not a symlink. Xcode was opened on its `packages/ios/ListRunner.xcodeproj`; AppleScript readback confirmed that exact active workspace path. The earlier outside-iCloud Release build log identifies the same source checkout. Other sessions' handoff guidance was retained and updated from migration-pending to verified paths.

Actual app-bundle inspection exposed a gap the earlier compile-only checks missed: the canonical Xcode project omitted `bunnings.json` from Copy Bundle Resources while the preserved Mac project supplied its duplicate variant. Added the canonical resource reference and a reusable bundle verifier with six regression tests (matching, missing Bunnings, changed resource, duplicate variant, missing app and empty canonical folder). This supersedes any inference that earlier successful compilation alone established complete resource loading. The canonical store data and automation policies are unchanged. No retailer/cart or device data mutation was performed for this audit.

Validation of committed revision `0f5e6f279b7973bcc26cb062d91eb16f4a6baa6a`, received on the Mac through the shared Git remote: **439 parser checks**, **265 native checks**, synthetic-store proof, **6 bundle-verifier regression tests**, and the unsigned Release simulator build passed. The built app's **9 JSON resources all byte-match the canonical sources**, including Bunnings, with no `*-v2.json` variants. Linux reran **51 DOM fixtures**, **90 core tests** and core type-checking successfully; **13 ignore-rule checks** passed. Logs on Mac: `/tmp/listrunner-migration-parser.log`, `/tmp/listrunner-migration-release.log`. Linux DOM log: `/tmp/opencode/listrunner-migration-dom.log`.

Opening Xcode initially caused a formatting-only rewrite of the project. Parsed plist comparison confirmed semantic equality before preserving that rewrite in a named Mac Git stash; no settings were discarded. Reopening the final project left its tracked files clean. The original archive's **155 Mac source/configuration files were checked byte-for-byte against the pushed preservation branch**, with every file matching; five Finder/Xcode metadata files remain privately archived instead of committed. Mac-only root-level source/test copies differ from the current canonical versions and are preserved on that branch, not silently labelled disposable or merged into the app. Archive permissions are restricted to the owning user. Signing identities/profiles remain machine-local; this audit did not perform a new signed device build or device installation.

## Git reconciliation and preservation — 29 October 2026

Before reconciliation, both worktrees and their Git metadata were archived outside the checkouts under `listrunner-backups/20261029T013952Z` in the corresponding user home directories. Linux holds both archives. All 33 Linux changes were checkpointed in `b12db0e`. The complete Mac source/resource state, including its extra copies and launch asset variant, was checkpointed on `backup/mac-before-sync-20261029` at `bed0e50`; machine-local Finder/Xcode user state is retained in the archive rather than committed.

The reconciled shared project uses canonical `ListRunner/Resources/*.json` paths, keeps signing team `KWV4SPU7LX` and app ID `com.AdrianZ.ListRunner`, and retains the Mac's UI-test ID `com.adriangith.ListRunnerUITests`. Local newer Mark Pending documentation is retained. The canonical launch artwork is used; the original Mac asset is preserved on the backup branch. Duplicate Mac resource variants were verified to contain the same JSON data as their canonical counterparts. Both working checkouts now use `main`; the preservation branch remains available independently. Generated build directories and machine-local editor state are ignored; Git ignore rules do not prevent cloud synchronization, so Derived Data must remain outside the project/iCloud folder.

The reconciled Mac checkout passed **439 parser checks**, **265 native recovery/diagnostics checks**, and synthetic-store proof. Linux passed **51 cart-detection fixtures**, **90 core tests**, and core type-checking. The unsigned Release simulator build passed using the default Derived Data location outside the checkout (`/tmp/listrunner-sync-release-build.log` on Mac). Parser log: `/tmp/listrunner-sync-parser-tests.log`. This confirms build/resource integration and focused regressions, not a full UI-suite, physical-device or release sign-off. No iPhone app installation, list/cookie reset or retailer-cart change was performed during reconciliation.

Final verification detected older contents reappearing in the iCloud-backed Mac folder after a successful pull (`.gitignore`, the screen-audit document and this validation document). A fresh `main` checkout was therefore cloned from GitHub outside iCloud-managed Documents. Its final location is `/Users/adrianzafir/Projects/listrunner`. The original Documents folder remains a recovery copy, not the synchronized working checkout. The preexisting Projects folder contained only Finder metadata and an empty `test` directory; it was preserved intact at `~/listrunner-backups/20261029T013952Z/preexisting-projects-listrunner` before relocating the clean clone. The outside-iCloud clone also passed the same 439 parser/265 native checks, synthetic-store proof and unsigned Release build (`/tmp/listrunner-native-sync-parser-tests.log`, `/tmp/listrunner-native-sync-release-build.log`).

## Cherry tomato variety preservation — 29 October 2026

Added `cherry` to the approved tomato modifiers so `4 cups cherry tomatoes` retains display/search name **Cherry tomatoes**, ingredient ID `tomatoes`, and quantity **4 cups**, with no unmatched text. Four new regression fixtures cover the exact input, singular tomato wording, trailing preparation and plain tomatoes. All **439 parser checks passed** on Mac (`/tmp/listrunner-cherry-tomato-parser-tests.log`). The normal app launched successfully on Adrian’s iPhone, PID **4124**, with no build errors; the built app's dictionary hash matches the canonical resource. Run log: `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261029-100408.txt`. Existing saved items are not automatically rewritten; manual re-import was not verified.

## Spinach product details and boxed quantities — 29 October 2026

Fixed the reported input `1 box (10 ounces) frozen chopped spinach thawed and squeezed dry`. It now resolves to ingredient ID `spinach`, display/search name **Frozen chopped spinach**, and package quantity **1 × 10 oz box**. `thawed and squeezed dry` is recorded in omitted preparation, with no unmatched text. Added compound/frozen spinach dictionary modifiers, box/boxes container support and plural display, and container-before-size parsing while preserving size-before-container and parenthetical unit conversions. Existing saved groceries are not automatically rewritten.

All **433 parser checks passed** on Mac, including ten new fixtures for the exact input, plural boxes, alternate package ordering, fresh/frozen spinach, trailing preparation, parenthetical conversions and unknown container plural normalization. Fixture assertions now optionally verify preparation metadata, unmatched text and grocery amount/unit, in addition to identity/name/quantity/disposition. The Mac runner was brought up to the existing Linux validation/Codable/fallback superset. The normal app built and launched on Adrian’s iPhone with no build errors, PID **4109**, 22.681 seconds. Run log: `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261029-100158.txt`. This is parser regression and device build/launch evidence, not a manual re-import verification or full release sign-off.

## Bunnings product-grid cart detection — 29 October 2026

The user's screenshot identified `productIdUnavailable`: the original Bunnings detector required a product-detail URL and could not identify Add taps on search-result cards. The script now finds the smallest card ancestor containing one unique trusted numeric product link and an Add/increment control. It refuses HTTP, credentials, nondefault ports, foreign/lookalike hosts, multiple product identities and page-wide containers. Duplicate links for one product are permitted. Only a stable increase in that identified card's quantity confirms an add; another card and the header cart badge cannot confirm it. React replacements must retain the same product ID. Detail/sticky controls continue using the detail-page ID, with recommendation cards explicitly scoped to their own links. No timeout, native trust/bridge policy or Bunnings cart-Undo capability was widened.

Actual iPhone DOM inspection confirmed Bunnings' mobile grid uses a linked product inside a `div` card, an aria-labelled Add to Cart button, and a product-specific Quantity input after adding. Other cards already held quantities, so those could not be treated as evidence for the test product. The user then made a real finger tap on **Trojan 8mm Heavy Duty Staples — 1000 Pack** in the grid without pressing Mark Added. They confirmed ListRunner automatically marked Staples Added. Native state recorded `detectionSequence: 1` and `detectionUnavailable: false`; the saved iPhone diagnostics recorded Bunnings `cartDetection succeeded none` at **2026-10-29 08:04:31 Australia/Sydney**. The user explicitly chose **Keep the staples**, so the added pack and Added status were preserved; existing cart contents were not cleared or reset. No checkout, purchase or account/payment action occurred.

**51 DOM fixtures passed**, including 11 new grid-focused scenarios covering nested taps, duplicate/ambiguous links, existing quantities, unrelated-card/header changes, synthetic clicks, same-product replacement, different-product recycling/replacement, unsafe URLs, stale contexts/expired windows and recommendation identity. Existing Coles/Woolworths and Bunnings detail/sticky regressions remain green. **265 native checks**, synthetic-store proof and the final unsigned Release simulator build passed (`/tmp/listrunner-bunnings-grid-release-final.log` on Mac). No full UI-suite rerun is claimed for this script-only change.

The temporary app-side inspection class, initialization hook and Mac compilation flag were removed. The final normal app built and launched on Adrian’s iPhone, no errors, PID **4073**, 18.55 seconds. Mac run log: `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261029-095556.txt`. Private native-state evidence is `/tmp/opencode/bunnings-grid-verified-state.json` on Linux; the diagnostic snapshot is `/tmp/listrunner-bunnings-grid-diagnostics.json` on Mac. This scoped real-tap result supersedes the earlier lack of live Bunnings detection verification below, but not broader manual/release gates.

## Bunnings authentication frame and real iPhone cart — 28–29 October 2026

The user reported Bunnings Add to Cart failing in the embedded iPhone browser and explicitly authorized test cart additions. Physical iPhone inspection showed ListRunner rejecting a subframe navigation to `authorisation.api.bunnings.com.au/connect/authorize`. The homepage rendered, but opening the cart stalled and reached Bunnings' “Sorry, we hit a snag” error page. The fix adds the exact Bunnings-owned authentication host to native browsing navigation only. HTTPS, credential-free URLs and default/443 port are required; all other store identities, storefront/automation hosts and bridge/main-frame validation remain unchanged. Advertising hosts remain blocked. Bunnings session-reset ownership already includes its subdomains.

Live evidence on Adrian’s iPhone (iOS 27.2), using the real Bunnings WKWebView and existing persistent website data: after the fix the cart loaded with HTTP 200 and was initially empty. One **Trojan 8mm Heavy Duty Staples — 1000 Pack**, product **0217507**, was added once using the website's product button. Cart creation returned HTTP 201 and adding the entry HTTP 200. The product page reported quantity 1, and reloading the actual cart confirmed exactly that one pack. Its product-specific Remove action and confirmation restored “Your cart is empty!” (**0→1→0**). No checkout/payment/contact/account changes occurred; no lists, item statuses, store selections or logins were reset. Private evidence remains under `/tmp/opencode/bunnings-staples-after-add.json`, `/tmp/opencode/bunnings-staples-cart-one-item.json`, `/tmp/opencode/bunnings-cart-restored-empty.json` and corresponding PNG captures on Linux. Website add/remove verification used a scoped debug inspection channel; it does not claim a new trusted-tap automatic-detection or cart-Undo result.

Xcode's physical UI-test connection intermittently failed with authorization/trust/automation-mode/network errors, despite the user confirming device trust and UI Automation. Successful captures were checked against the real iPhone UDID, not simulator summaries. A temporary app-side inspection channel was used to finish diagnosis. All temporary inspection source, live UI-test driver code and Mac project compilation flags were then removed; no command channel remains in the normal app. The temporary GUI inspection job was also unloaded. The Mac project baseline and unrelated pre-existing work were preserved.

Final cleaned-source verification: **265 native checks**, synthetic-store proof and **40 DOM fixtures passed**. The unsigned Release simulator build passed (`/tmp/listrunner-bunnings-auth-release-final.log` on Mac). New regression checks cover the exact authentication host, rejection of HTTP/nonstandard ports/credentials/lookalikes/other subdomains, exclusion from automation origins, cross-retailer rejection and existing reset ownership. The final ordinary Debug app built and launched successfully on Adrian’s iPhone with no errors, PID **2368**; Mac run log `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261029-074021.txt`. A full UI-suite rerun/manual release sign-off is not claimed. Earlier Bunnings HTTP 503/no-mutation limitations below are historical and are superseded by this scoped live result.

## Hide the chooser when no stores are enabled

The user requested removing the store chooser from the neutral all-disabled screen. The header now omits the chooser entirely when visibility is empty; the dedicated Manage Stores action and Settings remain available. Re-enabling a store restores the chooser and the enabled-list selection behavior. No list/session persistence logic changed.

**2/2 focused iOS 26.5 UI tests passed** in `/tmp/listrunner-hide-empty-picker-results`: no-store chooser absence, management access, chooser restoration, Bunnings→all-disabled→Coles with relaunch, and saved Bunnings list restoration. The ordinary Debug iPhone build succeeded with no errors. Xcode's first launch attempt failed; explicit CoreDevice installation of the freshly built app and normal launch both succeeded on Adrian’s iPhone. No UI tests, fixture mode or retailer/cart interactions were used on the physical phone.

## Disabled active store always yields an enabled list

The user reported disabled Bunnings still showing its editable list and branding while other stores remained enabled. The earlier fix only handled the all-disabled transition. The list screen now reconciles selection on every appearance: retain an enabled current store; otherwise select the first enabled store alphabetically, or retain the neutral no-stores presentation when none are enabled. Reconciliation waits until returning from Manage Stores/Settings, and also repairs a legacy disabled selection on launch without requiring another toggle cycle. The obsolete all-disabled recovery flag is removed on preference initialization. Lists, item statuses, drafts and website/login data are not moved, deleted or reset; selecting a fallback does not open a website.

This user-approved rule supersedes the historical hidden-active-list behavior described below. It also applies if explicit regional confirmation disables the old active region; the confirmation copy now explains enabled-store selection on return. A current store that remains enabled is never switched just because another store is enabled, a country changes or alphabetical order changes.

**255 native checks**, **40 DOM fixtures**, synthetic-store proof and the final unsigned Release simulator build passed. Six focused iOS 26.5 UI scenarios passed across runs: disabling only active Bunnings selects Coles while preserving Added/Skipped Bunnings items and relaunch; hiding/re-enabling through Settings; all-disabled→Coles recovery; all-hidden Settings returning to Woolworths; Shopping country protecting an enabled Costco region; and confirmed Costco AU→US→AU list isolation with enabled-list fallback. Five passed in `/tmp/listrunner-disabled-active-store-results`; its regional test initially expected Coles but the alphabetically first enabled fixture store was Bunnings. Correcting that expected destination produced the passing regional round trip in `/tmp/listrunner-disabled-active-regional-results`.

The updated regional explanation initially caused the separate Dynamic Type audit to fail. Concise explanation text and vertically intrinsic text/button layout resolved it: the picker audit passed without exemptions in `/tmp/listrunner-disabled-active-final-audit-results` (hit regions, descriptions, contrast and Dynamic Type). The final Release build log is `/tmp/listrunner-disabled-active-release-final.log` on Mac. This is focused regression evidence, not a full-suite or manual accessibility release sign-off.

The final ordinary Debug app built, installed and launched successfully on Adrian’s iPhone with no build errors, PID 50236, 6.042 seconds. Mac run log: `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261027-210814.txt`. No physical-device UI tests, fixture mode or retailer/cart interactions were used. The user's previously saved disabled Bunnings selection now reconciles on launch without having to repeat the all-disabled flow.

## Neutral all-disabled screen and enabled-list recovery

User-reported regression: all stores disabled while Bunnings was active left its grocery rows/colours on screen; enabling only Coles still showed Bunnings as the active list. The no-store list now uses a native neutral empty state with Manage Stores, no grocery rows/input/Edit/Show Store and no retailer tint. After the all-disabled transition, selection is deferred until returning to the list: retain an enabled current store or select the first enabled store alphabetically. The pending recovery survives relaunch. Normal regional changes still do not automatically change the active list. No saved lists, drafts, website data or logins are moved or cleared.

**252 native checks passed**, **40 DOM fixtures passed**, synthetic-store proof passed, and the unsigned Release simulator build succeeded. New checks cover empty→Coles-only recovery, relaunch, one-time consumption, stable multiple-store fallback, retaining a re-enabled active store, regional brand switches and Reset Local Data clearing the recovery flag.

Five focused iOS 26.5 UI scenarios passed across runs: the exact Bunnings→all disabled→Coles-only sequence with relaunch and Bunnings list restoration; all-hidden management via the picker; all-hidden Settings followed by selecting Woolworths on return; ordinary hide/re-enable list preservation; and Costco AU→US→AU confirmation/list isolation. The two no-store/picker scenarios passed together in the final `/tmp/listrunner-neutral-stores-verified-results`; the other three passed in `/tmp/listrunner-neutral-stores-final-results` (whose Bunnings scenario initially failed on a test identifier). Earlier failures exposed ambiguous Manage Stores queries and ContentUnavailableView propagating a container identifier onto its action; dedicated action identifiers and removal of the container identifier resolved these. Actual simulator screenshot: `/tmp/opencode/listrunner-neutral-no-stores.png` on Linux; attached to the final passing Bunnings test on Mac. This is focused regression evidence, not a full-suite or new accessibility audit.

The final ordinary Debug device build installed and launched on Adrian’s iPhone (iOS 27.2), no build errors, app PID 49511, 11.481 seconds. Mac run log: `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261027-200737.txt`. An earlier launch attempt built successfully but failed while CoreDevice reported the phone unavailable; the final launch succeeded. No test/fixture launch mode, physical-device UI tests or retailer/cart interactions were used. Manual physical-device functional/accessibility release checks remain open.

## Physical iPhone build and launch — 27 October 2026

Xcode reported Adrian’s iPhone (iOS 27.2) eligible for the ListRunner scheme. The ordinary Debug Run action built, installed and launched successfully with no build errors (16.331 seconds; app PID 48989). The scheme's Launch action contains no fixture/test environment or launch arguments; no UI tests were run and no retailer/cart interactions were performed. Xcode run log: `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20261027-193431.txt` on Mac. This confirms physical-device build/install/launch only, not manual functional/accessibility or full release sign-off. Earlier physical-device limitations below describe their historical runs.

## Regional brand discovery — Costco first

Added browsing-only Costco US (`costcoUS`, US coverage, exact `www.costco.com`/`costco.com`, stable list/website-data IDs ending `000008`). Existing Costco Australia IDs, configuration/search support, lists and session are unchanged. All US automation is disabled in bundled data and native ceilings. No US website/login/cart interactions or compatibility checks were performed; the dormant schema-required search URL is not an enabled search integration.

Manage Stores now groups reviewed regional identities into a single brand switch, with a separate Website country button and explicit regional-choice confirmation. Costco has one row; Kmart remains Australian and separate. Shopping country regroups/suggests, but cannot switch an enabled or explicitly chosen region. A confirmed website choice replaces enabled regional visibility without changing activeStoreID or deleting/transferring regional data; the old active list stays visible behind the existing hidden-store shopping gate. Disabled brands remain disabled when choosing regions. Preferences persist across relaunch and reset only with Reset Local Data. Search matches regional names/countries and the index lists brands only once. The former names-only-row constraint is intentionally superseded for multi-region brands so the chosen website is visible.

**243 native checks passed**, including one-row grouping in AU/US/other countries, regional search, legacy AU visibility migration, country-change protection, explicit switching and disabled-state behavior, malformed preference rejection, distinct host/list/website IDs, independent AU/US diagnostics/cookie resets, and local reset boundaries. Synthetic-store proof and **40 DOM fixtures passed**; simulator app/test and unsigned Release simulator builds succeeded. Release resource audit confirmed all eight canonical regional configurations, disabled US automation and minimum iOS 17.0. The List Runner OpenPencil document is no longer open (the active document is Tasks App); no unrelated design document was modified. UI retains the established native search/inset groups/index and adds a native regional-choice sheet.

**6/6 focused iOS 26.5 UI checks passed** (`/tmp/listrunner-regional-costco-complete-results` on Mac): AU→US→AU confirmation/cancellation/list preservation, no automatic country-driven switch/persistence, existing Australian Costco capability Settings, native index/search, all-hidden Settings and Manage Stores accessibility. An initial test raced sheet dismissal and was corrected to wait for the sheet to disappear and Back to become hittable; the list-preservation round trip then passed. An older index assertion incorrectly assumed an off-screen W header must exist after adding larger regional rows; native index/menu navigation is tested instead. iOS 27 sometimes exposes native Back as Other rather than Button, so the test helper uses its stable identifier.

The new regional picker audit exposed capped Dynamic Type in the default section header and toolbar Done action. The heading is now an accessible scaling content row and Done is a scalable 44pt bottom action. The final picker accessibility audit (selected-region trait, contrast, Dynamic Type, descriptions and hit regions, with no exemptions on this screen) and AU→US→AU round trip passed **2/2** on iOS 26.5 (`/tmp/listrunner-regional-picker-final-audit-results`). Final simulator captures are attached there. A supplementary iOS 27.1 run suffered runner restarts/diagnostic collection hangs and was stopped; it is not cross-version sign-off for this revision. No full-suite or physical-device result is claimed. Manual accessibility, iOS 17 runtime and physical-device release gates remain open. No live website or retailer cart mutations occurred.

## Kmart Australia — browsing-only profile

Added Kmart with AU coverage, exact `www.kmart.com.au`/`kmart.com.au` browsing hosts, unique stable list/website-data IDs ending `000007`, blue/red branding and per-store diagnostics/reset scope. It starts disabled, sorted between Costco and Woolworths in the Australian section. Search, cart detection and retailer-cart Undo are all off in configuration and native policy; the schema-required query template remains dormant. No new detector strategy, automated website interactions, live-cart mutations or login/account changes were performed. Kmart live website/login compatibility is not verified by this addition.

Verification: **216 native checks passed**, including Kmart schema, exact-host rejection, country grouping, unique IDs and disabled-by-default migration; synthetic registration proof passed. **4/4 focused iOS 26.5 simulator tests passed** (`/tmp/listrunner-kmart-results` on Mac): Kmart disabled/enabled Settings and all capabilities Not included, reset confirmation, all-hidden Settings, Australian grouping, and management accessibility with the existing documented OS-index exception. The simulator app/test build succeeded. These are focused fixture results, not a fresh full-suite, physical-device or live-retailer certification.

## Browsing-only Walmart US profile — simulator verified

Added Walmart with US coverage and exact `www.walmart.com`/`walmart.com` browsing hosts, isolated stable list/website-data IDs ending `000006`, its own diagnostics/reset scope, and disabled-by-default visibility. All search/cart-detection/cart-Undo flags are false, cart strategy is null, and native ceilings reject attempts to enable those capabilities through JSON. This matches the browsing-only Tesco scope; no live Walmart site/login/cart compatibility or automation is claimed. Other Walmart markets and unreviewed authentication subdomains remain outside the allowlist. No website or cart mutation occurred for this addition.

Australia now shows the four AU stores first and nonlocal Tesco/Walmart in real T/W sections. Choosing United States places Walmart in the local section exactly once, leaving the other five stores available below. Changing country does not enable Walmart or switch the active list. Added the resource to both project layouts without overwriting unrelated Mac project/asset work.

Verification: **210 native checks passed**, covering the six-store registry, US/AU grouping, unique IDs, native capability ceilings, exact-host restrictions, hidden-by-default migration and Walmart-only WebKit cookie/reset isolation. The synthetic registration proof passed. **6/6 iOS 26.5 simulator tests passed** (`/tmp/listrunner-walmart-preview-results` on Mac): Walmart disabled/settings capability state, US local-country grouping/capture, Tesco UK grouping, Australian catalogue, native index/search and accessibility (with the previously documented OS-index exception only). These are focused fixture results, not a fresh full-suite or physical-device run. The captured United States screen uses actual bundled metadata, not synthetic service areas.

## Browsing-only Tesco UK preview — simulator verified

Configured Tesco with GB coverage, exact `www.tesco.com`/`tesco.com` browsing hosts, stable isolated list/website-data IDs ending `000005`, and disabled-by-default visibility. All automation flags (including search) are false and the cart strategy is null; native policy additionally prohibits enabling search, detection or cart Undo through JSON. The required search template is dormant, not a verified integration. No Tesco website was automated or live cart/account data accessed. Existing Australian store definitions and session identities are unchanged.

With Shopping country Australia, the real catalogue now has four Australian stores followed by the inset OTHER STORES separator, T group and Tesco. The native right-hand index has a T target. Choosing United Kingdom moves Tesco into the local section without enabling it or hiding the Australian stores. This is real bundled metadata, not the earlier synthetic service-area override. Current UI tests were updated to expect a genuine Other Stores section and retain only the documented native-index hit-region exception with its accessible menu alternative.

Verification: **201 native checks passed**, including Tesco capability ceilings, exact-host isolation, AU/GB grouping, hidden-by-default migration, and Tesco-only cookie/reset behavior. Synthetic registration proof passed. **4/4 iOS 26.5 simulator tests passed** (`/tmp/listrunner-tesco-preview-results` on Mac): Australian/other-store presentation and capture, UK country selection, production catalogue/search placement, and accessibility. Tesco Settings reports search/detection as Not included in both support/session sections and Cart Undo as Not included. The saved simulator screenshot shows the actual disabled Tesco row under OTHER STORES → T. No physical-device verification or full-suite/Release result is claimed for this preview.

## Costco Australia addition — search/manual support

Added Costco through the shared registry with `serviceArea.countryCodes: ["AU"]`, exact Australian hosts (`www.costco.com.au`, `costco.com.au`), encoded `/search?text={query}`, blue/red branding, and permanent isolated list/website-data UUIDs ending `000004`. Costco starts disabled, appears in Manage Stores for enabling, and preserves existing store visibility, lists and sessions. Its own Settings includes diagnostics/reset controls. No shopping progression, cross-store transfer, database schema, or retailer-specific detector strategy was added. Mac project changes are limited to adding `costco-v2.json` as a resource; the canonical Linux JSON and local project resource entry are also present. Unrelated Mac project/assets were preserved.

**Capability boundary:** search, browser access and manual Mark Added/Skip/local Undo only. Costco cart detection and retailer-cart Undo are disabled in bundled data and native ceilings; `cart` is null. The shared information notice now correctly says **Cart detection not included** for intentionally unsupported detection, rather than implying a live retailer failure. Existing supported-retailer failure warnings retain their wording. No Costco or other retailer cart was mutated; no login form was submitted, membership/account/payment data changed, or checkout attempted.

Read-only live browser evidence on 27 October 2026:
- Homepage and login form rendered on `www.costco.com.au`; bare Australian host redirected to the canonical www host. No external authentication host was verified or added.
- `https://www.costco.com.au/search?text=coffee` rendered 29 results; `https://www.costco.com.au/search?text=laundry%20detergent` rendered 28 results.
- `https://www.costco.com.au/search?text=milk` redirected to `/content/sameday`, which advertises DoorDash at a separate external host. That is Costco's observed query-specific behavior, not a promise that every grocery term returns online results. DoorDash and other Costco markets remain outside the integration/allowlist.
- Public product HTML exposes SKU, add-button product identity and an intended order quantity. Neither is confirmed cart-quantity evidence. Business Delivery product URLs also contain `_BD` suffixes; do not assume the existing numeric-only cart identity strategy is suitable. Cart automation remains unverified and disabled.

Verification: **192 native checks passed**, including all four configuration contracts, Costco host/query/capability ceilings, unique persistence IDs, hidden-by-default/enablement persistence, four-store country grouping, cross-store bridge rejection, Costco-only diagnostics clearing and nonpersistent WebKit cookie/reset isolation. **40 existing DOM/cart fixtures passed** and the synthetic-store proof passed. **8 focused iOS 26.5 simulator UI checks passed** (`/tmp/listrunner-costco-final-results`), covering new Costco flow/settings and existing Settings/country/index/accessibility behavior. After correcting unsupported-capability notice wording, **3/3 final simulator checks passed** (`/tmp/listrunner-costco-notice-final-results`), including Costco manual shopping/list isolation/relaunch, capability/reset Settings, and the existing supported-retailer detection-warning flow. The final simulator app/test build and unsigned **Release simulator build succeeded**, including the final notice wording. The bundle audit confirms all four canonical retailer definitions and minimum iOS **17.0**; Costco is search-only with no cart strategy. The earlier 35-test full suite predates Costco and is not a new full 37-test-suite result.

Live embedded iOS WKWebView search/login/cart behavior remains a release-validation follow-up, separately tracked in OpenChamber. The optional DeviceInteraction route could not proceed because its required device-interaction skill was unavailable; its session was closed/not active, with no interaction or installation through that route. Public browser checks and local simulator fixture tests are not live embedded WebKit certification. Physical-device and iOS 17 runtime checks remain unavailable. No cart capability may be enabled based only on these fixture results.

## Country-first Manage Stores revision — 27 October 2026

Replaced the Alphabetical/Nearby segmented control and foreground location/geocoder flow with a persisted Shopping country. Device region is a one-time suggestion only; an explicit choice is retained despite later region changes, and missing/invalid suggestions leave country unset. Both old sort values migrate without changing enabled stores, active store, lists or sessions. Removed the discovery-only location usage-description key and CoreLocation implementation; no IP service or other network lookup was added.

Manage Stores shows country matches first, then the subtle OTHER STORES separator and alphabetical nonmatches. Empty groups/index entries disappear; AU-only stores in Australia have no empty Other Stores section. Unknown-country discovery remains alphabetical; no-local-match discovery keeps other stores accessible. Invalid setups remain separately identified. The right-hand index is the actual native UITableView index on an inset-grouped table, including on the iOS 17 deployment target; it is not drawn artwork. A 44-point native toolbar menu provides accessible letter jumps without requiring dragging and honors Reduce Motion. Search is explicitly below the title (not the iOS 26/27 automatic bottom/collapsed placement), flattens matching results, and hides the index/menu. Shopping country is editable through a native searchable country list. Main Settings remains enabled-only; disabled stores remain manageable.

Final automated evidence: **177 native configuration/country-preference/grouping/migration/reset/security checks passed**, **415 parser checks passed** (including Mint canonicalization), **40 DOM fixtures passed**, and the trusted synthetic-store proof passed. The revised native suite replaces removed location-permission/fix/geocoder policy checks with country preference, migration and catalogue tests. The initial full iOS 26.5 simulator run passed 33/35; failures exposed header contrast and Apple's narrow native-index hit region. Explicit dynamic system-label colors corrected header/footer contrast. A subsequent focused iOS 26.5 rerun passed **4/4** including native-index/menu navigation, search placement, production catalogue, and both accessibility surfaces (`/tmp/listrunner-country-first-accessibility-final-results` on Mac). The final iOS 27.1 cross-version run passed **7/7**, covering country suggestion/selection/persistence, unset country, native index/menu, mixed sections, accessibility and search/clear (`/tmp/listrunner-country-first-271-final-results` on Mac). The final full iOS 26.5 simulator suite passed **35/35, zero failures** (`/tmp/listrunner-country-first-final-suite-results` on Mac), including the earlier first-item scrolling, shopping/list/session isolation, enabled-only Settings, Paprika fixtures and preload regressions. The final unsigned **Release simulator build succeeded**; its bundle declares minimum iOS **17.0**, contains no location permission keys, and retains the exact three approved store configurations. No physical-device build/test was attempted for this revision; the earlier physical-device evidence below is historical only.

**Known native-control limitation:** the unmodified UIKit section index reports an undersized hit region in Apple's accessibility audit. The mixed-country audit explicitly records/exempts only `.hitRegion` for the OS-owned element labelled `Section index`; no app-row, menu, contrast, Dynamic Type or description findings are suppressed. The separately tested 44-point native **Jump to store letter** menu provides equivalent non-drag navigation. This is not a claim that the native index itself meets a 44-point hit target or that manual VoiceOver/Switch Control review is complete. Mixed-country screenshots use a presentation-only test override (Bunnings displayed with NZ service area); real bundled Bunnings remains AU and no fourth retailer ships.

All builds/tests for this revision target simulators, not the unavailable physical iPhone. iOS 17 runtime coverage and manual VoiceOver/Switch Control/Dynamic Type/Reduce Motion/dark-mode review remain release gates, alongside physical verification when the phone reconnects and the previously blocked Bunnings live check. No live cart mutations were performed for this revision.

## Pasta dictionary expansion — verified

Expanded the bundled ingredient dictionary from five named pasta entries to 69 shapes/varieties, plus generic Pasta. Added alternate names/spellings and explicit compound names for filled pasta and egg tagliatelle, while preserving existing ingredient IDs. Rice vermicelli is separately identified to avoid mistaking it for Italian vermicelli. Common gluten-free/wholemeal qualifiers are covered; alternative ingredients remain ambiguous.

Verification: **408 parser checks passed** on Mac, comprising the original fixtures, 81 new pasta/related regression fixtures, the existing parser behavior checks and 266 name/alias identity/quantity checks. **174 native recovery checks passed** with the expanded dictionary, and the Xcode app build succeeded. The dictionary schema remains version 1; no parser algorithm, saved-list migration or retailer automation change was needed. The updated resource/tests are synchronized to the Mac; these are build/native-parser results, not a new physical-device UI-suite result.

## Enabled-only main Settings follow-up — simulator verified

At the user's request, the main Settings Stores section now lists enabled stores only and is omitted when every store is disabled. Manage Stores remains available and still lists all bundled stores for re-enabling; disabling does not delete their lists or website sessions. Two new UI tests cover disabling/re-enabling and the all-disabled Settings state. These and the existing list-preservation/reset-navigation checks passed on the iOS 26.5 simulator: **4/4, zero failures** (`/tmp/listrunner-enabled-settings-results` on Mac). The earlier 32/32 suite below predates this follow-up; this result is focused verification, not a new full-suite run or physical-device sign-off.

## First-item scrolling and Manage Stores follow-up — simulator verified

The reported first-item regression was reproduced on the physical iPhone: all three stronger checks failed against the previous app code, with the first cell partly behind Show Store. The patch replaces the fixed 100 ms delay with native geometry/row-appearance requests that account for safe-area insets, cancels superseded requests, and avoids animating the empty-state replacement. It also corrects the text field's later Return-key scroll adjustment. Manual scrolling and typing the next entry retire the old positioning request.

The tests now require the complete cell above Show Store/the keyboard and cover Add Items, Return, and a long first item. All three passed on iOS 27.1 (3/3, zero failures; `/tmp/listrunner-first-item-271-results` on Mac). The final full iOS 26.5 simulator suite also passed **32/32, zero failures**, including the three first-item paths, existing typing/focus/shopping flows, and Manage Stores navigation/accessibility (`/tmp/listrunner-first-item-final-suite-results` on Mac). Temporary debug instrumentation has been removed. The final device/test build succeeded through Xcode. The iPhone became unavailable before the final physical verification, so installation/verification on it remains pending. Scoped app/test sources are synchronized between Linux and Mac.

At the user's request, the chooser action, Settings link and screen title are now **Manage Stores**. Corresponding tests and current documentation use the new wording. The successful framework evidence below predates this follow-up and must not be presented as final verification of these changes.

## Framework evidence before the follow-up

Last verified: 27 October 2026. Implementation and automated validation are complete; the release/manual gates below remain open. Passing simulated checks is not certification of every live retailer flow.

## Baseline and scope

- The Mac Xcode project is the build/signing baseline. Scoped source/test changes are synchronized with `/home/claude-svc/listrunner`; unrelated Mac assets, project edits, duplicated resource folders and user work were not removed.
- Production catalogue: Coles, Woolworths and Bunnings only, all with `serviceArea.countryCodes: ["AU"]`. Nearby is country matching, not distance, delivery, stock or postcode coverage.
- Stable list/website-store identities, Coles browsing-only login exceptions, existing Bunnings selectors/identity and teal/gold styling remain unchanged. Woolworths and Bunnings cart Undo remain disabled by a native ceiling as well as configuration.
- Existing stores migrate as visible; unseen stores start hidden. All-hidden preferences persist. Hiding preserves list/session data, cancels the hidden store's interaction and cannot silently select another store. Confirmed local-data recovery reset clears visibility/order preferences.

## Automated evidence

| Check | Result | Environment/evidence |
| --- | --- | --- |
| Full iPhone UI suite | 30 passed, 0 failed | Adrian's iPhone, iOS 27.2; Xcode full run at 00:35 on 27 October |
| Final focused accessibility/preload rerun | 2 passed, 0 failed | Same physical iPhone; Xcode run at 01:24 after final source updates |
| Full simulator UI suite | 30 passed, 0 failed | iPhone 17e, iOS 26.5; `/tmp/listrunner-framework-265-results-final` on Mac |
| Native recovery/configuration/location-policy/migration/reset checks | 174 passed | `bash packages/ios/tests/run-recovery-tests.sh`, macOS |
| Ingredient parser | 61 passed | `bash packages/ios/tests/run-parser-tests.sh`, macOS |
| Trusted synthetic registration proof | Passed | `bash packages/ios/tests/run-store-proof.sh`, macOS; no network |
| DOM/cart fixtures | 40 passed | `node --test packages/ios/tests/coles-add-detection.test.mjs`, Linux |
| Unsigned Release device build | Succeeded | `xcodebuild`, generic iOS device; built bundle declares minimum iOS 17.0 |
| Release resource audit | Passed | All three bundled `*-v2.json` definitions semantically equal canonical Linux source JSON |
| Whitespace/error check | Passed | `git diff --check` |

The physical/simulator accessibility audit checks contrast, Dynamic Type, element descriptions and hit regions without suppressing findings. It found undersized letter-index hit regions and insufficient supporting-text contrast; both were fixed. Index scrolling also respects Reduce Motion.

The standalone runner now includes the current ingredient-parser compile dependencies and uses an injected dictionary for Paprika planning. It checks all three list migrations and real deletion boundaries in a **nonpersistent** WebKit cookie store. It never resets a real retailer session or accesses real Reminders.

Location checks exercise permission-decision policy, services disabled, approximate/invalid/stale/future fixes, unambiguous/missing/conflicting country results, UI success/failure and rejection of a cancelled request's late result. Native permission/fix/geocoder waits are each bounded to 15 seconds; native cancellation resumes pending continuations and ends location/geocoder work. These checks do not substitute for manually exercising Apple's permission prompt on each supported OS.

## Resolved regressions

- The hidden preload in UI-test mode contacted a retailer even though visible navigation used a local fixture. Hidden and visible test navigation now both use local HTML; the ordinary suite contains no live-cart tests.
- Parser canonicalization and duplicate underlying-list/overlay accessibility matches caused incorrect assertions. Queries now target the correct elements and current parser behavior.
- Empty text fields expose a placeholder value on iOS 26 but nil on iOS 27. Empty-input assertions accept either platform representation while rejecting retained typed text.
- Bullet-only input could create an empty grocery row. Parsing now rejects it, with dedicated regression coverage.
- Duplicate JSON keys (including nested and escaped keys) are rejected before decoding. JSON cannot enable Woolworths/Bunnings cart reversal.
- Hidden-store relaunch and grocery-row entry points are tested: the saved list stays visible, Show Store stays disabled, and tapping a row cannot bypass the hidden-store gate.

## Explicitly authorized live verification

These were deliberately run on the physical iPhone from a **disposable project copy**, separate from the normal UI suite. The copy used a temporary local list and existing persistent retailer sessions. Only the named, user-approved products and quantity deltas were authorized; no checkout, purchase, delivery-slot selection or account/payment changes were made.

- **Coles full-cream milk, 1 L:** explicit zero baseline; trusted add changed quantity **0 → 1**; ListRunner detected the add; native ListRunner Undo restored **1 → 0**. No manual cleanup was needed. Evidence: physical `LiveVerificationTests/testVerifyColesAddUndo()` run at 01:13.
- **Woolworths So Good Barista Oat Long Life Milk, 1 L:** explicit Add-to-cart/zero baseline; trusted add changed quantity **0 → 1**; ListRunner detected the add; the retailer's own Decrease quantity control restored **1 → 0**. No retailer Undo capability was enabled. Evidence: physical `LiveVerificationTests/testVerifyWoolworthsAddAndManualRemoval()` run at 01:23.
- **Bunnings Esky 26 L Chilla Hard Cooler:** search and then the approved direct product page reached load recovery. The direct main-frame response was **HTTP 503** from the trusted Bunnings host. **No cart mutation occurred.** Retries stopped; no allowlist/security changes or retailer-block bypass were attempted. Live detection remains unverified in this run; existing bundled support was preserved, not newly certified.

All performed live cart changes were verified back at their starting quantities. The disposable project workspace was closed and the normal project was rebuilt/reinstalled and launched on the iPhone at 01:25. The disposable driver and read-only instrumentation are not present in either primary checkout or the shipping app source.

## Remaining release/manual gates

- [ ] Repeat Bunnings product-specific add/detection/manual removal when the retailer no longer returns HTTP 503. Confirm the current product/quantity delta before the next mutation.
- [ ] Run on iOS 17 hardware or a compatible iOS 17 simulator installation. This Mac has only iOS 26.5 and 27.1 simulator runtimes; minimum-target compilation is not runtime coverage.
- [ ] Manually review VoiceOver focus/announcements, Switch Control, smaller/larger text, Reduce Motion, keyboard and foreground-location permission states. Automated audits passed on physical iOS 27.2 and simulator iOS 26.5 but are not exhaustive assistive-technology sign-off.
- [ ] Compare the final native UI against the approved OpenPencil document. The design MCP reported that OpenPencil was not connected; it was not automatically started or retried.

No additional production retailer, remote configuration, arbitrary-site support, automatic product selection or checkout functionality was added. Changes remain uncommitted.
## Regional ingredient search names — 29 October 2026

Implementation branch: `feature/regional-ingredient-naming`. Search-only AU/NZ/GB/US mappings, default-on Settings toggle and context-generation invalidation are implemented. No saved-data migration, visible-name localisation, retailer capability change or cart operation is part of this feature.

Linux: **7 bundled-resource verifier regressions**, **51 DOM/cart-safety fixtures**, JSON parsing and `git diff --check` passed. Swift is not installed on this Linux host.

Mac checks at `5be885bc0fa57ed2349bdfc77e3b1b69ac7b219b` passed **195 regional search checks** and all **439 existing parser checks**. Native compilation caught an initialisation-order error, fixed in `e87c26497239680dbb412ab68e7c9c99614f98b5`. That revision passed **300 native checks**, the synthetic-store proof, unsigned simulator `build-for-testing`, and byte-for-byte verification of all **11 bundled JSON resources**. The first focused iOS 26.5 run passed **3/3 tests** (regional browser checks, toggle persistence/existing-item preservation, existing preload promotion). The local SSH wait timed out after 120 seconds, but the remote Xcode test continued; a kernel process-exit notification collected its successful completed result, not an inferred pass from partial output.

The normal Mac checkout was busy with another session's full UI suite and was not switched or edited. Validation uses the clean detached worktree `/Users/adrianzafir/Projects/listrunner-regional-validation`, with exact pushed commits and external build output. Dedicated iOS 26.5 simulator: `3B83848B-A269-41CA-A66B-A0278272061C` (ListRunner Regional Validation). Debug test build: `~/Library/Developer/Xcode/DerivedData/ListRunnerRegionalValidation`; first result: `~/Library/Developer/Xcode/DerivedData/listrunner-regional-tests-e87c264.xcresult`. No source was copied outside Git.

Final expanded run: **5/5 simulator tests passed** at `316a5a1767496a91486ec9b918699719e3d31ee9`, covering browser deferred/preload/recovery checks, cached-browser Country changes, toggle changes before and after relaunch, existing preload promotion and the existing main Settings hierarchy. The browser fixture includes **15 internal assertions**, including the browsing-only retailer search ceiling. Result bundle: `~/Library/Developer/Xcode/DerivedData/listrunner-regional-tests-316a5a1.xcresult`; log: `~/Library/Developer/Xcode/DerivedData/listrunner-regional-tests-316a5a1.log`. The preceding expanded run at `f86c569b8fec32ae4e4cbc7f2047e5d3cfb076d0` had two test interaction failures: returning from Settings restored keyboard focus, and XCTest computed no hit point for Show Store, so the store never opened. The test-only fix dismisses the keyboard using the existing summary gesture and asserts the button is hittable. No production preference change was required.

The production code at `f86c569b8fec32ae4e4cbc7f2047e5d3cfb076d0` also passed an unsigned **Release simulator build**, with all **11 JSON resources** byte-identical to canonical sources. Release output/log: `~/Library/Developer/Xcode/DerivedData/ListRunnerRegionalRelease` and `~/Library/Developer/Xcode/DerivedData/listrunner-regional-release-f86c569.log`. Subsequent changes are test interactions, runner executable permission and documentation only; no production Swift, resource or project changes followed those verified builds. This is a focused feature regression, not a new full-suite or live-retailer certification.

OpenPencil `List Runner` → `Settings & reset` was inspected: its older consolidated frame still shows store rows, so the newer native hierarchy in `plan.md` takes precedence. The implementation uses native Form/Toggle styling; no mockup fidelity or manual VoiceOver/Dynamic Type/light-dark sign-off is claimed. iOS 17 runtime and physical-device validation are not claimed.

Fixtures must stay offline, using isolated UI-test preferences and nonpersistent WebKit. No new live retailer or physical-device install is required/claimed.
# Waitrose signed-in native cart proof — 2026-11-02

On simulator build `0ca7f554ce2b72296483c35ca0acaf2412b1e544`, a user-operated
trusted Add for Essential British Free Range Semi-Skimmed Milk 4 Pints (£1.75)
changed product quantity 0→1, emitted a successful native cart-detection diagnostic,
and persisted the isolated Waitrose `Milk` item as `Added`. Read-only inspection
was restricted to the exact public product DOM and the named test namespace.
User's minus tap restored Add/no quantity field and trolley 0 items/£0.00.
Waitrose production detection enabled after this proof; retailer-cart Undo remains
disabled. Full evidence and scope are in `docs/retailer-expansion-2026-11-01.md`.
# JB Hi-Fi human-assisted native cart proof — 2026-11-02

Simulator build `c66d3ddbed06e5b676ec936ed0517b25543e3941` detected the user's
Add for Belkin Hi Speed USB Cable (1.8 Metres). The user saw automatic Added;
native diagnostics independently recorded cartDetection/succeeded (sequence 3),
and the isolated SwiftData row persisted `usb cable / Added / jbHiFi` before any
manual local reset. User confirmed the retailer cart empty afterward and restored
the local item to Pending. Final cart cleanup is user-confirmed, not a fresh
independent open-cart inspection. Production detection enabled, retailer Undo off.
The optional attach dialog is content-gated by the retailer; this profile uses the
exact product button's stable, unclipped Added animation instead. See the ledger
for public-source findings, runtime flags and negative clipping fixtures.
# Bunnings NZ native cart proof — 2026-11-02

Build `27bf24106a594502eaa5459f8f861becc0ae61d5` fixes the observed blocked NZ
silent-auth frame with an exact browsing-only exception. User verified cart loaded
empty, then one trusted Add for Craftright 8oz Steel Claw Hammer (`5660292`) changed
the scoped quantity 0→1 and automatically updated ListRunner. Native success
diagnostic sequence 3 and isolated SwiftData `craftright hammer / Added / bunningsNZ`
independently confirm it. User decreased once; read-only inspection of `/cart`
verified visible `Your cart is empty!`. Production detection enabled after proof;
retailer-cart Undo remains disabled. Prior namespace timeout was pre-fix, not a pass.
Auth fix passed 1,513 native checks, 244 DOM tests, synthetic proof, Debug build and
34 bundled-resource comparisons. See expansion ledger for details and scope.
# Officeworks website-cart blocker — 2026-11-02

At `d1b3c01`, corrected exact icon-prefixed Add label passes 249 DOM tests,
1,512 native checks, synthetic proof, Debug build and all 34 resource comparisons.
Live trusted Add still does not establish an observed cart: POST carts 204 then
GET carts/111-fake 404, generic confirmation with no product row/title, native item
Pending. Guest location 3000 is retained; initial session/header GETs return 200.
Public frontend code uses `111-fake` when cartId is unreadable and still dispatches
success after the empty follow-up result. Native metadata found no matching cartId
cookie; no cookie values were inspected/exported. Underlying cookie/session-creation
failure remains unexplained. Production detection and retailer Undo stay off.
Temporary status-only observer is removed; no request bodies/headers were captured.
User reported empty cart before the final diagnostic Add; final recheck pending.
See expansion ledger for precise evidence and boundaries, not a passing claim.
# Officeworks persistent-session native proof — 2026-11-02

Build `b704794e160a927fe8e1419390c88b70b1b061b3` passed a human-operated Add for
Keji Ballpoint Pens 1mm Assorted 10 Pack, guest location 3000, in an isolated named
persistent store (verified exact test ID, never a normal retailer store). Visible
receipt contained the exact title; user saw automatic Added. Native diagnostic
sequence 4 and isolated SwiftData `Pens / Added` independently confirm detection.
User removed the one pack and confirmed empty; final inspection was search/no
receipt, so cleanup is user-confirmed rather than an independent empty-page check.
Status-only trace recorded carts POST204, fallback GET200 and real-cart GET200;
no bodies, headers, IDs or cookie values exported. Temporary observer removed.
Production detection enabled, retailer Undo off; normal persistent-storage policy
unchanged. This run passed where ephemeral runs failed, not proof of the precise
underlying cause. Earlier Officeworks blocker below is historical test evidence.
# Hide unverified-search destinations — 2 November 2026

App code at `4f3907d480bb843f1da4cb6006ba5d968e5974fa` hides Tesco, Amazon US,
Costco US, New World, PAK’nSAVE, Boots and CVS from management/discovery search,
the active chooser, move destinations and regional choices. Costco AU remains
available. All 32 registrations, stable IDs, resources and implementations remain;
the available catalogue has 25 destinations in 24 brands. Raw enabled flags and
regional preferences are not rewritten just because a destination becomes hidden.
Hidden active destinations resolve to another available enabled list or the existing
returning-user no-stores state, never silently to a different regional website.

Final validation: **1,666 native checks**, **249 DOM/page-behaviour tests**, expansion
contracts and synthetic registration proof passed. Both Debug and unsigned Release
simulator builds passed; all **34 bundled JSON resources** byte-match the canonical
files in each configuration. No retailer resource changed in this task.

Six focused offline UI scenarios passed across runs, **not one clean final 6/6 run**:
- `ListRunner-Availability-d8ee622.xcresult`: 4/5 passed (no-stores recovery,
  Costco AU list/relaunch, seven hidden-name searches, and country changes). Move
  check failed before its menu because setup had selected another fixture store.
- `ListRunner-Availability-8d9f8e2.xcresult`: 2/3 passed (Costco AU/relaunch and real
  local item transfer). Move-menu filtering assertions passed, but its dismissal
  assumed a Cancel button absent from iOS 27's adaptive native menu.
- `ListRunner-Availability-4f3907d.xcresult`: corrected read-only move-menu test
  **1/1 passed**. The two follow-ups changed tests only, not application behaviour.
The preliminary `e175842` run had three passes plus a three-minute timeout in the
older no-stores regression; that regression passed in the bounded follow-up run.
Logs/result bundles are under Mac `~/Library/Logs/ListRunner-Availability-*`.

Verification used a dedicated iPhone 17/iOS 27 simulator
`35E7A8A4-76B2-4C8F-B161-F7F82E78A3CB`, not the paused retailer-test simulator.
Representative preliminary screenshots (management and AU-only Costco settings)
were inspected without new layout issues; this is not broad accessibility sign-off.
The paused Petbarn process PID 8801 remained running on its original simulator.
No retailer pages/cart mutations, website resets, physical-phone installs or normal
store-data changes occurred during this availability task. The original twenty-store
verification goal remains paused at eight certified detectors.
## IKEA Australia — implementation and verification (4 November 2026)

The user selected full exact-product cart verification and authorized controlled
isolated guest-cart tests, with no purchase, credentials, account/payment or
fulfilment-setting changes. New `ikeaAU` IDs end `000033`; existing identities,
lists, preferences and sessions are unchanged. Registration uses the shared store
UI and exact Australian `/au/en/` HTTPS destinations only. Schema 5's separately
bundled snapshot engine holds an attributed Add tap until a fresh rendered cart
baseline exists, revalidates the same control and requested amount, replays once,
and verifies the exact article delta while preserving all unrelated quantities.
Undo uses fresh full-cart equality, single-use context-bound provenance, verified
single decrements and a final fresh persisted-cart check. A preflight failure
explicitly reports that Add was not sent; there is no blind Add retry. The native
Undo timeout/progress accommodates the new cart document reads without changing
other retailers' four-second boundary.

Initial evidence:

* At `6e85e7637a91a6e63a285612569263ef059af468`, **1,747 standalone native checks
  passed**. A dedicated iPhone 17 / iOS 27.2 simulator
  (`9BEEF1A5-4AAD-4EB4-9C40-27B221A817FC`, ListRunner IKEA AU) built successfully
  and passed **2/2** focused tests: read-only matching spoon search with visible
  query reflection, and IKEA discovery/settings/reset-cancel. Evidence on Mac:
  `/tmp/listrunner-ikea-au-search.log` and `/tmp/listrunner-ikea-au-search-results`.
* Separate Linux browser experiments passed grid and product-page DRAGON Spoon
  (`40515525`, $4.99/4 pack) 0→1→0 cycles with the new engine. The page's intended
  quantity and family-only toast were not used as actual cart quantities. Both
  engine Undo calls returned true after a fresh empty-cart check. Independent
  final navigation displayed `Your shopping bag is empty`; the isolated browser
  session was then closed. This is browser evidence, not native certification.
* At `bf22e9bde3137017dbcebb900aa7d03006b79a89`, both native cart tests failed
  **before retailer interaction** in shared first-store setup: XCTest queried
  hittability on a virtualized Coles row and reported an invalid activation point.
  No IKEA Add/Undo was attempted. Evidence: Mac
  `/tmp/listrunner-ikea-au-cart.log` and `/tmp/listrunner-ikea-au-cart-results`.
  The subsequent test guard checks finite, nonzero, fully visible row bounds
  before querying hittability. Live native cart certification remains pending;
  production detection/Undo remain disabled until it passes.

All Mac source handoffs use exact pushed Git commits in a separate detached task
worktree at `/Users/adrianzafir/Projects/listrunner-ikea-au`. The normal Mac checkout
and its untracked Xcode Cloud settings are preserved. No physical iPhone was used.

Final implementation check at `51d324702255aea25a1d3adba32e5d32aebc399f`:
**1,755 standalone native checks passed**, workspace-backed simulator build,
install and launch succeeded, and all **35 JSON resources plus the bundled
automation JavaScript byte-match** committed source. Linux checks passed **342
DOM/cart tests, 24 Python checks and 90 core tests plus core type-checking**.
The interceptor installs at document start before retailer event handlers; each
Undo decrement now also requires a fresh persisted-cart read. Confirmation
provenance retains quantity maps rather than old iframe DOM documents, and
cancelling an in-progress snapshot Undo shows the existing warning.

Live grid and detail sessions on the dedicated simulator reached the exact
DRAGON Spoon (`40515525`) controls, but IKEA's `You are in control of cookies used`
dialog covered shopping controls. No consent choice or bypass was attempted.
**No Add was sent; native detection and retailer Undo were not exercised or
certified.** No test-product removal was needed; an independently displayed empty
bag was not verified while blocked. Interaction sessions ended. Further live
testing requires an authorized isolated-session cookie-consent choice. Production
detection/Undo remain off. Evidence: Mac
`/tmp/listrunner-ikea-au-51d3247-recovery.log` and
`/tmp/listrunner-ikea-au-51d3247-device-evidence/`; Linux screenshots
`/tmp/opencode/ikea-final-grid-consent.png` and
`/tmp/opencode/ikea-final-detail-consent.png`.

The intermediate `f6fedb9c4d33a7211d5b1c8ba89ae38208a22b8c` XCTest run also
failed before retailer interaction: both cases expected Back while Manage Stores
search exposed Close. These are test-navigation failures, not engine evidence.
Logs/results remain on Mac at `/tmp/listrunner-ikea-au-f6fedb9-cart.log` and
`/tmp/listrunner-ikea-au-f6fedb9-cart-results`; exported attachments are under
`/tmp/listrunner-ikea-au-f6fedb9-attachments/`. Manual device verification on the
final source revision avoided that test-navigation path but encountered the
separate consent blocker described above.

### IKEA essential-only consent and completed native cart proof

The user subsequently authorized **essential cookies only**, and both manual
native cycles passed at `51d324702255aea25a1d3adba32e5d32aebc399f` on the dedicated
iPhone 17/iOS 27.2 simulator. Each cycle used fresh isolated guest storage, verified
an explicit empty shopping bag first, tapped the exact DRAGON Spoon (`40515525`)
Add control once, observed automatic native Pending→Added without Mark Added,
observed native Undo progress finish without a warning, then independently opened
a fresh bag page displaying `Your shopping bag is empty`. No manual removal was
needed. Both console captures record `Quantity increase confirmed; notifying
overlay` and `Store cart Undo confirmed`. This supersedes the consent blocker
above and authorizes production JSON/native detection and Undo ceilings; the
engine itself is unchanged from the verified source.

In each guest session, Cookies settings exposed Performance, Functional and
Targeting cookie switches. All three were set off and verified at `0`, Strictly
necessary cookies remained Always active, and `Confirm my choices` was pressed.
Neither `Ok` nor `Allow all` was used. No credentials, account, fulfilment,
postcode/store, checkout or purchase changes occurred.

Capture times (Mac local, 4 November 2026, UTC+11; not precise detector latency):

* Grid: empty baseline 11:10:40; Add 11:11:13; automatic Added 11:11:20; Undo
  progress 11:11:27; completion without warning 11:11:34; fresh empty bag 11:11:55.
* Detail: empty baseline 11:14:47; Add 11:15:32; automatic Added 11:15:39; Undo
  progress 11:15:46; completion without warning 11:15:53; fresh empty bag 11:16:33.

Screenshots, hierarchies and console logs: Mac
`/tmp/listrunner-ikea-au-51d3247-essential-evidence/` and Linux
`/tmp/opencode/listrunner-ikea-au-51d3247-essential-evidence/`. Stems for grid
Added/Undo/empty are `IKEA Essential Grid-11_11_20_082`, `-11_11_27_307` and
`-11_11_55_408`; detail equivalents are `IKEA Essential Detail-11_15_39_886`,
`-11_15_46_977` and `-11_16_33_838`. Each has `-screenshot.png`, `-hierarchy.txt`
and `-logs.txt` files. All interaction sessions ended. The installed resources
were reverified against canonical sources after the cycles.

IKEA's Shopping bag accessibility hitPoint activated its hamburger menu instead;
after observing that mismatch, the actual bag icon was targeted visually. The
main page's bag badge also remained stale after Undo. Neither was used as empty
cart evidence: the independent freshly loaded bag body was authoritative. These
manual passes do not relabel the earlier XCTest navigation-helper failures as
passing tests. Composite/multi-article bundles, account sign-in and all catalogue
layouts are not certified; unsupported article identities retain manual controls.

### Production-ceiling rerun and early-page handshake correction

At `a21b37868894fe4c1a6f67d8585873f07ad21793`, **1,756 native checks passed**,
the simulator build succeeded and all 35 JSON files plus JavaScript matched
canonical source. The essential-only XCTest setup now enters IKEA directly from
welcome, avoiding the former Back/Close mismatch. The live detail test passed
automatic detection, retailer Undo and independent empty-bag checks. The faster
grid test failed automatic detection, then removed the exact single test article
and independently confirmed an empty bag. It was not an Undo pass. Evidence:
Mac `/tmp/listrunner-ikea-au-enabled.log` and
`/tmp/listrunner-ikea-au-enabled-results`.

Review identified a document-start context-handshake race: the early capture
listener could request the previous native document generation before didCommit,
then wait for full window load to be corrected. Native now delivers the committed
context in didCommit for the snapshot engine only, and JavaScript requests its
ready handshake at DOMContentLoaded instead of document start. The interception
listener still installs before retailer handlers, and existing passive engines
are unchanged. A regression covers deferred DOM readiness. The corrected fast
grid path requires a fresh live rerun; earlier manual results do not substitute
for that check.

**Final automated native rerun passed at
`34baad57c350020fddca963f72b5882ed8b90d34`.** Both live XCTest cases passed
(2/2, no failures or skips) on the dedicated iPhone 17/iOS 27.2 simulator with
production search/detection/Undo enabled. Each case observed automatic native
addition, native Undo progress completing without a warning, restored local
Pending state, and an independently loaded empty shopping-bag page. Neither used
Mark Added or manual removal. The grid log explicitly records
`detected=true, localRestored=true` and
`undoVerifiedEmpty=true, cleanupVerified=true`. The earlier failed fast-grid
result is superseded by this successful rerun, not erased.

The app built successfully and all **35 JSON files plus the JavaScript engine
byte-match** canonical source. Current Linux DOM/cart coverage is **343 passing
tests**; Python checks remain 24 passing and core coverage remains 90 passing
plus type-checking. The production-ceiling native suite passed 1,756 checks.
Final native evidence: Mac `/tmp/listrunner-ikea-au-context.log` and
`/tmp/listrunner-ikea-au-context-results`. The two-case execution took about 140
seconds in total; this is test runtime, not measured detector latency. All test
carts ended independently empty. No physical device, credentials, account,
fulfilment, checkout or purchase was involved. This is branch validation, not a
merge, archive upload or TestFlight release.
## Configurable results auto-scroll — 4 November 2026

Branch `feat/auto-scroll-to-grid`; initial implementation revision
`dd73c1e3feaeacbc7f47681b1b0a6de67e2427bc` (not merged or installed on the phone).

* Added optional native `search.resultsSelector`/`resultsTopOffset`, strict native
  decoding/validation and onboarding preflight; existing schema 2–5 definitions
  remain valid. No legacy extension/core schema change or capability promotion.
* Added default-on global Settings → Shopping preference with persistent opt-out,
  live pending-scroll cancellation and Reset Local Data semantics. Existing
  Settings styling and the saved design-audit reference were consulted; the
  OpenPencil desktop connection was unavailable, so no live design comparison is
  claimed.
* Scrolling is isolated-world, one-shot and bounded to the exact requested item
  search URL/document. Waits for stable visible nonempty target geometry; cancels
  for early input/scroll, supersession, navigation, hidden/background state,
  dismissal, verification/recovery and setting-off. Preloads arm only on visible
  promotion. Retailer controls, carts, cookies and list statuses are untouched.
* Initial targets reuse existing reviewed first-result card selectors for Coles,
  Woolworths and IKEA AU. The 120px offset is conservative and still needs live
  retailer/viewport review; other stores remain no-ops until configured. Exact
  URL matching deliberately skips retailer redirects/query rewrites rather than
  risking unrelated grids. No new live retailer result-scroll certification.
* Linux: **386/386 JS tests** (`node --test packages/ios/tests/*.test.mjs`), including
  **39 new results-scroll script fixtures**; **43 Python checks** across the five
  `test-*.py` scripts, including optional-field validation; `git diff --check`
  passed. Standard unittest discovery cannot import these hyphenated script
  names; they were run individually, not counted as a successful zero-test run.
* Added native configuration/preference/reset regression checks and three
  isolated simulator UI tests for setting persistence, actual first-result
  positioning and disabled behaviour. Native execution/build results are recorded
  below when available. Fixtures use local HTML and nonpersistent retailer data;
  no real cart/account/network action is part of these checks.
* Mac Debug simulator **build-for-testing succeeded** at `dd73c1e`; actual built
  bundle audit passed: **35 JSON + 1 JavaScript resource** byte-match canonical
  files. Native checks initially exposed a test-order issue: reconstructing the
  preferences object repopulated migration keys before the existing clear-keys
  assertions. Test-only fix `8a00d6b1c25f9ae6a0bc856ef4ec66bcc74a5808` moves
  reconstruction after those assertions; no app code changed.
* Native rerun at `8a00d6b` passed **1,777 checks**. Synthetic store-registration
  proof, **195 regional-search checks** and **449 parser checks** also passed.
  The simulator UI rerun at `344017a` passed
  `testResultsScrollPositionsFirstResultNearTop` (actual WKWebView positioning).
  Opt-out exceeded its 120s allowance during the shared setup/flow; persistence
  failed because the whole-row switch tap left its value at 1. These are not
  counted as passing. Recording/touch-event inspection confirmed the persistence
  tap landed at `(201,435)` on the row label, not the visible switch; opt-out had
  not reached Settings. Evidence is preserved on both machines under
  `/tmp/opencode/auto-scroll-failure-evidence/`. Test-only correction
  `6fdab31528c0ef10576383c5eb8f7d8a7e452280` uses the existing right-edge switch
  tap pattern, waits for the off value and sets up only Coles. No application
  toggle code was changed to fix those test interactions.
* Final app revision `09cb382af53430e0553ecfe264bba5ba28aceb57` also passed a
  **Release simulator build** and a second **35 JSON + 1 JavaScript** canonical
  bundle audit. This revision retains cancellation during deferred search pacing
  and arms scrolling for an explicit retry of the original search after recovery.
  Release log: `~/Library/Logs/ListRunner-auto-scroll-release.log`; output:
  `~/Library/Developer/Xcode/DerivedData/ListRunner-auto-scroll-release`.
* Native checks rerun at `6fdab31` again passed **1,777/1,777**; log
  `~/Library/Logs/ListRunner-auto-scroll-native-final.log`.
* Focused UI run at `6fdab31` passed **positioning** (37.752s) and **setting
  persistence** (56.944s). Opt-out reached a confirmed off switch at 109.5s and
  opened the fixture, but the 120s whole-test allowance expired at page entry;
  this is not a passing opt-out result. Its isolated rerun uses a 240s allowance
  with no application/test-source changes. Full focused-run evidence:
  `~/Library/Logs/ListRunner-auto-scroll-ui-final.log` and
  `~/Library/Developer/Xcode/DerivedData/ListRunner-auto-scroll-ui-final.xcresult`.
* Isolated opt-out rerun at the same `6fdab31` revision **passed (85.321s)**:
  `~/Library/Logs/ListRunner-auto-scroll-ui-optout.log` and
  `~/Library/Developer/Xcode/DerivedData/ListRunner-auto-scroll-ui-optout.xcresult`.
  Thus all three focused UI scenarios passed at the final code/test revision
  **across two runs**, not one clean three-test run. No broader UI regression,
  live retailer offset review, iOS 17 runtime or exhaustive accessibility/design
  sign-off is implied. Existing app source is unchanged from Release-tested
  `09cb382`; later commits change test setup/hit targeting and documentation only.
  The dedicated simulator was shut down after testing, not deleted; evidence and
  the isolated Mac worktree are retained. No phone install, merge, distribution,
  retailer mutation, account change or shared-simulator cleanup was performed.
* Mac handoff uses a clean detached worktree at
  `/Users/adrianzafir/Projects/listrunner-worktrees/auto-scroll-results`, fetched
  through Git at the exact implementation SHA. Original checkout remains on
  `main` with its pre-existing untracked Xcode Cloud directory preserved. Build
  output lives in `~/Library/Developer/Xcode/DerivedData/ListRunner-auto-scroll`;
  logs in `~/Library/Logs/ListRunner-auto-scroll-{native,build}.log`. Dedicated
  simulator: `35E7458A-05FB-452F-8117-A62AAF4C20CE` (ListRunner Results Scroll,
  iOS 27.2). No shared simulator or physical phone is used.
## Background results positioning during cooldown — 4 November 2026

Supersedes the original hidden-preload restriction below, at the user's request.
Once a preload reaches a readable, non-verification search document, the results
engine may position its rendered grid in the background after three stable
100ms intervals. The exact requested URL, store allowlist, current preference,
naming generation and active browsing/recovery guards still apply. This never
scrolls the current visible browser or changes retailer/list data.

Promotion replaces a pending/completed/timed-out background attempt with a fresh
bounded visible geometry check. It issues no second scroll if already within
one CSS pixel, but can repair layout/scroll restoration or finish delayed work.
Input listeners remain installed between phases: touch, pointer, wheel, keyboard,
navigation or native cancellation prevents later correction. Preference-off
cancels both browsers; dismissal/backgrounding discards the unused preload.
Background timers/layout remain best effort, not an iOS scheduling guarantee.

Validation on Linux:

* **400 JavaScript tests passed**, including **53 exact bundled results-script
  fixtures** covering hidden positioning, unchanged promotion, changed layout,
  retailer scroll restoration, unfinished/timed-out background fallback, delayed
  document visibility, inter-phase input and stale URL/cancellation safeguards.
* **19 Python onboarding checks** and `git diff --check` passed.
* Added isolated, offline iOS UI test
  `StoreSelectionTests/testPreloadResultsScrollPositionsBeforePromotion`.
  Its debug-only read-only geometry observer requires positive scroll and the
  configured header gap before promotion, then confirms the promoted position.
  No live retailer access or cart actions are used.
* Initially Mac validation was blocked by SSH `No route to host`. After the user
  restored connectivity, the clean isolated Mac checkout was fast-forwarded to
  `ed351342b2413e91e6c049241bb98a4e63cacdab`.
* **1,777 native recovery/configuration checks passed** on that revision; log:
  `~/Library/Logs/ListRunner-preload-scroll-native-ed35134.log`.
* **Release simulator build passed**, including byte-match verification of all
  **35 JSON + 1 JavaScript** bundled resources. Log:
  `~/Library/Logs/ListRunner-preload-scroll-release-ed35134.log`; DerivedData:
  `~/Library/Developer/Xcode/DerivedData/ListRunner-preload-scroll-release`.
* At the user's request, **Debug device build, signing, in-place installation and
  launch succeeded** for `ed35134` on the physical iPhone 17e
  (`00008150-001402660A9BC01C`, bundle `com.adrianzafir.listrunner`). The device
  app also passed the **35 JSON + 1 JavaScript** byte-match audit. The first build
  failed signing with `errSecInternalComponent`; a scoped existing keychain
  unlock fixed the retry, and the keychain was relocked before installation.
  No signing credentials/access settings changed, no data reset or test launch
  arguments/environment were used, and no retailer/account/cart actions occurred.
  Log: `~/Library/Logs/ListRunner-preload-scroll-iphone-ed35134-retry.log`.
  Installation/launch does not constitute observed physical-phone scrolling.
* The focused iOS 27.2 simulator run completed **3/4**, not a clean pass.
  Existing preload promotion, visible positioning and opt-out passed. The new
  background-positioning scenario failed, then failed in an isolated rerun.
  Exported app stdout shows pacing deferred the preload by 0.5s; the hidden
  WebKit browser did not report navigation readiness before cooldown expiry.
  Production correctly discarded the unavailable preload and used normal search.
  Logs: `~/Library/Logs/ListRunner-preload-scroll-ed35134.log` and
  `ListRunner-preload-scroll-isolated-1d3b0e4.log`; exported diagnostic directory:
  `~/Library/Logs/ListRunner-preload-scroll-isolated-diagnostics`.
* The ready-preload fixture now permits a bounded 15s preparation wait before
  counting down, only when both isolated preload/results fixture flags are set.
  It still requires measured background positioning before promotion. Production
  keeps its three-second cooldown and best-effort fallback unchanged. This test
  does not certify cold hidden-WebKit startup within three seconds.
* The corrected ready-preload UI scenario **passed 1/1** at
  `cd9165d7ee51bc5638051197ece5ba1f6d51f775` in 63.665s. Its native observer
  measured the configured header gap and positive scroll before promotion, then
  confirmed the promoted position. Log:
  `~/Library/Logs/ListRunner-preload-scroll-cd9165d.log`; result:
  `~/Library/Developer/Xcode/DerivedData/ListRunner-preload-scroll-cd9165d.xcresult`.
  All four focused scenarios passed across runs, **not one clean final 4/4**.
  The later change is debug-fixture-only; the phone retains production code from
  `ed35134`, and no new physical-phone behavior was observed in this rerun.
* Merged to `main` as `6b975cb8e057e2129776bf364f9899ea98be0ce5` and pushed.
  The merged tree exactly matches reviewed feature tip `5d1927d`.
  Linux **400 JavaScript + 19 onboarding checks** passed again. The canonical
  Mac `main` checkout built **Release successfully** on the merged revision,
  with all **35 JSON + 1 JavaScript** resources matching; log:
  `~/Library/Logs/ListRunner-preload-scroll-main-6b975cb.log`.
  Feature worktrees on Linux/Mac and the local/remote feature branch were
  removed without force. Session/main Linux checkout is now
  `/home/claude-svc/listrunner-main`; the separate
  `/home/claude-svc/listrunner` marketing branch and its untracked `.openchamber/`
  remain untouched. Mac main remains `/Users/adrianzafir/Projects/listrunner`;
  its pre-existing untracked Xcode Cloud configuration is preserved. Simulator
  state, DerivedData and test evidence were not deleted. Phone installation
  remains the previously verified production-equivalent `ed35134` build.

When the Mac is available, use the normal Git handoff into the isolated
`/Users/adrianzafir/Projects/listrunner-worktrees/auto-scroll-results` checkout,
verify clean status and the exact pushed revision, then run the new preload UI
test plus `testPreloadSearchIsPromotedAfterCooldown`,
`testResultsScrollPositionsFirstResultNearTop` and
`testResultsScrollOptOutLeavesPageAtTop`. Use simulator DerivedData/results
outside the checkout. Do not reset the physical app or run fixtures on it.

## Woolworths results-grid repair — 4 November 2026

After the user requested a phone build, revision
`c60399e32e0cc1cfa15b115bf0ad45d968f6371e` was signed and installed in place on the
connected iPhone 17e. The initial signing attempt failed with
`errSecInternalComponent`; a user-supplied private secret unlocked the existing
login keychain for the retry, and the keychain was relocked afterward. No signing
identity/access settings were changed. Build retry succeeded and the actual
35 JSON + 1 JavaScript bundle audit passed. `devicectl` confirmed installation;
launch was refused because the phone was locked. No data reset or fixture launch
was performed on the phone. Evidence: Mac
`~/Library/Logs/ListRunner-auto-scroll-iphone-build-retry.log`.

The user subsequently reported no auto-scroll at Woolworths. An isolated mobile
viewport Chrome inspection found **zero `wc-product-tile` elements** and a real,
visible `[data-testid="search-results-product-scrollable-content"]` grid (top
608px, height 8,371px at the sampled 390×844 viewport). Requested/final search
URLs matched, the document was the scroll root, and no initialization scroll
events were observed in that browser run. These observations diagnose a stale
selector in Chrome, not yet a native-iOS live proof.

Fix revision `3b4439e988281c373315eaa1b0b480bec7e44e48` updates only Woolworths'
**search-scroll target**, not its cart detection/identity/capability definitions.
It also fixes an independent overbroad cancellation condition: a DOM `scroll`
event alone is not user intent. Touch, pointer, wheel, keyboard and native pan
cancellation remain; page-generated scroll restoration no longer suppresses the
pending assistance. Enum-only isolated-world state supports the explicit
read-only live probe; no product/query/account content is reported.

* Linux: **387 JavaScript fixtures passed**, including **40 results-scroll
  fixtures**, with the current Woolworths grid and page-generated scrolling
  regressions; **19 onboarding checks** and `git diff --check` passed.
* Mac: **1,777 native configuration/recovery checks passed** at `3b4439e`.
  `~/Library/Logs/ListRunner-woolworths-scroll-native.log`.
* Added `testLiveWoolworthsResultsScroll`, explicitly opted in through
  `TEST_RUNNER_LISTRUNNER_LIVE_RESULTS_SCROLL=1`. It uses a temporary list and
  nonpersistent WebKit store in the dedicated simulator, performs the real app
  item search, and checks that the actual bundled engine reports a scroll and
  places the grid within 3 CSS pixels of the configured header allowance. It
  never taps retailer controls or changes consent/location/account/cart state.
* **Live embedded-iOS proof passed** at `3b4439e`: the actual ListRunner browser
  searched Woolworths in the dedicated iOS 27.2 simulator, found exactly one
  configured grid, and reported
  `PASS: state=scrolled matches=1 top=120 y=488 urlMatches=true`. Test duration:
  114.046s. This proves actual automatic scrolling by the bundled engine, not a
  manually issued scroll or a desktop-only selector check. No retailer controls,
  account, location, consent, cart or checkout actions occurred. Evidence:
  `~/Library/Logs/ListRunner-woolworths-scroll-live.log` and
  `~/Library/Developer/Xcode/DerivedData/ListRunner-woolworths-scroll-live.xcresult`.
  Simulator was already shut down afterward; it and all evidence are preserved.
  Other retailers, other Woolworths layouts/queries and device accessibility
  remain outside this focused proof.
* **Corrected phone build signed and installed in place** at `3b4439e` on Adrian's
  iPhone 17e (`00008150-001402660A9BC01C`). The device bundle passed the
  **35 JSON + 1 JavaScript** byte-match audit. Build log:
  `~/Library/Logs/ListRunner-woolworths-scroll-iphone-build.log`; DerivedData:
  `~/Library/Developer/Xcode/DerivedData/ListRunner-auto-scroll-iphone`.
  The signing keychain was unlocked only for the build and relocked afterward;
  no credential/access settings changed. Installation succeeded; automatic
  launch was again refused by iOS because the phone was locked. The user can
  unlock/open ListRunner and trigger the next item search or original-search
  reload. Existing app data was not reset, no test environment/arguments were
  supplied to the phone launch, and no physical-phone retailer/cart interaction
  was performed. Live auto-scroll proof above is simulator evidence, not a
  claim of observed scrolling on the physical phone.
