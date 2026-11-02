# TestFlight revision 2 — 1.0 (2)

## Release record

- Status: **signed archive verified; awaiting TestFlight upload**.
- App identifier: `com.adrianzafir.listrunner`.
- Version/build: **1.0 (2)**.
- Comparison baseline: `testflight/revision-1` at `b01ff2835732d0940f1c8024b1cf74b1cfe7a832`.
- Baseline is an end-of-1-November Melbourne-time estimate, not a confirmed upload
  revision. The Mac also contains a 1.0 (1) archive created on 1 November at 10:41
  local time, but it contains no recorded Git revision. Its presence does not prove
  which source was uploaded, so the user-approved approximate baseline is retained.
- Prepared source commit: `26654a7a2923f1f593b3bfb3f34242d46350d46a`.
- User-created archive: Mac `~/Library/Developer/Xcode/Archives/2026-11-02/ListRunner 2-11-2026, 2.59 pm.xcarchive`
  (Finder/actual filename uses a narrow space before `pm`). Created at
  **2026-11-02 03:59:14 UTC / 14:59:14 Melbourne time**.
- Checkout was observed clean at `9cf688f4baf1a9b810e85095ec244fedce1323d6`
  before and after the user-operated archive. This is the source revision to
  associate with this archive; the archive does not embed an independent Git SHA.
- Completed archive independently verified: app identifier `com.adrianzafir.listrunner`,
  version **1.0**, build **2**, strict/deep code-signature verification passed,
  and all **34** JSON resources byte-match canonical sources.
- Archive executable SHA-256 (before App Store export/re-signing):
  `29709ec2354c03a9d9000ae513d85566f96e7d59c8e18c4d0dc6a8fbfbce8b01`.
- Local verification manifest: Mac `~/Library/Logs/ListRunner-TestFlight-1.0-2-archive-manifest.json`.
- Archive attempt: Mac `~/Library/Developer/Xcode/Archives/2026-11-02/ListRunner-1.0-2-26654a7.xcarchive`.
  This attempt failed at CodeSign with `errSecInternalComponent`; do not treat it
  as a completed signed archive. Compilation completed, and the staged app's
  plist independently reports `com.adrianzafir.listrunner`, version 1.0, build 2.
- Archive log: Mac `~/Library/Logs/ListRunner-TestFlight-1.0-2-26654a7-archive.log`.
- All 34 staged application JSON resources match canonical sources. Native 1,666,
  release-metadata 2 and expansion-contract 3 checks passed during preparation.
- The later user-created archive supersedes that failed CLI signing attempt.
- Next: upload the verified 1.0 (2) archive to App Store Connect for TestFlight.
  Record the actual uploaded build number/result (including any export-time version
  management), then create the successful-upload tag at the archived source revision.
  No upload tag for revision 2 has been created.

## What to Test

Automatic cart-add detection is now enabled for Chemist Warehouse, Priceline,
Officeworks, JB Hi-Fi, Supercheap Auto, Bunnings New Zealand, Ocado and Waitrose.
ListRunner should mark an item Added after a supported, confirmed retailer Add,
without requiring Mark Added.

This build also fixes Bunnings New Zealand cart-session navigation and Waitrose
sign-in navigation, and improves product-specific confirmation handling.

Stores without verified search are temporarily hidden: Tesco, Amazon US, Costco
US, New World, PAK’nSAVE, Boots and CVS. Their saved data is retained; Costco
Australia remains available.

Please test:
- Searching and adding products at your enabled stores, including the automatic
  Added status at the supported stores listed above.
- Switching stores and relaunching without losing lists, quantities or statuses.
- Store management and search: unavailable destinations should not be offered.
- Existing saved selections: a hidden destination should fall back to another
  enabled available store, or show No stores enabled—not silently switch regions.

Known limitations:
- The twenty-store expansion is incomplete. Other search-supported stores may
  still require manual Mark Added; do not assume cart detection from search support.
- Retailer-cart Undo remains disabled for all twenty expansion destinations.
- Sign-in, location, stock and security checks are controlled by each retailer.
- Broader physical-device, accessibility and iOS 17 runtime checks remain open.

## Developer validation

Application behaviour before the version-only preparation passed 1,666 native
checks, 249 DOM/page-behaviour tests, synthetic registration proof, Debug/Release
simulator builds and 34-resource audits. Six focused offline UI scenarios passed
across runs, not one clean final 6/6 run; see `packages/ios/VALIDATION.md`.

The archive must independently confirm version 1.0, build 2, the unchanged app
identifier, Release configuration, signing and canonical bundled resources.
