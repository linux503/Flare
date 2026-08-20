#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build-stitch-test"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
HOST="$(uname -m)"
BIN="$OUT/stitch_test"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Compile stitch test harness"
xcrun swiftc \
  -sdk "$SDK" \
  -target "${HOST}-apple-macos14.0" \
  -O \
  -framework AppKit \
  -framework ApplicationServices \
  -framework CoreGraphics \
  -o "$BIN" \
  "$ROOT/Scripts/stubs/ScreenCapturerStub.swift" \
  "$ROOT/Sources/Flare/Capture/LongScreenshot.swift" \
  "$ROOT/Scripts/test_long_stitch_main.swift"

echo "==> Run"
cd "$ROOT"
"$BIN"
