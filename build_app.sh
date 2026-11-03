#!/bin/zsh
# Construit « mBACKUP.app » dans le dossier du projet, la signe (certificat local stable) puis l'installe dans
# ~/Applications/Applications Personnelles. NO_INSTALL=1 : ne pas installer ; NO_OPEN=1 : ne pas lancer.
set -euo pipefail
cd "$(dirname "$0")"
APP="mBACKUP.app"
DEST="$HOME/Applications/Applications Personnelles"
GBP_RSYNC="/Applications/Get Backup Pro 3.app/Contents/Resources/rsync3"
rm -rf "$APP" build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/icon.iconset

swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos15 -o "$APP/Contents/MacOS/mBACKUP" Sources/*.swift

swift Resources/make_icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out build/icon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out build/icon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/icon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# rsync 3.x embarqué : Resources/rsync (copie de celui de Get Backup, GPL, usage personnel), sinon celui de Get Backup, sinon rsync du système.
if [ -f Resources/rsync ]; then
  cp Resources/rsync "$APP/Contents/Resources/rsync"
elif [ -f "$GBP_RSYNC" ]; then
  lipo "$GBP_RSYNC" -thin arm64 -output "$APP/Contents/Resources/rsync"
  chmod 755 "$APP/Contents/Resources/rsync"
else
  echo "Attention : rsync3 de Get Backup introuvable, rsync du système utilisé (sans attributs étendus)."
fi
rm -rf build

SIGN="/Volumes/SKYRIM/TOOLS/MAC/_tools/sign_app.sh"
if [ -x "$SIGN" ]; then "$SIGN" "$APP"; else codesign --force --deep -s - "$APP"; fi

if [ -z "${NO_INSTALL:-}" ]; then
  mkdir -p "$DEST"
  # Jamais d'installation pendant une sauvegarde : l'appli installée serait arrêtée en plein transfert.
  if pgrep -f "mBACKUP.app/Contents/Resources/rsync" >/dev/null && [ -z "${FORCE:-}" ]; then
    echo "Sauvegarde en cours : installation annulée (l'appli compilée est dans $PWD/$APP). Relancer quand elle est finie, ou FORCE=1." >&2
    exit 2
  fi
  pkill -x mBACKUP 2>/dev/null || true
  rm -rf "$DEST/$APP"
  cp -R "$APP" "$DEST/$APP"
  echo "Installée : $DEST/$APP"
fi
echo "OK : $APP"
