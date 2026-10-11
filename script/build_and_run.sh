#!/usr/bin/env bash
set -euo pipefail

# RTK is optional for people building the public project.
if ! command -v rtk >/dev/null 2>&1; then
    rtk() {
        if [[ "${1:-}" == "proxy" ]]; then shift; fi
        "$@"
    }
fi

MODE="${1:-run}"
APP_NAME="FrameBar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
INSTALLED_APP="$HOME/Applications/$APP_NAME.app"

rtk proxy pkill -x "$APP_NAME" >/dev/null 2>&1 || true
rtk proxy xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR"
rtk proxy xcodebuild -quiet -project "$ROOT_DIR/$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath "$BUILD_DIR" build CODE_SIGNING_ALLOWED=NO
# A stable certificate requirement lets macOS recognize subsequent local updates.
# Keep certificate names and team identifiers out of project files and build output.
SIGN_IDENTITY="${FRAMEBAR_SIGN_IDENTITY:-$(rtk proxy python3 -c 'import re, shutil, subprocess; command = ["security", "find-identity", "-v", "-p", "codesigning"]; output = subprocess.check_output((["rtk", "proxy"] if shutil.which("rtk") else []) + command, text=True); matches = [re.search(r"\b([0-9A-F]{40})\b", line) for line in output.splitlines() if "Apple Development:" in line]; print(next((match.group(1) for match in matches if match), "-"))')}"
rtk proxy codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
rtk proxy codesign --verify --deep --strict "$APP_BUNDLE"
rtk proxy mkdir -p "$HOME/Applications"
# ditto merges directories; old Debug dylibs invalidate a Release resource seal.
# Stage a complete replacement and keep the previous bundle until verification succeeds.
STAGING_DIR="$(rtk proxy mktemp -d "$HOME/Applications/.FrameBar-install.XXXXXX")"
rtk proxy ditto "$APP_BUNDLE" "$STAGING_DIR/FrameBar.app"
rtk proxy codesign --verify --deep --strict "$STAGING_DIR/FrameBar.app"
if [[ -d "$INSTALLED_APP" ]]; then
    rtk proxy mv "$INSTALLED_APP" "$STAGING_DIR/previous.app"
fi
if ! rtk proxy mv "$STAGING_DIR/FrameBar.app" "$INSTALLED_APP" || ! rtk proxy codesign --verify --deep --strict "$INSTALLED_APP"; then
    rtk proxy rm -rf "$INSTALLED_APP"
    if [[ -d "$STAGING_DIR/previous.app" ]]; then
        rtk proxy mv "$STAGING_DIR/previous.app" "$INSTALLED_APP"
    fi
    exit 1
fi
rtk proxy rm -rf "$STAGING_DIR"

case "$MODE" in
  run) rtk proxy open "$INSTALLED_APP" ;;
  --verify|verify)
    rtk proxy open "$INSTALLED_APP"
    rtk proxy sleep 2
    rtk proxy pgrep -x "$APP_NAME" >/dev/null
    ;;
  --debug|debug) rtk proxy lldb -- "$INSTALLED_APP/Contents/MacOS/$APP_NAME" ;;
  --logs|logs)
    rtk proxy open "$INSTALLED_APP"
    rtk proxy log stream --info --style compact --predicate 'process == "FrameBar"'
    ;;
  --telemetry|telemetry)
    rtk proxy open "$INSTALLED_APP"
    rtk proxy log stream --info --style compact --predicate 'subsystem == "app.italianseasoning.FrameBar"'
    ;;
  *) exit 2 ;;
esac
