#!/usr/bin/env bash
# Writes Info.plist to the path given as $1.
# Reads APP_VERSION from env. When unset, CFBundleShortVersionString defaults
# to 3.3.0 and CFBundleVersion to 8 so local dev builds continue to work.
# When set, both fields take the value of APP_VERSION.
set -euo pipefail

out="${1:?usage: write_info_plist.sh <output_path>}"
short_version="${APP_VERSION:-3.3.0}"
bundle_version="${APP_VERSION:-8}"

cat > "$out" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Subtitles</string>
    <key>CFBundleExecutable</key>
    <string>EventSubtitles</string>
    <key>CFBundleIdentifier</key>
    <string>com.eventsubtitles.app</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Subtitles</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${short_version}</string>
    <key>CFBundleVersion</key>
    <string>${bundle_version}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>EventSubtitles needs audio input access to transcribe and record stage audio locally.</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST
