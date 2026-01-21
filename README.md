# Corius Voice

A voice-to-text app for macOS with real-time transcription using Deepgram, inspired by Wispr Flow.

## Features

- **Real-time voice transcription** using Deepgram Nova-3
- **Hybrid recording mode**: Hold Option+Space for quick recordings, or keep holding for continuous mode
- **Smart text cleanup**: Automatically removes filler words (um, uh, eh, etc.)
- **Auto-paste**: Automatically pastes transcribed text into the active app
- **Custom dictionary**: Define word replacements and corrections
- **Snippets**: Create text shortcuts that expand when spoken
- **Voice notes**: Quick note-taking with voice
- **Floating flow bar**: Visual audio feedback during recording

## Requirements

- macOS 12.0 or later
- Node.js 18+
- Deepgram API key ([Get one free](https://console.deepgram.com))

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/corius-voice.git
cd corius-voice
```

2. Install dependencies:
```bash
npm install
```

3. Create a `.env` file with your Deepgram API key:
```bash
cp .env.example .env
# Edit .env and add your DEEPGRAM_API_KEY
```

4. Start the development server:
```bash
npm run dev
```

## Usage

### Keyboard Shortcut

Press **Option+Space** (Alt+Space) to start recording:

- **Hold-to-record mode**: Hold for less than 3 seconds, release to stop and paste
- **Continuous mode**: Hold for more than 3 seconds, release to continue recording hands-free
  - Recording stops automatically after 5 seconds of silence
  - Or press Option+Space again to stop manually

### Pages

- **Home**: View your transcription history grouped by date
- **Dictionary**: Add custom word replacements (e.g., "Q3" → "Q3 Roadmap")
- **Snippets**: Create text shortcuts (e.g., "linkedin" → "https://linkedin.com/in/yourprofile")
- **Style**: Choose your preferred writing style (coming soon)
- **Notes**: Quick voice notes for yourself
- **Settings**: Configure language, API key, and shortcut behavior

## Permissions

Corius Voice requires the following macOS permissions:

1. **Microphone** - Required for voice transcription
2. **Accessibility** - Optional, enables auto-paste with Cmd+V

## Building

```bash
# Build for development
npm run build

# Package for distribution
npm run dist
```

## Tech Stack

- **Electron** - Desktop app framework
- **React 19** - UI framework
- **Tailwind CSS 4** - Styling
- **Deepgram SDK** - Real-time speech-to-text
- **electron-store** - Local data persistence
- **uiohook-napi** - Global keyboard hooks
- **Zustand** - State management

## Project Structure

```
corius-voice/
├── src/
│   ├── main/                    # Electron main process
│   │   ├── index.ts             # Entry point, app lifecycle
│   │   ├── windows/             # Window management
│   │   ├── services/            # Core services
│   │   ├── ipc/                 # IPC handlers
│   │   └── utils/               # Utilities
│   ├── preload/                 # Preload scripts
│   ├── renderer/                # Main React app
│   │   └── src/
│   │       ├── components/      # UI components
│   │       ├── pages/           # App pages
│   │       ├── stores/          # Zustand stores
│   │       └── lib/             # Utilities
│   ├── renderer-flowbar/        # Flow bar overlay
│   └── shared/                  # Shared types and constants
├── resources/                   # App resources
└── build/                       # Build configuration
```

## License

MIT
