#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-}"
if [[ -z "$DEST" ]]; then
  echo "usage: embed_translate_vault.sh <FlareVault.dat>" >&2
  exit 1
fi

SRC="$ROOT/Secrets/translate.json"
if [[ ! -f "$SRC" ]]; then
  echo "!! 缺少 Secrets/translate.json，无法把翻译凭证加密打进 App" >&2
  exit 1
fi

SDK="$(xcrun --sdk macosx --show-sdk-path)"
TOOL_DIR="$ROOT/.build-universal"
TOOL="$TOOL_DIR/embed-translate-vault"
mkdir -p "$TOOL_DIR" "$(dirname "$DEST")"

echo "==> Encrypting translate vault"
xcrun swiftc \
  -sdk "$SDK" \
  -O \
  -swift-version 5 \
  -framework Foundation \
  -framework CryptoKit \
  "$ROOT/Sources/Flare/Features/TranslateVault.swift" \
  "$ROOT/Scripts/embed_translate_secrets.swift" \
  -o "$TOOL"

"$TOOL" "$SRC" "$DEST"
chmod 600 "$DEST"
