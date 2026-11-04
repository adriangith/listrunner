#!/bin/bash
# Offline only. Exit 2 means usage error or macOS-only checks remain blocked.
set -euo pipefail
base="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 -B "$base/tools/store-onboarding.py" check "$@"
