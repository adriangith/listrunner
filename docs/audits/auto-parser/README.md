# ListRunner auto-parser audit

Historical baseline report. Follow-up implementation and validation are described in `IMPLEMENTATION.md`; findings/file lines below refer to the audited revision, before fixes.

After the manual-entry bypass merge, the standalone probe's `ENTRY` output uses
`ParsedGrocery.productEntries(in:)`, matching current literal manual entry. `LIST`
and record probes still exercise import parsing. The historical observations below
describe the original parser-based manual-entry path, not the current app behavior.

Audit date: 9 November 2026. Baseline: `8fdbf1bc428b52a7217ef4e24eb44ffd322e0432`, branch `audit/auto-parser`.

**No implementation fixes were made.** Only this report and standalone observation probes were added in the audit worktree. The main Linux checkout and Mac checkout were not modified. No app installation, user-list mutation, Reminders access/write, retailer browsing or cart operation was performed.

## Scope and evidence

- Reviewed root `AGENTS.md`, `packages/ios/README.md`, relevant `VALIDATION.md` history, `plan.md`, native parser/dictionary/quantity/result code, manual-entry and Paprika consumers, merge behavior, regional search resolver, native fixtures/runner, and the separate TypeScript core parser/tests. The July Paprika design document is historical, not the native implementation specification.
- The active iOS path is deterministic Swift dictionary matching, **not an AI model**. Manual entry uses `parseProductEntry`; Paprika uses `parseGroceries` → `parseList`. The separate TypeScript parser does not perform this dictionary canonicalization and cannot explain the taco-to-pasta rewrite.
- `plan.md:249-250` calls for multiplier/decimal quantities and preservation of full input when quantity recognition fails. `plan.md:192-193` explicitly preserves existing parser canonicalization but restricts regional search rewriting to equivalent names. Do not mistake general canonicalization for permission to substitute different products.
- Installed no system packages: extracted a Swift 6.0.3 Linux toolchain under `/tmp/opencode/auto-parser-audit/swift-toolchain`. Compiled the **unchanged production Swift files**, with the checked-in dictionary injected just as the existing tests do.
- **Existing native suite: 449 reported checks passed**, including 276 name/alias identity-and-quantity checks. An additional exhaustive identity sweep of **888 dictionary names/aliases passed**. These are positive identity checks, not evidence that destructive partial matches are safe.
- **Separate TypeScript core: all 90 tests, typecheck and build passed**, run from a `git archive HEAD` snapshot under `/tmp/opencode/auto-parser-audit/core-baseline`, with dependencies installed there rather than in either checkout. Direct core probes preserved `taco shells`, parsed `12 taco shells` as count 12 plus search term `taco shells`, and parsed `2x apples` as count 2. This confirms the anchor belongs to the native dictionary path, not that all core cleanup behavior is safe. `npm ci` emitted 17 dependency-audit warnings (1 low, 8 moderate, 6 high, 2 critical); these were not triaged or fixed as part of this parser audit.
- Runtime observations are in `/tmp/opencode/auto-parser-audit/results/observations.log`; original-suite output is `baseline.log`; numeric-crash output/status are `large-package.log` / `large-package.exit` in the same directory. Compiler/revision are also recorded there. Selected results are preserved below so the report does not depend on temporary logs surviving.
- This proves standalone parser behavior on Linux, not a new iOS build/UI test. Persistence/merge/writeback consequences below are code-path findings rather than observed changes to a real list. Mac SSH initially allowed read-only status inspection, then became unreachable; no Mac source synchronization or branch change was attempted.

Priority: **P1** = address before trusting automatic rewriting; **P2** = important correctness/robustness issue; **P3** = lower-priority matcher defect.

## 1. P1 — Partial matches replace entire product identities; warnings are discarded

**Confirmed anchor and related observations:**

```text
taco shells       → Pasta shells, quantity unspecified, partial, unmatched=[taco]
12 taco shells    → Pasta shells, quantity unspecified, partial, unmatched=[taco]
rice cakes        → Rice, partial, unmatched=[cakes]
lemon detergent   → Lemon, partial, unmatched=[detergent]
gluten-free bread → Bread, partial, unmatched=[gluten-free]
soy  milk         → Milk, partial, unmatched=[soy]
soy milk          → Soy milk, recognized
```

