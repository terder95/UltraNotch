#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  UltraNotch — compila la app y la instala directo en Aplicaciones.
#  Uso:  ./instalar.sh
#  Si tenías la versión anterior (Isla), la quita; UltraNotch copia tus
#  ajustes la primera vez que abre.
# ─────────────────────────────────────────────────────────────
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/scripts/compilar.sh"

# Procesos a cerrar: UltraNotch y la versión anterior (Isla, cuyo programa se llamaba IslaMM).
PROCESOS=("$EXECUTABLE" "IslaMM")

step "▸ Cerrando la versión abierta…"
# Que el vigilante no vuelva a abrir la app mientras la cerramos.
mkdir -p "$HOME/Library/Application Support/UltraNotch"
touch "$HOME/Library/Application Support/UltraNotch/cierre-limpio"
pkill -f "ultranotch-guardian" 2>/dev/null || true
pkill -f "isla-guardian" 2>/dev/null || true
for P in "${PROCESOS[@]}"; do
  pkill -x "$P" 2>/dev/null || true
done
# Si a los 2 s sigue viva (por ejemplo, trabada), la forzamos a cerrar.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  VIVO=0
  for P in "${PROCESOS[@]}"; do
    pgrep -x "$P" >/dev/null 2>&1 && VIVO=1
  done
  [ "$VIVO" = "0" ] && break
  sleep 0.2
done
for P in "${PROCESOS[@]}"; do
  if pgrep -x "$P" >/dev/null 2>&1; then
    echo "   $P no se cerró; lo forzamos."
    pkill -9 -x "$P" 2>/dev/null || true
  fi
done
sleep 0.3

step "▸ Instalando…"
# Quitamos la app vieja (Isla / IslaMM) de las dos carpetas de Aplicaciones.
for DIR in "/Applications" "$HOME/Applications"; do
  rm -rf "$DIR/Isla.app" "$DIR/IslaMM.app" 2>/dev/null || true
done
DEST="/Applications"
if ! (rm -rf "$DEST/$DISPLAY_NAME.app" && cp -R "$APP" "$DEST/") 2>/dev/null; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
  rm -rf "$DEST/$DISPLAY_NAME.app"
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
ok "✓ ¡Listo! $DISPLAY_NAME quedó instalado en $DEST"
echo ""
echo "  Primeros pasos:"
echo "  1. Acepta los avisos de Escritorio y Descargas (para capturas y descargas)."
echo "  2. Activa '$DISPLAY_NAME' en Ajustes › Privacidad y seguridad › Accesibilidad"
echo "     (para los atajos ⌘C / ⌘V + número)."
echo "  3. Permite el micrófono y el reconocimiento de voz (para “Oye Claudio”)."
echo "  4. Lleva el mouse al notch (arriba al centro) y se abre el panel."
echo "  5. Pestaña Claude › Conectar con Claude Code (y abre una sesión nueva de Claude Code)."
echo ""
