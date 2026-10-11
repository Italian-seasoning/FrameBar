#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/Assets/FrameBar.svg"
DESTINATION="$ROOT_DIR/FrameBar/Assets.xcassets/AppIcon.appiconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "Install librsvg (brew install librsvg) to export the SVG app icon." >&2
    exit 1
fi

for size in 16 32 128 256 512; do
    rsvg-convert --width "$size" --height "$size" "$SOURCE" --output "$DESTINATION/icon_${size}x${size}.png"
    doubled=$((size * 2))
    rsvg-convert --width "$doubled" --height "$doubled" "$SOURCE" --output "$DESTINATION/icon_${size}x${size}@2x.png"
done
