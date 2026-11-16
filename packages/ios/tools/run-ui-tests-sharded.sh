#!/bin/bash
# Run StoreSelectionTests UI tests split across several simulators at once.
# Xcode's -parallel-testing-enabled distributes whole test classes, and these
# tests share one class, so it runs them serially; this shards by test instead.
#
# Usage (on the Mac, after build-for-testing into <derived-data>):
#   tools/run-ui-tests-sharded.sh <derived-data> <test-name-regex> <sim-udid> [<sim-udid>...]
# Example:
#   tools/run-ui-tests-sharded.sh /tmp/lr-dd '^testStoreProduct' <udid-1> <udid-2>
# Two simulators suit a 16 GB M1; each runs its own WebKit fixture pages.
set -uo pipefail
cd "$(dirname "$0")/.."

derived_data=$1; pattern=$2; shift 2
sims=("$@")
[ ${#sims[@]} -gt 0 ] || { echo "Give at least one simulator UDID" >&2; exit 2; }

tests=($(grep -oE 'func test[A-Za-z0-9_]+\(\)' ListRunnerUITests/StoreSelectionTests.swift \
    | sed -E 's/func (.*)\(\)/\1/' | grep -E "$pattern"))
[ ${#tests[@]} -gt 0 ] || { echo "No tests match $pattern" >&2; exit 2; }

stamp=$(date +%s)
count=${#sims[@]}
for i in "${!sims[@]}"; do
    args=()
    for j in "${!tests[@]}"; do
        if [ $(( j % count )) -eq "$i" ]; then
            args+=("-only-testing:ListRunnerUITests/StoreSelectionTests/${tests[$j]}")
        fi
    done
    xcodebuild -project ListRunner.xcodeproj -scheme ListRunner \
        -destination "platform=iOS Simulator,id=${sims[$i]}" -derivedDataPath "$derived_data" \
        -resultBundlePath "/tmp/lr-shard$i-$stamp.xcresult" test-without-building "${args[@]}" \
        > "/tmp/lr-shard$i-$stamp.log" 2>&1 &
done
wait

grep -hE "Test [Cc]ase .*(passed|failed)|error:" /tmp/lr-shard*-"$stamp".log \
    | sed -E "s/^.*StoreSelectionTests[ .]//; s/'//g"
passed=$(grep -hcE "Test [Cc]ase .*passed" /tmp/lr-shard*-"$stamp".log | paste -sd+ - | bc)
failed=$(grep -hcE "Test [Cc]ase .*failed" /tmp/lr-shard*-"$stamp".log | paste -sd+ - | bc)
echo "${#tests[@]} tests: $passed passed, $failed failed; wall $(( $(date +%s) - stamp ))s"
echo "results: /tmp/lr-shard*-$stamp.xcresult"
[ "$failed" -eq 0 ]
