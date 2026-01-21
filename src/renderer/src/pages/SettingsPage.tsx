import React, { useEffect, useState } from 'react'
import { useSettingsStore } from '../stores/settingsStore'
import { cn } from '../lib/utils'

type SettingsTab = 'general' | 'deepgram' | 'shortcuts'

const tabs: { id: SettingsTab; label: string }[] = [
  { id: 'general', label: 'General' },
  { id: 'deepgram', label: 'Deepgram' },
  { id: 'shortcuts', label: 'Shortcuts' }
]

export function SettingsPage() {
  const [activeTab, setActiveTab] = useState<SettingsTab>('general')
  const { settings, isLoading, loadSettings, updateSettings } = useSettingsStore()

  useEffect(() => {
    loadSettings()
  }, [loadSettings])

  if (isLoading) {
    return (
      <div className="flex h-full items-center justify-center">
        <div className="h-8 w-8 animate-spin rounded-full border-2 border-muted-foreground border-t-transparent" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-semibold">Settings</h2>
        <p className="text-muted-foreground">
          Configure Corius Voice to your preferences
        </p>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 border-b border-border">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={cn(
              'px-4 py-2 text-sm font-medium transition-colors',
              activeTab === tab.id
                ? 'border-b-2 border-primary text-foreground'
                : 'text-muted-foreground hover:text-foreground'
            )}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Tab content */}
      <div className="space-y-6">
        {activeTab === 'general' && (
          <GeneralSettings
            settings={settings}
            onUpdate={updateSettings}
          />
        )}
        {activeTab === 'deepgram' && (
          <DeepgramSettings
            settings={settings}
            onUpdate={updateSettings}
          />
        )}
        {activeTab === 'shortcuts' && (
          <ShortcutsSettings
            settings={settings}
            onUpdate={updateSettings}
          />
        )}
      </div>
    </div>
  )
}

function GeneralSettings({
  settings,
  onUpdate
}: {
  settings: ReturnType<typeof useSettingsStore>['settings']
  onUpdate: (s: Partial<typeof settings>) => Promise<void>
}) {
  return (
    <div className="space-y-4">
      <div className="rounded-lg border border-border bg-card p-4">
        <h3 className="font-medium">Language</h3>
        <p className="mb-3 text-sm text-muted-foreground">
          Primary language for transcription
        </p>
        <select
          value={settings.general.language}
          onChange={(e) =>
            onUpdate({
              general: { ...settings.general, language: e.target.value as 'es' | 'en' | 'auto' }
            })
          }
          className="w-48 rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-ring"
        >
          <option value="auto">Auto-detect</option>
          <option value="es">Spanish</option>
          <option value="en">English</option>
        </select>
      </div>

      <div className="rounded-lg border border-border bg-card p-4">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="font-medium">Launch at startup</h3>
            <p className="text-sm text-muted-foreground">
              Automatically start Corius Voice when you log in
            </p>
          </div>
          <button
            onClick={() =>
              onUpdate({
                general: { ...settings.general, launchAtStartup: !settings.general.launchAtStartup }
              })
            }
            className={cn(
              'relative h-6 w-11 rounded-full transition-colors',
              settings.general.launchAtStartup ? 'bg-primary' : 'bg-muted'
            )}
          >
            <span
              className={cn(
                'absolute left-0.5 top-0.5 h-5 w-5 rounded-full bg-white transition-transform',
                settings.general.launchAtStartup && 'translate-x-5'
              )}
            />
          </button>
        </div>
      </div>

      <div className="rounded-lg border border-border bg-card p-4">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="font-medium">Sound effects</h3>
            <p className="text-sm text-muted-foreground">
              Play sounds when recording starts/stops
            </p>
          </div>
          <button
            onClick={() =>
              onUpdate({
                general: { ...settings.general, soundEffects: !settings.general.soundEffects }
              })
            }
            className={cn(
              'relative h-6 w-11 rounded-full transition-colors',
              settings.general.soundEffects ? 'bg-primary' : 'bg-muted'
            )}
          >
            <span
              className={cn(
                'absolute left-0.5 top-0.5 h-5 w-5 rounded-full bg-white transition-transform',
                settings.general.soundEffects && 'translate-x-5'
              )}
            />
          </button>
        </div>
      </div>
    </div>
  )
}

