#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -swift-version 5 -O -warnings-as-errors \
  -module-cache-path "${TMPDIR:-/tmp}/splinter-swift-module-cache" \
  -target "$(uname -m)-apple-macos14.0" \
  Sources/Localization.swift Sources/Models.swift Sources/Engine.swift cli/main.swift -o cli/mouse-remap
print "Built: $PWD/cli/mouse-remap"
