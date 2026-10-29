#!/bin/bash
set -euo pipefail
base="$(cd "$(dirname "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/listrunner-recovery-tests.XXXXXX")"
trap 'rm -f "$output/recovery-tests" "$output/legacy-writer" "$output/store-v2-writer"; rmdir "$output"' EXIT
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  "$base/tests/LegacyStoreWriter.swift" -o "$output/legacy-writer"
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  "$base/ListRunner/ShoppingModels.swift" \
  "$base/ListRunner/IngredientQuantity.swift" \
  "$base/ListRunner/IngredientParseResult.swift" \
  "$base/ListRunner/IngredientDictionary.swift" \
  "$base/ListRunner/IngredientParser.swift" \
  "$base/ListRunner/ShoppingLists.swift" \
  "$base/ListRunner/StoreConfiguration.swift" \
  "$base/tests/StoreV2Writer.swift" -o "$output/store-v2-writer"
xcrun swiftc -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
  "$base/ListRunner/ShoppingModels.swift" \
  "$base/ListRunner/ShoppingLists.swift" \
  "$base/ListRunner/PaprikaReminders.swift" \
  "$base/ListRunner/IngredientQuantity.swift" \
  "$base/ListRunner/IngredientParseResult.swift" \
  "$base/ListRunner/IngredientDictionary.swift" \
  "$base/ListRunner/IngredientParser.swift" \
  "$base/ListRunner/StoreConfiguration.swift" \
  "$base/ListRunner/RecoverySupport.swift" \
  "$base/ListRunner/RecoveryServices.swift" \
  "$base/tests/RecoveryTests.swift" -framework EventKit -o "$output/recovery-tests"
"$output/recovery-tests" "$base/ListRunner/Resources" "$output/legacy-writer" "$output/store-v2-writer"
