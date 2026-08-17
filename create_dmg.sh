#!/bin/bash
set -e

APP_NAME="iCollegamenti"
APP_BUNDLE="iCollegamenti.app"
DMG_NAME="iCollegamenti.dmg"
STAGING_DIR="$(pwd)/.build/dmg-staging"

echo "=== Building DMG for $APP_NAME ==="

if [ ! -d "$APP_BUNDLE" ]; then
    echo "App bundle $APP_BUNDLE not found. Running build_app.sh first..."
    ./build_app.sh
fi

echo "1. Preparing staging directory..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

echo "2. Copying $APP_BUNDLE..."
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

echo "3. Creating Applications link for drag-and-drop installation..."
ln -s /Applications "$STAGING_DIR/Applications"

echo "4. Creating compressed DMG file: $DMG_NAME..."
rm -f "$DMG_NAME"
hdiutil create -volname "$APP_NAME" \
               -srcfolder "$STAGING_DIR" \
               -ov \
               -format UDZO \
               "$DMG_NAME"

echo "5. Cleaning up staging files..."
rm -rf "$STAGING_DIR"

echo "=== DMG Build Complete! ==="
echo "File created: $(pwd)/$DMG_NAME"
ls -lh "$DMG_NAME"
