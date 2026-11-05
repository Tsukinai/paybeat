#!/bin/bash
# Build PayBeat (app + widget) with Xcode and install it as /Applications/PayBeat.app.
# Needs Xcode and xcodegen (brew install xcodegen). Open at login is a switch in Settings > General.
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

xcodegen generate --quiet
xcodebuild -project PayBeat.xcodeproj -scheme PayBeat -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath .build/xcode build -quiet

APP=/Applications/PayBeat.app
pkill -x PayBeat || true
rm -rf "$APP"
cp -R .build/xcode/Build/Products/Release/PayBeat.app "$APP"
open "$APP"
echo "Installed $APP"
