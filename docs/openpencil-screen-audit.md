# OpenPencil screen audit

Source of truth: `plan.md`. Design: **List Runner → Shopping Flow**.

## Status

The requested reference-screen coverage and in-Pencil cleanup pass are complete: 67 screens, 14 pages including Components, and 38 transition/reference arrows. Saved-file checks confirm the examples, text overrides and component links after FIG parsing. Visual checks were representative rather than an exhaustive pixel-by-pixel review of every board. This is **not runtime, on-device accessibility, or exact Apple-vector fidelity sign-off**. Canvas arrows describe transitions, not executable prototype links. No real Coles actions are performed.

## Canvas organization

To reduce active-canvas rendering pressure, the 67 screens are distributed across 13 screen pages plus Components. Shopping Flow is retained as the main journey/overlay overview, reduced from 32 to 14 screens, with a START HERE directory. Editing/import, recovery, fallback and settings states were moved—not duplicated—to their own pages with their original arrows. The added coverage remains on focused pages with three to six screens each. Component masters remain on Components and board identities were preserved. Smaller pages reduce active-page drawing work, but do not guarantee that OpenPencil releases all other page data; long editing/export sessions still hit browser memory limits.

Component masters are grouped on Components. The two Apple keyboard references are now shared masters with four linked instances, and the capability explanation sheet has six linked instances. The final S3 FIG readback resolved all 496 instances to main components, with no orphans. This is not a claim that every native settings/list/modal fragment is componentized; the Name validation variant intentionally uses a standalone layout to avoid reconstructed-instance geometry problems.

- **A — Shopping:** empty list → review → store → timed confirmation → final-item confirmation → all items handled → completed list.
- **B — Overlay alternatives:** collapsed, untimed confirmation, collapsed final confirmation, final confirmation on the revealed list.
- **C — List/import:** inline edit, name validation, importing, import access failure, pending-list clear confirmation.
- **D — Recovery:** local-data failure and confirmed reset; initial store-load failure; independent search/cart/both capability failures; cart-undo and local-save warnings.
- **E — Settings:** settings, Coles-reset confirmation, resetting, reset failure, diagnostics feedback.

There are 67 phone artboards: Shopping Flow 14; Shopping state variants 4; Capability explanations 6; Paprika import outcomes 5; Input, keyboards & validation 5; Appearance & Dynamic Type 5; Web recovery 3; Resume, lifecycle & deletion 4; Final confirmation & adaptive input 3; List management 5; Local data & store recovery 3; Warnings & manual fallback 5; Settings & reset 5. The original 19 arrows were retained across their relevant pages and 19 transition/reference arrows were added. Appearance and adaptive-layout pages show variants, not invented sequential transitions. Numbers retain their identities; page names, headings and arrows define reading order.

## Reuse and corrections

