// Transcription types
export interface Transcription {
  id: string
  text: string
  cleanedText: string
  timestamp: number
  duration: number
  language: string
}

export interface TranscriptionResult {
  text: string
  isFinal: boolean
  confidence: number
  words?: Word[]
}

export interface Word {
  word: string
  start: number
  end: number
  confidence: number
}

// Dictionary types
export interface DictionaryEntry {
  id: string
  original: string
  replacement: string
  enabled: boolean
  createdAt: number
}

// Snippet types
export interface Snippet {
  id: string
  trigger: string
  content: string
  enabled: boolean
  createdAt: number
}

// Note types
export interface Note {
  id: string
  text: string
  timestamp: number
  duration: number
}

// Settings types
export interface Settings {
  general: GeneralSettings
  deepgram: DeepgramSettings
  shortcuts: ShortcutSettings
}

export interface GeneralSettings {
  language: 'es' | 'en' | 'auto'
  launchAtStartup: boolean
  showInMenuBar: boolean
  soundEffects: boolean
}

export interface DeepgramSettings {
  apiKey: string
  model: string
  smartFormat: boolean
  utteranceEndMs: number
}

export interface ShortcutSettings {
  activationKey: string
  holdThresholdMs: number
  silenceTimeoutMs: number
}

// Recording state
export type RecordingMode = 'idle' | 'hold' | 'continuous'

export interface RecordingState {
  isRecording: boolean
  mode: RecordingMode
  startTime: number | null
  interimText: string
  finalText: string
}

// Audio data for visualizer
export interface AudioData {
  levels: number[]
  timestamp: number
}

// Store data structure
export interface StoreData {
  transcriptions: Transcription[]
  dictionary: DictionaryEntry[]
  snippets: Snippet[]
  notes: Note[]
  settings: Settings
}
