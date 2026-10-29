#!/bin/bash
# Compila o app e monta o bundle em build/MacMonitor.app
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/MacMonitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MacMonitor "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Pronto: $APP"
