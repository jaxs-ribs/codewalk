# Debug Sync - Easy Access to Session Artifacts

## Problem Solved

Session artifacts in the iOS simulator are buried deep in the sandbox:
```
~/Library/Developer/CoreSimulator/Devices/{device-id}/data/Containers/Data/Application/{app-id}/Documents/sessions/
```

This made debugging annoying. You're right - it should be simple!

## Solution: Dual Storage with Perfect Sync

When running in the simulator/debug mode, **all session artifacts are automatically mirrored** to your project folder:

```
artifacts/
  debug-sessions/           # Mirror of all sessions
    {session-uuid}/
      session.json
      conversation.json
      artifacts/
        description.md
        phasing.md
        backups/

  active-session -> ...     # Symlink to currently active session (SUPER CONVENIENT!)
```

## How It Works

1. **Primary Storage**: iOS Documents directory (works on device)
2. **Mirror Storage**: Project artifacts folder (easy debugging)
3. **Automatic Sync**: Every write to primary → instant copy to mirror
4. **Active Session Symlink**: Always points to current session

## Quick Access

### Option 1: Use the active-session symlink (Easiest!)

```bash
# Always points to your current session
cat artifacts/active-session/artifacts/description.md
cat artifacts/active-session/conversation.json
ls -la artifacts/active-session/
```

### Option 2: Browse all sessions

```bash
ls -la artifacts/debug-sessions/
cat artifacts/debug-sessions/{session-id}/conversation.json
```

### Option 3: Open in Finder

```bash
open artifacts/
```

## What Gets Synced

Every write operation is immediately mirrored:

✅ Session metadata (`session.json`)
✅ Conversation history (`conversation.json`)
✅ Artifacts (`description.md`, `phasing.md`)
✅ All writes are instant - no delays

## Device vs Simulator

- **Simulator**: Debug sync enabled ✅
  - Primary: Documents directory
  - Mirror: Project artifacts folder
  - Symlink: Active session

- **Physical Device**: Debug sync disabled
  - Primary: Documents directory only
  - No mirror (can't access project folder from device)
  - Use Xcode to download container if needed

## Implementation Details

- `DebugSessionSync` detects simulator via environment variables
- Only enabled when project folder is accessible
- Zero performance impact (simple file copies)
- Logs every sync operation for transparency

## Example Workflow

```bash
# Run app in simulator
# Create some artifacts via voice
# Then immediately:

cat artifacts/active-session/artifacts/description.md
cat artifacts/active-session/conversation.json

# Or watch changes in real-time:
watch -n 1 cat artifacts/active-session/conversation.json
```

## Best of Both Worlds

You get:
1. ✅ Proper iOS-compatible storage (works on device)
2. ✅ Easy debugging access (project folder)
3. ✅ Perfect sync (no manual copying)
4. ✅ Symlink convenience (active-session points to current)

Life is simple again! 🎉
