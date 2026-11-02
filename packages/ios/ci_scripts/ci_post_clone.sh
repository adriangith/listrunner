#!/bin/bash
set -euo pipefail
base="$(cd "$(dirname "$0")/.." && pwd)"

# Cloud images include Homebrew, but do not promise a compatible Node runtime.
if ! command -v node >/dev/null || ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)'; then
  command -v brew >/dev/null || { echo "error: Node.js 22+ and Homebrew are unavailable" >&2; exit 1; }
  export HOMEBREW_NO_AUTO_UPDATE=1
  brew list --versions node@22 >/dev/null 2>&1 || brew install node@22
  export PATH="$(brew --prefix node@22)/bin:$PATH"
fi

bash "$base/tests/run-cloud-checks.sh"
