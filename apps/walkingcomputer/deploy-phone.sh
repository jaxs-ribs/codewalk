#!/bin/bash
# deploy-phone.sh
set -euo pipefail

# ---------- Colors ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
die(){ echo -e "${RED}❌ $*${NC}"; exit 1; }
ok(){  echo -e "${GREEN}✓ $*${NC}"; }
warn(){ echo -e "${YELLOW}⚠️  $*${NC}"; }

# ---------- Flags (match simulator script) ----------
USE_GROQ_TTS=""; USE_ELEVENLABS=""; USE_AVALON_STT=""
for arg in "$@"; do
  case "$arg" in
    --groq-tts)   USE_GROQ_TTS="YES";   echo "[run] Groq TTS enabled via flag";;
    --elevenlabs) USE_ELEVENLABS="YES"; echo "[run] ElevenLabs TTS enabled via flag";;
    --avalon-stt) USE_AVALON_STT="YES"; echo "[run] Avalon STT enabled via flag";;
    *) echo "[run] Usage: $0 [--groq-tts | --elevenlabs] [--avalon-stt]";;
  esac
done

# ---------- Paths / config ----------
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$APP_DIR/WalkingComputer.xcworkspace"
PROJECT="$APP_DIR/WalkingComputer.xcodeproj"
SCHEME="WalkingComputer"
CONFIG="Debug"
DERIVED="$APP_DIR/build"
APP_NAME="WalkingComputer"
BUNDLE_ID="com.lucbaracat.walkingcomputer"

echo "[run] Using project at: $APP_DIR"

# ---------- Tool checks ----------
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found (install Xcode)."
command -v xcrun >/dev/null 2>&1 || die "xcrun not found (install Xcode)."
command -v ios-deploy >/dev/null 2>&1 || die "ios-deploy not found. Install with: brew install ios-deploy"

# Optional: regenerate project if XcodeGen exists
if [ -f "$APP_DIR/project.yml" ] && command -v xcodegen >/dev/null 2>&1; then
  echo "[run] Regenerating Xcode project with XcodeGen..."
  (cd "$APP_DIR" && xcodegen generate) || true
fi

# ---------- Fast DDI/activation sanity ----------
if xcrun devicectl list devices 2>/dev/null | grep -Eiq 'connected \(no DDI\)'; then
  die "Device is connected but Developer Disk Image is not mounted.
Open Xcode → Window → Devices and Simulators and let it finish preparing the device (no 'no DDI' banner)."
fi

# ---------- Resolve physical device UDID ----------
echo "🔍 Resolving UDID for physical device..."
XCTRACE="$(xcrun xctrace list devices 2>/dev/null || true)"
LINE="$(echo "$XCTRACE" | grep -E 'iPhone|iPad' | grep -vi 'Simulator' | grep -E '\([0-9A-F-]{25,}\)$' | head -1 || true)"
[ -z "$LINE" ] && die "No physical iOS device found by xctrace. Is the phone unlocked, trusted, and prepared in Xcode?"
DEVICE_UDID="$(echo "$LINE" | grep -Eo '\([0-9A-F-]{25,}\)$' | tr -d '()')"
DEVICE_NAME="$(echo "$LINE" | sed -E 's/ *\([0-9A-F-]{25,}\)$//' | sed -E 's/ +$//')"
ok "Found: $DEVICE_NAME ($DEVICE_UDID)"

# ---------- Workspace or project ----------
BUILD_TARGET=()
if [ -f "$WORKSPACE" ]; then
  BUILD_TARGET=(-workspace "$WORKSPACE")
else
  BUILD_TARGET=(-project "$PROJECT")
fi
echo "🧱 Build target: ${BUILD_TARGET[*]:-<none>}"

# ---------- Team ID (non-fatal) ----------
echo "🔍 Looking for development team..."
TEAM_ID=""
if [ -f "$PROJECT/project.pbxproj" ]; then
  TEAM_ID="$((grep -m1 'DEVELOPMENT_TEAM = ' "$PROJECT/project.pbxproj" || true) | sed -E 's/.*DEVELOPMENT_TEAM = ([A-Z0-9]+);/\1/' || true)"
fi
if [ -z "$TEAM_ID" ]; then
  TEAM_ID="$(
    security find-identity -p codesigning -v 2>/dev/null \
      | grep 'Apple Development' | head -1 \
      | sed -E 's/.*\(([A-Z0-9]{10})\).*/\1/' || true
  )"
fi
if [ -n "$TEAM_ID" ]; then ok "Using team: $TEAM_ID"; else warn "No team found; Xcode will try auto-provisioning."; fi

# ---------- Build for device (iphoneos) ----------
echo ""
echo "🔨 Building for device…"
echo "  Scheme: $SCHEME"
echo "  Config: $CONFIG"
echo "  Device: $DEVICE_UDID"
[ -n "$TEAM_ID" ] && echo "  Team:   $TEAM_ID"

echo "🧹 Cleaning previous builds…"
rm -rf "$DERIVED"

BUILD_CMD=(xcodebuild "${BUILD_TARGET[@]}"
  -scheme "$SCHEME"
  -configuration "$CONFIG"
  -destination "platform=iOS,id=$DEVICE_UDID"
  -derivedDataPath "$DERIVED"
  -sdk iphoneos
  CODE_SIGN_IDENTITY="Apple Development"
  -allowProvisioningUpdates
)
[ -n "$TEAM_ID" ] && BUILD_CMD+=("DEVELOPMENT_TEAM=$TEAM_ID")

echo "🛠️  Starting xcodebuild…"
"${BUILD_CMD[@]}"

APP_PATH="$DERIVED/Build/Products/$CONFIG-iphoneos/$APP_NAME.app"
[ -d "$APP_PATH" ] || die "Built app not found at: $APP_PATH"

# ---------- Launch args ----------
LAUNCH_ARGS=()
if [ -n "$USE_ELEVENLABS" ]; then
  LAUNCH_ARGS+=(--UseElevenLabs); echo "[run] Using ElevenLabs TTS"
elif [ -n "$USE_GROQ_TTS" ]; then
  LAUNCH_ARGS+=(--UseGroqTTS);    echo "[run] Using Groq TTS"
else
  echo "[run] Using iOS native TTS"
fi

if [ -n "$USE_AVALON_STT" ]; then
  LAUNCH_ARGS+=(--avalon-stt); echo "[run] Using Avalon STT for transcription"
else
  echo "[run] Using Groq STT for transcription"
fi

# ---------- Install & launch ----------
echo "📲 Installing to $DEVICE_NAME…"
# Ensure uninstall to avoid “already installed” + mismatched signature issues
ios-deploy --id "$DEVICE_UDID" --uninstall_only --bundle_id "$BUNDLE_ID" >/dev/null 2>&1 || true
ios-deploy --id "$DEVICE_UDID" --bundle "$APP_PATH"

echo "▶️  Launching with args: ${LAUNCH_ARGS[*]:-<none>}"
ios-deploy --id "$DEVICE_UDID" --bundle "$APP_PATH" --justlaunch ${LAUNCH_ARGS:+--args "${LAUNCH_ARGS[*]}"}

ok "App installed and launched on $DEVICE_NAME"
echo "⏰ If using a free Apple ID, the installed app expires in ~7 days; rerun to refresh."
