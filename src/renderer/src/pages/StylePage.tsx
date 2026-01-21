import React, { useState } from 'react'
import { Check } from 'lucide-react'
import { cn } from '../lib/utils'

const styles = [
  {
    id: 'casual',
    name: 'Casual',
    description: 'Relaxed and conversational tone',
    example: "hey, just wanted to let you know that the meeting's been moved to 3pm"
  },
  {
    id: 'formal',
    name: 'Formal',
    description: 'Professional and polished language',
    example: 'I wanted to inform you that the meeting has been rescheduled to 3:00 PM.'
  },
  {
    id: 'excited',
    name: 'Excited',
    description: 'Enthusiastic and energetic expression',
    example: "Great news! The meeting's been moved to 3pm - can't wait to see everyone there!"
  }
]

export function StylePage() {
  const [selectedStyle, setSelectedStyle] = useState('casual')

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-2xl font-semibold">Writing Style</h2>
        <p className="text-muted-foreground">
          Choose how your transcriptions should sound
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        {styles.map((style) => (
          <button
            key={style.id}
            onClick={() => setSelectedStyle(style.id)}
            className={cn(
              'relative rounded-lg border p-4 text-left transition-all hover:border-ring',
              selectedStyle === style.id
                ? 'border-primary bg-primary/5'
                : 'border-border bg-card'
            )}
          >
            {selectedStyle === style.id && (
              <div className="absolute right-3 top-3">
                <div className="flex h-5 w-5 items-center justify-center rounded-full bg-primary">
                  <Check className="h-3 w-3 text-primary-foreground" />
                </div>
              </div>
            )}

            <h3 className="font-semibold">{style.name}</h3>
            <p className="mt-1 text-sm text-muted-foreground">
              {style.description}
            </p>

            <div className="mt-4 rounded-md bg-muted/50 p-3">
              <p className="text-sm italic text-muted-foreground">
                "{style.example}"
              </p>
            </div>
          </button>
        ))}
      </div>

      <div className="rounded-lg border border-border bg-card p-4">
        <h3 className="font-medium">Coming soon</h3>
        <p className="mt-1 text-sm text-muted-foreground">
          Style transformation will be available in a future update. Your transcriptions will
          be automatically adjusted to match your selected writing style.
        </p>
      </div>
    </div>
  )
}
