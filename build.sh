#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p dist
stage="$(mktemp -d "${TMPDIR:-/tmp}/uc-reconnect.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/mac-reconnect-wake.app"
resources="$app/Contents/Resources"
mkdir -p "$app/Contents/MacOS" "$resources" "$stage/AppIcon.iconset"
cp Assets/MenuBar*.png "$resources/"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/mac-reconnect-wake.png --out "$stage/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    pixels=$((size * 2))
    sips -z "$pixels" "$pixels" Assets/mac-reconnect-wake.png --out "$stage/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 - "$stage/AppIcon.iconset" "$resources/AppIcon.icns" <<'PYICON'
import struct
import sys
from pathlib import Path

source = Path(sys.argv[1])
types = {
    "16x16": b"icp4", "32x32": b"icp5",
    "128x128": b"ic07", "256x256": b"ic08", "512x512": b"ic09",
    "16x16@2x": b"ic11", "32x32@2x": b"ic12",
    "128x128@2x": b"ic13", "256x256@2x": b"ic14", "512x512@2x": b"ic10",
}
entries = []
for size, kind in types.items():
    png = (source / f"icon_{size}.png").read_bytes()
    entries.append(struct.pack(">4sI", kind, len(png) + 8) + png)
body = b"".join(entries)
Path(sys.argv[2]).write_bytes(struct.pack(">4sI", b"icns", len(body) + 8) + body)
PYICON
cp Info.plist "$app/Contents/Info.plist"
for spec in main:UniversalControlReconnect password:MacMiniPassword; do
    xcrun clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Werror \
        -mmacosx-version-min=13.0 -arch x86_64 -arch arm64 -framework Cocoa \
        "Sources/${spec%%:*}.m" -o "$app/Contents/MacOS/${spec#*:}"
done
codesign --force --sign - "$app/Contents/MacOS/MacMiniPassword"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
if UC_WAKE_TARGET='Test Mac' UC_WAKE_DESTINATION='tester@mac.local' \
    "$app/Contents/MacOS/MacMiniPassword" "another@mac.local's password:"; then
    echo 'Unexpected SSH prompt accepted.' >&2
    exit 1
fi
ditto -c -k --keepParent --norsrc "$app" "$stage/mac-reconnect-wake-macOS.zip"
unzip -tq "$stage/mac-reconnect-wake-macOS.zip"
mv "$stage/mac-reconnect-wake-macOS.zip" dist/
