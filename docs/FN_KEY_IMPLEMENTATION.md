# FN Key Implementation - Technical Documentation

## Overview

This document describes the implementation of FN key detection for Corius Voice on macOS, enabling users to use the FN key as a global hotkey similar to Wispr Flow.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Electron Main Process                     │
│  ┌───────────────────────────────────────────────────────┐  │
│  │               ShortcutService                          │  │
│  │  • Detects activation mode from settings               │  │
│  │  • Routes to FnKeyService or globalShortcut            │  │
│  └──────────────────────┬────────────────────────────────┘  │
│                         │                                    │
│  ┌──────────────────────┴────────────────────────────────┐  │
│  │               FnKeyService (fnkey.service.ts)          │  │
│  │  • Spawns native helper binary                         │  │
│  │  • Connects via Unix Domain Socket                     │  │
│  │  • EventEmitter: 'fn-down' / 'fn-up'                   │  │
│  └──────────────────────┬────────────────────────────────┘  │
└─────────────────────────┼───────────────────────────────────┘
                          │ Unix Socket: /tmp/corius-fnkey.sock
                          │
┌─────────────────────────┴───────────────────────────────────┐
│              FnKeyHelper (Swift CLI Binary)                  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  NSEvent.addGlobalMonitorForEvents(.flagsChanged)      │  │
│  │  • Monitors modifier key changes                       │  │
│  │  • Detects .function flag for FN key                   │  │
│  │  • Sends JSON events via Unix Socket                   │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Native Helper (Swift)

**Location:** `native/FnKeyHelper/Sources/main.swift`

The Swift helper uses `NSEvent.addGlobalMonitorForEvents` to detect FN key events:

```swift
// Monitor flags changed events (modifier keys including FN)
globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
    let fnPressed = event.modifierFlags.contains(.function)
    // Handle FN state change...
}
```

**Why NSEvent instead of IOKit HID?**
- `NSEvent` with `.flagsChanged` is the most reliable way to detect FN on modern macOS
- It properly detects the `.function` modifier flag
- Less complex than raw IOKit HID access
- Works consistently across macOS Ventura, Sonoma, and Sequoia

**Communication Protocol:**
- Unix Domain Socket at `/tmp/corius-fnkey.sock`
- JSON messages with newline delimiter:
  ```json
  {"event": "fn-down", "data": {"timestamp": 1234567890.123}}
  {"event": "fn-up", "data": {"timestamp": 1234567890.456}}
  ```

### 2. FnKeyService (TypeScript)

**Location:** `src/main/services/fnkey.service.ts`

Node.js service that:
1. Spawns the native helper binary
2. Connects to the Unix socket
3. Parses JSON events
4. Emits typed events to the application

```typescript
// Usage
fnKeyService.on('fn-down', () => { /* start recording */ })
fnKeyService.on('fn-up', () => { /* stop recording */ })
await fnKeyService.start()
```

### 3. ShortcutService Integration

**Location:** `src/main/services/shortcut.service.ts`

The ShortcutService now supports two activation modes:

1. **keyboard-shortcut** (default): Uses Electron's `globalShortcut`
2. **fn-key**: Uses the native FnKeyHelper

Mode is determined by the `activationKey` setting:
- If set to `"fn"` (case-insensitive) → FN key mode
- Otherwise → Standard keyboard shortcut mode

## Build Process

### Prerequisites

- Xcode Command Line Tools (`xcode-select --install`)
- Swift 5.7+

### Building

```bash
# Build everything (native + Electron)
npm run build

# Build native helper only
npm run build:native

# Build for distribution
npm run dist
```

### Build Script

The native helper is built using Swift Package Manager:

```bash
cd native/FnKeyHelper
swift build -c release
```

Output binary: `resources/bin/FnKeyHelper`

## Permissions

### Required macOS Permissions

1. **Accessibility** (already configured)
   - System Preferences → Privacy & Security → Accessibility
   - Required for global event monitoring

2. **Input Monitoring** (may be required on some systems)
   - System Preferences → Privacy & Security → Input Monitoring
   - Required in macOS Catalina+ for keyboard event monitoring

### Entitlements

The app's entitlements (`build/entitlements.mac.plist`) already include:
- `com.apple.security.automation.apple-events` - For AppleScript automation
- `com.apple.security.device.audio-input` - For microphone access

## Usage

### Configuration

To enable FN key activation, set `activationKey` to `"fn"` in settings:

```typescript
// In your settings
{
  "shortcuts": {
    "activationKey": "fn"  // or "Fn" or "FN"
  }
}
```

### Behavior

- **FN Press:** Starts recording (hold mode)
- **FN Release within 3s:** Stops recording, pastes transcription
- **FN Hold > 3s:** Switches to continuous mode
- **FN Press in continuous mode:** Stops recording

This matches the Wispr Flow behavior exactly.

## Troubleshooting

### Helper Not Starting

1. Check if binary exists: `ls -la resources/bin/FnKeyHelper`
2. Check permissions: `chmod +x resources/bin/FnKeyHelper`
3. Try running manually: `./resources/bin/FnKeyHelper --help`

### FN Key Not Detected

1. Grant Accessibility permission in System Preferences
2. Grant Input Monitoring permission (if prompted)
3. Restart the application after granting permissions

### Socket Connection Failed

1. Check if socket exists: `ls -la /tmp/corius-fnkey.sock`
2. Remove stale socket: `rm /tmp/corius-fnkey.sock`
3. Restart the application

### Debug Logs

The helper writes logs to stderr. View with:
```bash
./resources/bin/FnKeyHelper 2>&1 | tee helper.log
```

## File Structure

```
corius-voice/
├── native/
│   └── FnKeyHelper/
│       ├── Package.swift          # Swift package manifest
│       ├── build.sh               # Build script
│       └── Sources/
│           └── main.swift         # Helper source code
├── resources/
│   └── bin/
│       └── FnKeyHelper            # Compiled binary
├── src/
│   └── main/
│       └── services/
│           ├── fnkey.service.ts   # Node.js FN key service
│           └── shortcut.service.ts # Updated shortcut service
├── build/
│   └── entitlements.mac.plist     # macOS entitlements
└── docs/
    └── FN_KEY_IMPLEMENTATION.md   # This file
```

## Compatibility

| macOS Version | Status | Notes |
|---------------|--------|-------|
| Ventura (13)  | ✅     | Fully supported |
| Sonoma (14)   | ✅     | Fully supported |
| Sequoia (15)  | ✅     | Fully supported |

## Known Limitations

1. **External keyboards:** Some non-Apple keyboards may not send FN events in the same way. The helper should still work, but behavior may vary.

2. **Keyboard Maestro / Karabiner conflicts:** If other software is modifying keyboard events, there may be conflicts. Ensure no other software is remapping the FN key.

3. **Touch Bar MacBooks:** FN key works normally on Touch Bar MacBooks.

## Security Considerations

- The helper runs as a subprocess of the Electron app
- No network access required (Unix socket only)
- Socket permissions are restricted to local user
- Helper terminates when parent process exits
