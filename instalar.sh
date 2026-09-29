#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  Isla — compila la app y la instala directo en Aplicaciones.
#  Uso:  ./instalar.sh
# ─────────────────────────────────────────────────────────────
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/scripts/compilar.sh"

step "▸ Instalando…"
# Que el vigilante de Isla no la vuelva a abrir mientras la cerramos.
mkdir -p "$HOME/Library/Application Support/IslaMM"
touch "$HOME/Library/Application Support/IslaMM/cierre-limpio"
pkill -f "isla-guardian" 2>/dev/null || true
pkill -x "$EXECUTABLE" 2>/dev/null || true
sleep 0.5
DEST="/Applications"
if ! (rm -rf "$DEST/$DISPLAY_NAME.app" "$DEST/IslaMM.app" && cp -R "$APP" "$DEST/") 2>/dev/null; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
  rm -rf "$DEST/$DISPLAY_NAME.app" "$DEST/IslaMM.app"
  cp -R "$APP" "$DEST/"
fi

if [ "$ADHOC" = "1" ]; then
  # Con firma local, cada compilación cambia la "huella" de la app y macOS
  # deja de reconocer el permiso anterior. Lo reiniciamos para que lo pida limpio.
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  tccutil reset Microphone "$BUNDLE_ID" >/dev/null 2>&1 || true
  tccutil reset SpeechRecognition "$BUNDLE_ID" >/dev/null 2>&1 || true
  tccutil reset Calendar "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

open "$DEST/$DISPLAY_NAME.app"

echo ""
ok "✓ ¡Listo! $DISPLAY_NAME quedó instalada en $DEST"
echo ""
echo "  Primeros pasos:"
echo "  1. Acepta los avisos de Escritorio y Descargas (para capturas y descargas)."
echo "  2. Activa 'Isla' en Ajustes › Privacidad y seguridad › Accesibilidad"
echo "     (para los atajos ⌘C / ⌘V + número)."
echo "  3. Permite el micrófono y el reconocimiento de voz (para “Oye Claudio”)."
echo "  4. Lleva el mouse al notch (arriba al centro) y la isla se abre."
echo "  5. Pestaña Claude › Conectar con Claude Code (y abre una sesión nueva de Claude Code)."
echo ""
