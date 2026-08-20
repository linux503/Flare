#!/bin/zsh
# 一次性配置：Developer ID 证书 + notarytool 凭证，之后打包即可过 Gatekeeper。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM_ID="${FLARE_TEAM_ID:-NFYZYS2VLL}"
PROFILE="${FLARE_NOTARY_PROFILE:-FlareNotary}"

echo "============================================"
echo " Flare Pro 公证配置（消除恶意软件提示）"
echo " Team: $TEAM_ID"
echo "============================================"
echo ""

has_dev_id=0
if security find-identity -v -p codesigning | grep -q 'Developer ID Application:'; then
  has_dev_id=1
  echo "✅ 已找到 Developer ID Application 证书："
  security find-identity -v -p codesigning | grep 'Developer ID Application:' || true
else
  echo "❌ 还没有 Developer ID Application 证书（当前只有 Apple Development，下载安装会被拦截）"
  echo ""
  echo "请按下面做（约 1 分钟）："
  echo "  1. 打开 Xcode → Settings… → Accounts"
  echo "  2. 选中 Apple ID（Liang Qi / Team NFYZYS2VLL）"
  echo "  3. 点 Manage Certificates…"
  echo "  4. 左下角 + → Developer ID Application"
  echo ""
  echo "正在打开 Xcode 设置…"
  open -a Xcode
  open "x-apple.systempreferences:" 2>/dev/null || true
  # 也打开开发者后台证书页作为备选
  open "https://developer.apple.com/account/resources/certificates/list"
  echo ""
  echo -n "创建完成后按回车继续…"
  read -r _
  if ! security find-identity -v -p codesigning | grep -q 'Developer ID Application:'; then
    echo "!! 仍未检测到 Developer ID Application。请确认已创建并安装到「登录」钥匙串。" >&2
    exit 1
  fi
  has_dev_id=1
fi

IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/^[[:space:]]*[0-9]*)[[:space:]]*[A-F0-9]*[[:space:]]*"\(Developer ID Application: .*\)"$/\1/p' | head -1)"
print -r -- "$IDENTITY" > "$ROOT/.codesign-identity"
echo "已写入 .codesign-identity → $IDENTITY"
echo ""

# 检查 notary 凭证
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "✅ notarytool 凭证已就绪 (profile: $PROFILE)"
else
  echo "需要配置 Apple 公证凭证（一次性）"
  echo "请先去生成 App 专用密码："
  echo "  https://appleid.apple.com/account/manage → 登录与安全 → App 专用密码"
  echo ""
  open "https://appleid.apple.com/account/manage"
  echo ""
  echo -n "Apple ID 邮箱: "
  read -r APPLE_ID
  echo -n "App 专用密码 (xxxx-xxxx-xxxx-xxxx): "
  read -r APP_PASSWORD
  if [[ -z "$APPLE_ID" || -z "$APP_PASSWORD" ]]; then
    echo "!! 需要 Apple ID 和 App 专用密码" >&2
    exit 1
  fi
  xcrun notarytool store-credentials "$PROFILE" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD"
  echo "✅ 已保存钥匙串凭证: $PROFILE"
fi

echo ""
echo "配置完成。接下来打包并公证："
echo "  ./Scripts/make_dmg.sh"
echo "  ./Scripts/notarize.sh dist/Flare-Pro-*-Universal.dmg"
echo ""
echo "或一次完成（make_dmg 末尾会尝试自动公证）："
echo "  NOTARIZE=1 ./Scripts/make_dmg.sh"