- Added actual component masters and instances for the Coles results surface, selected pending/added/skipped cards, neighbor cards, navigation states, expanded overlay states, and native banners. Existing Apple-library instances remain in use.
- Store screens now share the reference surface and overlay geometry instead of independently recreated controls.
- All 15 store-sheet containers, including the neutral initial-load recovery background, use 32-point top corners and clip their web content to that outline. The app should use native system sheet corners rather than hard-code the reference radius. Card overlap at the lower panel boundary is unchanged.
- The main example progresses through Milk (1/4), Bread (2/4), Eggs (3/4), and BBQ sauce (4/4), instead of keeping Milk selected throughout. Added neighbors are green, no next card is shown beyond the final item, and product search examples/illustrations follow the selected item. The list examples start at 4 Pending and finish at 4 Added.
- Selected pending cards use a blue gradient (`#185CCB` → `#429BFF`); Added cards retain their green gradient even while selected. The pending-card master and its action-text color are shared across normal shopping and fallback screens.
- Selected cards are 160 × 224; neighbors are 145 × 203, bottom-aligned. A horizontal viewport hides off-phone neighbors while allowing the cards to straddle the panel boundary.
- Timed and untimed confirmations use Undo / Next, not Back / Skip.
- Final confirmation uses Undo / Finish and hides Pause. Neighbor cards are visually disabled.
- Added-card actions consistently use `Pause`, not `More Time` or `Add more`. Screen 32 demonstrates the paused confirmation with `Paused · Next when ready` centered between Undo and Next, linked from the timed confirmation. Pause stops automatic progression, preserves the existing Undo record, and keeps subsequent adds untimed until an explicit exit such as Next. Revisited Added items retain the same Pause label without inventing an Undo record; the detailed state and test requirements are in `plan.md`. This is design/spec work, not an implementation of the state engine or coded prototype.
- Complete-store state shows All items handled and Continue to checkout when ready.
- Empty-list Show Store is removed and Settings remains accessible.
- Editing is inline, with separate amount and free-text unit fields rather than a unit dropdown.
- Initial load recovery uses a neutral web-view background.
- Persistent save warnings do not have a dismiss button. Warning layouts retain grocery entry in a scrollable content area.
- Screens 19 and 20 now clip their scrollable content above the fixed Show Store button, eliminating the grocery-row/button overlap. Lower rows and list footer are below the initial viewport, not deleted; implementation must provide actual scrolling and bottom content padding.
- Import, save, and cart-undo notices share compact neutral surfaces, semibold headings, secondary explanatory text, and 44-point dismiss targets where applicable. These are compositions of native controls, not an assertion that iOS provides a standard error-banner API. Screens 07 and 12 share a smaller system-alert reference with Retry and Return to List/Cancel; implementation should use the OS alert rather than custom-draw this reference.
- Screen 11 replaces the browsing hint with a centered `Search unavailable` warning and removes the separate warning strip. Screens 35–42 cover confirmation-priority warnings and scoped explanation sheets. Layer annotations specify 44-point warning targets; actual SF Symbol/native presentation behavior remains implementation work.
- Screens 27 and 28 use the same centered navigation-warning placement for `Cart detection unavailable` and `Automation unavailable`, wrapping to two lines at 12 points in a 44-point-high target. Their separate warning strips are hidden; scope-specific manual Mark Added guidance (plus manual search for full fallback) is specified for tapping the warning.
- The complete-list artboard retains entry/import controls so the user can add more items.

## Completed coverage and handoff

### Coverage added and saved

The user approved completing all remaining coverage. The following boards were added, saved, and confirmed present after reload:

- **Shopping state variants — 33–36:** selected Skipped; revisited Added with Back/Next and no invented Undo; countdown and paused confirmation with capability warnings.
- **Capability explanations — 37–42:** Search, Cart detection and Automation unavailable explanations, each in item and session scope. Native-sheet references include Done; session explanations retain reset guidance.
- **Paprika import outcomes — 43–47:** first-use Reminders permission reference; missing Paprika list; multiple exact-name lists; no new items; transactional import-save failure. Longer notice bodies were shortened to fit without changing their meaning.
- **Input, keyboards & validation — 48–52:** keyboard-visible entry/editing, invalid quantity, blank amount/unit clearing, long names and quantities.
- **Appearance & Dynamic Type — 53–57:** dark list/native store chrome; accessibility-sized list and proportional 200 × 280 store card; small Dynamic Type with normal tap targets.
- **Web recovery — 58–60:** navigation failure over a retained page; terminated web process over a neutral background; successful retry.
- **Resume, lifecycle & deletion — 61–64:** same-day resume, later-day list routing with preserved statuses, foreground return, immediate ListRunner-only deletion and selection fallback.
- **Final confirmation & adaptive input — 65–67:** final-confirmation keyboard entry, long selected item/quantity, numeric entry. Number-pad artwork is adapted with a decimal separator to represent decimalPad.

Screen 05 was refined to keep the final Undo/Finish banner, entry/import controls and groceries in scrollable content above fixed Show Store. Screen 29 now uses a readable compact final-item context and an Expand overlay control; expanding restores Undo/Finish, without adding a second overlay handle. First-item Added variants were corrected to show Bread as the next neighbor. Later-day list routing preserves Milk's Added status (3 Pending / 1 Added).

The user opened **Apple iOS & iPadOS 27**. Its lower-case and number-pad components were read from Keyboards and transferred as editable SVG artwork to List Runner's Components page, avoiding dangling cross-document variables. These became shared local masters and replace the hand-drawn keyboards in 48/49/65/67. The Apple document itself was not modified. Unsupported private-use Shift/Delete/Return/Microphone glyphs were replaced by positioned vector fallbacks, and the obsolete hand-drawn keyboard was removed. Saved-file checks verify symbol positions in all four instances. These are local components derived from Apple artwork, not live links to the Apple document.

Behavior/accessibility notes cover scope, focus/announcements, native presentation, cancellation/late callbacks, persistence boundaries, background/final-confirmation survival, deletion, and input validation. Static boards and notes do not establish runtime behavior or accessibility compliance.

### Closeout

