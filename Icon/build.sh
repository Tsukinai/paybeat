#!/bin/bash
# Regenerate Icon/AppIcon.icns from Icon/make_icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
SET=.build/AppIcon.iconset
rm -rf "$SET" && mkdir -p "$SET"
swift Icon/make_icon.swift .build/icon-1024.png
for s in 16 32 128 256 512; do
    sips -z $s $s .build/icon-1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) .build/icon-1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Icon/AppIcon.icns