**Cause:** `packages/ios/ListRunner/Resources/ingredients.json:211` assigns bare `shells` to `conchiglie` / Pasta shells. `IngredientParser.swift:108-127` accepts a single whole-word dictionary match anywhere in the text. `IngredientParser.swift:57-79,157-178` then rebuilds the entire name from that entry and approved modifiers, even when arbitrary source words remain. The double-space soy example additionally shows that compound aliases are matched literally, without whitespace normalization (`IngredientParser.swift:112-113`; compare `IngredientDictionary.swift:67-69`).

**Why metadata does not protect users:** `IngredientParser.swift:92-101` immediately converts results to `ParsedGrocery`; `IngredientParseResult.swift:26-52` retains only name/quantity, dropping original text, unmatched words and disposition. The manual caller at `GroceryListScreen.swift:1915-1929` and Paprika caller at `PaprikaReminders.swift:80-86` use those lossy groceries. `ShoppingModels.swift:27-30` also makes the rewritten name the saved search term.

**Likely downstream harm:** `parseProductEntry("taco shells, pasta shells")` produces two identical Pasta shells names. `ShoppingLists.swift:121-136` merges matching names/compatible units, so distinct products can collapse into a single saved row; linked-row merges can enqueue Reminder writeback (`GroceryListScreen.swift:1929-1931`). Dietary or non-food qualifiers can likewise disappear. These persistence consequences follow from code; no real list was changed to demonstrate them.

**Recommended fix:** Permit full canonicalization only when every non-quantity source span is accounted for safely. Preserve the original product wording on partial/uncertain matches and carry provenance through the add/import boundary. Give broad aliases such as `shells` explicit context constraints; adding only a `taco shells` entry would patch one example, not the general defect. Normalize whitespace for matching with a mapping back to source spans. Do not retroactively guess lost words in existing saved items.

## 2. P1 — Multiple approved modifiers lose information while reporting a clean match

**Confirmed:**

```text
gluten-free wholemeal penne → Gluten-free penne   (recognized, unmatched=[])
wholemeal gluten-free penne → Wholemeal penne     (recognized, unmatched=[])
lactose-free 2% milk        → Lactose-free milk   (recognized, unmatched=[])
2% lactose-free milk        → 2% milk             (recognized, unmatched=[])
```

`IngredientParser.swift:158-169` finds all modifiers but renders only the first. `IngredientParser.swift:66-70` excludes *all* modifier words from unmatched text, concealing the omitted qualifiers. The result can omit a dietary constraint depending solely on word order, even if partial results are later made safe.

**Recommended fix:** Preserve all distinct, nonoverlapping approved modifier spans, in source order; resolve overlapping phrases explicitly. A result must not be `recognized` if meaningful qualifiers disappeared. Test reordered combinations, not only individual modifiers. Entries are at `Resources/ingredients.json:21,195`.

## 3. P1 — Unknown-ingredient preparation stripping can create empty or truncated names

**Confirmed:**

```text
500 g diced jackfruit → name="", amount=500, unit=g
250 g minced seitan  → name="", amount=250, unit=g
500 g unmelted candy → name="un", amount=500, unit=g
diced mystery greens → name="diced mystery greens", amount=nil
```

`IngredientParser.swift:231-249` extracts an unknown quantity and calls `cleanUnknown`. Its regex has no left word boundary, permits zero whitespace, and removes the preparation term **and everything after it**, including the actual unknown product. `IngredientParser.swift:57-59,75-80` returns that empty name without validating it; it can even explain that source wording was preserved when it was not. Dictionary-unavailable fallback has the same defect.

**Likely downstream harm:** `parseProductEntry` returns a nonempty array containing a blank-named grocery. Add enablement checks only array emptiness (`GroceryListScreen.swift:855,1560`), and `ShoppingLists.swift:133-135` inserts the name without another nonempty check. Thus the production path permits blank rows; no UI/persistence run was performed.

**Recommended fix:** Remove only proven preparation spans, never an unknown product tail wholesale. Require word boundaries, preserve the unknown source name on uncertainty, and enforce a nonempty post-parse name before returning/inserting a grocery. Test unknown products both with and without quantities and with the dictionary unavailable.

