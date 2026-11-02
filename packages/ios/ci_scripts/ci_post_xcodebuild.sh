#!/bin/bash
set -euo pipefail
base="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${CI_XCODEBUILD_EXIT_CODE:-}" != "0" ]]; then
  echo "error: xcodebuild failed or its result is missing; archive is not verified" >&2
  exit 1
fi
if [[ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]]; then
  echo "Skipping archive audit for non-archive action"
  exit 0
fi
: "${CI_ARCHIVE_PATH:?Archive action must provide CI_ARCHIVE_PATH}"
python3 -B "$base/tests/verify-cloud-archive.py" "$CI_ARCHIVE_PATH"
