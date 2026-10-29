#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/listrunner-ingredient-parser-tests"
swiftc \
  "$ROOT/ListRunner/IngredientQuantity.swift" \
  "$ROOT/ListRunner/IngredientParseResult.swift" \
  "$ROOT/ListRunner/IngredientDictionary.swift" \
  "$ROOT/ListRunner/IngredientParser.swift" \
  "$(dirname -- "$0")/IngredientParserTests.swift" \
  -o "$OUT"
"$OUT" "$ROOT/ListRunner/Resources/ingredients.json" \
  "$(dirname -- "$0")/ingredient-parser-fixtures.json" \
  "$(dirname -- "$0")/pasta-parser-fixtures.json"
