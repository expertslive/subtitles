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

echo "All install.sh tests passed."
