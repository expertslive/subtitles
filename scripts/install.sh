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

# Verifies every payload file in $1 against $1/SHA256SUMS.
# Aborts (non-zero) on any mismatch or if SHA256SUMS is missing.
verify_sums() {
  local dir="$1"
  local sumfile="$dir/SHA256SUMS"
  if [[ ! -f "$sumfile" ]]; then
    err "SHA256SUMS not found at $sumfile"
    return 1
  fi
  ( cd "$dir" && shasum -a 256 -c SHA256SUMS --status )
}

# Prints one profile filename per line, skipping blanks and #-comments.
# Prints nothing (exit 0) when MANIFEST.profiles is absent — "no profiles ship".
read_profile_manifest() {
  local dir="$1"
  local file="$dir/MANIFEST.profiles"
  [[ -f "$file" ]] || return 0
  # Strip CR (in case of CRLF), then drop blank lines and comments.
  tr -d '\r' < "$file" | sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d'
}

require_macos() {
  [[ "$(uname)" == "Darwin" ]] \
    || die "this installer only supports macOS (uname=$(uname))" \
           "run install.sh on the target event Mac"
}

require_streamdeck_app() {
  [[ -d "/Applications/Elgato Stream Deck.app" ]] \
    || die "Elgato Stream Deck app not found at /Applications/Elgato Stream Deck.app" \
           "install Elgato Stream Deck first: https://www.elgato.com/downloads"
}

# Downloads a single asset from $base into $dir. Returns 0 on HTTP 200,
# 22 (curl's HTTP-error code) on 404, anything else on transport failure.
download_asset() {
  local base="$1" name="$2" dir="$3"
  curl -fsSL --retry 3 --retry-delay 2 -o "$dir/$name" "${base}${name}"
}

# Same as download_asset but treats HTTP 404 as "not present" (returns 0)
# rather than an error, used for optional assets like MANIFEST.profiles.
download_optional_asset() {
  local base="$1" name="$2" dir="$3"
  local status
  status="$(curl -fsSL --retry 3 --retry-delay 2 \
    -o "$dir/$name" -w '%{http_code}' "${base}${name}" || true)"
  case "$status" in
    200) return 0 ;;
    404) rm -f "$dir/$name"; return 0 ;;
    *)   return 1 ;;
  esac
}

fetch_version_text() {
  local base="$1" dir="$2"
  download_asset "$base" "VERSION" "$dir" \
    || die "could not fetch VERSION from $base" \
           "check the release exists at https://github.com/${REPO_OWNER}/${REPO_NAME}/releases"
  tr -d '\r\n' < "$dir/VERSION"
}

download_all_assets() {
  local base="$1" dir="$2"
  log "downloading EventSubtitles.zip"
  download_asset "$base" "EventSubtitles.zip" "$dir" \
    || die "failed to download EventSubtitles.zip" "check network connectivity"
  log "downloading EventSubtitles.streamDeckPlugin"
  download_asset "$base" "EventSubtitles.streamDeckPlugin" "$dir" \
    || die "failed to download EventSubtitles.streamDeckPlugin"
  log "downloading SHA256SUMS"
  download_asset "$base" "SHA256SUMS" "$dir" \
    || die "failed to download SHA256SUMS"
  log "checking for optional MANIFEST.profiles"
  download_optional_asset "$base" "MANIFEST.profiles" "$dir" \
    || die "transport error fetching MANIFEST.profiles"

  local profile
  while IFS= read -r profile; do
    [[ -z "$profile" ]] && continue
    log "downloading profile: $profile"
    download_asset "$base" "$profile" "$dir" \
      || die "failed to download profile $profile"
  done < <(read_profile_manifest "$dir")
}

