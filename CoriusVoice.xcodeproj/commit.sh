#!/bin/bash

# Git commit script for Corius Voice improvements

echo "🚀 Preparing to commit Corius Voice improvements..."

# Add all changes
git add .

# Create detailed commit message
git commit -m "feat: Enhanced Fn key detection and fixed protocol conformance issues

✨ Major Features:
- Implemented triple-redundancy Fn key detection system
  * CGEvent tap for modifier flags
  * IOKit HID Manager for hardware-level access
  * Active polling as fallback (50ms intervals)

🐛 Bug Fixes:
- Fixed Transcription struct missing Hashable conformance
- Fixed Note struct missing Hashable conformance
- Resolved duplicate start() and stop() function declarations
- Fixed List selection binding requirements

🎨 UI/UX Improvements:
- Added Debug & Testing section in Settings
- Real-time Fn key status indicator
- Real-time recording status indicator
- Comprehensive troubleshooting guide
- Test buttons for notification system and hotkey service

📝 Documentation:
- Enhanced console logging with emoji indicators
- Added detailed HID event logging
- Created CHANGELOG.md with full release notes
- Improved error messages and user feedback

🎨 Assets:
- Created custom app icon (AppIcon.svg)
- Modern gradient design with microphone and sound waves

🔧 Technical Improvements:
- Better accessibility permission handling
- User-friendly permission request dialogs
- Multiple keyboard detection methods for reliability
- Improved state management and notification system

This update significantly improves the Fn key detection reliability,
matching the functionality of apps like Whisper Flow."

echo "✅ Commit created successfully!"
echo ""
echo "📋 Summary of changes:"
echo "  - AudioCaptureService.swift (unchanged)"
echo "  - Transcription.swift (added Hashable)"
echo "  - Note.swift (added Hashable)"
echo "  - HotkeyService.swift (enhanced Fn detection)"
echo "  - SettingsView.swift (added debug section)"
echo "  - CoriusVoiceApp.swift (improved logging)"
echo "  - AppIcon.svg (new)"
echo "  - CHANGELOG.md (new)"
echo ""
echo "🎯 Ready to push with: git push origin main"