function DeepgramSettings({
  settings,
  onUpdate
}: {
  settings: ReturnType<typeof useSettingsStore>['settings']
  onUpdate: (s: Partial<typeof settings>) => Promise<void>
}) {
  const [apiKey, setApiKey] = useState(settings.deepgram.apiKey)

  const handleSaveApiKey = () => {
    onUpdate({
      deepgram: { ...settings.deepgram, apiKey }
    })
  }

  return (
    <div className="space-y-4">
      <div className="rounded-lg border border-border bg-card p-4">
        <h3 className="font-medium">API Key</h3>
        <p className="mb-3 text-sm text-muted-foreground">
          Your Deepgram API key for transcription services
        </p>
        <div className="flex gap-2">
          <input
            type="password"
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            placeholder="Enter your Deepgram API key"
            className="flex-1 rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-ring"
          />
          <button
            onClick={handleSaveApiKey}
            className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
          >
            Save
          </button>
        </div>
        <p className="mt-2 text-xs text-muted-foreground">
          Get your API key from{' '}
          <button
            onClick={() => window.electronAPI?.openExternal('https://console.deepgram.com')}
            className="text-primary hover:underline"
          >
            console.deepgram.com
          </button>
        </p>
      </div>

      <div className="rounded-lg border border-border bg-card p-4">
        <h3 className="font-medium">Silence timeout</h3>
        <p className="mb-3 text-sm text-muted-foreground">
          Stop recording after this many seconds of silence (in continuous mode)
        </p>
        <select
          value={settings.deepgram.utteranceEndMs}
          onChange={(e) =>
            onUpdate({
              deepgram: { ...settings.deepgram, utteranceEndMs: parseInt(e.target.value) }
            })
          }
          className="w-48 rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-ring"
        >
          <option value="3000">3 seconds</option>
          <option value="5000">5 seconds</option>
          <option value="7000">7 seconds</option>
          <option value="10000">10 seconds</option>
        </select>
      </div>
    </div>
  )
}

function ShortcutsSettings({
  settings,
  onUpdate
}: {
  settings: ReturnType<typeof useSettingsStore>['settings']
  onUpdate: (s: Partial<typeof settings>) => Promise<void>
}) {
  return (
    <div className="space-y-4">
      <div className="rounded-lg border border-border bg-card p-4">
        <h3 className="font-medium">Activation shortcut</h3>
        <p className="mb-3 text-sm text-muted-foreground">
          Keyboard shortcut to start/stop recording
        </p>
        <div className="flex items-center gap-2">
          <kbd className="rounded-md border border-border bg-muted px-3 py-2 text-sm font-mono">
            {settings.shortcuts.activationKey}
          </kbd>
          <span className="text-sm text-muted-foreground">
            (Currently not configurable)
          </span>
        </div>
      </div>

      <div className="rounded-lg border border-border bg-card p-4">
        <h3 className="font-medium">Hold threshold</h3>
        <p className="mb-3 text-sm text-muted-foreground">
          Time to hold before switching to continuous recording mode
        </p>
        <select
          value={settings.shortcuts.holdThresholdMs}
          onChange={(e) =>
            onUpdate({
              shortcuts: { ...settings.shortcuts, holdThresholdMs: parseInt(e.target.value) }
            })
          }
          className="w-48 rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-ring"
        >
          <option value="2000">2 seconds</option>
          <option value="3000">3 seconds</option>
          <option value="4000">4 seconds</option>
          <option value="5000">5 seconds</option>
        </select>
      </div>
    </div>
  )
}
