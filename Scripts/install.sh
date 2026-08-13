#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/dist/Flare Pro.app"
DEST="/Applications/Flare Pro.app"
BIN_NAME="FlarePro"

if [[ ! -f "$SRC/Contents/MacOS/$BIN_NAME" ]]; then
  echo "未找到构建产物，先执行 build…"
  "$ROOT/Scripts/build.sh"
fi

echo "==> 安装 Flare Pro 到 /Applications"
killall FlarePro 2>/dev/null || true
killall "Flare Pro" 2>/dev/null || true
killall Snap 2>/dev/null || true
killall Flare 2>/dev/null || true
# 顺带清掉从 dist 启动的残留
pkill -f "/Downloads/Flare/dist/Flare Pro.app" 2>/dev/null || true
sleep 0.3

# 清理旧名，避免 Dock 里多个图标 / 多份 TCC 条目
rm -rf /Applications/Flare.app
rm -rf /Applications/Snap.app
rm -rf "$DEST"
ditto "$SRC" "$DEST"
chmod +x "$DEST/Contents/MacOS/$BIN_NAME"

xattr -cr "$DEST" 2>/dev/null || true

codesign --force --deep --sign - \
  --identifier "app.flare.screenshot" \
  --entitlements "$ROOT/Resources/Flare.entitlements" \
  "$DEST"

# 清掉「自动重启已用过」粘性标记，避免权限修好后仍无法自动重启
defaults delete app.flare.screenshot flareDidAutoRelaunchForTCC 2>/dev/null || true

echo ""
echo "✅ 已安装: $DEST"
echo ""
echo "请完成屏幕录制授权（macOS 15+ 叫「屏幕与系统音频录制」）："
echo "  1. 系统设置 → 隐私与安全性 → 屏幕与系统音频录制"
echo "  2. 打开 Flare Pro（若有灰色旧条目：先 − 删除，再重新勾选）"
echo "  3. 必须完全退出再打开（打开开关后同一进程内截不了）"
echo "  4. 请只运行本路径：$DEST（不要用 dist/ 里的副本）"
echo ""

open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" 2>/dev/null || true
sleep 0.5
open "$DEST"
