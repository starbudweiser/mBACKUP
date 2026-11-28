#!/bin/zsh
# Construit « mBACKUP.app » dans le dossier du projet, la signe (certificat local stable) puis l'installe dans
# ~/Applications/Applications Personnelles. NO_INSTALL=1 : ne pas installer ; NO_OPEN=1 : ne pas lancer.
# DEV=1 : édition de développement « mBACKUP Dev.app » (identifiant fr.stephan.mbackup.dev, données dans
# « Application Support/mBACKUP Dev »), laissée dans le dossier du projet, jamais installée.
set -euo pipefail
cd "$(dirname "$0")"
APP="mBACKUP.app"
if [ -n "${DEV:-}" ]; then APP="mBACKUP Dev.app"; NO_INSTALL=1; fi
DEST="$HOME/Applications/Applications Personnelles"
rm -rf "$APP" build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos15 -o "$APP/Contents/MacOS/mBACKUP" Sources/*.swift

cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${DEV:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier fr.stephan.mbackup.dev" -c "Set :CFBundleName mBACKUP Dev" "$APP/Contents/Info.plist"
fi
# Descriptions des autorisations dans les 4 langues
for l in fr en es it; do mkdir -p "$APP/Contents/Resources/$l.lproj"; cp "Resources/$l.lproj/InfoPlist.strings" "$APP/Contents/Resources/$l.lproj/InfoPlist.strings"; done

# rsync 3.x embarqué : Resources/rsync (binaire GPL, usage personnel) ; à défaut, rsync du système.
if [ -f Resources/rsync ]; then
  cp Resources/rsync "$APP/Contents/Resources/rsync"
else
  echo "Attention : Resources/rsync absent, rsync du système utilisé (sans attributs étendus)."
fi
rm -rf build

SIGN="/Volumes/SKYRIM/TOOLS/MAC/_tools/sign_app.sh"
if [ -x "$SIGN" ]; then "$SIGN" "$APP"; else codesign --force --deep -s - "$APP"; fi

if [ -z "${NO_INSTALL:-}" ]; then
  mkdir -p "$DEST"
  # Jamais d'installation pendant une sauvegarde : l'appli installée serait arrêtée en plein transfert.
  BUSY="$HOME/Library/Application Support/mBACKUP/busy.pid"      # témoin écrit par l'appli tant qu'une tâche tourne
  if { { [ -f "$BUSY" ] && kill -0 "$(cat "$BUSY")" 2>/dev/null; } || pgrep -f "mBACKUP.app/Contents/Resources/rsync" >/dev/null || pgrep -f "mbackup-zip-" >/dev/null; } && [ -z "${FORCE:-}" ]; then
    echo "Sauvegarde en cours : installation annulée (l'appli compilée est dans $PWD/$APP). Relancer quand elle est finie, ou FORCE=1." >&2
    exit 2
  fi
  pkill -x mBACKUP 2>/dev/null || true
  rm -rf "$DEST/$APP"
  cp -R "$APP" "$DEST/$APP"
  echo "Installée : $DEST/$APP"
fi
echo "OK : $APP"
