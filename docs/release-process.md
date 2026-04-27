# Release Process

## Policy

GitHub should only show the latest downloadable build.

When publishing a new GitHub release:

1. Build and validate the new app bundle.
2. Create the new release tag and GitHub release.
3. Upload the new `.zip` asset.
4. Verify the new release URL and asset checksum.
5. Delete the previous GitHub release and its tag.

This keeps the public download path simple for operators and prevents older event builds from being installed accidentally.

Historical release notes may remain in the repository under `docs/releases/`, but GitHub Releases should expose only the latest build unless there is a specific reason to keep an older build online.

## Validation Commands

Run these from the repository root before publishing:

```bash
swift build --product EventSubtitles
swift run EventSubtitlesSmokeTests
./scripts/build_app_bundle.sh
codesign --verify --deep --strict build/EventSubtitles.app
```

Create the release zip:

```bash
ditto -c -k --keepParent build/EventSubtitles.app build/EventSubtitles-vX.Y.Z-macos-arm64.zip
shasum -a 256 build/EventSubtitles-vX.Y.Z-macos-arm64.zip
```

Publish:

```bash
git tag -a vX.Y.Z -m "EventSubtitles vX.Y.Z"
git push origin main
git push origin vX.Y.Z
gh release create vX.Y.Z build/EventSubtitles-vX.Y.Z-macos-arm64.zip --title "EventSubtitles vX.Y.Z" --notes-file docs/releases/vX.Y.Z.md
```

After verifying the new release, remove the previous online release:

```bash
gh release delete vOLD --cleanup-tag --yes
```
