# Copilot Instructions for Corius Voice

## Project Overview

Corius Voice is a native macOS app (Swift/SwiftUI) for real-time voice-to-text transcription, speaker diarization, and voice profile training. Inspired by Wispr Flow.

## Build & Development

### Quick Start

- Open `CoriusVoice.xcodeproj` in Xcode
- Build & Run the CoriusVoice target (⌘R)

### Requirements

- macOS 14+
- Xcode 15+
- Microphone & Accessibility permissions

## Architecture

### App Structure

```
CoriusVoice/
├── CoriusVoiceApp.swift        # App entry point & AppState
├── Models/                     # Data models (RecordingSession, Speaker, Settings, etc.)
├── Services/                   # Core services
├── Views/                      # SwiftUI views
├── ViewModels/                 # View models
└── Utilities/                  # Helpers & extensions
```

### Key Services

- **RecordingService**: Recording flow, session lifecycle
- **DeepgramService**: Cloud transcription via WebSocket
- **WhisperService**: Local transcription with WhisperKit
- **LocalDiarizationService**: On-device diarization + 256-dim speaker embeddings (FluidAudio)
- **VoiceProfileService**: Voice training & speaker identification (embeddings preferred, legacy features as fallback)
- **StorageService**: Persistence (sessions, settings, notes)

## Recording & Training Flow

1. Record a session (mic/system/both)
2. Transcribe (Deepgram cloud or Whisper local)
3. Diarization identifies speakers (if enabled)
4. Assign speakers to library (link to known speakers)
5. Train voice profiles (uses 256-dim embeddings when available)
6. Auto-identify speakers in future sessions

## Voice Identification

Two methods available:

1. **Modern (Embeddings)**: 256-dim speaker embeddings from FluidAudio/WeSpeaker. Higher accuracy, preferred method.
2. **Legacy (Features)**: MFCCs, pitch, energy. Fallback when embeddings unavailable.

Training prioritizes embeddings → extraction via FluidAudio → legacy features fallback.

## Conventions

- Use `StorageService` for persistence
- Use `SpeakerLibrary` for known speakers
- Use `VoiceProfileService` for training/identification
- Keep UI changes in SwiftUI; preserve existing visual style
- Console logs use emoji prefixes (🎤, 🧬, 📝, 🔊) for filtering

## Build & Verify

After every change:
1. Build in Xcode (⌘B)
2. Check Issue Navigator for errors (⌘⇧M)
3. Fix any errors before proceeding

## Debugging

- Use Console.app to view logs
- Filter by process name or emoji prefixes
- Check System Settings for microphone/accessibility permissions
