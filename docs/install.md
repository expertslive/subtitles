# Installing EventSubtitles on an Event Mac

The repository publishes a packaged `.app` and Stream Deck plugin on every
release tag. The installer is a small bash script attached to the same
release; it downloads, verifies, and installs everything in one command.

## Prerequisites

- macOS 14 (Sonoma) or later, Apple silicon.
- [Elgato Stream Deck](https://www.elgato.com/downloads) installed and
  launched at least once. The installer aborts if it is missing.

## Install the latest release

```bash
curl -fsSL https://github.com/expertslive/subtitles/releases/latest/download/install.sh | bash
```

## Pin a specific release

```bash
curl -fsSL https://github.com/expertslive/subtitles/releases/download/vX.Y.Z/install.sh \
  | bash -s -- --version vX.Y.Z
```

## Flags

| Flag | Behavior |
| --- | --- |
| `--version vX.Y.Z` | Install a specific tag. Default: latest stable. |
| `--reinstall` | Reinstall even if the same version is already present. |
| `--dry-run` | Resolve, download, and verify only. No filesystem changes. |
| `--help` | Show usage and exit. |

Environment-variable equivalents: `VERSION=vX.Y.Z`, `REINSTALL=1`, `DRY_RUN=1`.

## After the script finishes

1. **First launch** — open Finder → Applications → right-click
   `EventSubtitles` → **Open** → **Open**. macOS requires this once because
   the binary is unsigned. Subsequent launches use a normal double-click.
2. **Stream Deck plugin** — accept the install prompt the Elgato Stream Deck
   app shows after the script runs.
3. **Stream Deck profile** — if the release bundled any
   `*.streamDeckProfile` files, the installer staged them in `~/Downloads`.
   Double-click to import.
4. **Verify** — launch `EventSubtitles` and confirm the Stream Deck keys
   transition from `APP OFFLINE` to live status.

## Re-running the script

Re-running with no `--version` upgrades to the newest stable release. The
script is idempotent: running it with the same version that is already
installed is a no-op unless you pass `--reinstall`.

## Updating across multiple event Macs

Run the same one-liner on every Mac. No configuration files, tokens, or
SSH access are required; the installer pulls anonymously from the public
GitHub Release.
