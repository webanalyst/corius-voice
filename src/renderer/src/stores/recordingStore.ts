import { create } from 'zustand'
import type { RecordingMode, TranscriptionResult } from '../../../shared/types'

interface RecordingState {
  isRecording: boolean
  mode: RecordingMode
  interimText: string
  finalText: string
  startTime: number | null
}

interface RecordingActions {
  setRecordingState: (state: Partial<RecordingState>) => void
  setInterimText: (text: string) => void
  appendFinalText: (text: string) => void
  reset: () => void
}

const initialState: RecordingState = {
  isRecording: false,
  mode: 'idle',
  interimText: '',
  finalText: '',
  startTime: null
}

export const useRecordingStore = create<RecordingState & RecordingActions>((set) => ({
  ...initialState,

  setRecordingState: (state) => set((prev) => ({ ...prev, ...state })),

  setInterimText: (text) => set({ interimText: text }),

  appendFinalText: (text) =>
    set((state) => ({
      finalText: state.finalText + text + ' '
    })),

  reset: () => set(initialState)
}))

// Initialize listener for recording events from main process
if (typeof window !== 'undefined' && window.electronAPI) {
  window.electronAPI.onRecordingStateChanged((state) => {
    useRecordingStore.getState().setRecordingState({
      isRecording: state.isRecording,
      mode: state.mode,
      startTime: state.isRecording ? Date.now() : null
    })

    if (!state.isRecording) {
      useRecordingStore.getState().reset()
    }
  })

  window.electronAPI.onTranscriptionInterim((result: TranscriptionResult) => {
    useRecordingStore.getState().setInterimText(result.text)
  })

  window.electronAPI.onTranscriptionFinal((result: TranscriptionResult) => {
    useRecordingStore.getState().appendFinalText(result.text)
    useRecordingStore.getState().setInterimText('')
  })
}
