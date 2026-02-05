# Corius Voice

A native macOS voice-to-text app with real-time transcription, speaker diarization, and voice profile training.

## Features

- **Real-time voice transcription** using Deepgram Nova-3 (cloud) or WhisperKit (local)
- **Speaker diarization** with FluidAudio - identifies who said what
- **Voice profile training** - train the app to recognize known speakers using 256-dim embeddings
- **Hybrid recording mode**: Hold Fn key for quick recordings, or use continuous mode
- **Smart text cleanup**: Automatically removes filler words (um, uh, eh, etc.)
- **Auto-paste**: Automatically pastes transcribed text into the active app
- **Custom dictionary**: Define word replacements and corrections
- **Snippets**: Create text shortcuts that expand when spoken
- **Voice notes**: Quick note-taking with voice
- **Floating flow bar**: Visual audio feedback during recording
- **Session playback**: Review and edit past transcription sessions
- **AI chat**: Ask questions about your transcriptions using OpenRouter

## Requirements

- macOS 14.0 or later
- Xcode 15+
- Deepgram API key ([Get one free](https://console.deepgram.com)) - for cloud transcription
- OpenRouter API key (optional) - for AI chat features

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/corius-voice.git
cd corius-voice
```

2. Open the Xcode project:
```bash
open CoriusVoice.xcodeproj
```

3. Build and run (⌘R)

4. Grant permissions when prompted:
   - **Microphone** - Required for voice transcription
   - **Accessibility** - Required for Fn key detection and auto-paste

5. Configure your API keys in Settings:
   - Deepgram API key for cloud transcription
   - OpenRouter API key for AI chat (optional)

## Usage

### Recording

- **Fn key**: Press and hold to record, release to stop and transcribe
- **Option+Space**: Alternative shortcut for recording
- **Continuous mode**: Hold for 3+ seconds, then release to continue hands-free

### Transcription Modes

- **Cloud (Deepgram)**: Fast, accurate, requires internet. Best for real-time dictation.
- **Local (Whisper)**: Private, offline. Models are downloaded on first use (~1-2GB).

### Speaker Features

1. **Diarization**: Enable in Settings to identify different speakers
2. **Speaker Library**: Add known speakers with custom colors
3. **Voice Training**: Assign speakers in a session, then train voice profiles
4. **Auto-identification**: Future recordings can auto-identify trained speakers

## Architecture

```
CoriusVoice/
├── CoriusVoiceApp.swift        # App entry point & AppState
├── Models/                     # Data models (RecordingSession, Speaker, Settings, etc.)
├── Services/                   # Core services
│   ├── DeepgramService.swift   # Cloud transcription via WebSocket
│   ├── WhisperService.swift    # Local transcription with WhisperKit
│   ├── LocalDiarizationService.swift  # FluidAudio diarization + embeddings
│   ├── VoiceProfileService.swift      # Voice training & identification
│   ├── RecordingService.swift  # Recording orchestration
│   └── ...
├── Views/                      # SwiftUI views
└── ViewModels/                 # View models
```

## Voice Identification

Corius Voice uses two methods for speaker identification:

1. **Modern (Embeddings)**: 256-dimensional speaker embeddings from FluidAudio's WeSpeaker model. Higher accuracy, requires macOS 14+.

2. **Legacy (Features)**: MFCCs, pitch, and energy features. Works on older macOS, serves as fallback.

Training prioritizes embeddings when available, falling back to legacy features only when necessary.

## License

MIT License - see LICENSE file for details.
