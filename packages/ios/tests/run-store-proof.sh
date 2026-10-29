#!/bin/bash
set -euo pipefail
base="$(cd "$(dirname "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/listrunner-store-proof.XXXXXX")"
trap 'rm -f "$output/store-proof"; rmdir "$output"' EXIT
xcrun swiftc -parse-as-library -D STORE_REGISTRY_PROOF \
  -target "$(uname -m)-apple-macosx14.0" \
  "$base/ListRunner/StoreConfiguration.swift" \
  "$base/ListRunner/IngredientQuantity.swift" \
  "$base/ListRunner/IngredientParseResult.swift" \
  "$base/ListRunner/IngredientDictionary.swift" \
  "$base/ListRunner/IngredientParser.swift" \
  "$base/ListRunner/RegionalIngredientSearchResolver.swift" \
  "$base/tests/SyntheticStoreTests.swift" -o "$output/store-proof"
"$output/store-proof" "$base/ListRunner/Resources"
