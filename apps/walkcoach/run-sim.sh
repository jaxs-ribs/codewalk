#!/usr/bin/env bash
set -euo pipefail

# Parse command line arguments
USE_GROQ_TTS=""
USE_ELEVENLABS=""
for arg in "$@"; do
    case $arg in
        --groq-tts)
            USE_GROQ_TTS="YES"
            echo "[run] Groq TTS enabled via flag"
            ;;
        --elevenlabs)
            USE_ELEVENLABS="YES"
            echo "[run] ElevenLabs TTS enabled via flag"
            ;;
        *)
            echo "[run] Usage: $0 [--groq-tts | --elevenlabs]"
            echo "  --groq-tts    Use Groq TTS with PlayAI voices"
            echo "  --elevenlabs  Use ElevenLabs TTS (fastest, most natural)"
            echo "  (default)     Use iOS native TTS"
            ;;
    esac
done

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_YML="$APP_DIR/project.yml"
PROJ_XCODEPROJ="$APP_DIR/WalkCoach.xcodeproj"
DERIVED="$APP_DIR/build/DerivedData"
SCHEME="WalkCoach"
APP_NAME="WalkCoach"
BUNDLE_ID="com.example.walkcoach"
CONFIG="Debug"
LOG_DIR="$APP_DIR/logs"
LOG_FILE="$LOG_DIR/WalkCoach_$(date +%Y%m%d_%H%M%S).log"

echo "[run] Using project at: $APP_DIR"

# Create logs directory
mkdir -p "$LOG_DIR"
echo "[run] Logs will be saved to: $LOG_FILE"

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

echo "[run] Verifying Info.plist privacy keys..."
INFO_PLIST="$APP_PATH/Info.plist"
if [[ -f "$INFO_PLIST" ]]; then
  if ! /usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$INFO_PLIST" >/dev/null 2>&1; then
    echo "[run] Adding NSMicrophoneUsageDescription..."
    /usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string 'WalkCoach needs microphone access for voice recording.'" "$INFO_PLIST" || true
  fi
fi

echo "[run] Installing app to simulator..."
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_PATH"

echo "[run] Launching app with logging..."
if [[ -n "$USE_ELEVENLABS" ]]; then
    echo "[run] Launching with ElevenLabs TTS enabled"
    xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID" --UseElevenLabs 2>&1 | tee "$LOG_FILE" &
elif [[ -n "$USE_GROQ_TTS" ]]; then
    echo "[run] Launching with Groq TTS enabled"
    xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID" --UseGroqTTS 2>&1 | tee "$LOG_FILE" &
else
    echo "[run] Launching with iOS native TTS"
    xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID" 2>&1 | tee "$LOG_FILE" &
fi
LOG_PID=$!

echo ""
echo "=========================================="
echo "App is running!"
echo "Logs are being saved to: $LOG_FILE"
echo "Press Ctrl+C to stop"
echo "=========================================="
echo ""

# Keep script running and forward Ctrl+C to terminate app
trap "echo '[run] Stopping app...'; xcrun simctl terminate '$UDID' '$BUNDLE_ID' 2>/dev/null || true; kill $LOG_PID 2>/dev/null || true; exit 0" INT

# Wait for log process
wait $LOG_PID