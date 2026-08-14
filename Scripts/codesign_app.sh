#!/bin/zsh
# 用稳定的代码签名身份给 .app 签名。
# ad-hoc（codesign -s -）每次构建 CDHash 都变，macOS TCC 会当成新应用，屏幕录制权限必须重开。
set -euo pipefail

APP="${1:?usage: codesign_app.sh /path/to/App.app}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT/Resources/Flare.entitlements"
BUNDLE_ID="app.flare.screenshot"
SAVED="$ROOT/.codesign-identity"

pick_identity() {
  if [[ -n "${FLARE_CODESIGN_IDENTITY:-}" ]]; then
    print -r -- "$FLARE_CODESIGN_IDENTITY"
    return 0
  fi
  if [[ -f "$SAVED" ]]; then
    local name
    name="$(<"$SAVED")"
    name="${name//$'\n'/}"
    if [[ -n "$name" ]] && security find-identity -v -p codesigning | grep -F "\"$name\"" >/dev/null; then
      print -r -- "$name"
      return 0
    fi
    echo "!! 已记录的签名身份不可用: ${name:-?}" >&2
  fi

  local id=""
  id="$(security find-identity -v -p codesigning | sed -n 's/^[[:space:]]*[0-9]*)[[:space:]]*[A-F0-9]*[[:space:]]*"\(Developer ID Application: .*\)"$/\1/p' | head -1)"
  if [[ -z "$id" ]]; then
    id="$(security find-identity -v -p codesigning | sed -n 's/^[[:space:]]*[0-9]*)[[:space:]]*[A-F0-9]*[[:space:]]*"\(Apple Development: .*\)"$/\1/p' | head -1)"
  fi
  if [[ -n "$id" ]]; then
    print -r -- "$id" > "$SAVED"
    print -r -- "$id"
    return 0
  fi
  return 1
}

sign_adhoc() {
  echo "!! 没有 Apple Development / Developer ID 证书，只能 ad-hoc 签名" >&2
  echo "!! 每次重新编译安装后，系统都会要求重新打开「屏幕录制」权限" >&2
  codesign --force --sign - \
    --identifier "$BUNDLE_ID" \
    --entitlements "$ENTITLEMENTS" \
    "$APP"
}

IDENTITY=""
if IDENTITY="$(pick_identity)"; then
  echo "==> Codesign: $IDENTITY"
  if ! codesign --force --sign "$IDENTITY" \
    --identifier "$BUNDLE_ID" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp=none \
    "$APP"
  then
    echo "!! 使用「$IDENTITY」签名失败。" >&2
    echo "!! 若弹出钥匙串提示，请点「始终允许」后重试（不要回退 ad-hoc，否则截图权限每次都会丢）。" >&2
    exit 1
  fi
else
  sign_adhoc
fi

echo "==> Signature:"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Identifier=|Signature=|TeamIdentifier=|Authority=|flags=' || true
codesign -d -r- "$APP" 2>&1 | grep designated || true
codesign --verify --strict "$APP"
