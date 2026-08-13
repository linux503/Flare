#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build-universal"
APP_DIR="$ROOT/dist/Flare Pro.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
MIN_OS="14.0"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
BIN_NAME="FlarePro"

echo "==> Flare Pro Universal Build"
echo "    SDK: $SDK"
echo "    Root: $ROOT"

rm -rf "$BUILD_DIR" "$APP_DIR"
# 清理旧产物名
rm -rf "$ROOT/dist/Snap.app"
mkdir -p "$BUILD_DIR" "$MACOS" "$RESOURCES"

SOURCES=()
while IFS= read -r f; do
  SOURCES+=("$f")
done < <(find "$ROOT/Sources/Flare" -name '*.swift' | sort)

build_arch_main() {
  local arch="$1"
  local out="$BUILD_DIR/${BIN_NAME}-$arch"
  echo "==> Compiling ${arch}..."
  xcrun swiftc \
    -sdk "$SDK" \
    -target "${arch}-apple-macos${MIN_OS}" \
    -O \
    -swift-version 5 \
    -strict-concurrency=minimal \
    -framework AppKit \
    -framework SwiftUI \
    -framework ScreenCaptureKit \
    -framework Vision \
    -framework AVFoundation \
    -framework Carbon \
    -framework CoreGraphics \
    -framework UniformTypeIdentifiers \
    -o "$out" \
    "${SOURCES[@]}"
}

HOST_ARCH="$(uname -m)"
build_arch_main "$HOST_ARCH"

OTHER_ARCH=""
if [[ "$HOST_ARCH" == "arm64" ]]; then
  OTHER_ARCH="x86_64"
elif [[ "$HOST_ARCH" == "x86_64" ]]; then
  OTHER_ARCH="arm64"
fi

UNIVERSAL_OUT="$BUILD_DIR/$BIN_NAME"
if [[ -n "$OTHER_ARCH" ]]; then
  # Intel / Apple Silicon 双架构必过，避免只打出单切片
  if ! build_arch_main "$OTHER_ARCH"; then
    echo "!! ERROR: $OTHER_ARCH 交叉编译失败，Universal（含 Intel）构建中止"
    exit 1
  fi
  echo "==> Creating universal binary (arm64 + x86_64)..."
  lipo -create \
    "$BUILD_DIR/${BIN_NAME}-arm64" \
    "$BUILD_DIR/${BIN_NAME}-x86_64" \
    -output "$UNIVERSAL_OUT"
else
  cp "$BUILD_DIR/${BIN_NAME}-$HOST_ARCH" "$UNIVERSAL_OUT"
fi

cp "$UNIVERSAL_OUT" "$MACOS/$BIN_NAME"
chmod +x "$MACOS/$BIN_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
echo -n "APPLFLAR" > "$CONTENTS/PkgInfo"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS/Info.plist"
fi

# 菜单栏小图 + 应用内 Logo（Brand / 状态栏回退）
if [[ -f "$ROOT/Resources/StatusBarIcon.png" ]]; then
  cp "$ROOT/Resources/StatusBarIcon.png" "$RESOURCES/StatusBarIcon.png"
elif [[ -f "$ROOT/Resources/FlareIcon.png" ]]; then
  sips -z 128 128 "$ROOT/Resources/FlareIcon.png" --out "$RESOURCES/StatusBarIcon.png" >/dev/null
fi
if [[ -f "$ROOT/Resources/FlareIcon.png" ]]; then
  # 缩到 256 边长再打包，兼顾清晰度与体积
  sips -z 256 256 "$ROOT/Resources/FlareIcon.png" --out "$RESOURCES/FlareIcon.png" >/dev/null
fi

xattr -cr "$APP_DIR" 2>/dev/null || true

if command -v codesign >/dev/null; then
  echo "==> Ad-hoc codesign (stable identifier)..."
  codesign --force --deep --sign - \
    --identifier "app.flare.screenshot" \
    --entitlements "$ROOT/Resources/Flare.entitlements" \
    "$APP_DIR" || true
fi

echo "==> Done: $APP_DIR"
lipo -info "$MACOS/$BIN_NAME" || true
echo ""
echo "推荐安装："
echo "  ./Scripts/install.sh"
echo "或直接运行："
echo "  open \"$APP_DIR\""
echo "首次使用请授予「屏幕录制」权限后重启 Flare Pro。"
