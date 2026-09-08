# Flare Pro website (GitHub Pages)

- Site: https://linux503.github.io/Flare/
- Update feed: https://linux503.github.io/Flare/version.json
- Product README: [中文](../README.md) · [English](../README.en.md)

Pages source: branch `main`, folder `/docs`.

When shipping a release, update:

1. `Resources/Info.plist` and `FlareBrand.version`
2. `docs/version.json` — set `downloadURL` to the site DMG  
   `https://linux503.github.io/Flare/downloads/Flare-Pro-X.Y.Z-Universal.dmg`  
   Also copy the DMG/APK into `docs/downloads/` and upload EXE to the GitHub release.
3. Fallback version strings in `docs/index.html`
