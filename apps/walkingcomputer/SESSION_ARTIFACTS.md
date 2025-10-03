# Finding Session Artifacts

## Overview

When running in the iOS Simulator, all session artifacts are stored in the app's sandboxed Documents directory:

```
{app-documents}/sessions/
  {session-uuid}/
    session.json          # Session metadata (id, timestamps)
    conversation.json     # Full conversation history
    artifacts/
      description.md      # Project description
      phasing.md         # Project phases
      backups/           # Artifact backups
```

## Quick Access

### Method 1: Use the finder script (Easiest)

```bash
./find-sessions.sh
```

This will:
- Find the app's Documents directory in the simulator
- List all sessions
- Show session contents (metadata, message count, artifacts)
- Provide quick commands to open in Finder

### Method 2: Check Xcode logs

When the app launches, it logs the sessions directory path:

```
📁 Sessions directory: /Users/.../Documents/sessions
```

Look for this line in the Xcode console output.

### Method 3: Manual lookup (Advanced)

The full path is typically:
```
~/Library/Developer/CoreSimulator/Devices/{device-uuid}/data/Containers/Data/Application/{app-uuid}/Documents/sessions/
```

## Quick Commands

Once you have the path from `find-sessions.sh`:

```bash
# Open in Finder
open "/path/to/Documents"

# Watch sessions in real-time
watch -n 1 ls -lR "/path/to/Documents/sessions"

# View a specific session's conversation
cat "/path/to/Documents/sessions/{session-id}/conversation.json" | python3 -m json.tool

# View a specific artifact
cat "/path/to/Documents/sessions/{session-id}/artifacts/description.md"
```

## On Physical Device

When deployed to a physical device, artifacts are stored in the app's sandboxed Documents directory. You can access them:

1. Via Xcode: Window → Devices and Simulators → Select device → Select app → Download Container
2. Via Files app: If you enable "Supports iTunes file sharing" in Info.plist
3. Via iCloud sync: If you implement iCloud Documents support

Currently optimized for simulator development.
