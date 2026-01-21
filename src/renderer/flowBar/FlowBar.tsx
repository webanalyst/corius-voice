import React, { useEffect, useState, useCallback } from 'react'
import { AudioVisualizer } from './components/AudioVisualizer'

declare global {
  interface Window {
    flowBarAPI: {
      sendAudioData: (data: ArrayBuffer) => void
      sendAudioLevels: (levels: number[]) => void
      onRecordingStateChanged: (callback: (state: { isRecording: boolean; mode: string }) => void) => () => void
      onAudioData: (callback: (data: { levels: number[]; timestamp: number }) => void) => () => void
      onAudioLevel: (callback: (levels: number[]) => void) => () => void
      onTranscriptionInterim: (callback: (result: { text: string }) => void) => () => void
      onTranscriptionFinal: (callback: (result: { text: string }) => void) => () => void
    }
  }
}

export function FlowBar() {
  const [isRecording, setIsRecording] = useState(false)
  const [mode, setMode] = useState<'hold' | 'continuous'>('hold')
  const [audioLevels, setAudioLevels] = useState<number[]>(new Array(32).fill(0))
  const [interimText, setInterimText] = useState('')

  // Start audio capture when recording begins
  const startAudioCapture = useCallback(async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          channelCount: 1,
          sampleRate: 16000,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      })

      // Setup audio context at 16kHz for Deepgram compatibility
      const audioContext = new AudioContext({ sampleRate: 16000 })
      const analyser = audioContext.createAnalyser()
      analyser.fftSize = 256

      // Add gain node to boost audio signal (microphone levels are often too low)
      const gainNode = audioContext.createGain()
      gainNode.gain.value = 2.5 // Moderate boost to avoid noise issues

      const source = audioContext.createMediaStreamSource(stream)
      source.connect(gainNode)
      gainNode.connect(analyser)

      const dataArray = new Uint8Array(analyser.frequencyBinCount)

      // Use ScriptProcessorNode to capture raw PCM audio
      const scriptProcessor = audioContext.createScriptProcessor(4096, 1, 1)

      scriptProcessor.onaudioprocess = (event) => {
        const inputData = event.inputBuffer.getChannelData(0)

        // Convert Float32 to Int16 PCM
        const pcm16 = new Int16Array(inputData.length)
        for (let i = 0; i < inputData.length; i++) {
          const s = Math.max(-1, Math.min(1, inputData[i]))
          pcm16[i] = s < 0 ? s * 0x8000 : s * 0x7fff
        }

        window.flowBarAPI?.sendAudioData(pcm16.buffer)
      }

      gainNode.connect(scriptProcessor)
      scriptProcessor.connect(audioContext.destination)

      // Animation loop for audio levels
      let animationId: number
      const updateLevels = () => {
        analyser.getByteFrequencyData(dataArray)
        const levels = Array.from(dataArray.slice(0, 32))
        setAudioLevels(levels)

        window.flowBarAPI?.sendAudioLevels(levels)

        animationId = requestAnimationFrame(updateLevels)
      }

      updateLevels()

      return {
        stream,
        audioContext,
        cleanup: () => {
          cancelAnimationFrame(animationId)
          scriptProcessor.disconnect()
          source.disconnect()
          stream.getTracks().forEach((track) => track.stop())
          audioContext.close()
        }
      }
    } catch (error) {
      console.error('Failed to start audio capture:', error)
      return null
    }
  }, [])

  useEffect(() => {
    let cleanup: (() => void) | null = null

    // Listen for recording state changes
    const unsubscribeState = window.flowBarAPI?.onRecordingStateChanged((state) => {
      setIsRecording(state.isRecording)
      setMode(state.mode as 'hold' | 'continuous')

      if (state.isRecording) {
        startAudioCapture().then((result) => {
          if (result) {
            cleanup = result.cleanup
          }
        })
      } else {
        cleanup?.()
        cleanup = null
        setAudioLevels(new Array(32).fill(0))
        setInterimText('')
      }
    })

    // Listen for audio levels from main process
    const unsubscribeLevels = window.flowBarAPI?.onAudioLevel((levels) => {
      setAudioLevels(levels)
    })

    // Listen for interim transcription
    const unsubscribeInterim = window.flowBarAPI?.onTranscriptionInterim((result) => {
      setInterimText(result.text)
    })

    // Listen for final transcription
    const unsubscribeFinal = window.flowBarAPI?.onTranscriptionFinal(() => {
      setInterimText('')
    })

    return () => {
      unsubscribeState?.()
      unsubscribeLevels?.()
      unsubscribeInterim?.()
      unsubscribeFinal?.()
      cleanup?.()
    }
  }, [startAudioCapture])

  return (
    <div className="flow-bar drag-handle flex h-[72px] w-[380px] items-center gap-3 px-4">
      {/* Recording indicator */}
      <div className="flex items-center gap-2">
        <div
          className={`h-3 w-3 rounded-full ${
            mode === 'continuous' ? 'bg-green-500' : 'bg-red-500'
          } animate-pulse`}
        />
      </div>

      {/* Audio visualizer */}
      <div className="flex-1">
        <AudioVisualizer levels={audioLevels} />
      </div>

      {/* Mode indicator */}
      <div className="text-xs text-white/60">
        {mode === 'continuous' ? 'Continuous' : 'Hold'}
      </div>
    </div>
  )
}
