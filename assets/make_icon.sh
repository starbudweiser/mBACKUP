#!/bin/zsh
# Régénère l'icône : icon-1024.png et AppIcon.icns à partir de make_icon.swift (à relancer après toute retouche du dessin).
set -euo pipefail
cd "$(dirname "$0")"
rm -rf icon.iconset; mkdir icon.iconset
swift make_icon.swift icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s icon-1024.png --out icon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) icon-1024.png --out icon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns icon.iconset -o AppIcon.icns
rm -rf icon.iconset
echo "OK : assets/icon-1024.png, assets/AppIcon.icns"
