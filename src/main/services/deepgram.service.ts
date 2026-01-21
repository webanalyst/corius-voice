import { createClient, LiveTranscriptionEvents, LiveClient } from '@deepgram/sdk'
import { getDeepgramApiKey, getSettings } from './store.service'
import type { TranscriptionResult } from '../../shared/types'
import { DEEPGRAM_CONFIG } from '../../shared/constants/defaults'

type TranscriptCallback = (result: TranscriptionResult) => void
type UtteranceEndCallback = () => void
type ErrorCallback = (error: Error) => void

export class DeepgramService {
  private connection: LiveClient | null = null
  private transcriptCallback: TranscriptCallback | null = null
  private utteranceEndCallback: UtteranceEndCallback | null = null
  private errorCallback: ErrorCallback | null = null

  onTranscript(callback: TranscriptCallback): void {
    this.transcriptCallback = callback
  }

  onUtteranceEnd(callback: UtteranceEndCallback): void {
    this.utteranceEndCallback = callback
  }

  onError(callback: ErrorCallback): void {
    this.errorCallback = callback
  }

  async connect(): Promise<void> {
    const apiKey = getDeepgramApiKey()
    if (!apiKey) {
      throw new Error('Deepgram API key not configured')
    }

    const settings = getSettings()
    const language = settings.general.language === 'auto' ? undefined : settings.general.language

    const deepgram = createClient(apiKey)

    this.connection = deepgram.listen.live({
      model: DEEPGRAM_CONFIG.model,
      language,
      smart_format: DEEPGRAM_CONFIG.smart_format,
      interim_results: DEEPGRAM_CONFIG.interim_results,
      utterance_end_ms: settings.deepgram.utteranceEndMs || DEEPGRAM_CONFIG.utterance_end_ms,
      vad_events: DEEPGRAM_CONFIG.vad_events,
      endpointing: DEEPGRAM_CONFIG.endpointing,
      punctuate: true,
      encoding: 'linear16',
      sample_rate: 16000,
      channels: 1
    })

    this.setupEventListeners()

    // Wait for connection to be established
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Deepgram connection timeout'))
      }, 10000)

      this.connection?.on(LiveTranscriptionEvents.Open, () => {
        clearTimeout(timeout)
        console.log('Deepgram connection established')
        resolve()
      })

      this.connection?.on(LiveTranscriptionEvents.Error, (error) => {
        clearTimeout(timeout)
        reject(error)
      })
    })
  }

  private setupEventListeners(): void {
    if (!this.connection) return

    this.connection.on(LiveTranscriptionEvents.Transcript, (data) => {
      console.log('[Deepgram] Raw transcript event:', JSON.stringify(data).slice(0, 200))

      const transcript = data.channel?.alternatives?.[0]
      if (!transcript) {
        console.log('[Deepgram] No transcript in alternatives')
        return
      }

      const result: TranscriptionResult = {
        text: transcript.transcript || '',
        isFinal: data.is_final || false,
        confidence: transcript.confidence || 0,
        words: transcript.words?.map((w) => ({
          word: w.word,
          start: w.start,
          end: w.end,
          confidence: w.confidence
        }))
      }

      console.log(`[Deepgram] Transcript text: "${result.text}" (final: ${result.isFinal})`)

      // Only emit if there's actual text
      if (result.text.trim()) {
        this.transcriptCallback?.(result)
      }
    })

    this.connection.on(LiveTranscriptionEvents.UtteranceEnd, () => {
      console.log('Utterance end detected')
      this.utteranceEndCallback?.()
    })

    this.connection.on(LiveTranscriptionEvents.Error, (error) => {
      console.error('Deepgram error:', error)
      this.errorCallback?.(error instanceof Error ? error : new Error(String(error)))
    })

    this.connection.on(LiveTranscriptionEvents.Close, () => {
      console.log('Deepgram connection closed')
    })
  }

  sendAudio(audioData: Buffer | ArrayBuffer): void {
    if (this.connection) {
      // Send the raw ArrayBuffer to Deepgram
      const buffer = audioData instanceof ArrayBuffer
        ? audioData
        : audioData.buffer.slice(audioData.byteOffset, audioData.byteOffset + audioData.byteLength)
      console.log(`[Deepgram] Sending ${(buffer as ArrayBuffer).byteLength} bytes`)
      this.connection.send(buffer as ArrayBuffer)
    } else {
      console.log('[Deepgram] Cannot send audio - no connection')
    }
  }

  disconnect(): void {
    if (this.connection) {
      this.connection.requestClose()
      this.connection = null
    }
  }

  isConnected(): boolean {
    return this.connection !== null
  }
}
