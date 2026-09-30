#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  UltraNotch — crea un instalador .dmg (arrastra la app a Aplicaciones).
#  Uso:  ./crear-dmg.sh
#  Resultado:  UltraNotch-<versión>.dmg en esta misma carpeta.
# ─────────────────────────────────────────────────────────────
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/scripts/compilar.sh"

VOLUME="$DISPLAY_NAME"
STAGE="$ROOT/build/dmg"
TMP_DMG="$ROOT/build/temporal.dmg"
DMG="$ROOT/$DISPLAY_NAME-$VERSION.dmg"

step "▸ Preparando el contenido del DMG…"
rm -rf "$STAGE" "$TMP_DMG" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Aplicaciones"

step "▸ Creando la imagen de disco…"
# Si ya hay un disco "UltraNotch" abierto, lo expulsamos para no confundirlo.
hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$TMP_DMG" >/dev/null

MOUNT_DIR="$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)"
DISK_NAME="$(basename "$MOUNT_DIR")"

# Ícono del disco (opcional)
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
  fi
fi

step "▸ Acomodando la ventana (si macOS pregunta si Terminal puede controlar Finder, dale OK)…"
osascript <<EOF >/dev/null 2>&1 || echo "   (No se pudo acomodar la ventana; el DMG funciona igual.)"
tell application "Finder"
    tell disk "$DISK_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 140, 760, 480}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set position of item "$DISPLAY_NAME.app" of container window to {150, 150}
        set position of item "Aplicaciones" of container window to {410, 150}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

sync
hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || hdiutil detach "$MOUNT_DIR" -force -quiet

step "▸ Comprimiendo…"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$TMP_DMG"
rm -rf "$STAGE"

if [ "$ADHOC" = "0" ]; then
  codesign --force --sign "$IDENTITY" "$DMG" >/dev/null 2>&1 || true
fi

echo ""
ok "✓ DMG listo: $DMG"
echo ""
echo "  Para instalar: abre el DMG y arrastra UltraNotch a la carpeta Aplicaciones."
echo ""
open -R "$DMG"
