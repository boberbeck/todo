#!/bin/bash
# Baut build/Tagwerk.app (ad-hoc signiert, für den eigenen Mac).
# Aufruf: scripts/make-app.sh          → Release-Build
#         scripts/make-app.sh debug    → Debug-Build
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Tagwerk.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Tagwerk" "$APP/Contents/MacOS/Tagwerk"
# MCP-Server für Claude liegt neben der App
cp "$BIN_DIR/tagwerk-mcp" "$APP/Contents/MacOS/tagwerk-mcp"
cp Support/Info.plist "$APP/Contents/Info.plist"

# App-Symbol aus Support/AppIcon.png (1024 × 1024)
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" Support/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" Support/AppIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

codesign --force --sign - "$APP/Contents/MacOS/tagwerk-mcp"
codesign --force --sign - "$APP"

echo "Fertig: $APP"
echo "Starten mit: open $APP"
echo "Claude-Anbindung: $PWD/$APP/Contents/MacOS/tagwerk-mcp"
