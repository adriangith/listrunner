#!/bin/bash
# Offline iCloud sync model checks (macOS): no iCloud account or network.
set -euo pipefail
base="$(cd "$(dirname "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/listrunner-sync-tests.XXXXXX")"
trap 'rm -f "$output/sync-tests"; rmdir "$output"' EXIT
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  "$base/ListRunner/SyncModel.swift" \
  "$base/ListRunner/ShoppingModels.swift" \
  "$base/ListRunner/ShoppingLists.swift" \
  "$base/ListRunner/IngredientQuantity.swift" \
  "$base/ListRunner/IngredientParseResult.swift" \
  "$base/ListRunner/IngredientDictionary.swift" \
  "$base/ListRunner/IngredientParser.swift" \
  "$base/ListRunner/StoreConfiguration.swift" \
  "$base/ListRunner/RegionalIngredientSearchResolver.swift" \
  "$base/tests/SyncModelTests.swift" -o "$output/sync-tests"
"$output/sync-tests"
