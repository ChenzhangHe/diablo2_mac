#!/bin/bash
# Build a release AshenSigil.app into ./build
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/AshenSigil.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/AshenSigil "$APP/Contents/MacOS/AshenSigil"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Ashen Sigil</string>
  <key>CFBundleDisplayName</key><string>灰烬圣印</string>
  <key>CFBundleIdentifier</key><string>dev.ashensigil.game</string>
  <key>CFBundleExecutable</key><string>AshenSigil</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.role-playing-games</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
