#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/debug"
APP_DIR="$ROOT_DIR/.build/LoopDev/Loop.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build --product Loop

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/Loop" "$MACOS_DIR/Loop"
if [[ -d "$BUILD_DIR/Loop_MinderCore.bundle" ]]; then
  cp -R "$BUILD_DIR/Loop_MinderCore.bundle" "$APP_DIR/Loop_MinderCore.bundle"
elif [[ -d "$BUILD_DIR/Minder_MinderCore.bundle" ]]; then
  cp -R "$BUILD_DIR/Minder_MinderCore.bundle" "$APP_DIR/Minder_MinderCore.bundle"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Loop</string>
  <key>CFBundleIdentifier</key>
  <string>com.kainoanishida.loop.dev</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Loop</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>LoopReleaseChannel</key>
  <string>dev</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>Loop creates calendar events only after you confirm a suggested event.</string>
  <key>NSCalendarsUsageDescription</key>
  <string>Loop creates calendar events only after you confirm a suggested event.</string>
  <key>NSCalendarsWriteOnlyAccessUsageDescription</key>
  <string>Loop asks for write-only calendar access to save confirmed event drafts.</string>
  <key>NSContactsUsageDescription</key>
  <string>Loop uses Contacts locally to show names instead of phone numbers or email handles in imported Messages.</string>
  <key>NSRemindersFullAccessUsageDescription</key>
  <string>Loop creates reminders only after you confirm a suggested reminder.</string>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/Loop"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "Built $APP_DIR"
if [[ "${LOOP_SKIP_OPEN:-${MINDER_SKIP_OPEN:-0}}" != "1" ]]; then
  open "$APP_DIR"
fi
