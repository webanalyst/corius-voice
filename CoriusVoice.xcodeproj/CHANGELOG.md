# Changelog - Corius Voice

## [Unreleased] - 2026-01-21

### Fixed
- ✅ Fixed `Transcription` struct not conforming to `Hashable` protocol
- ✅ Fixed `Note` struct not conforming to `Hashable` protocol
- ✅ Resolved duplicate function declarations in `HotkeyService`

### Added
- 🎯 **Enhanced Fn Key Detection System**
  - Method 1: CGEvent tap for modifier flags (primary method)
  - Method 2: IOKit HID Manager for direct keyboard hardware access
  - Method 3: Active polling as fallback mechanism (50ms intervals)
  
- 🐛 **Debug & Testing Section in Settings**
  - Real-time Fn key status indicator
  - Real-time recording status indicator
  - Test notification system button
  - Restart hotkey service button
  - Comprehensive troubleshooting guide
  
- 📝 **Improved Logging**
  - Enhanced console logging with emojis for better readability
  - Detailed flag state reporting
  - HID event logging for debugging
  - Polling state tracking

- 🎨 **Custom App Icon**
  - Modern gradient design (purple to blue)
  - Microphone icon with sound waves
  - Audio bars and glow effects
  - SVG format for easy scaling

### Improved
- 🔧 Better accessibility permission handling with user-friendly alerts
- 📊 More detailed error messages and state tracking
- 🎤 Multiple detection methods ensure Fn key works reliably
- 💬 Clear user instructions in Settings UI

### Technical Details
The Fn key detection now uses a triple-redundancy approach:
1. **CGEvent API**: Detects `maskSecondaryFn` flag in keyboard events
2. **IOKit HID**: Direct hardware-level keyboard monitoring
3. **Polling**: Continuously checks modifier key state as fallback

This ensures maximum compatibility across different Mac keyboards and configurations.

### Notes
- Requires Accessibility permissions for full functionality
- Tested with macOS 13.0 and later
- Compatible with both internal and external keyboards
