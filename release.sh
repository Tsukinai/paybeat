#!/bin/bash
# Build a universal (Apple silicon + Intel) WorkTicker.app and package it as .build/WorkTicker-<version>.dmg.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
STAGE=.build/dmg-stage
APP="$STAGE/WorkTicker.app"
DMG=".build/WorkTicker-$VERSION.dmg"

swift build -c release --triple arm64-apple-macosx15.0
swift build -c release --triple x86_64-apple-macosx15.0

rm -rf "$STAGE" "$DMG"
mkdir -p "$APP/Contents/MacOS"
lipo -create -output "$APP/Contents/MacOS/WorkTicker" \
    .build/arm64-apple-macosx/release/WorkTicker .build/x86_64-apple-macosx/release/WorkTicker
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname WorkTicker -srcfolder "$STAGE" -format UDZO "$DMG"
echo "$DMG"
