import Foundation
import AVFoundation

protocol AudioCaptureDelegate: AnyObject {
    func audioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer)
    func audioCaptureDidEncounterError(_ error: Error)
}

class AudioCaptureService {
    static let shared = AudioCaptureService()

    weak var delegate: AudioCaptureDelegate?

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var isCapturing = false

    // Audio format: 16kHz, mono, 16-bit PCM
    private let sampleRate: Double = 16000
    private let channels: AVAudioChannelCount = 1
    private let bufferSize: AVAudioFrameCount = 4096

    private init() {}

    var isRunning: Bool {
        return isCapturing && (audioEngine?.isRunning ?? false)
    }

    func startCapture() throws {
        guard !isCapturing else { return }

        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw AudioCaptureError.engineInitFailed
        }

        inputNode = engine.inputNode

        guard let inputNode = inputNode else {
            throw AudioCaptureError.inputNodeUnavailable
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create output format for Deepgram (16kHz, mono, 16-bit)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        ) else {
            throw AudioCaptureError.formatCreationFailed
        }

        // Create converter if needed
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        var bufferCount = 0
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            bufferCount += 1
            if bufferCount % 50 == 0 { // Log every 50 buffers (~1 second)
                print("[AudioCapture] 🎙️ Captured \(bufferCount) buffers, frameLength: \(buffer.frameLength)")
            }

            // Calculate audio levels for waveform visualization
            let levels = self.calculateAudioLevels(buffer: buffer, bandCount: 12)
            let rmsLevel = self.calculateRMSLevel(buffer: buffer)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .audioLevelsUpdated,
                    object: nil,
                    userInfo: ["levels": levels, "micLevel": rmsLevel]
                )
            }

            if let converter = converter {
                // Convert to 16kHz mono
                let frameCount = AVAudioFrameCount(
                    Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate
                )

                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: frameCount
                ) else {
                    if bufferCount < 5 {
                        print("[AudioCapture] ❌ Failed to create converted buffer")
                    }
                    return
                }

                var error: NSError?
                let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                if status == .haveData || status == .endOfStream {
                    if bufferCount < 5 {
                        print("[AudioCapture] ✅ Sending buffer #\(bufferCount) to delegate")
                    }
                    self.delegate?.audioCaptureDidReceiveBuffer(convertedBuffer)
                } else if let error = error {
                    print("[AudioCapture] ❌ Conversion error: \(error.localizedDescription)")
                }
            } else {
                self.delegate?.audioCaptureDidReceiveBuffer(buffer)
            }
        }

        try engine.start()
        isCapturing = true

        print("[AudioCapture] Started - format: \(inputFormat)")
    }

    func stopCapture() {
        guard isCapturing else { return }

        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        isCapturing = false

        print("[AudioCapture] Stopped")
    }

    func getAvailableMicrophones() -> [AVCaptureDevice] {
        if #available(macOS 14.0, *) {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone, .external],
                mediaType: .audio,
                position: .unspecified
            )
            return discoverySession.devices
        } else {
            // For macOS 13, use DiscoverySession with builtInMicrophone
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInMicrophone],
                mediaType: .audio,
                position: .unspecified
            )
            return discoverySession.devices
        }
    }

    func setMicrophone(_ deviceID: String?) {
        // On macOS, we need to use AudioUnit to change input device
        // For simplicity, we use the default device
        print("[AudioCapture] Microphone selection: \(deviceID ?? "default")")
    }

    /// Calculate audio levels from buffer for waveform visualization
    private func calculateAudioLevels(buffer: AVAudioPCMBuffer, bandCount: Int) -> [CGFloat] {
        guard let channelData = buffer.floatChannelData?[0] else {
            return Array(repeating: 0.1, count: bandCount)
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return Array(repeating: 0.1, count: bandCount)
        }

        let samplesPerBand = frameLength / bandCount
        var levels: [CGFloat] = []

        for band in 0..<bandCount {
            let startSample = band * samplesPerBand
            let endSample = min(startSample + samplesPerBand, frameLength)

            var sum: Float = 0
            for i in startSample..<endSample {
                sum += abs(channelData[i])
            }

            let average = sum / Float(endSample - startSample)
            // Normalize and scale (typical voice is 0.01-0.3 range)
            let normalized = CGFloat(min(average * 5, 1.0))
            levels.append(max(0.1, normalized))
        }

        return levels
    }

    /// Calculate simple RMS level for meter display
    private func calculateRMSLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else {
            return 0
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return 0
        }

        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(frameLength))

        // Apply noise gate and normalize
        let noiseThreshold: Float = 0.005
        if rms < noiseThreshold { return 0 }

        // Normalize to 0-1 range (typical voice RMS is 0.01-0.3)
        let sensitivity = StorageService.shared.settings.microphoneSensitivity
        return min(1.0, rms * sensitivity * 3.0)
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case engineInitFailed
    case inputNodeUnavailable
    case formatCreationFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .engineInitFailed:
            return "Failed to initialize audio engine"
        case .inputNodeUnavailable:
            return "Audio input node is unavailable"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .permissionDenied:
            return "Microphone permission denied"
        }
    }
}

