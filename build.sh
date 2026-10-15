#!/bin/bash
# Builds AdbDock.app (menu bar app) from Sources/.
#   ./build.sh          build
#   ./build.sh --run    build and (re)launch
#
# The bundle identifier is also the LaunchAgent label used by "Start at login".
# Override it per machine with an untracked local.env:
#   BUNDLE_ID=com.yourname.adbdock
set -euo pipefail
cd "$(dirname "$0")"

[ -f local.env ] && . ./local.env
BUNDLE_ID="${BUNDLE_ID:-com.example.adbdock}"

APP_NAME="AdbDock"
OUT="build/${APP_NAME}.app"
ARCH="$(uname -m)"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"

swiftc -O -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -o "$OUT/Contents/MacOS/${APP_NAME}" \
  Sources/*.swift

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>ADB Dock</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>LSMultipleInstancesProhibited</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$OUT" >/dev/null 2>&1 || echo "warning: ad-hoc codesign failed (app still runs locally)"
echo "built $OUT (bundle id ${BUNDLE_ID})"

if [ "${1:-}" = "--run" ]; then
  pkill -f "$PWD/${OUT}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
  sleep 1
  open "$OUT"
  echo "launched"
fi
