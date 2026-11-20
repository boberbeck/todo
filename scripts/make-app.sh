#!/bin/bash
# Baut build/Tagwerk.app (für den eigenen Mac). GitHub baut die App bei jedem Push ebenfalls,
# fertig zum Herunterladen unter „Releases“ (siehe README).
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

# Signieren. Mit einem eigenen Zertifikat „Tagwerk Lokal“ (siehe README) bleibt die Signatur
# bei jedem Neubau gleich; dann behält macOS die Freigaben für Schlüsselbund, Kalender und Musik.
# Ohne Zertifikat wird ad hoc signiert, und macOS fragt nach jedem Neubau einmal neu.
IDENTITY="${TAGWERK_SIGN_IDENTITY:-Tagwerk Lokal}"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"${IDENTITY}\""; then
  SIGN="${IDENTITY}"
  echo "Signiere mit „${IDENTITY}“"
else
  SIGN="-"
  echo "Signiere ad hoc (ohne Zertifikat „${IDENTITY}“)."
fi
codesign --force --sign "${SIGN}" --identifier local.tagwerk.mcp "$APP/Contents/MacOS/tagwerk-mcp"
if [ "${SIGN}" = "-" ]; then
  # Ad hoc ändert sich die Signatur bei jedem Neubau. Damit macOS die Freigaben für Schlüsselbund,
  # Kalender und Musik trotzdem behält, verlangt die App nur ihre Kennung, nicht die genaue Fassung.
  codesign --force --sign - --requirements '=designated => identifier "local.tagwerk.app"' "$APP"
else
  codesign --force --sign "${SIGN}" "$APP"
fi

echo "Fertig: $APP"
echo "Starten mit: open $APP"
echo "Claude-Anbindung: $PWD/$APP/Contents/MacOS/tagwerk-mcp"
