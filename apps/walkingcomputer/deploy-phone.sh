#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "📱 Walking Computer Phone Deployer"
echo "=================================="

# Configuration - adjust these if needed
SCHEME="WalkingComputer"
WORKSPACE="WalkingComputer.xcworkspace"
PROJECT="WalkingComputer.xcodeproj"
CONFIGURATION="Debug"

# Auto-detect if workspace exists, otherwise use project
if [ -f "$WORKSPACE" ]; then
    BUILD_TARGET="-workspace $WORKSPACE"
else
    BUILD_TARGET="-project $PROJECT"
fi

# Function to get connected device
get_device_id() {
    echo "🔍 Looking for connected iPhone..."

    # Try using devicectl first (newer Xcode)
    if command -v xcrun &> /dev/null; then
        DEVICE_INFO=$(xcrun devicectl device list 2>/dev/null | grep -E "iPhone.*connected" | head -1 || true)
        if [ ! -z "$DEVICE_INFO" ]; then
            DEVICE_ID=$(echo "$DEVICE_INFO" | awk '{print $1}')
            DEVICE_NAME=$(echo "$DEVICE_INFO" | sed 's/.*iPhone/iPhone/' | sed 's/ connected.*//')
            echo -e "${GREEN}✓ Found: $DEVICE_NAME ($DEVICE_ID)${NC}"
            return 0
        fi
    fi

    # Fallback to older instruments method
    DEVICE_INFO=$(instruments -s devices 2>/dev/null | grep -E "iPhone.*\[" | grep -v "Simulator" | head -1 || true)
    if [ ! -z "$DEVICE_INFO" ]; then
        DEVICE_ID=$(echo "$DEVICE_INFO" | sed 's/.*\[//' | sed 's/\].*//')
        DEVICE_NAME=$(echo "$DEVICE_INFO" | sed 's/ \[.*//')
        echo -e "${GREEN}✓ Found: $DEVICE_NAME ($DEVICE_ID)${NC}"
        return 0
    fi

    echo -e "${RED}❌ No iPhone detected. Please connect your iPhone via USB cable.${NC}"
    echo "   Make sure to:"
    echo "   1. Unlock your iPhone"
    echo "   2. Trust this computer if prompted"
    exit 1
}

# Function to get development team ID
get_team_id() {
    echo "🔍 Looking for development team..."

    # Try to extract from pbxproj
    if [ -f "$PROJECT/project.pbxproj" ]; then
        TEAM_ID=$(grep -m1 "DEVELOPMENT_TEAM = " "$PROJECT/project.pbxproj" | sed 's/.*DEVELOPMENT_TEAM = //' | sed 's/;//' | tr -d ' ')
    fi

    # If not found, try security command
    if [ -z "$TEAM_ID" ]; then
        TEAM_ID=$(security find-identity -p codesigning -v | grep "Apple Development" | head -1 | sed 's/.*(\(.*\)).*/\1/' | cut -d: -f1)
    fi

    if [ ! -z "$TEAM_ID" ]; then
        echo -e "${GREEN}✓ Using team: $TEAM_ID${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not auto-detect team ID${NC}"
        echo "   You may need to open Xcode and set up signing first"
    fi
}

# Main deployment
get_device_id
get_team_id

echo ""
echo "🔨 Building for device..."
echo "  Scheme: $SCHEME"
echo "  Device: $DEVICE_ID"
if [ ! -z "$TEAM_ID" ]; then
    echo "  Team: $TEAM_ID"
fi

# Build command
BUILD_CMD="xcodebuild $BUILD_TARGET \
    -scheme \"$SCHEME\" \
    -configuration $CONFIGURATION \
    -destination \"platform=iOS,id=$DEVICE_ID\" \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY=\"Apple Development\" \
    -allowProvisioningUpdates"

# Add team ID if we have it
if [ ! -z "$TEAM_ID" ]; then
    BUILD_CMD="$BUILD_CMD DEVELOPMENT_TEAM=\"$TEAM_ID\""
fi

# Clean build folder
echo "🧹 Cleaning previous builds..."
rm -rf build/

# Execute build
echo "🚀 Building and installing (this may take a minute)..."
if eval $BUILD_CMD; then
    echo -e "${GREEN}✅ Successfully deployed to $DEVICE_NAME!${NC}"
    echo ""
    echo "📱 Next steps:"
    echo "   1. On your iPhone, go to Settings → General → Device Management"
    echo "   2. Trust your developer certificate if prompted"
    echo "   3. Launch Walking Computer from your home screen"
    echo ""
    echo "⏰ Remember: The app will expire in 7 days ($(date -v +7d +%Y-%m-%d))"
    echo "   Run this script again to refresh it!"

    # Optional: Try to launch the app
    if command -v ios-deploy &> /dev/null; then
        echo ""
        echo "🚀 Attempting to launch app..."
        APP_PATH=$(find build -name "*.app" -type d | head -1)
        ios-deploy --justlaunch --bundle "$APP_PATH" --id "$DEVICE_ID" 2>/dev/null || true
    fi
else
    echo -e "${RED}❌ Build failed. Check the error messages above.${NC}"
    echo ""
    echo "Common fixes:"
    echo "  • Open project in Xcode and fix any signing issues"
    echo "  • Make sure your Apple ID is signed in (Xcode → Preferences → Accounts)"
    echo "  • Try building once manually in Xcode first"
    exit 1
fi