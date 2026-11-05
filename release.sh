#!/bin/bash
# Build a universal PayBeat.app (Apple silicon + Intel) with Xcode and package it as .build/PayBeat-<version>.dmg.
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
STAGE=.build/dmg-stage
DMG=".build/PayBeat-$VERSION.dmg"

xcodegen generate --quiet
xcodebuild -project PayBeat.xcodeproj -scheme PayBeat -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath .build/xcode ONLY_ACTIVE_ARCH=NO build -quiet

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R .build/xcode/Build/Products/Release/PayBeat.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname PayBeat -srcfolder "$STAGE" -format UDZO "$DMG"
echo "$DMG"
