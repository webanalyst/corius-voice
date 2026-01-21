import React from 'react'
import { useLocation } from 'react-router-dom'
import { useRecordingStore } from '../../stores/recordingStore'
import { cn } from '../../lib/utils'

const pageTitles: Record<string, string> = {
  '/': 'Home',
  '/dictionary': 'Dictionary',
  '/snippets': 'Snippets',
  '/style': 'Style',
  '/notes': 'Notes',
  '/settings': 'Settings'
}

export function Header() {
  const location = useLocation()
  const { isRecording, mode } = useRecordingStore()
  const title = pageTitles[location.pathname] || 'Corius Voice'

  return (
    <header className="drag-region flex h-12 items-center justify-between border-b border-border px-6">
      {/* macOS traffic lights spacing */}
      <div className="w-20" />

      <h1 className="no-drag text-sm font-medium">{title}</h1>

      <div className="no-drag flex w-20 items-center justify-end">
        {isRecording && (
          <div className="flex items-center gap-2">
            <div
              className={cn(
                'h-2 w-2 rounded-full',
                mode === 'continuous' ? 'bg-green-500' : 'bg-red-500',
                'animate-pulse-recording'
              )}
            />
            <span className="text-xs text-muted-foreground">
              {mode === 'continuous' ? 'Recording' : 'Hold'}
            </span>
          </div>
        )}
      </div>
    </header>
  )
}