// Extension to convert AVAudioPCMBuffer to Data
extension AVAudioPCMBuffer {
    /// Convert buffer to Data with optional gain amplification
    /// - Parameter gain: Amplification factor (1.0 = no change, 2.0 = double volume, etc.)
    func toData(gain: Float = 1.0) -> Data? {
        let frameLen = Int(frameLength)
        guard frameLen > 0 else {
            print("[AVAudioPCMBuffer.toData] ⚠️ Empty buffer (frameLength=0)")
            return nil
        }

        // Try Int16 format first (preferred for Deepgram)
        if let int16Data = int16ChannelData {
            let channelCount = Int(format.channelCount)
            let dataSize = frameLen * channelCount * MemoryLayout<Int16>.size
            var data = Data(capacity: dataSize)

            // Handle interleaved vs non-interleaved
            if format.isInterleaved && channelCount > 1 {
                // For interleaved, data is in int16Data[0] with samples alternating between channels
                let interleavedData = int16Data[0]
                for i in 0..<(frameLen * channelCount) {
                    var sample = interleavedData[i]
                    if gain != 1.0 {
                        let amplified = Int32(Float(sample) * gain)
                        sample = Int16(clamping: amplified)
                    }
                    data.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
                }
            } else {
                // Non-interleaved or mono
                for frame in 0..<frameLen {
                    for channel in 0..<channelCount {
                        var sample = int16Data[channel][frame]
                        if gain != 1.0 {
                            let amplified = Int32(Float(sample) * gain)
                            sample = Int16(clamping: amplified)
                        }
                        data.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
                    }
                }
            }
            return data
        }

        // Try Float32 format (convert to Int16)
        if let floatData = floatChannelData {
            let channelCount = Int(format.channelCount)
            let dataSize = frameLen * channelCount * MemoryLayout<Int16>.size
            var data = Data(capacity: dataSize)

            if format.isInterleaved && channelCount > 1 {
                let interleavedData = floatData[0]
                for i in 0..<(frameLen * channelCount) {
                    var floatSample = interleavedData[i] * gain
                    floatSample = max(-1.0, min(1.0, floatSample))  // Clamp
                    var sample = Int16(floatSample * 32767.0)
                    data.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
                }
            } else {
                for frame in 0..<frameLen {
                    for channel in 0..<channelCount {
                        var floatSample = floatData[channel][frame] * gain
                        floatSample = max(-1.0, min(1.0, floatSample))
                        var sample = Int16(floatSample * 32767.0)
                        data.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
                    }
                }
            }
            return data
        }

        print("[AVAudioPCMBuffer.toData] ⚠️ Unsupported format: \(format.commonFormat.rawValue)")
        return nil
    }
}
