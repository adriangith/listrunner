#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/listrunner-regional-search.XXXXXX")"
trap 'rm -f "$OUT/tests"; rmdir "$OUT"' EXIT
swiftc \
  "$ROOT/ListRunner/IngredientQuantity.swift" \
  "$ROOT/ListRunner/IngredientParseResult.swift" \
  "$ROOT/ListRunner/IngredientDictionary.swift" \
  "$ROOT/ListRunner/IngredientParser.swift" \
  "$ROOT/ListRunner/RegionalIngredientSearchResolver.swift" \
  "$ROOT/tests/RegionalIngredientSearchTests.swift" \
  -o "$OUT/tests"
"$OUT/tests" "$ROOT/ListRunner/Resources"
