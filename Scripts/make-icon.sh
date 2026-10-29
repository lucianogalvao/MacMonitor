#!/bin/bash
# Gera Resources/AppIcon.icns a partir do desenho em make-icon.swift
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=".build/icon"
ICONSET="$WORK/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

swift Scripts/make-icon.swift "$WORK/icon_1024.png"

for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
    sips -z $((size * 2)) $((size * 2)) "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Pronto: Resources/AppIcon.icns"
