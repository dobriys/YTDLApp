#!/bin/bash
# Собирает build/YTDLApp.app. С флагом --install копирует его в /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/YTDLApp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/YTDLApp "$APP/Contents/MacOS/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Загрузчик видео</string>
    <key>CFBundleDisplayName</key><string>Загрузчик видео</string>
    <key>CFBundleIdentifier</key><string>local.ytdlapp</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleExecutable</key><string>YTDLApp</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleDevelopmentRegion</key><string>ru</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Готово: $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/YTDLApp.app"
    cp -R "$APP" /Applications/
    echo "Установлено в /Applications/YTDLApp.app"
fi
