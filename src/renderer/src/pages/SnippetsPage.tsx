import React, { useEffect, useState } from 'react'
import { Plus, Trash2, ToggleLeft, ToggleRight } from 'lucide-react'
import type { Snippet } from '../../../shared/types'
import { generateId } from '../lib/utils'

export function SnippetsPage() {
  const [snippets, setSnippets] = useState<Snippet[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [newTrigger, setNewTrigger] = useState('')
  const [newContent, setNewContent] = useState('')

  useEffect(() => {
    loadSnippets()
  }, [])

  async function loadSnippets() {
    if (window.electronAPI) {
      const data = await window.electronAPI.getSnippets()
      setSnippets(data)
      setIsLoading(false)
    }
  }

  async function addSnippet() {
    if (!newTrigger.trim() || !newContent.trim()) return

    const snippet: Snippet = {
      id: generateId(),
      trigger: newTrigger.trim(),
      content: newContent.trim(),
      enabled: true,
      createdAt: Date.now()
    }

    if (window.electronAPI) {
      await window.electronAPI.addSnippet(snippet)
      setSnippets((prev) => [...prev, snippet])
      setNewTrigger('')
      setNewContent('')
    }
  }

  async function toggleSnippet(id: string, enabled: boolean) {
    if (window.electronAPI) {
      await window.electronAPI.updateSnippet(id, { enabled })
      setSnippets((prev) =>
        prev.map((s) => (s.id === id ? { ...s, enabled } : s))
      )
    }
  }

  async function deleteSnippet(id: string) {
    if (window.electronAPI) {
      await window.electronAPI.deleteSnippet(id)
      setSnippets((prev) => prev.filter((s) => s.id !== id))
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
        <h2 className="text-2xl font-semibold">Snippets</h2>
        <p className="text-muted-foreground">
          Create text shortcuts that expand when spoken
        </p>
      </div>

      {/* Add new snippet form */}
      <div className="space-y-3 rounded-lg border border-border bg-card p-4">
        <div className="flex items-end gap-3">
          <div className="w-48">
            <label className="mb-1.5 block text-sm font-medium">
              Trigger word
            </label>
            <input
              type="text"
              value={newTrigger}
              onChange={(e) => setNewTrigger(e.target.value)}
              placeholder="e.g., linkedin"
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-ring"
            />
          </div>
          <div className="flex-1">
            <label className="mb-1.5 block text-sm font-medium">
              Expands to
            </label>
            <input
              type="text"
              value={newContent}
              onChange={(e) => setNewContent(e.target.value)}
              placeholder="e.g., https://linkedin.com/in/yourprofile"
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus:ring-2 focus:ring-ring"
              onKeyDown={(e) => e.key === 'Enter' && addSnippet()}
            />
          </div>
          <button
            onClick={addSnippet}
            disabled={!newTrigger.trim() || !newContent.trim()}
            className="flex items-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90 disabled:opacity-50"
          >
            <Plus className="h-4 w-4" />
            Add
          </button>
        </div>
      </div>

      {/* Snippets list */}
      {snippets.length === 0 ? (
        <div className="rounded-lg border border-dashed border-border py-12 text-center">
          <p className="text-muted-foreground">
            No snippets yet. Add your first one above.
          </p>
        </div>
      ) : (
        <div className="space-y-2">
          {snippets.map((snippet) => (
            <div
              key={snippet.id}
              className="group rounded-lg border border-border bg-card px-4 py-3 transition-colors hover:bg-muted/50"
            >
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-4">
                  <button
                    onClick={() => toggleSnippet(snippet.id, !snippet.enabled)}
                    className="text-muted-foreground hover:text-foreground"
                  >
                    {snippet.enabled ? (
                      <ToggleRight className="h-5 w-5 text-green-500" />
                    ) : (
                      <ToggleLeft className="h-5 w-5" />
                    )}
                  </button>
                  <span
                    className={`font-mono font-medium ${snippet.enabled ? '' : 'opacity-50'}`}
                  >
                    {snippet.trigger}
                  </span>
                </div>

                <button
                  onClick={() => deleteSnippet(snippet.id)}
                  className="rounded p-1.5 opacity-0 transition-opacity hover:bg-muted group-hover:opacity-100"
                >
                  <Trash2 className="h-4 w-4 text-muted-foreground" />
                </button>
              </div>

              <p
                className={`mt-2 truncate text-sm text-muted-foreground ${snippet.enabled ? '' : 'opacity-50'}`}
              >
                {snippet.content}
              </p>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
