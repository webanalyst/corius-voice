import { ipcMain, BrowserWindow, shell, clipboard } from 'electron'
import { IPC_CHANNELS } from '../../shared/constants/ipcChannels'
import {
  getSettings,
  setSettings,
  getTranscriptions,
  addTranscription,
  deleteTranscription,
  clearTranscriptions,
  getDictionary,
  addDictionaryEntry,
  updateDictionaryEntry,
  deleteDictionaryEntry,
  getSnippets,
  addSnippet,
  updateSnippet,
  deleteSnippet,
  getNotes,
  addNote,
  deleteNote
} from '../services/store.service'
import type {
  Transcription,
  DictionaryEntry,
  Snippet,
  Note,
  Settings
} from '../../shared/types'

export function setupIpcHandlers(
  mainWindow: BrowserWindow | null,
  flowBar: BrowserWindow | null
): void {
  // Settings handlers
  ipcMain.handle(IPC_CHANNELS.SETTINGS_GET, () => {
    return getSettings()
  })

  ipcMain.handle(IPC_CHANNELS.SETTINGS_SET, (_, settings: Partial<Settings>) => {
    setSettings(settings)
    return getSettings()
  })

  // Transcription history handlers
  ipcMain.handle(IPC_CHANNELS.HISTORY_GET, () => {
    return getTranscriptions()
  })

  ipcMain.handle(IPC_CHANNELS.HISTORY_ADD, (_, transcription: Transcription) => {
    addTranscription(transcription)
    return getTranscriptions()
  })

  ipcMain.handle(IPC_CHANNELS.HISTORY_DELETE, (_, id: string) => {
    deleteTranscription(id)
    return getTranscriptions()
  })

  ipcMain.handle(IPC_CHANNELS.HISTORY_CLEAR, () => {
    clearTranscriptions()
    return []
  })

  // Dictionary handlers
  ipcMain.handle(IPC_CHANNELS.DICTIONARY_GET, () => {
    return getDictionary()
  })

  ipcMain.handle(IPC_CHANNELS.DICTIONARY_ADD, (_, entry: DictionaryEntry) => {
    addDictionaryEntry(entry)
    return getDictionary()
  })

  ipcMain.handle(IPC_CHANNELS.DICTIONARY_UPDATE, (_, id: string, updates: Partial<DictionaryEntry>) => {
    updateDictionaryEntry(id, updates)
    return getDictionary()
  })

  ipcMain.handle(IPC_CHANNELS.DICTIONARY_DELETE, (_, id: string) => {
    deleteDictionaryEntry(id)
    return getDictionary()
  })

  // Snippets handlers
  ipcMain.handle(IPC_CHANNELS.SNIPPETS_GET, () => {
    return getSnippets()
  })

  ipcMain.handle(IPC_CHANNELS.SNIPPETS_ADD, (_, snippet: Snippet) => {
    addSnippet(snippet)
    return getSnippets()
  })

  ipcMain.handle(IPC_CHANNELS.SNIPPETS_UPDATE, (_, id: string, updates: Partial<Snippet>) => {
    updateSnippet(id, updates)
    return getSnippets()
  })

  ipcMain.handle(IPC_CHANNELS.SNIPPETS_DELETE, (_, id: string) => {
    deleteSnippet(id)
    return getSnippets()
  })

  // Notes handlers
  ipcMain.handle(IPC_CHANNELS.NOTES_GET, () => {
    return getNotes()
  })

  ipcMain.handle(IPC_CHANNELS.NOTES_ADD, (_, note: Note) => {
    addNote(note)
    return getNotes()
  })

  ipcMain.handle(IPC_CHANNELS.NOTES_DELETE, (_, id: string) => {
    deleteNote(id)
    return getNotes()
  })

  // System handlers
  ipcMain.handle(IPC_CHANNELS.OPEN_EXTERNAL, (_, url: string) => {
    shell.openExternal(url)
  })

  ipcMain.handle(IPC_CHANNELS.CLIPBOARD_WRITE, (_, text: string) => {
    clipboard.writeText(text)
  })

  ipcMain.handle(IPC_CHANNELS.APP_MINIMIZE, () => {
    mainWindow?.minimize()
  })

  ipcMain.handle(IPC_CHANNELS.APP_MAXIMIZE, () => {
    if (mainWindow?.isMaximized()) {
      mainWindow.unmaximize()
    } else {
      mainWindow?.maximize()
    }
  })

  // Handle audio data from renderer (flow bar captures audio)
  ipcMain.on('audio:raw-data', (_, data: ArrayBuffer) => {
    // This will be forwarded to DeepgramService
    // The main process manages the Deepgram connection
  })

  ipcMain.on('audio:levels', (_, levels: number[]) => {
    // Forward audio levels to flow bar for visualization
    flowBar?.webContents.send(IPC_CHANNELS.AUDIO_LEVEL, levels)
  })
}
