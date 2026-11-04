# Adding a store

This is the short operating guide for a new retailer destination. Start with the
smallest useful capability; registration is not evidence that automation works.

## Capability ladder

1. **Registration and manual shopping** — trusted HTTPS hosts, homepage, country,
   display name, permanent list/session IDs, disabled-by-default visibility and the
   shared manual controls.
2. **Search** — enable only after native WebKit checks show the requested query is
   reflected and results actually correspond to it. A search page loading or a few
   coincidentally matching products is not proof.
3. **Add detection** — only when a user-requested add can be correlated to the exact
   product and a stable retailer confirmation using an existing reviewed strategy.
4. **Retailer-cart Undo** — separate scope. Require an independently reviewed,
   reversible operation and full-cart preservation proof. Never infer it from
   detection or from another retailer's implementation.

If the store needs a new strategy, stop treating it as routine store onboarding:
propose and test the generic engine change independently. Keep capability flags off
until the required evidence is recorded in `packages/ios/VALIDATION.md`.

## Before implementation

- Confirm scope and authorization. Read-only search checks do not authorize sign-in,
  account/fulfilment changes or cart mutations. Ask explicitly before any live Add,
  Undo, location selection or other state-changing test.
- Check existing store JSON, native strategy implementations and prior validation
  for the closest analogue. Reuse a strategy only if its evidence requirements fit.
- Do a read-only route feasibility check early in the actual iOS WebKit environment.
  Record exact final HTTPS host, route, query reflection, matching product links and
  blockers (consent, location/verification walls, empty results). Stop early if the
  site cannot support the requested capability safely.
- Reserve a permanent store ID and list/session/diagnostic identities; never reuse
  or renumber an existing identity. Regional variants need an explicit reviewed
  brand relationship and isolated data identities.

## Implementation and proof

Generate a disabled, unregistered draft and a short evidence checklist (no network,
no native permissions changed, no existing files overwritten):

```bash
python3 -B packages/ios/tools/store-onboarding.py scaffold \
  --id exampleAU --name 'Example Store' --country AU \
  --host shop.example --homepage 'https://shop.example/au/' \
  --search 'https://shop.example/search?q={query}' \
  --output /tmp/opencode/exampleAU-draft
```

The output directory must not already exist. Repeat `--host` for additional exact
reviewed hosts. Keep this draft as the one input for registration and search probes.
Keep `STATUS.md` as the compact current evidence record; link to detailed logs rather
than copying their contents into agent context. Never include account/cart secrets.

### Generate registration, rather than editing multiple switches

After fetching and checking current task branches for reserved identities, choose an
unused permanent serial explicitly. The example `999` is for disposable proofs, not
a reservation for a real store. The tool rejects collisions in the current source;
it cannot prevent another branch independently reserving the same serial.

```bash
python3 -B packages/ios/tools/store-onboarding.py register \
  --config /tmp/opencode/exampleAU-draft/exampleAU.json \
  --serial 999 --data-domain shop.example \
  --output /tmp/opencode/exampleAU-registration.patch
git apply --check /tmp/opencode/exampleAU-registration.patch
# Review the patch, including exact hosts, reset-data domain, IDs and branding.
git apply /tmp/opencode/exampleAU-registration.patch
```

This generates the native case, names, exact hosts, homepage, data domain, two stable
UUID mappings, data-only JSON and Xcode reference/build/resource/group wiring.
It does not infer regional grouping or modify existing code/capability ceilings.
All capabilities remain disabled; new destinations remain unavailable in current
search-verified-only discovery. A changed source/project layout fails closed instead
of guessing. Existing stores retain their permanent identities and permissions.

### Inspect early, before building new cart logic

Use `strategies` for a small inventory of configured strategies and enabled examples.
This is generated from the current JSON, not a separate catalogue to maintain.

```bash
python3 -B packages/ios/tools/store-onboarding.py strategies
python3 -B packages/ios/tools/store-onboarding.py probe-plan \
  --config /tmp/opencode/exampleAU-draft/exampleAU.json \
  --query tea --query bread --product-selector 'a[href*="/product/"]' \
  --output /tmp/opencode/exampleAU-search.json
```

Review selectors for product links, reflected query, Add controls and card containers
(`--query-selector`, `--add-selector`, `--container-selector`). The DOM inspector
returns bounded product paths/counts, query reflection, control structure, conservative
strategy hints and blocker categories, not whole pages, cookies, account fields or raw dialog text. It never
clicks, submits or reads storage. Invalid selectors fail the probe, not open it up.
The two unrelated queries need stable predominantly relevant results, query reflection
and less than 50% catalogue overlap; matching links in a fixed catalogue cannot pass.
This is a baseline search proof, not proof of all catalogue types or cart support.

On a dedicated Mac simulator (never use one owned by another task):

```bash
python3 -B packages/ios/tools/store-onboarding.py probe \
  --plan /tmp/opencode/exampleAU-search.json \
  --destination 'platform=iOS Simulator,id=YOUR-DEDICATED-SIMULATOR-UUID' \
  --allow-live-search
```

Live search is explicit, GET-navigation-only and uses fresh nonpersistent iOS WebKit
sessions. No consent choice, verification bypass, sign-in, fulfilment or cart actions
are performed. Blockers fail the check; they are not reasons to broaden trust or loop.
The `.xcresult` retains structured observations and Xcode's pass/fail outcome. A JSON
report automatically includes the native inspection attachment, revision, config/plan
hashes, elapsed time and actual test counts; zero/skipped tests or missing inspection
evidence cannot produce a pass. The runner prints only outcome and artifact
paths. It never promotes capability flags. Build output is cached outside the checkout,
isolated per worktree; `--derived-data /external/cache/path` can reuse a reviewed cache.

For a network-blocked native smoke test, generate a plan with `--fixture` and run
`probe ... --fixture` without `--allow-live-search`. Synthetic fixture mode cannot
fall back to real websites and is **not** live retailer certification.

### Run checks and promote capabilities independently

- Run `bash packages/ios/tests/run-store-onboarding-check.sh <store-id>` on macOS.
  It also runs on Linux: it validates the selected resource and runs existing offline
  registration/resource/strategy, inspection, tooling and cloud-contract tests. On macOS it
  runs the complete existing native offline suite. It prints short outcomes and
  saves logs plus a JSON report outside the checkout. Exit 0 means all offline checks
  passed; 1 means failure; 2 means usage error or macOS checks remain blocked. It
  does **not** perform live retailer verification or validate the complete native
  schema on Linux. It checks the selected native enum and Xcode resource graph.
  Shared regression checks are not exhaustive for every new store:
  add that store's specific contract and live proof.
- Run only the focused native live test for the requested capability. Keep read-only
  search proof separate from authorized cart tests. Record device/OS, revision,
  query/product evidence, outcome and blockers in `packages/ios/VALIDATION.md`.
- Enable each capability in both bundled configuration and native policy only after
  its own proof passes. Preserve manual fallback and fail-closed behavior.

## Useful precedents

- Registration is generated from the disabled draft, not copied from an enabled store.
- URL-template search example: `walmart.json` (a new destination still needs its own proof).
- Existing cart strategy examples: inspect the current `cart.strategy` values in
  `packages/ios/ListRunner/Resources/` and their corresponding native implementation
  and live-proof records. Similar-looking markup alone is not enough to reuse one.

## Completion report

Report: destination identity, changed files, enabled capabilities, offline checks,
live checks, evidence path/revision and anything still blocked. Use **registered**,
**search verified**, **detection verified** and **Undo verified** precisely; do not
call a registration automated support.
