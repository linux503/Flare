#!/bin/zsh
# 对 .app / .dmg 做 Apple 公证并装订票据，消除「无法验证是否恶意软件」提示。
# 前置：
#   1) 钥匙串里有「Developer ID Application」证书
#   2) 已执行：xcrun notarytool store-credentials FlareNotary --apple-id ... --team-id NFYZYS2VLL --password ...
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:?usage: notarize.sh /path/to/App.app|/path/to.dmg}"
PROFILE="${FLARE_NOTARY_PROFILE:-FlareNotary}"
TEAM_ID="${FLARE_TEAM_ID:-NFYZYS2VLL}"

if [[ ! -e "$TARGET" ]]; then
  echo "!! 找不到: $TARGET" >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -q 'Developer ID Application:'; then
  echo "!! 未找到 Developer ID Application 证书。" >&2
  echo "!! 请先运行: ./Scripts/setup_notarization.sh" >&2
  exit 1
fi

IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/^[[:space:]]*[0-9]*)[[:space:]]*[A-F0-9]*[[:space:]]*"\(Developer ID Application: .*\)"$/\1/p' | head -1)"
print -r -- "$IDENTITY" > "$ROOT/.codesign-identity"

# 若是 .app，先用 Developer ID 重签
if [[ "$TARGET" == *.app ]]; then
  echo "==> 使用 Developer ID 重签 App…"
  FLARE_CODESIGN_IDENTITY="$IDENTITY" "$ROOT/Scripts/codesign_app.sh" "$TARGET"
fi

# DMG 也建议签名（可选但推荐）
if [[ "$TARGET" == *.dmg ]]; then
  echo "==> 签名 DMG…"
  codesign --force --sign "$IDENTITY" --timestamp "$TARGET" 2>/dev/null || true
fi

echo "==> 提交公证 ($PROFILE)…"
xcrun notarytool submit "$TARGET" \
  --keychain-profile "$PROFILE" \
  --wait

echo "==> 装订公证票据 (stapler)…"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"

echo "==> Gatekeeper 检查…"
if [[ "$TARGET" == *.app ]]; then
  spctl -a -vv -t exec "$TARGET" || true
else
  spctl -a -vv -t open --context context:primary-signature "$TARGET" || true
fi

echo ""
echo "✅ 公证完成: $TARGET"
