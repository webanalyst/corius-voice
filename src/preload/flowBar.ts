import { contextBridge, ipcRenderer } from 'electron'
import { IPC_CHANNELS } from '../shared/constants/ipcChannels'
import type { RecordingState, TranscriptionResult, AudioData } from '../shared/types'

// API exposed to flow bar renderer
const flowBarApi = {
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

// Expose API to flow bar renderer
contextBridge.exposeInMainWorld('flowBarAPI', flowBarApi)

// Type declaration for flow bar renderer
export type FlowBarAPI = typeof flowBarApi
