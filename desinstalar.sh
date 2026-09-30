#!/bin/bash
# Quita UltraNotch de tu Mac (app, datos y permisos), y también la versión anterior (Isla).
EXECUTABLE="UltraNotch"
BUNDLE_ID="io.github.terder95.ultranotch"
# Versión anterior: se llamaba Isla (programa IslaMM).
OLD_EXECUTABLE="IslaMM"
OLD_BUNDLE_ID="com.mexicomakers.islamm"

# Primero quitamos los avisos (hooks) y la línea de estado que la app agregó a Claude Code
# (reconoce tanto los de UltraNotch como los de Isla; deja un respaldo de settings.json).
for BIN in "/Applications/UltraNotch.app/Contents/MacOS/$EXECUTABLE" \
           "$HOME/Applications/UltraNotch.app/Contents/MacOS/$EXECUTABLE" \
           "/Applications/Isla.app/Contents/MacOS/$OLD_EXECUTABLE" \
           "$HOME/Applications/Isla.app/Contents/MacOS/$OLD_EXECUTABLE"; do
  if [ -x "$BIN" ]; then
    "$BIN" --remove-claude-hooks || true
    break
  fi
done

# Que el vigilante no la vuelva a abrir mientras la cerramos.
pkill -f "ultranotch-guardian" 2>/dev/null || true
pkill -f "isla-guardian" 2>/dev/null || true
pkill -x "$EXECUTABLE" 2>/dev/null || true
pkill -x "$OLD_EXECUTABLE" 2>/dev/null || true
sleep 2
pkill -9 -x "$EXECUTABLE" 2>/dev/null || true
pkill -9 -x "$OLD_EXECUTABLE" 2>/dev/null || true

for DIR in "/Applications" "$HOME/Applications"; do
  rm -rf "$DIR/UltraNotch.app" "$DIR/Isla.app" "$DIR/IslaMM.app"
done
rm -rf "$HOME/Library/Application Support/UltraNotch"
rm -rf "$HOME/Library/Application Support/IslaMM"
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
defaults delete "$OLD_BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset All "$OLD_BUNDLE_ID" >/dev/null 2>&1 || true
echo "✓ UltraNotch desinstalado."