quit_running_app() {
  local bid="com.eventsubtitles.app"
  # Is it running? pgrep -lf matches the binary path; bail early if not.
  if ! pgrep -f "/Applications/EventSubtitles.app/Contents/MacOS/EventSubtitles" >/dev/null 2>&1; then
    return 0
  fi
  log "asking EventSubtitles to quit"
  osascript -e "tell application id \"$bid\" to quit" >/dev/null 2>&1 || true
  # Wait up to ~5 seconds for the process to disappear.
  local i
  for i in 1 2 3 4 5; do
    sleep 1
    pgrep -f "/Applications/EventSubtitles.app/Contents/MacOS/EventSubtitles" >/dev/null 2>&1 \
      || return 0
  done
  die "EventSubtitles is still running and refuses to quit" \
      "quit it manually (Cmd+Q in the app or Force Quit) and re-run installer"
}

install_app() {
  local dir="$1"
  local dest="$APPS_DIR/EventSubtitles.app"

  log "unzipping app bundle"
  ( cd "$dir" && unzip -q -o EventSubtitles.zip )

  local sudo_prefix=""
  if [[ -e "$dest" && ! -w "$dest" ]] || [[ ! -w "$APPS_DIR" ]]; then
    log "$APPS_DIR not writable; using sudo for ditto"
    sudo_prefix="sudo"
  fi

  log "installing to $dest"
  $sudo_prefix rm -rf "$dest"
  $sudo_prefix ditto "$dir/EventSubtitles.app" "$dest"
}

install_plugin() {
  local dir="$1"
  log "opening EventSubtitles.streamDeckPlugin for Stream Deck install prompt"
  open "$dir/EventSubtitles.streamDeckPlugin"
}

stage_profiles() {
  local dir="$1"
  local downloads="$HOME/Downloads"
  local manifest_out
  manifest_out="$(read_profile_manifest "$dir")"
  [[ -z "$manifest_out" ]] && return 0

  mkdir -p "$downloads"
  local profile
  while IFS= read -r profile; do
    [[ -z "$profile" ]] && continue
    log "staging profile to $downloads/$profile"
    cp "$dir/$profile" "$downloads/$profile"
  done <<< "$manifest_out"
}

print_summary() {
  local version="$1"
  cat <<EOF

[install] Done. Installed EventSubtitles $version.

Next steps (one-time, per Mac):
  1. Open Finder → Applications → right-click EventSubtitles → Open → Open.
     (Required once because the binary is unsigned.)
  2. Confirm the Stream Deck install prompt in the Elgato Stream Deck app.
  3. (Optional) Double-click any *.streamDeckProfile file in ~/Downloads to
     import the bundled key layout.
  4. Launch EventSubtitles and verify Stream Deck keys flip from
     APP OFFLINE to live status.

EOF
}

main() {
  parse_args "$@"

  require_macos
  require_streamdeck_app

  local base
  base="$(resolve_base_url)"
  log "using base URL: $base"

  local workdir
  workdir="$(mktemp -d -t eventsubtitles_install.XXXXXX)"
  # shellcheck disable=SC2064
  trap "rm -rf '$workdir'" EXIT

  log "fetching VERSION"
  local want
  want="$(fetch_version_text "$base" "$workdir")"
  log "target version: $want"

  if is_already_installed "$want" && [[ "$OPT_REINSTALL" == "0" ]]; then
    log "EventSubtitles $want is already installed (pass --reinstall to force)"
    exit 0
  fi

  download_all_assets "$base" "$workdir"

  log "verifying SHA-256 sums"
  verify_sums "$workdir" \
    || die "SHA-256 verification failed — refusing to install" \
           "re-run the installer; if it still fails, file an issue with the version"

  if [[ "$OPT_DRY_RUN" == "1" ]]; then
    log "dry-run complete; no filesystem changes were made"
    exit 0
  fi

  quit_running_app
  install_app "$workdir"
  install_plugin "$workdir"
  stage_profiles "$workdir"
  print_summary "$want"
}

# Skip main() when sourced for unit tests.
if [[ "${__TEST_MODE:-0}" != "1" ]]; then
  main "$@"
fi
