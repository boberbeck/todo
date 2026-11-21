#!/bin/bash
# Packt build/Tagwerk.app in build/Tagwerk.dmg: Tagwerk und eine Verknüpfung zu „Programme“ zum Hineinziehen.
# Vorher scripts/make-app.sh ausführen. GitHub macht beides bei jedem Push (Release „aktuell“).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Tagwerk.app"
DMG="build/Tagwerk.dmg"
VOLUME="Tagwerk"
[ -d "$APP" ] || { echo "build/Tagwerk.app fehlt. Erst scripts/make-app.sh ausführen."; exit 1; }

WORK="$(mktemp -d)"
trap 'hdiutil detach "${MOUNT:-/nonexistent}" -quiet 2>/dev/null || true; rm -rf "${WORK}"' EXIT
STAGE="${WORK}/${VOLUME}"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Tagwerk.app"
ln -s /Applications "$STAGE/Programme"

# Erst beschreibbar anlegen, um das Laufwerkssymbol zu setzen, dann komprimieren.
hdiutil create -quiet -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "${WORK}/roh.dmg"
MOUNT="${WORK}/mount"
mkdir -p "$MOUNT"
if hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$MOUNT" "${WORK}/roh.dmg"; then
  if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns" || true
    if command -v SetFile >/dev/null 2>&1; then
      SetFile -a C "$MOUNT" || true
      SetFile -a V "$MOUNT/.VolumeIcon.icns" || true
    fi
  fi
  sync
  hdiutil detach -quiet "$MOUNT" || hdiutil detach -quiet -force "$MOUNT"
fi
MOUNT=""

rm -f "$DMG"
hdiutil convert -quiet "${WORK}/roh.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"

# Mit dem festen Zertifikat signieren, falls vorhanden (sonst bleibt die DMG unsigniert; die App darin ist signiert).
IDENTITY="${TAGWERK_SIGN_IDENTITY:-Tagwerk Lokal}"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"${IDENTITY}\""; then
  codesign --force --sign "${IDENTITY}" "$DMG" || true
fi

hdiutil verify -quiet "$DMG"
echo "Fertig: $DMG ($(du -h "$DMG" | cut -f1))"
