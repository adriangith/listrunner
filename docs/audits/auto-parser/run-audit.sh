#!/bin/sh
# Run from any directory. Outputs must stay outside the checkout.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
OUT="${1:?usage: sh run-audit.sh /absolute/external/output-directory}"
case "$OUT" in /*) ;; *) echo 'Output must be absolute' >&2; exit 2 ;; esac
case "$OUT/" in "$ROOT/"*) echo 'Output must be outside checkout' >&2; exit 2 ;; esac
mkdir -p "$OUT"
SWIFTC="${SWIFTC:-swiftc}"
"$SWIFTC" --version > "$OUT/compiler.txt"
git -C "$ROOT" rev-parse HEAD > "$OUT/revision.txt"
SRC="$ROOT/packages/ios/ListRunner"
"$SWIFTC" "$SRC/IngredientQuantity.swift" "$SRC/IngredientParseResult.swift" \
    "$SRC/IngredientDictionary.swift" "$SRC/IngredientParser.swift" \
    "$ROOT/packages/ios/tests/IngredientParserTests.swift" -o "$OUT/baseline"
"$OUT/baseline" "$SRC/Resources/ingredients.json" \
    "$ROOT/packages/ios/tests/ingredient-parser-fixtures.json" \
    "$ROOT/packages/ios/tests/pasta-parser-fixtures.json" > "$OUT/baseline.log"
"$SWIFTC" "$SRC/IngredientQuantity.swift" "$SRC/IngredientParseResult.swift" \
    "$SRC/IngredientDictionary.swift" "$SRC/IngredientParser.swift" \
    "$ROOT/docs/audits/auto-parser/ParserAudit.swift" -o "$OUT/probe"
"$OUT/probe" "$SRC/Resources/ingredients.json" > "$OUT/observations.log"
# A deliberate crash probe runs only in its own process; no core dump is needed.
ulimit -c 0
set +e
"$OUT/probe" "$SRC/Resources/ingredients.json" --large-package > "$OUT/large-package.log" 2>&1
STATUS=$?
set -e
echo "$STATUS" > "$OUT/large-package.exit"
echo "Baseline and observations saved in $OUT; large-package exit=$STATUS"
