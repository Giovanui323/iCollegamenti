#!/bin/bash
set -e

APP_VERSION="2.0"
APP_BUNDLE="iCollegamenti.app"
BUILD_SCRATCH="/tmp/codex-builds/cavi-release"

echo "Building CAVI executable..."
swift build -c release --product CAVI --scratch-path "$BUILD_SCRATCH"

APP_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

mkdir -p "$APP_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BUILD_SCRATCH/release/CAVI" "$APP_DIR/CAVI"
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"
fi

xcrun actool AppIcon.icon \
    --compile "$RESOURCES_DIR" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon

cat << EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CAVI</string>
    <key>CFBundleIdentifier</key>
    <string>com.giovanui.iCollegamenti</string>
    <key>CFBundleName</key>
    <string>iCollegamenti</string>
    <key>CFBundleDisplayName</key>
    <string>iCollegamenti</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "$APP_BUNDLE bundle built successfully (version $APP_VERSION)."
