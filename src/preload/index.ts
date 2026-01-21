import { contextBridge, ipcRenderer } from 'electron'
import { IPC_CHANNELS } from '../shared/constants/ipcChannels'
import type {
  Transcription,
  DictionaryEntry,
  Snippet,
  Note,
  Settings,
  RecordingState,
  TranscriptionResult,
  AudioData
} from '../shared/types'

// Main app API exposed to renderer
const electronAPI = {
  // Settings
  getSettings: (): Promise<Settings> => ipcRenderer.invoke(IPC_CHANNELS.SETTINGS_GET),
  setSettings: (settings: Partial<Settings>): Promise<Settings> =>
    ipcRenderer.invoke(IPC_CHANNELS.SETTINGS_SET, settings),

  // Transcription history
  getHistory: (): Promise<Transcription[]> => ipcRenderer.invoke(IPC_CHANNELS.HISTORY_GET),
  addToHistory: (transcription: Transcription): Promise<Transcription[]> =>
    ipcRenderer.invoke(IPC_CHANNELS.HISTORY_ADD, transcription),
  deleteFromHistory: (id: string): Promise<Transcription[]> =>
    ipcRenderer.invoke(IPC_CHANNELS.HISTORY_DELETE, id),
  clearHistory: (): Promise<Transcription[]> => ipcRenderer.invoke(IPC_CHANNELS.HISTORY_CLEAR),

  // Dictionary
  getDictionary: (): Promise<DictionaryEntry[]> => ipcRenderer.invoke(IPC_CHANNELS.DICTIONARY_GET),
  addDictionaryEntry: (entry: DictionaryEntry): Promise<DictionaryEntry[]> =>
    ipcRenderer.invoke(IPC_CHANNELS.DICTIONARY_ADD, entry),
  updateDictionaryEntry: (id: string, updates: Partial<DictionaryEntry>): Promise<DictionaryEntry[]> =>
    ipcRenderer.invoke(IPC_CHANNELS.DICTIONARY_UPDATE, id, updates),
  deleteDictionaryEntry: (id: string): Promise<DictionaryEntry[]> =>
    ipcRenderer.invoke(IPC_CHANNELS.DICTIONARY_DELETE, id),

  // Snippets
  getSnippets: (): Promise<Snippet[]> => ipcRenderer.invoke(IPC_CHANNELS.SNIPPETS_GET),
  addSnippet: (snippet: Snippet): Promise<Snippet[]> =>
    ipcRenderer.invoke(IPC_CHANNELS.SNIPPETS_ADD, snippet),
  updateSnippet: (id: string, updates: Partial<Snippet>): Promise<Snippet[]> =>
    ipcRenderer.invoke(IPC_CHANNELS.SNIPPETS_UPDATE, id, updates),
  deleteSnippet: (id: string): Promise<Snippet[]> =>
    ipcRenderer.invoke(IPC_CHANNELS.SNIPPETS_DELETE, id),

  // Notes
  getNotes: (): Promise<Note[]> => ipcRenderer.invoke(IPC_CHANNELS.NOTES_GET),
  addNote: (note: Note): Promise<Note[]> => ipcRenderer.invoke(IPC_CHANNELS.NOTES_ADD, note),
  deleteNote: (id: string): Promise<Note[]> => ipcRenderer.invoke(IPC_CHANNELS.NOTES_DELETE, id),

  // System
  openExternal: (url: string): Promise<void> => ipcRenderer.invoke(IPC_CHANNELS.OPEN_EXTERNAL, url),
  copyToClipboard: (text: string): Promise<void> =>
    ipcRenderer.invoke(IPC_CHANNELS.CLIPBOARD_WRITE, text),
  minimize: (): Promise<void> => ipcRenderer.invoke(IPC_CHANNELS.APP_MINIMIZE),
  maximize: (): Promise<void> => ipcRenderer.invoke(IPC_CHANNELS.APP_MAXIMIZE),

  // Recording events (listen)
  onRecordingStateChanged: (callback: (state: RecordingState) => void) => {
    const handler = (_: Electron.IpcRendererEvent, state: RecordingState) => callback(state)
    ipcRenderer.on(IPC_CHANNELS.RECORDING_STATE_CHANGED, handler)
    return () => ipcRenderer.removeListener(IPC_CHANNELS.RECORDING_STATE_CHANGED, handler)
  },

  onTranscriptionInterim: (callback: (result: TranscriptionResult) => void) => {
    const handler = (_: Electron.IpcRendererEvent, result: TranscriptionResult) => callback(result)
    ipcRenderer.on(IPC_CHANNELS.TRANSCRIPTION_INTERIM, handler)
    return () => ipcRenderer.removeListener(IPC_CHANNELS.TRANSCRIPTION_INTERIM, handler)
  },

  onTranscriptionFinal: (callback: (result: TranscriptionResult) => void) => {
    const handler = (_: Electron.IpcRendererEvent, result: TranscriptionResult) => callback(result)
    ipcRenderer.on(IPC_CHANNELS.TRANSCRIPTION_FINAL, handler)
    return () => ipcRenderer.removeListener(IPC_CHANNELS.TRANSCRIPTION_FINAL, handler)
  },

  onTranscriptionError: (callback: (error: string) => void) => {
    const handler = (_: Electron.IpcRendererEvent, error: string) => callback(error)
    ipcRenderer.on(IPC_CHANNELS.TRANSCRIPTION_ERROR, handler)
    return () => ipcRenderer.removeListener(IPC_CHANNELS.TRANSCRIPTION_ERROR, handler)
  }
}

