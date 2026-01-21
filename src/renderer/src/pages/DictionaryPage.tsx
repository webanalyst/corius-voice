import React, { useEffect, useState } from 'react'
import { Plus, Trash2, ToggleLeft, ToggleRight } from 'lucide-react'
import type { DictionaryEntry } from '../../../shared/types'
import { generateId } from '../lib/utils'

export function DictionaryPage() {
  const [entries, setEntries] = useState<DictionaryEntry[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [newOriginal, setNewOriginal] = useState('')
  const [newReplacement, setNewReplacement] = useState('')

  useEffect(() => {
    loadEntries()
  }, [])

  async function loadEntries() {
    if (window.electronAPI) {
      const data = await window.electronAPI.getDictionary()
      setEntries(data)
      setIsLoading(false)
    }
  }

  async function addEntry() {
    if (!newOriginal.trim() || !newReplacement.trim()) return

    const entry: DictionaryEntry = {
      id: generateId(),
      original: newOriginal.trim(),
      replacement: newReplacement.trim(),
      enabled: true,
      createdAt: Date.now()
    }

    if (window.electronAPI) {
      await window.electronAPI.addDictionaryEntry(entry)
      setEntries((prev) => [...prev, entry])
      setNewOriginal('')
      setNewReplacement('')
    }
  }

  async function toggleEntry(id: string, enabled: boolean) {
    if (window.electronAPI) {
      await window.electronAPI.updateDictionaryEntry(id, { enabled })
      setEntries((prev) =>
        prev.map((e) => (e.id === id ? { ...e, enabled } : e))
      )
    }
  }

  async function deleteEntry(id: string) {
    if (window.electronAPI) {
      await window.electronAPI.deleteDictionaryEntry(id)
      setEntries((prev) => prev.filter((e) => e.id !== id))
    }
  }

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
        <h2 className="text-2xl font-semibold">Dictionary</h2>
        <p className="text-muted-foreground">
          Add custom word replacements and corrections
        </p>
      </div>

      {/* Add new entry form */}
      <div className="flex items-end gap-3 rounded-lg border border-border bg-card p-4">
        <div className="flex-1">
          <label className="mb-1.5 block text-sm font-medium">
            Original word
          </label>
          <input
            type="text"
            value={newOriginal}
            onChange={(e) => setNewOriginal(e.target.value)}
            placeholder="e.g., Q3"
            className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-ring"
          />
        </div>
        <div className="flex-1">
          <label className="mb-1.5 block text-sm font-medium">
            Replace with
          </label>
          <input
            type="text"
            value={newReplacement}
            onChange={(e) => setNewReplacement(e.target.value)}
            placeholder="e.g., Q3 Roadmap"
            className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-ring"
            onKeyDown={(e) => e.key === 'Enter' && addEntry()}
          />
        </div>
        <button
          onClick={addEntry}
          disabled={!newOriginal.trim() || !newReplacement.trim()}
          className="flex items-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90 disabled:opacity-50"
        >
          <Plus className="h-4 w-4" />
          Add
        </button>
      </div>

      {/* Entries list */}
      {entries.length === 0 ? (
        <div className="rounded-lg border border-dashed border-border py-12 text-center">
          <p className="text-muted-foreground">
            No dictionary entries yet. Add your first one above.
          </p>
        </div>
      ) : (
        <div className="space-y-2">
          {entries.map((entry) => (
            <div
              key={entry.id}
              className="group flex items-center justify-between rounded-lg border border-border bg-card px-4 py-3 transition-colors hover:bg-muted/50"
            >
              <div className="flex items-center gap-4">
                <button
                  onClick={() => toggleEntry(entry.id, !entry.enabled)}
                  className="text-muted-foreground hover:text-foreground"
                >
                  {entry.enabled ? (
                    <ToggleRight className="h-5 w-5 text-green-500" />
                  ) : (
                    <ToggleLeft className="h-5 w-5" />
                  )}
                </button>
                <div className={entry.enabled ? '' : 'opacity-50'}>
                  <span className="font-medium">{entry.original}</span>
                  <span className="mx-2 text-muted-foreground">→</span>
                  <span>{entry.replacement}</span>
                </div>
              </div>

              <button
                onClick={() => deleteEntry(entry.id)}
                className="rounded p-1.5 opacity-0 transition-opacity hover:bg-muted group-hover:opacity-100"
              >
                <Trash2 className="h-4 w-4 text-muted-foreground" />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
