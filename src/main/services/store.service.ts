import Store from 'electron-store'
import type {
  StoreData,
  Transcription,
  DictionaryEntry,
  Snippet,
  Note,
  Settings
} from '../../shared/types'
import { DEFAULT_SETTINGS } from '../../shared/constants/defaults'

let store: Store<StoreData> | null = null

export function initStore(): void {
  store = new Store<StoreData>({
    name: 'corius-voice-data',
    defaults: {
      transcriptions: [],
      dictionary: [],
      snippets: [],
      notes: [],
      settings: DEFAULT_SETTINGS
    }
  })
}

export function getStore(): Store<StoreData> {
  if (!store) {
    throw new Error('Store not initialized. Call initStore() first.')
  }
  return store
}

// Settings
export function getSettings(): Settings {
  return getStore().get('settings')
}

export function setSettings(settings: Partial<Settings>): void {
  const current = getSettings()
  getStore().set('settings', { ...current, ...settings })
}

export function getDeepgramApiKey(): string {
  return getSettings().deepgram.apiKey || process.env.DEEPGRAM_API_KEY || ''
}

// Transcriptions
export function getTranscriptions(): Transcription[] {
  return getStore().get('transcriptions')
}

export function addTranscription(transcription: Transcription): void {
  const transcriptions = getTranscriptions()
  transcriptions.unshift(transcription)
  // Keep only last 1000 transcriptions
  if (transcriptions.length > 1000) {
    transcriptions.pop()
  }
  getStore().set('transcriptions', transcriptions)
}

export function deleteTranscription(id: string): void {
  const transcriptions = getTranscriptions().filter((t) => t.id !== id)
  getStore().set('transcriptions', transcriptions)
}

export function clearTranscriptions(): void {
  getStore().set('transcriptions', [])
}

// Dictionary
export function getDictionary(): DictionaryEntry[] {
  return getStore().get('dictionary')
}

export function addDictionaryEntry(entry: DictionaryEntry): void {
  const dictionary = getDictionary()
  dictionary.push(entry)
  getStore().set('dictionary', dictionary)
}

export function updateDictionaryEntry(id: string, updates: Partial<DictionaryEntry>): void {
  const dictionary = getDictionary().map((entry) =>
    entry.id === id ? { ...entry, ...updates } : entry
  )
  getStore().set('dictionary', dictionary)
}

export function deleteDictionaryEntry(id: string): void {
  const dictionary = getDictionary().filter((entry) => entry.id !== id)
  getStore().set('dictionary', dictionary)
}

// Snippets
export function getSnippets(): Snippet[] {
  return getStore().get('snippets')
}

export function addSnippet(snippet: Snippet): void {
  const snippets = getSnippets()
  snippets.push(snippet)
  getStore().set('snippets', snippets)
}

export function updateSnippet(id: string, updates: Partial<Snippet>): void {
  const snippets = getSnippets().map((snippet) =>
    snippet.id === id ? { ...snippet, ...updates } : snippet
  )
  getStore().set('snippets', snippets)
}

export function deleteSnippet(id: string): void {
  const snippets = getSnippets().filter((snippet) => snippet.id !== id)
  getStore().set('snippets', snippets)
}

// Notes
export function getNotes(): Note[] {
  return getStore().get('notes')
}

export function addNote(note: Note): void {
  const notes = getNotes()
  notes.unshift(note)
  getStore().set('notes', notes)
}

export function deleteNote(id: string): void {
  const notes = getNotes().filter((note) => note.id !== id)
  getStore().set('notes', notes)
}
