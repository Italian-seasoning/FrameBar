#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/Distribution"
APP="$DERIVED/Build/Products/Release/FrameBar.app"
SPARKLE_BIN="${SPARKLE_BIN_OVERRIDE:-$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin}"
xcodebuild -quiet -project "$ROOT/FrameBar.xcodeproj" -scheme FrameBar -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" build CODE_SIGNING_ALLOWED=NO
strip -S "$APP/Contents/MacOS/FrameBar"
codesign --force --deep --sign - "$APP"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
DIST="$ROOT/dist/releases/$VERSION"
ARCHIVE="FrameBar-$VERSION-macOS.zip"
mkdir -p "$DIST"
ditto -c -k --norsrc --keepParent "$APP" "$DIST/$ARCHIVE"
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "https://github.com/Italian-seasoning/FrameBar/releases/download/v$VERSION/" --maximum-versions 1 --maximum-deltas 0 "$DIST"
python3 "$ROOT/script/verify_update.py" "$APP" "$DIST/$ARCHIVE" "$DIST/appcast.xml" --sparkle-bin "$SPARKLE_BIN" --repository Italian-seasoning/FrameBar --require-newer
echo "Verified release ready: $DIST"
