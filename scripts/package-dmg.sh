#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Codex Synced"
APP_VERSION="1.0.0"
BUNDLE_ID="com.zhoujia.codex-synced"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
VERSIONED_DMG_PATH="$DIST_DIR/Codex-Synced-$APP_VERSION.dmg"
STAGING_DMG="$DIST_DIR/$APP_NAME-staging.dmg"
ICON_SOURCE="$ROOT_DIR/Resources/AppIconSource.png"
ICON_FILE="$ROOT_DIR/Resources/AppIcon.icns"

mkdir -p "$DIST_DIR"
rm -rf "$APP_DIR" "$DMG_PATH" "$VERSIONED_DMG_PATH" "$STAGING_DMG"

swift build -c release --disable-sandbox

if [[ -f "$ICON_SOURCE" ]]; then
  "$ROOT_DIR/scripts/generate-app-icon.sh"
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/CodexSynced" "$MACOS_DIR/Codex Synced"
chmod +x "$MACOS_DIR/Codex Synced"

if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Codex Synced</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>100</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

hdiutil create -volname "$APP_NAME" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH"
cp "$DMG_PATH" "$VERSIONED_DMG_PATH"

echo "$DMG_PATH"
echo "$VERSIONED_DMG_PATH"
