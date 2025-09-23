#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_YML="$APP_DIR/project.yml"
PROJ_XCODEPROJ="$APP_DIR/VoiceRelaySwiftUI.xcodeproj"
DERIVED="$APP_DIR/build/DerivedData"
SCHEME="VoiceRelaySwiftUI"
APP_NAME="VoiceRelaySwiftUI"
BUNDLE_ID="com.example.voicerelayswiftui"
CONFIG="Debug"
LOG_FILE="$APP_DIR/app_debug.log"

echo "[run] Using project at: $APP_DIR"
echo "[run] Logs will be written to: $LOG_FILE"

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
  build | xcpretty || true

APP_PATH="$DERIVED/Build/Products/$CONFIG-iphonesimulator/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then echo "[run] App not found at $APP_PATH"; exit 1; fi

echo "[run] Verifying Info.plist privacy keys..."
INFO_PLIST="$APP_PATH/Info.plist"
if [[ -f "$INFO_PLIST" ]]; then
  if ! /usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$INFO_PLIST" >/dev/null 2>&1; then
    echo "[run] NSMicrophoneUsageDescription missing; adding default message"
    /usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string 'We use the microphone to capture voice commands for transcription.'" "$INFO_PLIST" || true
  fi
  # Looser ATS for local dev and ws/http on 127.0.0.1
  if ! /usr/libexec/PlistBuddy -c "Print :NSAppTransportSecurity" "$INFO_PLIST" >/dev/null 2>&1; then
    echo "[run] Adding NSAppTransportSecurity overrides for dev"
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "$INFO_PLIST" || true
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool YES" "$INFO_PLIST" || true
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool YES" "$INFO_PLIST" || true
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains dict" "$INFO_PLIST" || true
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:api.groq.com dict" "$INFO_PLIST" || true
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:api.groq.com:NSIncludesSubdomains bool YES" "$INFO_PLIST" || true
    /usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSExceptionDomains:api.groq.com:NSTemporaryExceptionMinimumTLSVersion string TLSv1.2" "$INFO_PLIST" || true
  fi
  # Add fullscreen and UI settings
  if ! /usr/libexec/PlistBuddy -c "Print :UIRequiresFullScreen" "$INFO_PLIST" >/dev/null 2>&1; then
    echo "[run] Adding fullscreen and UI settings"
    /usr/libexec/PlistBuddy -c "Add :UIRequiresFullScreen bool YES" "$INFO_PLIST" || true
    /usr/libexec/PlistBuddy -c "Add :UIStatusBarStyle string UIStatusBarStyleLightContent" "$INFO_PLIST" || true
    /usr/libexec/PlistBuddy -c "Add :UIViewControllerBasedStatusBarAppearance bool NO" "$INFO_PLIST" || true
    /usr/libexec/PlistBuddy -c "Add :UILaunchScreen dict" "$INFO_PLIST" || true
    /usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations array" "$INFO_PLIST" || true
    /usr/libexec/PlistBuddy -c "Add :UISupportedInterfaceOrientations:0 string UIInterfaceOrientationPortrait" "$INFO_PLIST" || true
  fi
fi

echo "[run] Installing app to simulator..."
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_PATH"

echo "[run] Starting log capture..."
# Clear the log file
> "$LOG_FILE"

# Start capturing logs in background
echo "[run] Capturing logs to $LOG_FILE (tail -f $LOG_FILE to watch)"
echo "========== Log started at $(date) ==========" >> "$LOG_FILE"

# Method 1: Using xcrun simctl spawn to capture stdout/stderr
# This launches the app and pipes its output
xcrun simctl spawn "$UDID" log stream --predicate "processImagePath CONTAINS 'VoiceRelaySwiftUI'" --style compact >> "$LOG_FILE" 2>&1 &
LOG_PID=$!

# Give log stream a moment to start
sleep 1

echo "[run] Launching app..."
xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID" >> "$LOG_FILE" 2>&1 &
APP_PID=$!

echo "[run] App launched. Logs are being written to: $LOG_FILE"
echo "[run] Commands:"
echo "  - Watch logs:     tail -f $LOG_FILE"
echo "  - Filter DEBUG:   tail -f $LOG_FILE | grep DEBUG"
echo "  - Stop logging:   kill $LOG_PID"
echo ""
echo "[run] Press Ctrl+C to stop log capture and exit"

# Wait for Ctrl+C
trap "kill $LOG_PID 2>/dev/null; kill $APP_PID 2>/dev/null; exit" INT
wait