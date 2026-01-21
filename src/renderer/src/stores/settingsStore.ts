import { create } from 'zustand'
import type { Settings } from '../../../shared/types'
import { DEFAULT_SETTINGS } from '../../../shared/constants/defaults'

interface SettingsState {
  settings: Settings
  isLoading: boolean
}

interface SettingsActions {
  loadSettings: () => Promise<void>
  updateSettings: (settings: Partial<Settings>) => Promise<void>
  updateDeepgramApiKey: (apiKey: string) => Promise<void>
  updateLanguage: (language: 'es' | 'en' | 'auto') => Promise<void>
}

export const useSettingsStore = create<SettingsState & SettingsActions>((set, get) => ({
  settings: DEFAULT_SETTINGS,
  isLoading: true,

  loadSettings: async () => {
    if (window.electronAPI) {
      const settings = await window.electronAPI.getSettings()
      set({ settings, isLoading: false })
    }
  },

  updateSettings: async (newSettings) => {
    if (window.electronAPI) {
      const current = get().settings
      const merged = { ...current, ...newSettings }
      const updated = await window.electronAPI.setSettings(merged)
      set({ settings: updated })
    }
  },

  updateDeepgramApiKey: async (apiKey) => {
    const current = get().settings
    await get().updateSettings({
      ...current,
      deepgram: { ...current.deepgram, apiKey }
    })
  },

  updateLanguage: async (language) => {
    const current = get().settings
    await get().updateSettings({
      ...current,
      general: { ...current.general, language }
    })
  }
}))
