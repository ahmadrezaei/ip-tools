#!/bin/bash
# Runs the package unit tests on the host Mac.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/IPToolsKit" && swift test "$@"
