#!/bin/bash
# Builds Hinge.app. A real bundle with a stable identifier is required for
# Screen Recording permission to stick to the app.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="Hinge.app"

python3 make_icon.py >/dev/null
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Hinge"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hinge"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Hinge</string>
    <key>CFBundleDisplayName</key><string>Hinge</string>
    <key>CFBundleExecutable</key><string>Hinge</string>
    <key>CFBundleIdentifier</key><string>local.hinge</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
PLIST
echo "</plist>" >> "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"

# An ad-hoc signature changes hash on every build, which invalidates the
# existing Screen Recording grant while still showing as enabled. Clearing it
# means the next launch asks again instead of silently failing.
tccutil reset ScreenCapture local.hinge >/dev/null 2>&1 || true

echo "built $(pwd)/$APP"
echo "Screen Recording permission was reset; allow Hinge again on next launch."
