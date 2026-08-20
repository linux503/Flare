<p align="center">
  <img src="docs/logo.png" width="88" height="88" alt="Flare Pro" />
</p>

<h1 align="center">Flare Pro</h1>

<p align="center">
  <strong>Capture in a flash</strong> — native macOS screenshot and screen recorder<br/>
  Menu-bar click to capture · dedicated recording menu · annotate / OCR / pin / history
</p>

<p align="center">
  <a href="README.md">中文</a> · <b>English</b>
</p>

<p align="center">
  <a href="https://github.com/linux503/Flare/releases/latest"><img src="https://img.shields.io/github/v/release/linux503/Flare?style=flat-square&color=111111" alt="Release" /></a>
  <a href="https://github.com/linux503/Flare/releases"><img src="https://img.shields.io/badge/macOS-14%2B-0f9f6e?style=flat-square" alt="macOS 14+" /></a>
  <a href="https://github.com/linux503/Flare/releases"><img src="https://img.shields.io/badge/Universal-arm64%20%2B%20x86__64-24292f?style=flat-square" alt="Universal" /></a>
</p>

<p align="center">
  <a href="https://github.com/linux503/Flare/releases/download/v1.3.6/Flare-Pro-1.3.6-Universal.dmg"><strong>Download DMG</strong></a>
  ·
  <a href="https://linux503.github.io/Flare/">Website</a>
  ·
  <a href="https://github.com/linux503/Flare/releases">All releases</a>
</p>

---

<p align="center">
  <img src="docs/poster-capture.jpg" alt="Screenshot" width="270" />
  <img src="docs/poster-record.jpg" alt="Recording" width="270" />
  <img src="docs/poster-annotate.jpg" alt="Annotation" width="270" />
</p>

<p align="center"><sub>Capture · Record · Annotate</sub></p>

---

## What it does

Flare Pro is a native macOS screen tool: capture fast, record cleanly, annotate in place. No Electron. One Universal binary for Apple Silicon and Intel.

| Area | Details |
|------|---------|
| **Screenshot** | Region, window, full screen, 3s delay. Magnifier, color picker, size readout. Confirm with Space / Return / double-click |
| **Recording** | Full screen or region, H.264 MOV. Audio: off / system / microphone / both (off by default) |
| **Annotate** | Pen, highlight, arrow, line, rectangle, ellipse, text, mosaic, numbers, steps |
| **OCR** | Recognize text and export TXT |
| **Pin** | Keep a shot on the desktop for reference |
| **History** | Three-column cards; click to edit, copy, or delete |
| **New file** | Create TXT / Word / PPT / Excel in one tap |
| **Appearance** | Light / dark translucent themes, window opacity, in-app update check |

### Screenshots

- **Click** the menu-bar icon to start a region capture
- After capture: open editor, copy to clipboard, save to file, or pin on screen
- Clipboard copy, shutter sound, and magnifier are optional
- Formats: PNG / JPEG / TIFF; save folder is configurable

### Recording

- Record menu, main-panel Record tab, and a red menu-bar timer
- Quality: 720p / 1080p / native / high bitrate
- Frame rate 15 / 24 / 30 / 60; countdown off / 3 / 5 / 10 seconds
- Show cursor, exclude Flare windows, hide the app when recording starts
- The floating timer is **not** captured in the video; pauses skip the timeline instead of freezing frames
- `Esc` stops from any app; quitting while recording asks save / discard / cancel

### Main window

Sidebar: **Capture** · **Record** · **New** · **History** · **Settings**. Open with the Dock icon or `⌘O`.

---

## Shortcuts

Defaults use **⌘⌥** so they do not collide with system capture ⌘⇧3 / 4 / 5. Change them in Settings → Shortcuts.

| Action | Default |
|--------|---------|
| Region capture | `⌘⌥5` |
| Full screen | `⌘⌥4` |
| Window | `⌘⌥6` |
| Delayed capture | `⌘⌥3` |
| Start / stop recording | `⌘⌥R` |
| History | `⌘⌥H` |
| Main window | `⌘O` |
| Confirm selection | `Space` / `Return` / double-click |
| Stop recording | `Esc` |
| Pause / resume | `⌘P` |

**Right-click** the menu-bar icon for the full menu.

---

## Install

1. Download [Flare-Pro-1.3.6-Universal.dmg](https://github.com/linux503/Flare/releases/download/v1.3.6/Flare-Pro-1.3.6-Universal.dmg)
2. Drag **Flare Pro** into Applications
3. Always run `/Applications/Flare Pro.app` (not a copy from `dist/`)

Requires **macOS 14.0** or later.

### Screen Recording permission

Capture and recording both need Screen Recording:

1. **System Settings → Privacy & Security → Screen & System Audio Recording**
2. Enable **Flare Pro** (delete any grey leftover entry first)
3. **Quit fully** and reopen; the app relaunches itself after you grant access

Microphone permission is requested only if you record with the mic.

Build scripts sign with your local Apple Development identity, so reinstalling on the same Mac usually does not need another grant.

---

## Build from source

Needs macOS 14+ and Xcode Command Line Tools.

```bash
git clone https://github.com/linux503/Flare.git
cd Flare
./Scripts/build.sh      # Universal .app → dist/Flare Pro.app
./Scripts/install.sh    # Install to /Applications
./Scripts/make_dmg.sh   # Optional DMG
```

| Path | Contents |
|------|----------|
| `Sources/Flare/` | SwiftUI / AppKit source |
| `Resources/` | Info.plist, icons |
| `Scripts/` | Build, sign, install, package |
| `docs/` | GitHub Pages site and update feed |

The app checks [`docs/version.json`](docs/version.json) from Settings → About.

Enable the site: repo Settings → Pages → `main` / `/docs`.

---

## Other apps

| App | Role |
|-----|------|
| [ZipX](https://github.com/linux503/ZipX) | Compress / extract / preview |
| [MacText](https://github.com/linux503/MacText) | Native text editor |
| [SupTools](https://github.com/linux503/suptools) | Monitor, clean, uninstall |
| [FilesDesk](https://github.com/linux503/FilesDesk) | Batch rename |
| [MacFan](https://github.com/linux503/MacFan) | Fan control |

---

## License

Personal use and learning are welcome. Contact the owner before commercial redistribution. Issues: [GitHub Issues](https://github.com/linux503/Flare/issues).
