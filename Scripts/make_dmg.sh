#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SRC="$ROOT/dist/Flare Pro.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist" 2>/dev/null || echo "1.1.0")"
STAGE="$ROOT/.dmg-stage"
VOL_NAME="Flare Pro"
DMG_NAME="Flare-Pro-${VERSION}-Universal.dmg"
OUT_DMG="$ROOT/dist/$DMG_NAME"
TMP_DMG="$ROOT/dist/.${DMG_NAME}.tmp.dmg"

echo "==> Flare Pro DMG 打包"
echo "    版本: $VERSION"
echo "    输出: $OUT_DMG"

# 1) 确保 Universal 构建最新（可用 SKIP_BUILD=1 跳过）
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "==> 重新构建 Universal App…"
  "$ROOT/Scripts/build.sh"
else
  echo "==> 跳过构建 (SKIP_BUILD=1)，使用现有 $APP_SRC"
fi

if [[ ! -d "$APP_SRC" ]]; then
  echo "!! 未找到 $APP_SRC"
  exit 1
fi

ARCHS="$(lipo -info "$APP_SRC/Contents/MacOS/FlarePro" 2>/dev/null || true)"
echo "    $ARCHS"
echo "$ARCHS" | grep -q "arm64" || { echo "!! 缺少 arm64"; exit 1; }
echo "$ARCHS" | grep -q "x86_64" || { echo "!! 缺少 x86_64 (Intel)"; exit 1; }

# 2) 准备 DMG 内容
rm -rf "$STAGE" "$TMP_DMG" "$OUT_DMG"
mkdir -p "$STAGE"
ditto "$APP_SRC" "$STAGE/Flare Pro.app"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/安装说明.txt" <<EOF
Flare Pro ${VERSION}  ·  Universal (Apple Silicon + Intel)

安装
1. 将「Flare Pro」拖到「Applications」文件夹
2. 打开「启动台」或 /Applications 中的 Flare Pro

首次使用
1. 系统设置 → 隐私与安全性 → 屏幕录制 → 打开 Flare Pro
2. 完全退出后再打开一次（授权后必须重启）

用法
· 菜单栏图标单击 = 区域截图
· 右键菜单栏图标 = 更多功能
· 选区确认后可编辑 / 复制 / 保存 / 钉住 / OCR

Bundle ID: app.flare.screenshot
EOF

xattr -cr "$STAGE" 2>/dev/null || true

# 3) 生成可写临时 DMG → 布局 → 压缩
SIZE_MB="$(du -sm "$STAGE" | awk '{print int($1)+28}')"
echo "==> 创建临时镜像 (${SIZE_MB} MB)…"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -fs HFS+ \
  -format UDRW \
  -size "${SIZE_MB}m" \
  "$TMP_DMG"

echo "==> 挂载并设置 Finder 布局…"
ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG" 2>&1)" || true
echo "$ATTACH_OUT"
# 卷名含空格：必须截取完整 /Volumes/... 路径
MOUNT_DIR="$(print -r -- "$ATTACH_OUT" | grep -o '/Volumes/.*' | tail -1 | sed 's/[[:space:]]*$//')"
DEV_NODE="$(print -r -- "$ATTACH_OUT" | awk '/^\/dev\//{print $1; exit}')"

if [[ -z "${MOUNT_DIR:-}" || ! -d "$MOUNT_DIR" ]]; then
  echo "!! 读写挂载失败，回退为直接压缩打包…"
  rm -f "$TMP_DMG"
  hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$OUT_DMG"
else
  echo "    挂载点: $MOUNT_DIR"
  sleep 1.2

  osascript <<APPLESCRIPT || true
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 160, 840, 560}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set position of item "Flare Pro.app" of container window to {160, 180}
    set position of item "Applications" of container window to {480, 180}
    try
      set position of item "安装说明.txt" of container window to {320, 360}
    end try
    update without registering applications
    delay 0.8
    close
  end tell
end tell
APPLESCRIPT

  sync
  if [[ -n "${MOUNT_DIR:-}" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
  fi
  if [[ -n "${DEV_NODE:-}" ]]; then
    hdiutil detach "$DEV_NODE" -quiet 2>/dev/null || hdiutil detach "$DEV_NODE" -force 2>/dev/null || true
  fi

  echo "==> 压缩为最终 DMG…"
  hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG"
  rm -f "$TMP_DMG"
fi

rm -rf "$STAGE"

if command -v codesign >/dev/null; then
  codesign --force --sign - "$OUT_DMG" 2>/dev/null || true
fi

echo ""
echo "✅ DMG 已生成"
echo "   $OUT_DMG"
ls -lh "$OUT_DMG"
echo ""
echo "内容："
echo "  · Flare Pro.app (Universal: arm64 + x86_64)"
echo "  · Applications 快捷方式（拖入即可安装）"
echo "  · 安装说明.txt"
echo ""
lipo -info "$APP_SRC/Contents/MacOS/FlarePro" || true
shasum -a 256 "$OUT_DMG" | awk '{print "SHA256: "$1}'
echo ""
echo "打开： open \"$OUT_DMG\""
