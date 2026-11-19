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
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Fertig: $APP"
echo "Starten mit: open $APP"
