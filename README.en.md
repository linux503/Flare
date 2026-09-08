<p align="center">
  <img src="docs/logo.png" width="96" height="96" alt="Flare Pro" />
</p>

<h1 align="center">Flare Pro</h1>

<p align="center">
  <strong>Capture in one shot</strong><br/>
  Native macOS screenshot · recording · privacy redaction · webpage evidence<br/>
  Windows / Android for scrolling webpage stitches
</p>

<p align="center">
  <a href="README.md">中文</a> · <b>English</b>
</p>

<p align="center">
  <a href="https://github.com/linux503/Flare/releases/latest"><img src="https://img.shields.io/github/v/release/linux503/Flare?style=flat-square&color=0c6b4d" alt="Release" /></a>
  <a href="https://linux503.github.io/Flare/"><img src="https://img.shields.io/badge/Website-linux503.github.io-148a66?style=flat-square" alt="Website" /></a>
  <a href="https://github.com/linux503/Flare/releases"><img src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square" alt="macOS 14+" /></a>
  <a href="https://github.com/linux503/Flare/releases"><img src="https://img.shields.io/badge/Universal-arm64%20%2B%20x86__64-24292f?style=flat-square" alt="Universal" /></a>
</p>

<p align="center">
  <a href="https://linux503.github.io/Flare/downloads/Flare-Pro-1.3.19-Universal.dmg"><strong>macOS DMG</strong></a>
  ·
  <a href="https://github.com/linux503/Flare/releases/download/v1.3.19/Flare-Windows-x64.exe"><strong>Windows EXE</strong></a>
  ·
  <a href="https://linux503.github.io/Flare/downloads/Flare-Android.apk"><strong>Android APK</strong></a>
  ·
  <a href="https://linux503.github.io/Flare/">Website</a>
</p>

---

<p align="center">
  <img src="docs/ui-home.jpg" alt="Capture home" width="860" />
</p>

<p align="center"><sub>Main panel · region / window / display / long shot</sub></p>

<p align="center">
  <img src="docs/ui-record.jpg" alt="Recording" width="420" />
  &nbsp;
  <img src="docs/ui-evidence.jpg" alt="Webpage evidence" width="420" />
</p>

<p align="center"><sub>Recording · Webpage evidence snapshot</sub></p>

---

## Highlights

| | |
|---|---|
| **Full capture kit** | Region, window, display, delay, long screenshot — double-click follows your after-capture setting |
| **Recording on its own** | Full screen or region, optional system audio, H.264 MOV; floating timer stays out of the video |
| **Privacy mode** | On-device scan for API keys, seed phrases, private keys, wallets, cards, IDs, email, phone, QR, tokens — share redacted or keep original local |
| **Webpage evidence** | URL, time, long shot, hashes, certificate; block height when recognized; timeline PDF (business archive only — not legal proof) |
| **New documents** | One-tap blank TXT / Word / PPT / Excel |
| **Cross-platform stitch** | Windows EXE and Android APK auto-scroll a page into one long image |

---

## Features

### macOS

- **Capture**: click the menu-bar icon for region capture; right-click for the full menu  
- **Record**: Record menu, red status timer, `⌘⌥R` to toggle  
- **Annotate / OCR / Pin / History**: edit, recognize, pin, and review in one flow  
- **Privacy**: Settings → Privacy for scan + optional auto-redact  
- **Evidence**: open “Webpage evidence snapshot”, paste a URL, export an archive pack  

### Windows / Android

- Download and run — no heavy setup  
- Open a URL, auto-scroll, stitch a long image  
- Handy for product pages, chats, and docs  

---

## Shortcuts (macOS)

Defaults use **⌘⌥** so they avoid system capture ⌘⇧3 / 4 / 5. Change them in Settings → Shortcuts.

| Action | Default |
|--------|---------|
| Region capture | `⌘⌥5` |
| Full screen | `⌘⌥4` |
| Window | `⌘⌥6` |
| Delayed capture | `⌘⌥3` |
| Start / stop recording | `⌘⌥R` |
| New document | `⌘⇧D` |
| History | `⌘⌥H` |
| Main window | `⌘O` |
| Confirm selection | `Space` / `Return` / double-click |
| Stop recording | `Esc` |
| Pause / resume | `⌘P` |

---

## Install

### macOS 1.3.19

1. Download [Flare-Pro-1.3.19-Universal.dmg](https://linux503.github.io/Flare/downloads/Flare-Pro-1.3.19-Universal.dmg)  
2. Drag **Flare Pro** into Applications  
3. Always run `/Applications/Flare Pro.app`  

Requires **macOS 14+** (Universal: Apple Silicon + Intel).

**Screen Recording**

1. System Settings → Privacy & Security → Screen & System Audio Recording  
2. Enable **Flare Pro** (remove any grey leftover first)  
3. Quit fully and reopen; the app relaunches after you grant access  

### Windows / Android

- [Flare-Windows-x64.exe](https://github.com/linux503/Flare/releases/download/v1.3.19/Flare-Windows-x64.exe) — double-click  
- [Flare-Android.apk](https://linux503.github.io/Flare/downloads/Flare-Android.apk) — allow unknown sources, then install  

---

## Build from source

```bash
git clone https://github.com/linux503/Flare.git
cd Flare
./Scripts/build.sh      # → dist/Flare Pro.app
./Scripts/install.sh    # Install to /Applications
./Scripts/make_dmg.sh   # Optional DMG
```

| Path | Contents |
|------|----------|
| `Sources/Flare/` | SwiftUI / AppKit |
| `Resources/` | Info.plist, icons |
| `Scripts/` | Build, sign, install, package |
| `docs/` | GitHub Pages site and [`version.json`](docs/version.json) |

---

## Other apps

| App | Role |
|-----|------|
| [ZipX](https://github.com/linux503/ZipX) | Compress / extract / preview |
| [MacText](https://github.com/linux503/MacText) | Native text editor |
| [SupTools](https://github.com/linux503/suptools) | Monitor, clean, uninstall |
| [FilesDesk](https://github.com/linux503/FilesDesk) | Batch rename |
| [MacFan](https://github.com/linux503/MacFan) | Fan control |
| [BattyBar](https://github.com/linux503/BattyBar) | Battery |
| [RemoteX](https://github.com/linux503/RemoteX) | Remote desktop |

---

## License

Personal use and learning are welcome. Contact the owner before commercial redistribution. Issues: [GitHub Issues](https://github.com/linux503/Flare/issues).
