#!/bin/bash
# Build a universal (Apple silicon + Intel) PayBeat.app and package it as .build/PayBeat-<version>.dmg.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
STAGE=.build/dmg-stage
APP="$STAGE/PayBeat.app"
DMG=".build/PayBeat-$VERSION.dmg"

swift build -c release --triple arm64-apple-macosx15.0
swift build -c release --triple x86_64-apple-macosx15.0

rm -rf "$STAGE" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/PayBeat" \
    .build/arm64-apple-macosx/release/PayBeat .build/x86_64-apple-macosx/release/PayBeat
cp Info.plist "$APP/Contents/Info.plist"
cp -R Localization/*.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname PayBeat -srcfolder "$STAGE" -format UDZO "$DMG"
echo "$DMG"
