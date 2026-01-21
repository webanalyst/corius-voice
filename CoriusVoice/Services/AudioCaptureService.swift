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

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            if let converter = converter {
                // Convert to 16kHz mono
                let frameCount = AVAudioFrameCount(
                    Double(buffer.frameLength) * self.sampleRate / inputFormat.sampleRate
                )

                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: frameCount
                ) else { return }

                var error: NSError?
                let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                if status == .haveData || status == .endOfStream {
                    self.delegate?.audioCaptureDidReceiveBuffer(convertedBuffer)
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
            // For macOS 13, use the older API
            return AVCaptureDevice.devices(for: .audio)
        }
    }

    func setMicrophone(_ deviceID: String?) {
        // On macOS, we need to use AudioUnit to change input device
        // For simplicity, we use the default device
        print("[AudioCapture] Microphone selection: \(deviceID ?? "default")")
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
    func toData() -> Data? {
        guard let int16Data = int16ChannelData else { return nil }

        let channelCount = Int(format.channelCount)
        let frameLength = Int(frameLength)
        let bytesPerFrame = channelCount * MemoryLayout<Int16>.size
        let dataSize = frameLength * bytesPerFrame

        var data = Data(capacity: dataSize)

        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                var sample = int16Data[channel][frame]
                data.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
            }
        }

        return data
    }
}
