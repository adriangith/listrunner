# TestFlight revision 2 — 1.0 (2)

## Release record

- Status: **preparing; not yet uploaded**.
- App identifier: `com.adrianzafir.listrunner`.
- Version/build: **1.0 (2)**.
- Comparison baseline: `testflight/revision-1` at `b01ff2835732d0940f1c8024b1cf74b1cfe7a832`.
- Baseline is an end-of-1-November Melbourne-time estimate, not a confirmed upload
  revision. The Mac also contains a 1.0 (1) archive created on 1 November at 10:41
  local time, but it contains no recorded Git revision. Its presence does not prove
  which source was uploaded, so the user-approved approximate baseline is retained.
- Exact source commit, archive path and upload result: to be recorded after the
  archive/upload steps. Do not create the successful-upload tag before verification.

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
