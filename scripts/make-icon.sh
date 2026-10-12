#!/bin/zsh
# Regenerates Resources/AppIcon.icns from Resources/icon-source.png (1024x1024 recommended).
set -e
cd "$(dirname "$0")/.."
rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
swift scripts/make-icon.swift Resources/icon-source.png build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
echo "Updated Resources/AppIcon.icns"
