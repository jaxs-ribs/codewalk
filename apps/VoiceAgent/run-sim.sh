#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_YML="$APP_DIR/project.yml"
PROJ_XCODEPROJ="$APP_DIR/VoiceAgent.xcodeproj"
DERIVED="$APP_DIR/build/DerivedData"
SCHEME="VoiceAgent"
APP_NAME="VoiceAgent"
BUNDLE_ID="com.example.voiceagent"
CONFIG="Debug"

echo "[run] Using project at: $APP_DIR"

command -v xcodegen >/dev/null 2>&1 || { echo "[run] Install XcodeGen: brew install xcodegen"; exit 1; }
command -v xcodebuild >/dev/null 2>&1 || { echo "[run] xcodebuild not found (install Xcode)."; exit 1; }
command -v xcrun >/dev/null 2>&1 || { echo "[run] xcrun not found (install Xcode)."; exit 1; }

echo "[run] Generating Xcode project from project.yml..."
pushd "$APP_DIR" >/dev/null
xcodegen generate
popd >/dev/null

echo "[run] Selecting simulator device..."
TARGET_DEVICE="iPhone 16 Pro"
RUNTIME_ID=$(xcrun simctl list runtimes | awk -F '[() ]+' '/iOS/ {print $(NF-1)}' | tail -1)
if [[ -z "$RUNTIME_ID" ]]; then echo "[run] No iOS runtimes found"; exit 1; fi

DEVICE_LINE=$(xcrun simctl list devices "$RUNTIME_ID" | grep -E "$TARGET_DEVICE \(" || true)
if [[ -z "$DEVICE_LINE" ]]; then
  echo "[run] $TARGET_DEVICE not found, selecting first bootable iPhone..."
  DEVICE_LINE=$(xcrun simctl list devices "$RUNTIME_ID" | grep -E "iPhone .*\(Shutdown\)|iPhone .*\(Booted\)" | head -1)
fi

UDID=$(echo "$DEVICE_LINE" | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
if [[ -z "$UDID" ]]; then echo "[run] Failed to select simulator UDID"; exit 1; fi
echo "[run] Using simulator UDID: $UDID"

echo "[run] Booting simulator (if needed)..."
xcrun simctl bootstatus "$UDID" -b || (xcrun simctl boot "$UDID" && xcrun simctl bootstatus "$UDID" -b)
open -a Simulator >/dev/null 2>&1 || true

echo "[run] Building app for simulator..."
mkdir -p "$DERIVED"
xcodebuild \
  -project "$PROJ_XCODEPROJ" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  -sdk iphonesimulator \
  build | xcpretty || xcodebuild \
  -project "$PROJ_XCODEPROJ" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  -sdk iphonesimulator \
  build

APP_PATH="$DERIVED/Build/Products/$CONFIG-iphonesimulator/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then echo "[run] App not found at $APP_PATH"; exit 1; fi

echo "[run] Installing app to simulator..."
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_PATH"

echo "[run] Launching app..."
xcrun simctl launch "$UDID" "$BUNDLE_ID" || true
echo "[run] Done. The app should now be running in Simulator."