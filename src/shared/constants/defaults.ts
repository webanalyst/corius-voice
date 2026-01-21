import type { Settings } from '../types'

export const DEFAULT_SETTINGS: Settings = {
  general: {
    language: 'es',
    launchAtStartup: false,
    showInMenuBar: true,
    soundEffects: true
  },
  deepgram: {
    apiKey: '',
    model: 'nova-3',
    smartFormat: true,
    utteranceEndMs: 5000
  },
  shortcuts: {
    // Use 'fn' (case-insensitive) to enable FN key mode
    // Other values use Electron globalShortcut (e.g., 'Alt+Space', 'CommandOrControl+Shift+R')
    activationKey: 'fn',
    holdThresholdMs: 3000,
    silenceTimeoutMs: 5000
  }
}

// Filler words to remove during text cleanup
export const FILLER_WORDS = {
  spanish: [
    'eh',
    'este',
    'pues',
    'bueno',
    'o sea',
    'entonces',
    'como que',
    'es que',
    'osea',
    'ósea',
    'esteee',
    'emmm',
    'mmm',
    'hmm',
    'ajá',
    'aja',
    'verdad',
    'sabes',
    'no sé',
    'digamos'
  ],
  english: [
    'um',
    'uh',
    'like',
    'you know',
    'i mean',
    'basically',
    'actually',
    'literally',
    'right',
    'so',
    'well',
    'anyway',
    'kind of',
    'sort of',
    'umm',
    'uhh',
    'err',
    'hmm',
    'mmm'
  ],
  sounds: [
    'hmm',
    'mmm',
    'emm',
    'er',
    'ah',
    'oh',
    'uh',
    'um',
    'ehh',
    'ahh',
    'ohh',
    'uhh'
  ]
}

export const DEEPGRAM_CONFIG = {
  model: 'nova-2',
  smart_format: true,
  interim_results: true,
  utterance_end_ms: 5000,
  vad_events: true,
  endpointing: 300
}
