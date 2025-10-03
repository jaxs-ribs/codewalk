#!/bin/bash
# Find Walking Computer app directory in simulator

echo "🔍 Searching for Walking Computer app in simulator..."
echo ""

# Get the most recently modified app container for WalkingComputer
APP_DIR=$(find ~/Library/Developer/CoreSimulator/Devices -name "WalkingComputer.app" 2>/dev/null | head -1)

if [ -z "$APP_DIR" ]; then
    echo "❌ App not found. Make sure to run it in the simulator first."
    exit 1
fi

# Get the device UUID from the path
DEVICE_UUID=$(echo "$APP_DIR" | grep -o 'Devices/[^/]*' | cut -d'/' -f2)

# Find the app's data container
DATA_DIR=$(find ~/Library/Developer/CoreSimulator/Devices/$DEVICE_UUID/data/Containers/Data/Application -name "Documents" -type d 2>/dev/null | while read dir; do
    if [ -d "$dir/../Library/Preferences" ]; then
        bundle_id_plist="$dir/../Library/Preferences/com.example.walkingcomputer.plist"
        if [ -f "$bundle_id_plist" ] || ls "$dir/../Library/Preferences/"*.plist 2>/dev/null | grep -q .; then
            echo "$dir"
            break
        fi
    fi
done | head -1)

# Fallback: just find the most recently modified Documents directory
if [ -z "$DATA_DIR" ]; then
    DATA_DIR=$(find ~/Library/Developer/CoreSimulator/Devices/$DEVICE_UUID/data/Containers/Data/Application -name "Documents" -type d 2>/dev/null | xargs ls -dt 2>/dev/null | head -1)
fi

if [ -z "$DATA_DIR" ]; then
    echo "❌ Could not find app data directory"
    exit 1
fi

echo "📁 App Documents Directory:"
echo "$DATA_DIR"
echo ""

if [ -d "$DATA_DIR/sessions" ]; then
    echo "📂 Sessions found:"
    ls -la "$DATA_DIR/sessions/" 2>/dev/null | grep "^d" | tail -n +2
    echo ""

    # Show contents of each session
    for session_dir in "$DATA_DIR/sessions"/*; do
        if [ -d "$session_dir" ]; then
            session_id=$(basename "$session_dir")
            echo "📦 Session: $session_id"
            echo "   Path: $session_dir"

            if [ -f "$session_dir/session.json" ]; then
                echo "   📄 session.json:"
                cat "$session_dir/session.json" | python3 -m json.tool 2>/dev/null | head -10
            fi

            if [ -f "$session_dir/conversation.json" ]; then
                msg_count=$(cat "$session_dir/conversation.json" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null)
                echo "   💬 conversation.json: $msg_count messages"
            fi

            if [ -d "$session_dir/artifacts" ]; then
                echo "   📝 Artifacts:"
                ls -lh "$session_dir/artifacts/" | grep "^-" | awk '{print "      -", $9, "("$5")"}'
            fi
            echo ""
        fi
    done
else
    echo "⚠️  No sessions directory yet. Run the app and create some artifacts first."
fi

echo ""
echo "💡 Quick commands:"
echo "   Open in Finder: open \"$DATA_DIR\""
echo "   Watch sessions:  watch -n 1 ls -lR \"$DATA_DIR/sessions\""
