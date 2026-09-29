#!/bin/bash
# Quita Isla de tu Mac (app, datos y permisos).
EXECUTABLE="IslaMM"
BUNDLE_ID="com.mexicomakers.islamm"

# Primero quitamos los avisos (hooks) que Isla agregó a Claude Code.
for APP in "/Applications/Isla.app" "$HOME/Applications/Isla.app"; do
  if [ -x "$APP/Contents/MacOS/$EXECUTABLE" ]; then
    "$APP/Contents/MacOS/$EXECUTABLE" --remove-claude-hooks || true
  fi
done

# Que el vigilante de Isla no la vuelva a abrir mientras la cerramos.
mkdir -p "$HOME/Library/Application Support/IslaMM"
touch "$HOME/Library/Application Support/IslaMM/cierre-limpio"
pkill -f "isla-guardian" 2>/dev/null || true
pkill -x "$EXECUTABLE" 2>/dev/null || true
rm -rf "/Applications/Isla.app" "$HOME/Applications/Isla.app"
rm -rf "/Applications/IslaMM.app" "$HOME/Applications/IslaMM.app"
rm -rf "$HOME/Library/Application Support/IslaMM"
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "✓ Isla desinstalada."
