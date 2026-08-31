#!/bin/zsh
# 构建可提交到 Mac App Store 的 .pkg
# 前置：Apple Developer Program +「Apple Distribution」证书 + Mac App Store 描述文件
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Flare Pro.app"
PKG="$DIST/Flare-Pro-MAS.pkg"
ENTITLEMENTS="$ROOT/Resources/Flare-MAS.entitlements"
BUNDLE_ID="app.flare.screenshot"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/Resources/Info.plist")"

echo "==> Flare Pro Mac App Store 打包"
echo "    版本: $VERSION ($BUILD)"

# 1) 找 Mac App Store 发行证书
pick_mas_identity() {
  local id=""
  id="$(security find-identity -v -p codesigning | sed -n 's/^[[:space:]]*[0-9]*)[[:space:]]*[A-F0-9]*[[:space:]]*"\(Apple Distribution: .*\)"$/\1/p' | head -1)"
  if [[ -z "$id" ]]; then
    id="$(security find-identity -v -p codesigning | sed -n 's/^[[:space:]]*[0-9]*)[[:space:]]*[A-F0-9]*[[:space:]]*"\(3rd Party Mac Developer Application: .*\)"$/\1/p' | head -1)"
  fi
  print -r -- "$id"
}

pick_installer_identity() {
  # Installer 证书不出现在 -p codesigning 列表里
  local id=""
  id="$(security find-identity -v | sed -n 's/^[[:space:]]*[0-9]*)[[:space:]]*[A-F0-9]*[[:space:]]*"\(3rd Party Mac Developer Installer: .*\)"$/\1/p' | head -1)"
  print -r -- "$id"
}

APP_ID="$(pick_mas_identity)"
INST_ID="$(pick_installer_identity)"

if [[ -z "$APP_ID" ]]; then
  cat >&2 <<'EOF'
!! 未找到 Mac App Store 发行证书（Apple Distribution / 3rd Party Mac Developer Application）

请先完成：
  1. https://developer.apple.com/account → Certificates
  2. 创建「Apple Distribution」证书并安装到「登录」钥匙串
  3. Identifiers 确认 app.flare.screenshot 已启用 App Sandbox
  4. Profiles 创建 Mac App Store 类型的描述文件并下载双击安装

详细步骤见：docs/MAC_APP_STORE.md
EOF
  exit 1
fi

echo "==> App 签名身份: $APP_ID"
if [[ -n "$INST_ID" ]]; then
  echo "==> Installer 签名身份: $INST_ID"
else
  echo "!! 未找到 Installer 证书，将仅产出已签名的 .app（可用 Transporter / Xcode Organizer 再封装）"
fi

# 2) 用 MAS 宏重新构建
export FLARE_MAS=1
export FLARE_ENTITLEMENTS="$ENTITLEMENTS"
export FLARE_CODESIGN_IDENTITY="$APP_ID"

# 临时改 build：加上 -D FLARE_MAS，并用 MAS entitlements 签名
BUILD_DIR="$ROOT/.build-mas"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
MIN_OS="14.0"
BIN_NAME="FlarePro"
HOST="$(uname -m)"

SOURCES=()
while IFS= read -r f; do
  SOURCES+=("$f")
done < <(find "$ROOT/Sources/Flare" -name '*.swift' | sort)

build_one() {
  local arch="$1"
  echo "==> Compiling ${arch} (MAS)…"
  xcrun swiftc \
    -sdk "$SDK" \
    -target "${arch}-apple-macos${MIN_OS}" \
    -O \
    -D FLARE_MAS \
    -swift-version 5 \
    -strict-concurrency=minimal \
    -framework AppKit \
    -framework SwiftUI \
    -framework ScreenCaptureKit \
    -framework Vision \
    -framework AVFoundation \
    -framework Carbon \
    -framework CoreGraphics \
    -framework QuartzCore \
    -framework UniformTypeIdentifiers \
    -o "$BUILD_DIR/${BIN_NAME}-$arch" \
    "${SOURCES[@]}"
}

build_one "$HOST"
OTHER=""
if [[ "$HOST" == "arm64" ]]; then OTHER="x86_64"; else OTHER="arm64"; fi
build_one "$OTHER"
lipo -create "$BUILD_DIR/${BIN_NAME}-arm64" "$BUILD_DIR/${BIN_NAME}-x86_64" -output "$BUILD_DIR/$BIN_NAME"

# 3) 组装 .app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
chmod +x "$APP/Contents/MacOS/$BIN_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :FlareDistribution string mas" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :FlareDistribution mas" "$APP/Contents/Info.plist"
echo -n "APPLFLAR" > "$APP/Contents/PkgInfo"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
if [[ -f "$ROOT/Resources/StatusBarIcon.png" ]]; then
  cp "$ROOT/Resources/StatusBarIcon.png" "$APP/Contents/Resources/StatusBarIcon.png"
fi
if [[ -f "$ROOT/Resources/FlareIcon.png" ]]; then
  sips -z 256 256 "$ROOT/Resources/FlareIcon.png" --out "$APP/Contents/Resources/FlareIcon.png" >/dev/null
fi
for logo in LogoSpark LogoIris LogoBolt LogoDusk LogoCoral; do
  if [[ -f "$ROOT/Resources/${logo}.png" ]]; then
    sips -z 256 256 "$ROOT/Resources/${logo}.png" --out "$APP/Contents/Resources/${logo}.png" >/dev/null
  fi
done

xattr -cr "$APP" 2>/dev/null || true

# 嵌入描述文件（若有）
PROVISION=""
for cand in \
  "$ROOT/Resources/Flare_MacAppStore.provisionprofile" \
  "$ROOT/Resources/embedded.provisionprofile" \
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.provisionprofile
do
  if [[ -f "$cand" ]]; then
    # 粗检是否含 bundle id
    if security cms -D -i "$cand" 2>/dev/null | grep -q "$BUNDLE_ID"; then
      PROVISION="$cand"
      break
    fi
  fi
done

if [[ -n "$PROVISION" ]]; then
  echo "==> 嵌入描述文件: $PROVISION"
  cp "$PROVISION" "$APP/Contents/embedded.provisionprofile"
else
  echo "!! 未找到匹配 $BUNDLE_ID 的 Mac App Store 描述文件"
  echo "   请从 developer.apple.com 下载后放到 Resources/Flare_MacAppStore.provisionprofile"
fi

echo "==> Codesign (MAS)…"
codesign --force --sign "$APP_ID" \
  --identifier "$BUNDLE_ID" \
  --entitlements "$ENTITLEMENTS" \
  --options runtime \
  --timestamp \
  "$APP"
codesign --verify --strict "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Identifier=|Authority=|TeamIdentifier=' || true

# 4) 打 .pkg
if [[ -n "$INST_ID" ]]; then
  echo "==> productbuild…"
  rm -f "$PKG"
  productbuild \
    --component "$APP" /Applications \
    --sign "$INST_ID" \
    "$PKG"
  echo ""
  echo "✅ MAS 安装包已生成"
  echo "   $PKG"
  echo ""
  echo "下一步："
  echo "  1. 打开 Transporter（Mac App Store 下载）登录你的开发者账号"
  echo "  2. 拖入上述 .pkg 上传"
  echo "  3. 到 App Store Connect 填写元数据并提交审核"
  echo "  详见 docs/MAC_APP_STORE.md"
else
  echo ""
  echo "✅ MAS .app 已签名: $APP"
  echo "   缺少 Installer 证书，请用 Xcode / Transporter 继续封装上传"
fi
