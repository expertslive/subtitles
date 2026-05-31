#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL="$SCRIPT_DIR/install.sh"

# Source the script with __TEST_MODE=1 so main() does not auto-run.
# shellcheck disable=SC1090
__TEST_MODE=1 source "$INSTALL"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# ---- arg parsing ----

reset_opts() {
  OPT_VERSION=""
  OPT_REINSTALL=0
  OPT_DRY_RUN=0
}

reset_opts
parse_args
[[ "$OPT_VERSION" == "" && "$OPT_REINSTALL" == "0" && "$OPT_DRY_RUN" == "0" ]] \
  || fail "no args: expected all defaults"
pass "parse_args defaults"

reset_opts
parse_args --version v1.2.3
[[ "$OPT_VERSION" == "v1.2.3" ]] || fail "--version did not set OPT_VERSION"
pass "parse_args --version vX.Y.Z"

reset_opts
parse_args --reinstall --dry-run
[[ "$OPT_REINSTALL" == "1" && "$OPT_DRY_RUN" == "1" ]] \
  || fail "--reinstall --dry-run flags not set"
pass "parse_args boolean flags"

reset_opts
VERSION="v9.9.9" REINSTALL=1 DRY_RUN=1 parse_args
[[ "$OPT_VERSION" == "v9.9.9" && "$OPT_REINSTALL" == "1" && "$OPT_DRY_RUN" == "1" ]] \
  || fail "env-var equivalents not honored"
pass "parse_args env-var equivalents"


# ---- base URL resolution ----

reset_opts
OPT_VERSION=""
url="$(resolve_base_url)"
[[ "$url" == "https://github.com/expertslive/subtitles/releases/latest/download/" ]] \
  || fail "default base URL should be /releases/latest/download/, got: $url"
pass "resolve_base_url defaults to /latest/"

reset_opts
OPT_VERSION="v3.4.0"
url="$(resolve_base_url)"
[[ "$url" == "https://github.com/expertslive/subtitles/releases/download/v3.4.0/" ]] \
  || fail "pinned base URL malformed, got: $url"
pass "resolve_base_url pins to /download/<tag>/"


# ---- idempotency check ----

mock_plist() {
  local dir="$1" version="$2"
  mkdir -p "$dir/EventSubtitles.app/Contents"
  cat > "$dir/EventSubtitles.app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleShortVersionString</key><string>${version}</string>
</dict></plist>
PLIST
}

tmpdir="$(mktemp -d -t install_test.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

# No installed app: returns 1 (not installed)
APPS_DIR="$tmpdir/empty" mkdir -p "$tmpdir/empty"
APPS_DIR="$tmpdir/empty" is_already_installed "3.4.0" \
  && fail "should report not-installed when no .app present"
pass "is_already_installed returns false when nothing installed"

# Installed but version mismatch: returns 1
mock_plist "$tmpdir/v1" "3.3.0"
APPS_DIR="$tmpdir/v1" is_already_installed "3.4.0" \
  && fail "should report not-installed when versions differ"
pass "is_already_installed returns false on version mismatch"

# Installed and version matches: returns 0
mock_plist "$tmpdir/v2" "3.4.0"
APPS_DIR="$tmpdir/v2" is_already_installed "3.4.0" \
  || fail "should report installed when versions match"
pass "is_already_installed returns true on version match"

echo "All install.sh tests passed."
