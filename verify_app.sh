#!/bin/bash
set -euo pipefail

APP_BUNDLE="iCollegamenti.app"
BUILD_SCRATCH="/tmp/codex-builds/cavi-verify"

swift build -c release --product CAVI --scratch-path "$BUILD_SCRATCH"
./build_app.sh

test "$(plutil -extract CFBundleExecutable raw "$APP_BUNDLE/Contents/Info.plist")" = "CAVI"
test "$(plutil -extract CFBundleName raw "$APP_BUNDLE/Contents/Info.plist")" = "iCollegamenti"
test "$(plutil -extract CFBundleDisplayName raw "$APP_BUNDLE/Contents/Info.plist")" = "iCollegamenti"
test "$(plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Contents/Info.plist")" = "2.0"
test "$(plutil -extract CFBundleVersion raw "$APP_BUNDLE/Contents/Info.plist")" = "2.0"
test "$(plutil -extract CFBundleIconFile raw "$APP_BUNDLE/Contents/Info.plist")" = "AppIcon"
test "$(plutil -extract CFBundleIconName raw "$APP_BUNDLE/Contents/Info.plist")" = "AppIcon"
test -x "$APP_BUNDLE/Contents/MacOS/CAVI"
cmp -s AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
test -s "$APP_BUNDLE/Contents/Resources/Assets.car"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "iCollegamenti bundle verification passed."