## 4. P2 — Dictionary “aliases” sometimes collapse non-equivalent products or forms

**Confirmed:**

```text
coconut cream   → Coconut milk (recognized)
coconut milk    → Coconut milk (recognized)
cinnamon stick → Cinnamon     (recognized)
ground cinnamon→ Cinnamon     (recognized)
```

`Resources/ingredients.json:351` treats coconut cream as an alias of coconut milk. `Resources/ingredients.json:319` groups whole cinnamon sticks and ground cinnamon without preserving form. Additional review candidates include fresh vs ground ginger (`:95`), cumin seeds vs ground cumin (`:316`), generic hot sauce vs specific sriracha/tabasco (`:346`) and vegetable oil vs canola oil (`:358`). The latter candidates may be deliberate shopping generalizations, but they are not all interchangeable identities and should be explicitly reviewed.

Unlike finding 1, these are full matches: a safeguard on `partial` alone cannot catch them. Different inputs become the same saved/search name and can then merge.

**Recommended fix:** Separate spelling/regional synonyms from product substitutions, preparation forms and brand generalization. Use distinct entries or retained qualifiers where the shopping choice changes. Add negative-equivalence tests proving that coconut cream/milk and whole/ground forms remain distinguishable.

## 5. P2 — Quantities depend on dictionary recognition and strict surrounding wording

**Confirmed:**

```text
2 apples                      → Apples, amount=2
2x apples / 2 x apples         → Apples, amount=nil
1.5 apples / ½ apples          → Apples, amount=nil, recognized, unmatched=[]
2 chairs                      → "2 chairs", amount=nil
2 large eggs                  → Eggs, amount=nil
2 organic apples              → Apples, amount=nil
500 g organic apples          → Apples, amount=500 g
2 x 400 g cans organic tomatoes→ Tomatoes, amount=nil
```

`IngredientParser.swift:139-154` parses quantity from the entire prefix/suffix after stripping only approved modifiers. `quantityPattern` handles measures/fractions but accepts only integer bare counts (`:196-209`) and no count-only multiplier form. Unknown parsing supports only packages/measures (`:231-241`), not ordinary counts. Meanwhile numeric tokens are removed from unmatched text even when no quantity consumed them (`:69-70,292-294`). This contradicts the supported `2x apples` example and fallback wording requirement at `plan.md:249-250`.

`2 chairs` preserving the full text is conservative, but loses a useful quantity and is inconsistent with known products. More seriously, recognized products can lose quantity text without either a quantity value or a warning.

**Recommended fix:** Extract a validated quantity span independently of ingredient identity, then match the remaining product phrase. Support the specified multiplier/decimal formats consistently; do not hide tokens as consumed unless they actually contributed to the parsed quantity. Preserve full input if a format cannot be interpreted safely. Keep numeric product-name controls (`7 Up`, `2% milk`, `Vitamin B12`, `Formula stage 2`) in regression coverage.

## 6. P2 — Recipe comma detection mistakes preparation references for new groceries

**Confirmed through the Paprika-facing list parser:**

```text
parseList("2 eggs, beaten with milk")  → [Eggs ×2, Milk (unspecified)]
parseList("1 onion, diced with garlic")→ [Onion ×1, Garlic (unspecified)]
parseList("milk, mystery fizz")        → [Milk]  // mystery fizz silently lost
```

`IngredientParser.swift:84-88` splits commas whenever each segment has *any* dictionary match. A preparation segment such as `beaten with milk` has a partial Milk match and is therefore treated as a separate item. If not every segment matches, the whole line is instead canonicalized as one ingredient, allowing finding 1 to discard the unknown segment. Paprika calls this path at `PaprikaReminders.swift:80-86`, linking the source reminder only to the first resulting grocery.

`parseRecord("2 eggs, beaten with milk")` is also problematic: it resolves ambiguity before stripping preparation (`IngredientParser.swift:44-58`) and returns name `2 eggs` with no count. Merely switching Paprika to `parseRecord` is therefore insufficient.

**Recommended fix:** Make recipe/Reminder comma handling preparation-aware before ingredient resolution/splitting. A partial match in a preparation clause is not proof of another list item. Preserve unknown segments; define explicit treatment for multi-item Reminder titles. Keep direct product-entry comma splitting separate: that behavior is intentional (`IngredientParser.swift:96-101`) and was not classified as a bug by itself.

