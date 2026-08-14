# Flare Pro website (GitHub Pages)

- Site: https://linux503.github.io/Flare/
- Update feed: https://linux503.github.io/Flare/version.json
- Product README: [中文](../README.md) · [English](../README.en.md)

Pages source: branch `main`, folder `/docs`.

When shipping a release, update:

1. `Resources/Info.plist` and `FlareBrand.version`
2. `docs/version.json` — set `downloadURL` to the DMG asset  
   `https://github.com/linux503/Flare/releases/download/vX.Y.Z/Flare-Pro-X.Y.Z-Universal.dmg`
3. Fallback version strings in `docs/index.html`
