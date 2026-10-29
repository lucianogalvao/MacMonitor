#!/bin/bash
# Compila o app e gera build/MacMonitor.dmg (app + atalho para Aplicativos + LEIAME)
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

STAGE="build/dmg"
DMG="build/MacMonitor.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/MacMonitor.app "$STAGE/"
cp Resources/LEIAME.txt "$STAGE/"
ln -s /Applications "$STAGE/Aplicativos"

hdiutil create -volname "MacMonitor" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
# A cópia temporária fica registrada no Launch Services e confunde o ícone das notificações
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "$STAGE/MacMonitor.app" 2>/dev/null || true
rm -rf "$STAGE"

echo "Pronto: $DMG"