## 7. P2 — Large accepted package size crashes during grocery conversion

**Confirmed in an isolated subprocess:**

```text
1 x 9223372036854775807 g cans tomatoes
→ Fatal error: Double value cannot be converted to Int because the result would be greater than Int.max
→ process exit 132 (illegal instruction on this Linux run)
```

The package parser accepts a valid `Int64.max` rational (`IngredientParser.swift:184-186,270`). `IngredientParseResult.swift:42-44` converts it to `Double`, which rounds it to an out-of-range integer, then performs trapping `Int(value)` conversion. Both add/import adapters eagerly access `.grocery`. `ShoppingModels.swift:43-44` contains the same unguarded integer formatting pattern for amounts, warranting a separate follow-up boundary test there.

This is a real crash but requires unrealistic quantity input; it is not prioritized above routine product/quantity corruption. Invalid `1/0 g milk` and overflowing numeric strings also return a unit with no amount rather than preserving the complete source (`IngredientParser.swift:197-199`), though they did not crash in the probe.

**Recommended fix:** Use nontrapping range-checked formatting (or rational/decimal formatting without a Double-to-Int round trip), reject unsupported magnitudes before projection, and retain invalid quantity text for correction. Add subprocess crash guards and numeric boundary tests; keep the test process isolated.

## 8. P3 — Matching stops after the first substring, even if its boundary is invalid

**Confirmed:** `milkshake milk` is `unknown` with no ingredient ID, even though the second `milk` is a valid standalone dictionary occurrence. `IngredientParser.swift:112-113` checks only the first `range(of:)` result and gives up if its boundaries fail. It also cannot enumerate repeated mentions when deciding ambiguity.

**Recommended fix:** Enumerate all boundary-valid occurrences, then resolve overlap/ambiguity. The separate search resolver already has an occurrence loop (`RegionalIngredientSearchResolver.swift:129-138`) and more conservative context checks (`:115-122`); it is a useful local reference, not a drop-in parser replacement. Keep source preservation from finding 1 when implementing this, otherwise better matching could increase destructive rewrites.

## Coverage gaps and recommended implementation sequence

Existing fixtures chiefly assert expected positive canonicalization. `tests/IngredientParserTests.swift:69-76` makes disposition/unmatched/grocery assertions optional, and `:140-150` expands aliases only for fixture-covered IDs. The audit's all-888 identity pass shows that wider positive identity coverage alone would still miss the failures above. The invalid-dictionary test (`:47-55`) exercises only an unknown measured ingredient, not unknown counts or empty-name stripping.

1. Establish a preservation invariant: meaningful source words cannot disappear silently; keep provenance through add/import and validate nonempty final names. Add negative compound, whitespace, dietary and no-dictionary regressions.
2. Preserve multiple qualifiers and audit unsafe alias equivalences. Avoid a dictionary-only taco exception as the sole fix.
3. Separate quantity extraction from identity resolution, then make recipe-comma handling preparation-aware. Keep direct-entry separators and numeric product names stable.
4. Harden numeric conversion and occurrence scanning. Add malformed/boundary/property tests plus a small native integration test for merge/persistence behavior.
5. Bump parser/dictionary content versions when behavior/data changes (`IngredientParser.swift:5`, `Resources/ingredients.json:2`), retain original input for future diagnosis, and do not migrate already-truncated saved names by guessing.

## Reproduce

On any host with compatible Swift and Foundation:

```sh
sh docs/audits/auto-parser/run-audit.sh /absolute/path/outside-checkout/parser-audit
```

On this Linux host:

```sh
SWIFTC=/tmp/opencode/auto-parser-audit/swift-toolchain/usr/bin/swiftc \
  sh docs/audits/auto-parser/run-audit.sh /tmp/opencode/auto-parser-audit/results
```

The script runs existing assertions unchanged, emits JSON observations and grocery projections, sweeps all dictionary identities, then deliberately invokes the extreme-package crash in a separate process with core dumps disabled. Exit status for that subprocess is captured rather than treated as a successful functional test. Observation probes are **not fixed-behavior regression assertions** and do not claim the bugs have been repaired. Outputs/build products stay outside the checkout.
