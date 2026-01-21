import React, { useEffect, useState } from 'react'
import { Mic, Copy, Trash2 } from 'lucide-react'
import type { Transcription } from '../../../shared/types'
import { groupByDate, formatTime } from '../lib/utils'

export function HomePage() {
  const [transcriptions, setTranscriptions] = useState<Transcription[]>([])
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    loadTranscriptions()

    // Listen for new transcriptions
    const unsubscribe = window.electronAPI?.onTranscriptionFinal((result) => {
      // Reload transcriptions when a new one is saved
      loadTranscriptions()
    })

    return () => {
      unsubscribe?.()
    }
  }, [])

  async function loadTranscriptions() {
    if (window.electronAPI) {
      const history = await window.electronAPI.getHistory()
      setTranscriptions(history)
      setIsLoading(false)
    }
  }

  async function copyToClipboard(text: string) {
    await window.electronAPI?.copyToClipboard(text)
  }

  async function deleteTranscription(id: string) {
    if (window.electronAPI) {
      await window.electronAPI.deleteFromHistory(id)
      setTranscriptions((prev) => prev.filter((t) => t.id !== id))
    }
  }

  const grouped = groupByDate(transcriptions)

  if (isLoading) {
    return (
      <div className="flex h-full items-center justify-center">
        <div className="h-8 w-8 animate-spin rounded-full border-2 border-muted-foreground border-t-transparent" />
      </div>
    )
  }

  if (transcriptions.length === 0) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-4 text-center">
        <div className="flex h-16 w-16 items-center justify-center rounded-full bg-muted">
          <Mic className="h-8 w-8 text-muted-foreground" />
        </div>
        <div>
          <h2 className="text-xl font-semibold">No transcriptions yet</h2>
          <p className="mt-1 text-muted-foreground">
            Press <kbd className="rounded bg-muted px-1.5 py-0.5 text-xs font-mono">Option+Space</kbd> to start recording
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-semibold">Welcome back</h2>
        <p className="text-muted-foreground">
          Your recent transcriptions are shown below
        </p>
      </div>

      <div className="space-y-6">
        {Object.entries(grouped).map(([date, items]) => (
          <div key={date}>
            <h3 className="mb-3 text-sm font-medium text-muted-foreground">
              {date}
            </h3>
            <div className="space-y-2">
              {items.map((transcription) => (
                <TranscriptionCard
                  key={transcription.id}
                  transcription={transcription}
                  onCopy={() => copyToClipboard(transcription.cleanedText)}
                  onDelete={() => deleteTranscription(transcription.id)}
                />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

interface TranscriptionCardProps {
  transcription: Transcription
  onCopy: () => void
  onDelete: () => void
}

function TranscriptionCard({ transcription, onCopy, onDelete }: TranscriptionCardProps) {
  const [showFull, setShowFull] = useState(false)
  const text = transcription.cleanedText
  const isLong = text.length > 200
  const displayText = isLong && !showFull ? text.slice(0, 200) + '...' : text

  return (
    <div className="group rounded-lg border border-border bg-card p-4 transition-colors hover:bg-muted/50">
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1 min-w-0">
          <p className="text-sm leading-relaxed">
            {displayText}
          </p>
          {isLong && (
            <button
              onClick={() => setShowFull(!showFull)}
              className="mt-2 text-xs text-muted-foreground hover:text-foreground"
            >
              {showFull ? 'Show less' : 'Show more'}
            </button>
          )}
        </div>

        <div className="flex items-center gap-1 opacity-0 transition-opacity group-hover:opacity-100">
          <button
            onClick={onCopy}
            className="rounded p-1.5 hover:bg-muted"
            title="Copy to clipboard"
          >
            <Copy className="h-4 w-4 text-muted-foreground" />
          </button>
          <button
            onClick={onDelete}
            className="rounded p-1.5 hover:bg-muted"
            title="Delete"
          >
            <Trash2 className="h-4 w-4 text-muted-foreground" />
          </button>
        </div>
      </div>

      <div className="mt-2 flex items-center gap-2 text-xs text-muted-foreground">
        <span>{formatTime(transcription.timestamp)}</span>
        <span>·</span>
        <span>{transcription.language.toUpperCase()}</span>
      </div>
    </div>
  )
}
