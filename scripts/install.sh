#!/usr/bin/env bash
# Install EventSubtitles.app and its Stream Deck plugin from a public
# GitHub Release. Designed for stock macOS: needs only curl, unzip, ditto,
# shasum, osascript, open, and plutil. Does not parse JSON.
#
# Usage:
#   install.sh [--version vX.Y.Z] [--reinstall] [--dry-run] [--help]
#
# Env-var equivalents: VERSION, REINSTALL=1, DRY_RUN=1.

set -euo pipefail

REPO_OWNER="expertslive"
REPO_NAME="subtitles"
APPS_DIR="${APPS_DIR:-/Applications}"

OPT_VERSION=""
OPT_REINSTALL=0
OPT_DRY_RUN=0

log()  { printf '[install] %s\n' "$*"; }
err()  { printf '[install] ERROR: %s\n' "$*" >&2; }
fix()  { printf '[install]   \xe2\x86\x92 fix: %s\n' "$*" >&2; }
die()  { err "$1"; shift; for hint in "$@"; do fix "$hint"; done; exit 1; }

usage() {
  cat <<'EOF'
Usage: install.sh [--version vX.Y.Z] [--reinstall] [--dry-run] [--help]

  --version vX.Y.Z   Install a specific release tag (default: latest stable).
  --reinstall        Install even if the same version is already installed.
  --dry-run          Resolve, download, and verify only. No filesystem changes.
  --help             Show this message and exit.

Env-var equivalents: VERSION, REINSTALL=1, DRY_RUN=1.
EOF
}

parse_args() {
  # Seed from env-vars first so CLI flags override them.
  OPT_VERSION="${VERSION:-$OPT_VERSION}"
  [[ "${REINSTALL:-0}" == "1" ]] && OPT_REINSTALL=1
  [[ "${DRY_RUN:-0}" == "1" ]] && OPT_DRY_RUN=1

  while (( $# > 0 )); do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || die "--version requires a tag like v1.2.3"
        OPT_VERSION="$2"
        shift 2
        ;;
      --reinstall) OPT_REINSTALL=1; shift ;;
      --dry-run)   OPT_DRY_RUN=1;   shift ;;
      --help|-h)   usage; exit 0 ;;
      *)
        die "unknown argument: $1" "run install.sh --help for usage"
        ;;
    esac
  done
}

resolve_base_url() {
  if [[ -n "$OPT_VERSION" ]]; then
    printf 'https://github.com/%s/%s/releases/download/%s/' \
      "$REPO_OWNER" "$REPO_NAME" "$OPT_VERSION"
  else
    printf 'https://github.com/%s/%s/releases/latest/download/' \
      "$REPO_OWNER" "$REPO_NAME"
  fi
}

# Returns 0 (success) when /Applications/EventSubtitles.app exists and its
# CFBundleShortVersionString equals the version argument. Returns 1 otherwise.
is_already_installed() {
  local want="$1"
  local plist="$APPS_DIR/EventSubtitles.app/Contents/Info.plist"
  [[ -f "$plist" ]] || return 1
  local have
  have="$(plutil -extract CFBundleShortVersionString raw -o - "$plist" 2>/dev/null || true)"
  [[ -n "$have" && "$have" == "$want" ]]
}

main() {
  parse_args "$@"
  log "EventSubtitles installer"
  log "(implementation continues in later tasks)"
}

# Skip main() when sourced for unit tests.
if [[ "${__TEST_MODE:-0}" != "1" ]]; then
  main "$@"
fi
