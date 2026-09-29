#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  Parte compartida: compila Isla, arma Isla.app y la firma.
#  La usan instalar.sh y crear-dmg.sh (no hace falta correrla sola).
#  Al terminar deja listas las variables:  APP  y  ADHOC
# ─────────────────────────────────────────────────────────────

EXECUTABLE="IslaMM"                 # nombre del programa (el proceso)
DISPLAY_NAME="Isla"                 # nombre visible de la app
BUNDLE_ID="com.mexicomakers.islamm"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Resources/Info.plist" 2>/dev/null || echo 1.0)"

ok()   { printf "\033[1;32m%s\033[0m\n" "$1"; }
step() { printf "\033[1m%s\033[0m\n" "$1"; }

if ! command -v swift >/dev/null 2>&1; then
  step "✗ No encuentro 'swift'. Instala las herramientas de Apple con:"
  echo "    xcode-select --install"
  exit 1
fi

step "▸ Compilando (la primera vez tarda 1–2 minutos)…"
swift build -c release --package-path "$ROOT"
BIN_DIR="$(swift build -c release --package-path "$ROOT" --show-bin-path)"

step "▸ Armando $DISPLAY_NAME.app…"
APP="$ROOT/build/$DISPLAY_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

step "▸ Firmando…"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Apple Development' | sed -E 's/.*"(.*)".*/\1/' || true)"
if [ -n "$IDENTITY" ]; then
  codesign --force --deep --sign "$IDENTITY" "$APP"
  echo "   Firmada con tu certificado: $IDENTITY"
  ADHOC=0
else
  codesign --force --deep --sign - "$APP"
  echo "   Firma local (sin cuenta de desarrollador)."
  ADHOC=1
fi
