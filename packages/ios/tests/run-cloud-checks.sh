#!/bin/bash
# Explicit offline allowlist: never invoke XCTest/live-retailer test discovery here.
set -euo pipefail
base="$(cd "$(dirname "$0")/.." && pwd)"

for tool in python3 node xcrun swiftc; do
  command -v "$tool" >/dev/null || { echo "error: Required offline-check tool missing: $tool" >&2; exit 1; }
done
node -e 'if (Number(process.versions.node.split(".")[0]) < 22) { console.error("Node.js 22 or later is required"); process.exit(1); }'

python3 -B "$base/tests/test-release-metadata.py"
python3 -B "$base/tests/test-store-categories.py"
python3 -B "$base/tests/test-store-expansion.py"
python3 -B "$base/tests/test-store-onboarding.py"
python3 -B "$base/tests/test-bundled-resources.py"
python3 -B "$base/tests/test-cloud-ci.py"
node --test \
  "$base/tests/results-scroll.test.mjs" \
  "$base/tests/bigw-cart-detection.test.mjs" \
  "$base/tests/coles-add-detection.test.mjs" \
  "$base/tests/profiled-expansion-cart.test.mjs"
node --test "$base/tests/store-inspection.test.mjs"
node --test "$base/tests/nightly-beta.test.mjs"
bash "$base/tests/run-parser-tests.sh"
bash "$base/tests/run-regional-search-tests.sh"
bash "$base/tests/run-store-proof.sh"
bash "$base/tests/run-recovery-tests.sh"
echo "PASS: all cloud offline checks"
