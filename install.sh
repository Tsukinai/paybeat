#!/bin/bash
# Build WorkTicker, install it as /Applications/WorkTicker.app and start it at login.
# Re-run after code changes to update the installed app.
set -euo pipefail
cd "$(dirname "$0")"

APP=/Applications/WorkTicker.app
ID=local.workticker
AGENT="$HOME/Library/LaunchAgents/$ID.plist"

swift build -c release

pkill -x WorkTicker || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/WorkTicker "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>$APP</string>
    </array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo "Installed $APP, login item $AGENT"
