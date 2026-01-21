import { desktopCapturer } from 'electron'

type AudioDataCallback = (data: Buffer) => void

export class AudioService {
  private mediaRecorder: MediaRecorder | null = null
  private audioContext: AudioContext | null = null
  private analyser: AnalyserNode | null = null
  private stream: MediaStream | null = null
  private callback: AudioDataCallback | null = null
  private isCapturing = false

  async startCapture(callback: AudioDataCallback): Promise<void> {
    if (this.isCapturing) {
      console.warn('Audio capture already in progress')
      return
    }

    this.callback = callback

    try {
      // Get microphone access
      // Note: In Electron main process, we need to use a different approach
      // The actual audio capture will happen in the renderer process via IPC
      // For now, this is a placeholder that will be connected via IPC

      this.isCapturing = true
      console.log('Audio capture started (via renderer)')
    } catch (error) {
      console.error('Failed to start audio capture:', error)
      throw error
    }
  }

  stopCapture(): void {
    if (!this.isCapturing) return

    if (this.mediaRecorder && this.mediaRecorder.state !== 'inactive') {
      this.mediaRecorder.stop()
    }

    if (this.stream) {
      this.stream.getTracks().forEach((track) => track.stop())
      this.stream = null
    }

    if (this.audioContext) {
      this.audioContext.close()
      this.audioContext = null
    }

    this.analyser = null
    this.mediaRecorder = null
    this.isCapturing = false
    this.callback = null

    console.log('Audio capture stopped')
  }

  // Called from renderer via IPC when audio data is available
  processAudioData(data: Buffer): void {
    if (this.isCapturing && this.callback) {
      this.callback(data)
    }
  }

  isActive(): boolean {
    return this.isCapturing
  }
}

// Audio capture utility for renderer process
export function createAudioCaptureScript(): string {
  return `
    let mediaRecorder = null;
    let audioContext = null;
    let analyser = null;
    let dataArray = null;

    async function startAudioCapture() {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          audio: {
            channelCount: 1,
            sampleRate: 16000,
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true
          }
        });

        // Setup audio context for visualization
        audioContext = new AudioContext({ sampleRate: 16000 });
        analyser = audioContext.createAnalyser();
        analyser.fftSize = 256;

        const source = audioContext.createMediaStreamSource(stream);
        source.connect(analyser);

        dataArray = new Uint8Array(analyser.frequencyBinCount);

        // Setup MediaRecorder for capturing audio data
        mediaRecorder = new MediaRecorder(stream, {
          mimeType: 'audio/webm;codecs=opus'
        });

        mediaRecorder.ondataavailable = async (event) => {
          if (event.data.size > 0) {
            const arrayBuffer = await event.data.arrayBuffer();
            // Convert to PCM format for Deepgram
            const pcmData = await convertToPCM(arrayBuffer);
            window.electronAPI.sendAudioData(pcmData);
          }
        };

        mediaRecorder.start(100); // Capture every 100ms

        // Start sending audio levels for visualization
        sendAudioLevels();

        return true;
      } catch (error) {
        console.error('Failed to start audio capture:', error);
        return false;
      }
    }

    function sendAudioLevels() {
      if (!analyser || !dataArray) return;

      analyser.getByteFrequencyData(dataArray);
      const levels = Array.from(dataArray.slice(0, 32));
      window.electronAPI.sendAudioLevels(levels);

      if (mediaRecorder?.state === 'recording') {
        requestAnimationFrame(sendAudioLevels);
      }
    }

    async function convertToPCM(webmBuffer) {
      // Create an AudioContext to decode the WebM audio
      const ctx = new OfflineAudioContext(1, 16000 * 0.1, 16000);
      const audioBuffer = await ctx.decodeAudioData(webmBuffer);

      // Get the raw PCM data
      const channelData = audioBuffer.getChannelData(0);

      // Convert to 16-bit PCM
      const pcm16 = new Int16Array(channelData.length);
      for (let i = 0; i < channelData.length; i++) {
        pcm16[i] = Math.max(-32768, Math.min(32767, channelData[i] * 32768));
      }

      return pcm16.buffer;
    }

    function stopAudioCapture() {
      if (mediaRecorder && mediaRecorder.state !== 'inactive') {
        mediaRecorder.stop();
      }
      if (audioContext) {
        audioContext.close();
      }
      mediaRecorder = null;
      audioContext = null;
      analyser = null;
    }
  `
}