// Flow bar API exposed to renderer
const flowBarAPI = {
  // Audio capture (flow bar captures audio and sends to main)
  sendAudioData: (data: ArrayBuffer): void => {
    ipcRenderer.send('audio:raw-data', data)
  },

  sendAudioLevels: (levels: number[]): void => {
    ipcRenderer.send('audio:levels', levels)
  },

  // Recording events (listen)
  onRecordingStateChanged: (callback: (state: RecordingState) => void) => {
    const handler = (_: Electron.IpcRendererEvent, state: RecordingState) => callback(state)
    ipcRenderer.on(IPC_CHANNELS.RECORDING_STATE_CHANGED, handler)
    return () => ipcRenderer.removeListener(IPC_CHANNELS.RECORDING_STATE_CHANGED, handler)
  },

  onAudioData: (callback: (data: AudioData) => void) => {
    const handler = (_: Electron.IpcRendererEvent, data: AudioData) => callback(data)
    ipcRenderer.on(IPC_CHANNELS.AUDIO_DATA, handler)
    return () => ipcRenderer.removeListener(IPC_CHANNELS.AUDIO_DATA, handler)
  },

  onAudioLevel: (callback: (levels: number[]) => void) => {
    const handler = (_: Electron.IpcRendererEvent, levels: number[]) => callback(levels)
    ipcRenderer.on(IPC_CHANNELS.AUDIO_LEVEL, handler)
    return () => ipcRenderer.removeListener(IPC_CHANNELS.AUDIO_LEVEL, handler)
  },

  onTranscriptionInterim: (callback: (result: TranscriptionResult) => void) => {
    const handler = (_: Electron.IpcRendererEvent, result: TranscriptionResult) => callback(result)
    ipcRenderer.on(IPC_CHANNELS.TRANSCRIPTION_INTERIM, handler)
    return () => ipcRenderer.removeListener(IPC_CHANNELS.TRANSCRIPTION_INTERIM, handler)
  },

  onTranscriptionFinal: (callback: (result: TranscriptionResult) => void) => {
    const handler = (_: Electron.IpcRendererEvent, result: TranscriptionResult) => callback(result)
    ipcRenderer.on(IPC_CHANNELS.TRANSCRIPTION_FINAL, handler)
    return () => ipcRenderer.removeListener(IPC_CHANNELS.TRANSCRIPTION_FINAL, handler)
  }
}

// Expose both APIs to renderer
contextBridge.exposeInMainWorld('electronAPI', electronAPI)
contextBridge.exposeInMainWorld('flowBarAPI', flowBarAPI)

// Type declarations
export type ElectronAPI = typeof electronAPI
export type FlowBarAPI = typeof flowBarAPI