- Screen 24 uses a stable standalone validation variant: blank focused Name, inline error immediately below it, shifted amount/unit fields, centered Cancel/Save, and immediate Delete Item below. The previous partial nested-instance edit was replaced, not left pending; this layout was visually checked and its saved geometry is verified.
- Corrected Back labels and no-Undo behavior in 34/63; Skipped/Next in 33; priority captions in 35/36; scope labels beneath 37–42; Paprika outcome wording; blank/invalid amounts; long item content; and all expected summary totals.
- Found that generic `update_node(text=...)` did not reliably persist text overrides inside instances. Reapplied changes with `set_text` and font changes with `set_font`; parsed the actual saved FIG to verify persistence rather than relying on the live view.
- Added 19 arrows, including page-entry reference chips where a sequential screen-to-screen transition would be misleading. No phone artboards overlap on any page in the saved geometry check.
- Reviewed representative native notices, validation, keyboard entry/editing, long content, appearance, large/small text, scoped explanations, permission, and completion references. Subsequent saved-file checks cover labels, counts, component links, symbol placement and validation geometry. Browser memory limits prevented an exhaustive final pixel-by-pixel export review of all 67 boards; that limitation is not runtime sign-off.
- Remaining work is implementation/device validation: native dialog and keyboard behavior, real scrolling and safe-area insets, VoiceOver/Switch Control focus and announcements, full Dynamic Type, Reduce Motion, real Coles failure/retry behavior, and platform-native contrast. Recovered non-keyboard vector approximations are documented reference artwork, not a guarantee of exact Apple paths.

## Verification

### Final saved-file verification — 2026-10-21

Read back S3 document `3758a235-313a-4893-80aa-f8e986d0c2cc` and parsed its FIG outside the browser. All checks passed: 67 unique screen numbers, 14 pages, 38 arrows, 496 linked instances / zero orphans, exact example totals, persisted warning/action/quantity text, four keyboard instances with correctly positioned vector symbols, six capability-sheet instances, small-text grocery titles at 15 points, stable Name validation geometry, and no overlapping phone boards.

- SHA-256: `55a1d02709460fde458f61f292e1519b6c733f1bfa5532eb421482ee24f866ca` (617,432 bytes).
- Readback backup in CT 129: `/var/lib/openpencil-recovery/List-Runner-review-1792535686321.fig`.
- Verification script used in CT 129: `/tmp/verify-listrunner-design.mjs` (also in this session's `/tmp/opencode/`); it reads S3 and writes a timestamped backup, never uploads/replaces the source.
- Older recovery details below are historical; they are not the latest screen/component counts.

### Recovery repair — 2026-10-20

- The original unsaved tab disappeared while the variable-link repair was in progress. The inspection snapshot was preserved before that repair; the recovered and repaired files are separate artifacts.
- `List-Runner-repaired-final-2026-10-20.fig` is the latest repaired copy. It restores 31 artboards, 197 linked instances, 31 component masters, and reconstructed auto-layout settings. Component synchronization and FIG export/import round-trips were checked before opening it.
- The repaired copy has been opened in OpenPencil. Representative list, store, inline-edit, final-confirmation, completion, and Eggs-added states were visually inspected. Reconstructed icon paths are not guaranteed to match the original Apple vectors exactly; a full visual review is still needed.
- SF Pro is now supplied to the browser renderer by a private hosted-font loader in CT 129. Regular, Medium, Semibold and Bold report available with no substitutions. Merely installing the font through Linux fontconfig did not make it available to the browser app.
- Current backups: `/home/claude-svc/openpencil-recovery/2026-10-20/` in CT 107 and `/var/lib/openpencil-recovery/` in CT 129. The user should Save As a local working copy of the repaired design.
- The repaired file is also saved in the S3 workspace as **List Runner — repaired**, in bucket `openpencil-documents`, document ID `3758a235-313a-4893-80aa-f8e986d0c2cc`. Its FIG and metadata objects were uploaded separately from existing designs, read back, hash-checked, and verified to contain all 31 artboards. Open this entry from the storage workspace to bind subsequent saves to S3 rather than the filesystem recovery URL.

- Visually exported the revised store, final-item, complete-store, completed-list, inline-edit, and local-data recovery compositions.
- OpenPencil top-level frame/component overlap analysis reported no major artboard overlaps after arrangement.
- Historical checks do not establish every nested layout, connector route or runtime interaction. The 2026-10-21 saved-file verification and closeout above describe the current scope and remaining device-validation limitations.
