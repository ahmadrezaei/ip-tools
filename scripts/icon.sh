#!/bin/bash
# Re-render App/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024x1024, no alpha) from docs/icon.svg.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 1024 -h 1024 "$ROOT/docs/icon.svg" -o "$TMP/icon.png"
else
    qlmanage -t -s 1024 -o "$TMP" "$ROOT/docs/icon.svg" >/dev/null 2>&1
    mv "$TMP/icon.svg.png" "$TMP/icon.png"
fi
# Round-trip through JPEG to drop any alpha channel, then back to PNG.
sips -s format jpeg -s formatOptions 100 "$TMP/icon.png" --out "$TMP/icon.jpg" >/dev/null
sips -s format png "$TMP/icon.jpg" --out "$OUT" >/dev/null
sips -g pixelWidth -g pixelHeight -g hasAlpha "$OUT"
