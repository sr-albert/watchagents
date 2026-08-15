#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ClaudeMonitor"
BUNDLE_ID="com.albert.claudemonitor"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$HOME/Applications/$APP_NAME.app"

echo "Building release binary..."
swift build -c release --package-path "$ROOT_DIR"

echo "Assembling app bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# SPM's generated accessor resolves Bundle.module against Bundle.main.bundleURL, which is
# the .app's root and can never be sealed by codesign. FarmAssets prefers Contents/Resources
# instead (a sealed location: everything under it is hashed into the resource seal
# regardless of --deep), so the bundle must land there, and it must do so BEFORE signing
# so codesign includes it in that seal. (Landing it in Contents/MacOS instead is what
# broke --deep previously: codesign tries to classify anything named "*.bundle" there as
# nested executable code and fails since it has no Info.plist -- Contents/Resources avoids
# that classification entirely.)
cp -R "$BUILD_DIR/ClaudeMonitor_ClaudeMonitor.bundle" "$APP_DIR/Contents/Resources/"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLIST

echo "Ad-hoc code signing..."
codesign --force --deep --sign - "$APP_DIR"

echo "Installed $APP_DIR"
echo "Launch with: open \"$APP_DIR\""
