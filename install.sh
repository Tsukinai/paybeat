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
BUILT="$PWD/.build/xcode/Build/Products/Release/PayBeat.app"
pkill -x PayBeat || true
rm -rf "$APP"
cp -R "$BUILT" "$APP"
# Keep only the installed copy registered: with the build product also registered,
# chronod rejects every widget timeline ("Bundle version did not match") and widgets stay blank.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$BUILT" 2>/dev/null || true  # fails when the build product is not registered
"$LSREGISTER" -f -R -trusted "$APP"
open "$APP"
echo "Installed $APP"
