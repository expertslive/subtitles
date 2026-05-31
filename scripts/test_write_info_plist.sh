#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$SCRIPT_DIR/write_info_plist.sh"

tmp="$(mktemp -t info_plist_test.XXXXXX)"
trap 'rm -f "$tmp"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# Test 1: when APP_VERSION is unset, CFBundleShortVersionString defaults to 3.3.0 and CFBundleVersion to 8
unset APP_VERSION
"$WRITER" "$tmp"
grep -q '<string>3.3.0</string>' "$tmp" || fail "default CFBundleShortVersionString missing"
grep -q '<string>8</string>' "$tmp" || fail "default CFBundleVersion missing"
pass "defaults preserved when APP_VERSION unset"

# Test 2: when APP_VERSION=9.9.9, both CFBundleShortVersionString and CFBundleVersion become 9.9.9
APP_VERSION=9.9.9 "$WRITER" "$tmp"
occurrences=$(grep -c '<string>9.9.9</string>' "$tmp" || true)
[[ "$occurrences" -eq 2 ]] || fail "expected 9.9.9 twice (short + bundle), got $occurrences"
pass "APP_VERSION substitutes into both fields"

# Test 3: bundle identifier and other static fields are unaffected
APP_VERSION=1.2.3 "$WRITER" "$tmp"
grep -q '<string>com.eventsubtitles.app</string>' "$tmp" || fail "CFBundleIdentifier missing"
grep -q '<string>EventSubtitles</string>' "$tmp" || fail "CFBundleExecutable missing"
grep -q '<string>14.0</string>' "$tmp" || fail "LSMinimumSystemVersion missing"
pass "static fields preserved"

# Test 4: writes valid plist (plutil round-trip)
plutil -lint "$tmp" >/dev/null || fail "plutil rejected the generated plist"
pass "generated plist is well-formed"

echo "All write_info_plist.sh tests passed."
