#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="EventSubtitles"
BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/$CONFIGURATION"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_ICON_SOURCE="$ROOT_DIR/Assets/AppIconSource.jpg"

cd "$ROOT_DIR"
swift build --configuration "$CONFIGURATION" --product EventSubtitles

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/EventSubtitles" "$MACOS_DIR/EventSubtitles"
if [[ -f "$APP_ICON_SOURCE" ]]; then
    swift -module-cache-path "$ROOT_DIR/build/ModuleCache" "$ROOT_DIR/scripts/generate_app_icon.swift" "$RESOURCES_DIR/AppIcon.icns" "$APP_ICON_SOURCE"
else
    swift -module-cache-path "$ROOT_DIR/build/ModuleCache" "$ROOT_DIR/scripts/generate_app_icon.swift" "$RESOURCES_DIR/AppIcon.icns"
fi

"$ROOT_DIR/scripts/write_info_plist.sh" "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
