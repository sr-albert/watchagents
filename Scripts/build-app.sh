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
# Sign before the resource bundle is added below: codesign refuses to seal a "*.bundle"
# directory sitting loose at the app's top level (it wants only Contents/ there), and
# --deep additionally chokes on it because it has no Info.plist of its own. Signing
# just the app is fine since there is no nested executable code to sign.
codesign --force --sign - "$APP_DIR"

# SPM's generated accessor looks for the resource bundle next to Bundle.main.bundleURL.
# For a packaged .app, Bundle.main.bundleURL is the .app bundle's root directory itself
# (NOT Contents/MacOS or Contents/Resources), so the resource bundle must land there or
# Bundle.module traps at runtime. It is copied in after signing (see note above).
cp -R "$BUILD_DIR/ClaudeMonitor_ClaudeMonitor.bundle" "$APP_DIR/"

echo "Installed $APP_DIR"
echo "Launch with: open \"$APP_DIR\""
