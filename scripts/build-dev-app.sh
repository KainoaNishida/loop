#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/debug"
APP_DIR="$ROOT_DIR/.build/LoopDev/Loop.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_STAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

quit_running_loop_dev() {
  if ! command -v pgrep >/dev/null 2>&1; then
    return
  fi

  local pids
  pids="$(running_loop_dev_pids)"
  if [[ -z "$pids" ]]; then
    return
  fi

  echo "Closing running LoopDev before rebuilding..."
  if command -v osascript >/dev/null 2>&1; then
    osascript -e 'tell application id "com.kainoanishida.loop.dev" to quit' >/dev/null 2>&1 || true
  fi

  for _ in {1..30}; do
    pids="$(running_loop_dev_pids)"
    if [[ -z "$pids" ]]; then
      return
    fi
    sleep 0.1
  done

  pids="$(running_loop_dev_pids)"
  if [[ -n "$pids" ]]; then
    while read -r pid; do
      [[ -n "$pid" ]] || continue
      kill "$pid" >/dev/null 2>&1 || true
    done <<< "$pids"
  fi
}

running_loop_dev_pids() {
  while read -r pid; do
    [[ -n "$pid" ]] || continue

    local command_path
    command_path="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    command_path="${command_path%% *}"

    case "$command_path" in
      */Loop.app/Contents/MacOS/Loop)
        local app_path
        app_path="${command_path%/Contents/MacOS/Loop}"

        local bundle_id
        bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist" 2>/dev/null || true)"
        if [[ "$bundle_id" == "com.kainoanishida.loop.dev" ]]; then
          echo "$pid"
        fi
        ;;
    esac
  done < <(pgrep -x Loop 2>/dev/null || true)
}

cd "$ROOT_DIR"
quit_running_loop_dev
swift build --product Loop -Xswiftc -DLOOP_INTERNAL_DIAGNOSTICS

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/Loop" "$MACOS_DIR/Loop"
if [[ -d "$BUILD_DIR/Loop_MinderCore.bundle" ]]; then
  cp -R "$BUILD_DIR/Loop_MinderCore.bundle" "$APP_DIR/Loop_MinderCore.bundle"
elif [[ -d "$BUILD_DIR/Minder_MinderCore.bundle" ]]; then
  cp -R "$BUILD_DIR/Minder_MinderCore.bundle" "$APP_DIR/Minder_MinderCore.bundle"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
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
  <key>LoopDevBuildStamp</key>
  <string>$BUILD_STAMP</string>
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
  open -n "$APP_DIR"
fi
