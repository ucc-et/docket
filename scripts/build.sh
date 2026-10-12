#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) Docket.app into build/.
# Usage: scripts/build.sh [version]
set -e
cd "$(dirname "$0")/.."
VERSION=${1:-0.0.0-dev}
APP=build/Docket.app
rm -rf build && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources

for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos13.0 -o build/Docket-$arch Sources/*.swift
done
lipo -create build/Docket-arm64 build/Docket-x86_64 -output $APP/Contents/MacOS/Docket
rm build/Docket-arm64 build/Docket-x86_64

cp Resources/AppIcon.icns $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Docket</string>
  <key>CFBundleDisplayName</key><string>Docket</string>
  <key>CFBundleIdentifier</key><string>local.docket</string>
  <key>CFBundleExecutable</key><string>Docket</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - $APP
echo "Built $APP ($VERSION)"
