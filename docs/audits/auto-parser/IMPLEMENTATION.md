# Auto-parser fixes

Implements the eight findings in the historical audit (`README.md`) on `fix/auto-parser`. Parser and dictionary content versions are now 2.

## Behavior

- Canonical names are used only when the remaining product wording is fully accounted for. Partial matches keep the complete product phrase after a successfully parsed quantity, including unknown brands and dietary qualifiers. Taco shells remain distinct from pasta shells without a taco-only dictionary exception.
- Quantity extraction consumes a validated leading span independently of the ingredient dictionary. Counts, fractions, decimals, count multipliers, packages, measures and dozen quantities work with known or unknown products. Unparseable quantities remain in the product phrase. Numeric aliases such as `4 cheese ravioli` and the existing numeric-product controls remain protected.
- Matching collapses internal whitespace and enumerates boundary-valid occurrences. Multiple approved modifier spans are retained in source order, choosing longer overlapping modifiers rather than dropping all but one.
- Unknown ingredients never have their leading preparation descriptor/product tail stripped. Recipe preparation clauses are handled before ingredient ambiguity and comma splitting. Unknown comma segments survive; direct product entry retains its explicit separators. Parenthetical commas stay inside recipe notes.
- Coconut cream/milk, cinnamon whole/ground forms, cumin seeds/ground forms, coriander seeds/ground forms and canola/vegetable oil stay distinguishable. Fresh/ground ginger qualifiers survive; named hot sauces no longer become generic Hot sauce.
- Package formatting avoids trapping integer conversions, preserves large integer package sizes exactly, and the saved-item amount formatter is nontrapping too. Blank names are rejected by both the parser and the shared insertion boundary.
- `ParsedGrocery` carries the full parse result through the add/import adapter. This is transient provenance, **not a persisted database/schema change**. Existing saved rows are not reparsed or migrated; already-lost wording cannot be recovered safely.

## Validation

- Linux Swift 6.0.3: all **162 existing fixtures**, **884 current dictionary names/aliases**, **884 unknown-brand preservation cases**, and focused audit regressions pass. Only two previous fixture expectations change intentionally: ground cumin and ground ginger now keep their form qualifier.
- The initial red run reproduced the unsafe numeric conversion (exit 132); the new boundary assertion exercises it in the passing suite.
- **195 regional search checks** and **9 resource-verifier tests** pass.
- Mac validation of **`dd06b058c1733dd9e5f9a521de678feabf1d88e1`** passed the parser/alias/unknown-brand/focused regressions, **195 regional checks** and **1,887 native recovery/configuration/diagnostics checks**, including the new isolated SwiftData save/fetch, identity/merge, blank-row rejection and Paprika-staging assertions.
- The unsigned Debug **iOS simulator build succeeded**. All **35 JSON and 1 JavaScript** resources in the built app byte-match the canonical files; no legacy `-v2` copies were found. This is build/service-test evidence, not a simulator UI-suite run or physical-device verification.
- The final review also protects unknown product names beginning with bare unit/container words (`L plates`, `cup holder`, `can opener`). The original extreme-package observation probe now exits **0**, not 132.
- Mac validation used a clean detached worktree at `/Users/adrianzafir/Projects/listrunner-auto-parser-e9b1004` checked out to the exact final code SHA above. Its folder name reflects the first validation revision; it is not a separate source variant. The main Mac checkout and its preexisting untracked cloud configuration were left unchanged. Logs: `/tmp/listrunner-auto-parser-dd06b05-{parser,regional,native,build,resources}.log`. Build output: `~/Library/Developer/Xcode/DerivedData/ListRunner-auto-parser-e9b1004`.
- Linux logs: `/tmp/opencode/auto-parser-audit/regressions-after.log` and `regional-after.log`. Run the usual `packages/ios/tests/run-parser-tests.sh`, `run-regional-search-tests.sh` and (on Mac) `run-recovery-tests.sh` to reproduce. The audit observation script remains available; its recorded original findings refer to the audit baseline, not the fixed code.

No user lists, Reminders, credentials or retailer carts were accessed or mutated during these checks. No physical-device install or release is implied.
