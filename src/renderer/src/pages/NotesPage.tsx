import React, { useEffect, useState } from 'react'
import { Mic, Trash2 } from 'lucide-react'
import type { Note } from '../../../shared/types'
import { formatDate, formatTime, formatDuration, groupByDate } from '../lib/utils'

export function NotesPage() {
  const [notes, setNotes] = useState<Note[]>([])
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    loadNotes()
  }, [])

  async function loadNotes() {
    if (window.electronAPI) {
      const data = await window.electronAPI.getNotes()
      setNotes(data)
      setIsLoading(false)
    }
  }

  async function deleteNote(id: string) {
    if (window.electronAPI) {
      await window.electronAPI.deleteNote(id)
      setNotes((prev) => prev.filter((n) => n.id !== id))
    }
  }

  const grouped = groupByDate(notes)

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
        <h2 className="text-2xl font-semibold">Voice Notes</h2>
        <p className="text-muted-foreground">
          Quick voice notes for yourself
        </p>
      </div>

      <div className="rounded-lg border border-border bg-card p-4">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-full bg-muted">
            <Mic className="h-5 w-5 text-muted-foreground" />
          </div>
          <div>
            <p className="font-medium">Record a note</p>
            <p className="text-sm text-muted-foreground">
              Press <kbd className="rounded bg-muted px-1.5 py-0.5 text-xs font-mono">Option+Space</kbd> anywhere to create a voice note
            </p>
          </div>
        </div>
      </div>

      {notes.length === 0 ? (
        <div className="rounded-lg border border-dashed border-border py-12 text-center">
          <p className="text-muted-foreground">
            No voice notes yet. Record one using the shortcut.
          </p>
        </div>
      ) : (
        <div className="space-y-6">
          {Object.entries(grouped).map(([date, items]) => (
            <div key={date}>
              <h3 className="mb-3 text-sm font-medium text-muted-foreground">
                {date}
              </h3>
              <div className="space-y-2">
                {items.map((note) => (
                  <div
                    key={note.id}
                    className="group flex items-start justify-between rounded-lg border border-border bg-card p-4 transition-colors hover:bg-muted/50"
                  >
                    <div className="flex-1">
                      <p className="text-sm leading-relaxed">{note.text}</p>
                      <div className="mt-2 flex items-center gap-2 text-xs text-muted-foreground">
                        <span>{formatTime(note.timestamp)}</span>
                        <span>·</span>
                        <span>{formatDuration(note.duration)}</span>
                      </div>
                    </div>

                    <button
                      onClick={() => deleteNote(note.id)}
                      className="ml-4 rounded p-1.5 opacity-0 transition-opacity hover:bg-muted group-hover:opacity-100"
                    >
                      <Trash2 className="h-4 w-4 text-muted-foreground" />
                    </button>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
