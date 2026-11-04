# Store onboarding workflow — validation

## Completion criteria

The routine onboarding path must consume one reviewed store definition, generate
registration without hand-editing repeated switches/project entries, reuse a native
search inspector, keep logs out of conversational context, and preserve explicit
capability approval. This does not promise that an arbitrary retailer will work or
that novel cart detection/Undo can be implemented without engineering.

## Implemented workflow

`packages/ios/tools/store-onboarding.py` provides:

- `scaffold`: disabled configuration plus compact evidence checklist.
- `register`: reviewable patch for native identity/trust/branding metadata, permanent
  list/session IDs, bundled JSON and Xcode resource wiring. No existing app files are
  modified by generation. Existing ceilings and identities remain untouched.
- `strategies`: current configured strategy/identity/confirmation examples derived
  from bundled definitions, with configured and enabled examples distinguished.
- `probe-plan`: the same two-query inspection plan for any reviewed destination,
  before or after registration. No per-retailer XCTest source edits are necessary.
- `probe`: one selected iOS WebKit test, isolated data, strict main-document hosts,
  all subframes denied, no cart mutations, explicit live-search opt-in, separate
  network-blocked synthetic mode, cached external build output and structured evidence.
- `check`: concise portable/native offline gate, with detailed external logs.

The short operating guide is `docs/adding-a-store.md`, linked from `AGENTS.md`.
Security review, permanent-ID review (cross-branch collision review for explicit serials), regional grouping,
selectors, live evidence and independent capability promotion remain intentional
review points rather than implicit permissions granted by a generator. By default,
new UUIDs are generated once into the reviewed source patch rather than allocated
from a shared counter or created on each app launch. Existing IDs are never changed.

## Measured mechanical trial

Linux synthetic trial artifacts:
`/tmp/opencode/store-onboarding-benchmark-3rtlbu4l/metrics.json`.

- Draft generation: **0.0590 seconds**.
- Registration patch generation: **0.0678 seconds**.
- Generated patch: **3 app files, 41 added lines, zero removed lines**, 6,307 bytes.
- The registration integration test applies the generated diff to a temporary
  checkout, checks the new resource graph, verifies that removing only the new
  store's native lines reproduces the original native source exactly, and rejects
  duplicate identities, unsafe metadata, changed source layouts and enabled drafts.
- On macOS the same test compiles the expanded native registry, decodes the generated
  resource, checks trusted metadata and unique IDs, and confirms it stays unavailable
  and disabled by default. The synthetic store is never shipped or committed.

These are measured generator timings, not total retailer research/verification time
or a measured percentage reduction in AI token usage. No prior human/AI onboarding
time baseline was captured.

The native offline suite at code revision
`77c1671` produced **67,760 log characters**; the normal wrapper output was **212
characters**. That is **99.69% less log text presented to the agent**, not a claim of
99.69% lower total task tokens. Full logs and machine-readable results are preserved.

## Native evidence already obtained

Dedicated Mac checkout: `/Users/adrianzafir/Projects/listrunner-store-onboarding`.
Dedicated simulator: `FC246B28-A10E-4D3D-BD4D-968DE3A9ADE3`, iPhone 17 / iOS 27.2.
The main and IKEA checkouts/simulators are not used by these checks.

- At `77c1671`, the complete native offline suite passed, including the generated
  registry compilation proof, 449 parser checks, 195 regional-search checks and
  1,701 native recovery/reset/diagnostic checks. Full log/report:
  `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/store-onboarding-0jxelh8u/`.
- At `a0bfdc3`, the expanded native offline suite passed:
  `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/store-onboarding-h6a_tin6/`.
- Network-blocked synthetic two-query inspection passed in actual iOS WebKit at
  `77c1671` and `a0bfdc3`. The latter evidence:
  `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/store-onboarding-native-jo3mgaqe/`.
- The first live JB Hi-Fi trial at `a0bfdc3` found 36/36 matching products for each
  of toaster/kettle, with reflected queries, no visible blockers and no truncation.
  The test correctly remained **failed**, because the probe incorrectly counted
  denied third-party subframes as rejected main-document navigation. No capabilities
  were changed. Evidence:
  `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/store-onboarding-native-h74lzd7g/`.
  Revision `f0a6071` fixes that probe classification without allowing those subframes
  or broadening any trusted host.

## End-to-end native completion

At app/test-code revision **`f0a6071772c5c86eb92b54e36c08e255a69abb46`**:

- The complete native offline suite passed:
  `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/store-onboarding-w3ddxf95/`.
- The generic network-blocked two-query fixture test passed, with exported native
  observations and exact test-count validation:
  `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/store-onboarding-native-scf1qrdi/`.
- The same generic test passed against **real JB Hi-Fi toaster/kettle searches** in
  isolated iOS WebKit sessions, with no retailer-specific XCTest source changes:
  `/var/folders/0h/0scshybs33ndyxvndzclnhj80000gn/T/store-onboarding-native-vvqjblq1/`.
  Both queries returned matching, reflected, stable and sufficiently distinct
  product sets. Structured observations are embedded in `report.json` and retained
  in `inspection.xcresult`. No capabilities or cart state were changed.

The final UUID-default generator change is additionally checked by the generated
native registration compilation test; its final-suite evidence is recorded below.

## Scope limits

Offline fixtures do not certify a retailer. Successful live differential search does
not certify sign-in, delivery/stock, every catalogue type, Add detection or Undo.
No live cart mutation, checkout, account change or verification bypass is part of
this tooling validation. New engine strategies remain separate scoped work.
