#!/bin/bash
# Builds the Swift package, then the iOS app for the simulator.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
(cd "$ROOT/IPToolsKit" && swift build)
cd "$ROOT"
xcodebuild -project IPTools.xcodeproj -scheme IPTools \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO build
