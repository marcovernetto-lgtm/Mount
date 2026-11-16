#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Mount"
VERSION="1.0.0"
APP_BUNDLE="$ROOT_DIR/build/$APP_NAME.app"
DMG_PATH="$ROOT_DIR/build/$APP_NAME-$VERSION.dmg"
DMG_STAGING="$ROOT_DIR/build/dmg-staging"

echo "Building $APP_NAME (release)..."
swift build -c release --package-path "$ROOT_DIR"

BIN_PATH="$ROOT_DIR/.build/release/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so macOS Gatekeeper / local launch works smoothly
codesign --force --deep --sign - "$APP_BUNDLE"
echo "Built: $APP_BUNDLE"

# Create DMG installer
rm -rf "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$DMG_STAGING"
echo "Built DMG: $DMG_PATH"
