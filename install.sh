#!/bin/bash
# Build PayBeat and install it as /Applications/PayBeat.app.
# Re-run after code changes to update the installed app. Open at login is a switch in Settings > General.
set -euo pipefail
cd "$(dirname "$0")"

APP=/Applications/PayBeat.app

swift build -c release

pkill -x PayBeat || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PayBeat "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Localization/*.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
open "$APP"
echo "Installed $APP"
