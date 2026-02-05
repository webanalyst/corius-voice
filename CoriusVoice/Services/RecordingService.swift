import Foundation
import AVFoundation
import AppKit
import AudioToolbox

protocol RecordingServiceDelegate: AnyObject {
    func recordingServiceDidStartRecording()
    func recordingServiceDidStopRecording()
    func recordingServiceDidReceiveTranscript(_ text: String, isFinal: Bool)
    func recordingServiceDidEncounterError(_ error: Error)
    // Session recording callbacks
    func recordingServiceDidReceiveSessionSegment(_ segment: TranscriptSegment)
    func recordingServiceSessionDidUpdate(_ session: RecordingSession)
}

// Default implementation for optional methods
extension RecordingServiceDelegate {
    func recordingServiceDidReceiveSessionSegment(_ segment: TranscriptSegment) {}
    func recordingServiceSessionDidUpdate(_ session: RecordingSession) {}
}

class RecordingService: NSObject {
    static let shared = RecordingService()

    weak var delegate: RecordingServiceDelegate?

    private let audioCapture = AudioCaptureService.shared
    private let systemAudioCapture = SystemAudioCaptureService.shared
    private let deepgram = DeepgramService.shared
    private let textCleanup = TextCleanupService.shared
    private let storage = StorageService.shared
    private let contextService = ContextService.shared
    private let vadService = VADService.shared
    private let whisperService = WhisperService.shared

    private var isRecording = false
    private var isAcceptingTranscripts = false  // Stays true during stop delay
    private var currentTranscript = ""
    private var interimTranscript = ""
    private var recordingStartTime: Date?
    private var keepAliveTimer: Timer?
    private var currentAppContext: AppContext?

    // Session recording state
    private(set) var currentMode: RecordingMode = .quickCapture
    private(set) var currentSession: RecordingSession?
    private(set) var currentAudioSource: AudioSource = .microphone
    private var autoSaveTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3

    // VAD statistics for token savings
    private var vadStats = VADService.Statistics()

    // MARK: - Whisper Streaming State

    /// Whether we're using local Whisper for transcription
    private var isUsingWhisper: Bool {
        return storage.settings.transcriptionProvider == .whisper
    }

    /// Audio samples accumulated for Whisper streaming
    private var whisperAudioBuffer: [Float] = []
    private let whisperAudioBufferLock = NSLock()

    /// Timer for periodic Whisper processing
    private var whisperProcessingTimer: Timer?

    /// Last time we processed Whisper audio
    private var lastWhisperProcessTime: Date?

    /// Minimum seconds of audio before processing with Whisper
    private let whisperMinChunkDuration: TimeInterval = 2.5

    /// Maximum seconds of audio before forcing processing
    private let whisperMaxChunkDuration: TimeInterval = 10.0

    /// Sample rate for Whisper (16kHz)
    private let whisperSampleRate: Double = 16000

    /// Whether Whisper is currently processing a chunk
    private var isWhisperProcessing = false

    /// Accumulated Whisper transcript for session
    private var whisperSessionTranscript: String = ""

    // Audio file recording for voice profile training
    private var audioFileWriter: AVAudioFile?
    private var audioSamplesBuffer: [Float] = []
    private let maxAudioBufferDuration: TimeInterval = 3600  // Max 1 hour of audio

    // DUAL AUDIO MODE: Separate files and Deepgram instances for mic and system
    private var micAudioFileWriter: AVAudioFile?
    private var systemAudioFileWriter: AVAudioFile?
    private var micDeepgram: DeepgramService?  // Separate instance for mic in dual mode
    private var systemDeepgram: DeepgramService?  // Separate instance for system in dual mode
    private var isDualMode: Bool { currentAudioSource == .both }

    // Note: Audio processing is now synchronous to maintain proper buffer order
    // This prevents gaps in recorded audio during playback

    // Thread-safe audio sample buffer for speaker identification
    private var recentAudioSamplesLock = NSLock()
    private var _recentAudioSamples: [Float] = []
    private var recentAudioSamples: [Float] {
        get {
            recentAudioSamplesLock.lock()
            defer { recentAudioSamplesLock.unlock() }
            return _recentAudioSamples
        }
        set {
            recentAudioSamplesLock.lock()
            _recentAudioSamples = newValue
            recentAudioSamplesLock.unlock()
        }
    }

    // Real-time voice identification
    private let recentAudioMaxSamples = 16000 * 5  // 5 seconds at 16kHz
    private var identifiedSpeakers: Set<Int> = []  // Deepgram speaker IDs already identified
    private var pendingSpeakerIdentification: Set<Int> = []  // Speakers being identified
    private let voiceProfileService = VoiceProfileService.shared
    private var lastEmbeddingIdentificationTime: Date?
    private let embeddingIdentificationCooldown: TimeInterval = 6.0

    private override init() {
        super.init()
        audioCapture.delegate = self
        systemAudioCapture.delegate = self
        deepgram.delegate = self
    }

    var isCurrentlyRecording: Bool {
        return isRecording
    }

    var isSessionRecording: Bool {
        return currentMode == .sessionRecording && isRecording
    }

    // MARK: - Quick Capture (Existing Fn key behavior)

    func startRecording() {
        startRecording(mode: .quickCapture)
    }

    // MARK: - Session Recording

    /// Start a session recording (manual start/stop for long recordings)
    func startSessionRecording(audioSource: AudioSource = .microphone, title: String? = nil) {
        print("[RecordingService] 🎬 Starting session recording with source: \(audioSource.displayName)")

        // Store the audio source for this session
        currentAudioSource = audioSource

        // Create audio file(s) for saving
        var micFileName: String? = nil
        var systemFileName: String? = nil
        var singleFileName: String? = nil

        if audioSource == .both {
            // DUAL MODE: Create separate files for mic and system
            let (mic, sys) = setupDualAudioFiles()
            micFileName = mic
            systemFileName = sys
            setupDualDeepgram()
        } else {
            // SINGLE MODE: One file
            singleFileName = setupAudioFile()
        }

        // Create new session
        print("[RecordingService] 📝 Creating session with audioFileName: \(singleFileName ?? "nil"), mic: \(micFileName ?? "nil"), system: \(systemFileName ?? "nil")")
        currentSession = RecordingSession(
            audioSource: audioSource,
            title: title,
            audioFileName: singleFileName,
            micAudioFileName: micFileName,
            systemAudioFileName: systemFileName
        )
        print("[RecordingService] 📝 Session created with audioFileName: \(currentSession?.audioFileName ?? "nil")")

        // Reset VAD stats and audio buffer
        vadStats = VADService.Statistics()
        vadService.reset()
        audioSamplesBuffer.removeAll()

        // Reset real-time identification state
        recentAudioSamples.removeAll()
        identifiedSpeakers.removeAll()
        pendingSpeakerIdentification.removeAll()

        startRecording(mode: .sessionRecording, audioSource: audioSource)

        // Start auto-save timer
        let interval = storage.settings.autoSaveInterval
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.autoSaveSession()
        }
    }

    /// Setup single audio file for recording (mic only or system only)
    private func setupAudioFile() -> String? {
        let sessionsFolder = RecordingSession.sessionsFolder
        try? FileManager.default.createDirectory(at: sessionsFolder, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let fileName = "session_\(timestamp).wav"
        let fileURL = sessionsFolder.appendingPathComponent(fileName)

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

        do {
            audioFileWriter = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            print("[RecordingService] 🎵 Audio file created: \(fileName)")
            return fileName
        } catch {
            print("[RecordingService] ⚠️ Failed to create audio file: \(error)")
            return nil
        }
    }

    /// Setup DUAL audio files for mic and system (when using "both" mode)
    private func setupDualAudioFiles() -> (micFileName: String?, systemFileName: String?) {
        let sessionsFolder = RecordingSession.sessionsFolder
        try? FileManager.default.createDirectory(at: sessionsFolder, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

        // Create mic audio file
        let micFileName = "session_\(timestamp)_mic.wav"
        let micURL = sessionsFolder.appendingPathComponent(micFileName)
        do {
            micAudioFileWriter = try AVAudioFile(forWriting: micURL, settings: format.settings)
            print("[RecordingService] 🎤 Mic audio file created: \(micFileName)")
        } catch {
            print("[RecordingService] ⚠️ Failed to create mic audio file: \(error)")
        }

        // Create system audio file
        let systemFileName = "session_\(timestamp)_system.wav"
        let systemURL = sessionsFolder.appendingPathComponent(systemFileName)
        do {
            systemAudioFileWriter = try AVAudioFile(forWriting: systemURL, settings: format.settings)
            print("[RecordingService] 🔊 System audio file created: \(systemFileName)")
        } catch {
            print("[RecordingService] ⚠️ Failed to create system audio file: \(error)")
        }

        return (micAudioFileWriter != nil ? micFileName : nil,
                systemAudioFileWriter != nil ? systemFileName : nil)
    }

    /// Setup dual Deepgram instances for parallel transcription
    private func setupDualDeepgram() {
        let settings = storage.settings

        // Create mic Deepgram instance
        micDeepgram = DeepgramService(instanceID: "mic")
        micDeepgram?.delegate = self

        // Create system Deepgram instance
        systemDeepgram = DeepgramService(instanceID: "system")
        systemDeepgram?.delegate = self

        print("[RecordingService] 🔄 Dual Deepgram instances created")
    }

    /// Write audio buffer to file (converts to Float32 if needed)
    private func writeAudioToFile(_ buffer: AVAudioPCMBuffer) {
        guard let writer = audioFileWriter else { return }

        // Get the target format from the audio file
        let targetFormat = writer.processingFormat

        // Check if conversion is needed
        if buffer.format.commonFormat != targetFormat.commonFormat ||
           buffer.format.sampleRate != targetFormat.sampleRate ||
           buffer.format.channelCount != targetFormat.channelCount {
            // Convert buffer to target format
            if let convertedBuffer = convertBufferToFormat(buffer, targetFormat: targetFormat) {
                do {
                    try writer.write(from: convertedBuffer)
                } catch {
                    print("[RecordingService] ⚠️ Failed to write converted audio: \(error)")
                }
            } else {
                print("[RecordingService] ⚠️ Failed to convert audio buffer format")
            }
        } else {
            // No conversion needed
            do {
                try writer.write(from: buffer)
            } catch {
                print("[RecordingService] ⚠️ Failed to write audio: \(error)")
            }
        }
    }

    /// Convert audio buffer to target format (e.g., Int16 to Float32)
    private func convertBufferToFormat(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Handle Int16 to Float32 conversion manually (most common case for system audio)
        if buffer.format.commonFormat == .pcmFormatInt16 && targetFormat.commonFormat == .pcmFormatFloat32 {
            guard let int16Data = buffer.int16ChannelData?[0] else {
                print("[RecordingService] ⚠️ No Int16 channel data in buffer")
                return nil
            }

            let frameLength = Int(buffer.frameLength)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(frameLength)) else {
                print("[RecordingService] ⚠️ Failed to create Float32 output buffer")
                return nil
            }

            outputBuffer.frameLength = AVAudioFrameCount(frameLength)

            guard let floatData = outputBuffer.floatChannelData?[0] else {
                print("[RecordingService] ⚠️ No Float32 channel data in output buffer")
                return nil
            }

            // Convert Int16 samples to Float32 (normalize to -1.0 to 1.0)
            for i in 0..<frameLength {
                floatData[i] = Float(int16Data[i]) / 32768.0
            }

            return outputBuffer
        }

        // Use AVAudioConverter for other format conversions
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            print("[RecordingService] ⚠️ Failed to create audio converter from \(buffer.format) to \(targetFormat)")
            return nil
        }

        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate
        )

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity + 100) else {
            print("[RecordingService] ⚠️ Failed to create output buffer for conversion")
            return nil
        }

        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = conversionError {
            print("[RecordingService] ⚠️ Audio conversion error: \(error.localizedDescription)")
            return nil
        }

        return outputBuffer
    }

    /// Finalize audio file(s)
    private func finalizeAudioFile() {
        if isDualMode {
            micAudioFileWriter = nil
            systemAudioFileWriter = nil
            print("[RecordingService] 🎵 Dual audio files finalized (mic + system)")
        } else {
            audioFileWriter = nil
            print("[RecordingService] 🎵 Audio file finalized")
        }

        // Cleanup dual Deepgram instances
        micDeepgram?.disconnect()
        systemDeepgram?.disconnect()
        micDeepgram = nil
        systemDeepgram = nil
    }

    // MARK: - Audio Compression (WAV to WebM/M4A)

    /// Find ffmpeg path - checks bundled version first, then system paths
    private func findFFmpegPath() -> String? {
        // 1. Check for bundled ffmpeg in app Resources (preferred)
        if let bundledPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) {
            if FileManager.default.fileExists(atPath: bundledPath) {
                return bundledPath
            }
        }

        // 2. Check common system installation paths
        let systemPaths = [
            "/opt/homebrew/bin/ffmpeg",  // Homebrew on Apple Silicon
            "/usr/local/bin/ffmpeg",     // Homebrew on Intel / manual install
            "/usr/bin/ffmpeg"            // System install
        ]

        for path in systemPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // 3. Fallback: use 'which' to find ffmpeg in PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            print("[RecordingService] Error finding ffmpeg: \(error)")
        }

        return nil
    }

    /// Check if ffmpeg is available for WebM conversion
    private func isFFmpegAvailable() -> Bool {
        return findFFmpegPath() != nil
    }

    /// Convert WAV file to WebM (Opus) using ffmpeg - best compression
    /// Returns the new filename if successful, or nil if failed
    /// IMPORTANT: Verifies converted file before deleting original
    private func convertWAVtoWebM(wavFileName: String, completion: @escaping (String?) -> Void) {
        let sessionsFolder = RecordingSession.sessionsFolder
        let wavURL = sessionsFolder.appendingPathComponent(wavFileName)
        let webmFileName = wavFileName.replacingOccurrences(of: ".wav", with: ".webm")
        let webmURL = sessionsFolder.appendingPathComponent(webmFileName)

        guard FileManager.default.fileExists(atPath: wavURL.path) else {
            print("[RecordingService] ⚠️ WAV file not found: \(wavFileName)")
            completion(nil)
            return
        }

        // Get original file size for verification
        let originalSize = (try? FileManager.default.attributesOfItem(atPath: wavURL.path)[.size] as? Int) ?? 0
        guard originalSize > 0 else {
            print("[RecordingService] ⚠️ Original WAV file is empty: \(wavFileName)")
            completion(nil)
            return
        }

        // Remove existing WebM if present
        try? FileManager.default.removeItem(at: webmURL)

        // Use ffmpeg for WebM/Opus conversion
        guard let ffmpegPath = findFFmpegPath() else {
            print("[RecordingService] ⚠️ ffmpeg not found, keeping WAV")
            completion(nil)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-i", wavURL.path,
            "-c:a", "libopus",
            "-b:a", "32k",
            "-vbr", "on",
            "-compression_level", "10",
            "-application", "voip",
            "-y",
            webmURL.path
        ]

        // Capture stderr for debugging ffmpeg errors
        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        print("[RecordingService] 🔄 Converting \(wavFileName) to WebM (Opus)...")
        print("[RecordingService] 🔧 ffmpeg: \(ffmpegPath)")
        print("[RecordingService] 📁 Input: \(wavURL.path)")
        print("[RecordingService] 📁 Output: \(webmURL.path)")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
                process.waitUntilExit()

                // Read stderr output
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""

                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        // VERIFICATION: Check converted file exists and has content
                        guard FileManager.default.fileExists(atPath: webmURL.path) else {
                            print("[RecordingService] ❌ Verification failed: WebM file doesn't exist")
                            completion(nil)
                            return
                        }

                        let webmSize = (try? FileManager.default.attributesOfItem(atPath: webmURL.path)[.size] as? Int) ?? 0

                        // WebM should be at least 1KB for any valid audio
                        guard webmSize > 1024 else {
                            print("[RecordingService] ❌ Verification failed: WebM file too small (\(webmSize) bytes)")
                            if !stderrOutput.isEmpty {
                                let errorLines = stderrOutput.suffix(800)
                                print("[RecordingService] 📋 ffmpeg stderr:\n\(errorLines)")
                            }
                            try? FileManager.default.removeItem(at: webmURL)
                            completion(nil)
                            return
                        }

                        // VERIFICATION: Try to read the WebM file header to ensure it's valid
                        guard let fileHandle = try? FileHandle(forReadingFrom: webmURL),
                              let headerData = try? fileHandle.read(upToCount: 4),
                              headerData.count >= 4 else {
                            print("[RecordingService] ❌ Verification failed: Cannot read WebM file")
                            try? FileManager.default.removeItem(at: webmURL)
                            completion(nil)
                            return
                        }
                        try? fileHandle.close()

                        // WebM files start with 0x1A45DFA3 (EBML header)
                        let ebmlHeader: [UInt8] = [0x1A, 0x45, 0xDF, 0xA3]
                        let headerBytes = [UInt8](headerData)
                        guard headerBytes == ebmlHeader else {
                            print("[RecordingService] ❌ Verification failed: Invalid WebM header")
                            try? FileManager.default.removeItem(at: webmURL)
                            completion(nil)
                            return
                        }

                        let compressionRatio = Double(webmSize) / Double(originalSize) * 100

                        print("[RecordingService] ✅ WebM conversion verified: \(webmFileName)")
                        print("[RecordingService] 📊 Size: \(originalSize / 1024)KB → \(webmSize / 1024)KB (\(String(format: "%.1f", compressionRatio))%)")

                        // Only delete original after successful verification
                        do {
                            try FileManager.default.removeItem(at: wavURL)
                            print("[RecordingService] 🗑️ Deleted original WAV file (verified)")
                        } catch {
                            print("[RecordingService] ⚠️ Failed to delete WAV: \(error)")
                        }

                        completion(webmFileName)
                    } else {
                        print("[RecordingService] ❌ ffmpeg failed with status: \(process.terminationStatus)")
                        if !stderrOutput.isEmpty {
                            // Log last 500 chars of stderr (ffmpeg output can be verbose)
                            let errorLines = stderrOutput.suffix(500)
                            print("[RecordingService] 📋 ffmpeg stderr:\n\(errorLines)")
                        }
                        completion(nil)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("[RecordingService] ❌ Failed to run ffmpeg: \(error)")
                    completion(nil)
                }
            }
        }
    }

    /// Convert WAV file to M4A (AAC) - fallback when ffmpeg not available
    /// Returns the new filename if successful, or nil if failed
    /// IMPORTANT: Verifies converted file before deleting original
    private func convertWAVtoM4A(wavFileName: String, completion: @escaping (String?) -> Void) {
        let sessionsFolder = RecordingSession.sessionsFolder
        let wavURL = sessionsFolder.appendingPathComponent(wavFileName)
        let m4aFileName = wavFileName.replacingOccurrences(of: ".wav", with: ".m4a")
        let m4aURL = sessionsFolder.appendingPathComponent(m4aFileName)

        guard FileManager.default.fileExists(atPath: wavURL.path) else {
            print("[RecordingService] ⚠️ WAV file not found: \(wavFileName)")
            completion(nil)
            return
        }

        // Get original file size for verification
        let originalSize = (try? FileManager.default.attributesOfItem(atPath: wavURL.path)[.size] as? Int) ?? 0
        guard originalSize > 0 else {
            print("[RecordingService] ⚠️ Original WAV file is empty: \(wavFileName)")
            completion(nil)
            return
        }

        // Remove existing M4A if present
        try? FileManager.default.removeItem(at: m4aURL)

        let asset = AVAsset(url: wavURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            print("[RecordingService] ⚠️ Failed to create export session")
            completion(nil)
            return
        }

        exportSession.outputURL = m4aURL
        exportSession.outputFileType = AVFileType.m4a

        print("[RecordingService] 🔄 Converting \(wavFileName) to M4A...")

        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    // VERIFICATION: Check converted file exists and has content
                    guard FileManager.default.fileExists(atPath: m4aURL.path) else {
                        print("[RecordingService] ❌ Verification failed: M4A file doesn't exist")
                        completion(nil)
                        return
                    }

                    let m4aSize = (try? FileManager.default.attributesOfItem(atPath: m4aURL.path)[.size] as? Int) ?? 0

                    // M4A should be at least 1KB for any valid audio
                    guard m4aSize > 1024 else {
                        print("[RecordingService] ❌ Verification failed: M4A file too small (\(m4aSize) bytes)")
                        try? FileManager.default.removeItem(at: m4aURL)
                        completion(nil)
                        return
                    }

                    // VERIFICATION: Try to load the M4A with AVAudioPlayer to ensure it's playable
                    do {
                        let testPlayer = try AVAudioPlayer(contentsOf: m4aURL)
                        guard testPlayer.duration > 0 else {
                            print("[RecordingService] ❌ Verification failed: M4A has zero duration")
                            try? FileManager.default.removeItem(at: m4aURL)
                            completion(nil)
                            return
                        }
                    } catch {
                        print("[RecordingService] ❌ Verification failed: Cannot play M4A: \(error)")
                        try? FileManager.default.removeItem(at: m4aURL)
                        completion(nil)
                        return
                    }

                    let compressionRatio = Double(m4aSize) / Double(originalSize) * 100

                    print("[RecordingService] ✅ M4A conversion verified: \(m4aFileName)")
                    print("[RecordingService] 📊 Size: \(originalSize / 1024)KB → \(m4aSize / 1024)KB (\(String(format: "%.1f", compressionRatio))%)")

                    // Only delete original after successful verification
                    do {
                        try FileManager.default.removeItem(at: wavURL)
                        print("[RecordingService] 🗑️ Deleted original WAV file (verified)")
                    } catch {
                        print("[RecordingService] ⚠️ Failed to delete WAV: \(error)")
                    }

                    completion(m4aFileName)

                case .failed:
                    print("[RecordingService] ❌ M4A conversion failed: \(exportSession.error?.localizedDescription ?? "unknown")")
                    completion(nil)

                case .cancelled:
                    print("[RecordingService] ⚠️ Conversion cancelled")
                    completion(nil)

                default:
                    completion(nil)
                }
            }
        }
    }

    /// Convert WAV to compressed format
    /// Uses WebM (Opus) for maximum compression (~20x) - ffmpeg is bundled with the app
    /// WebMAudioPlayer loads files as base64 data URL to avoid sandbox issues
    private func convertWAVtoCompressed(wavFileName: String, completion: @escaping (String?) -> Void) {
        // WebM/Opus: ~20x compression (best for speech)
        // WebMAudioPlayer uses base64 data URL to avoid WKWebView sandbox issues
        if isFFmpegAvailable() {
            convertWAVtoWebM(wavFileName: wavFileName, completion: completion)
        } else {
            print("[RecordingService] ⚠️ ffmpeg not available, using M4A fallback")
            convertWAVtoM4A(wavFileName: wavFileName, completion: completion)
        }
    }

    // MARK: - Batch WAV Conversion

    /// Scan sessions folder for WAV files and convert them to compressed format
    /// Call this on app launch to migrate old recordings
    func convertExistingWAVFiles(progress: ((Int, Int) -> Void)? = nil, completion: @escaping (Int, Int) -> Void) {
        let sessionsFolder = RecordingSession.sessionsFolder

        // Find all WAV files in sessions folder
        guard let contents = try? FileManager.default.contentsOfDirectory(at: sessionsFolder, includingPropertiesForKeys: nil) else {
            completion(0, 0)
            return
        }

        let wavFiles = contents.filter { $0.pathExtension.lowercased() == "wav" }

        guard !wavFiles.isEmpty else {
            print("[RecordingService] ✅ No WAV files to convert")
            completion(0, 0)
            return
        }

        print("[RecordingService] 📁 Found \(wavFiles.count) WAV files to convert")

        var convertedCount = 0
        var failedCount = 0
        let total = wavFiles.count
        let group = DispatchGroup()

        for wavURL in wavFiles {
            group.enter()
            let fileName = wavURL.lastPathComponent

            convertWAVtoCompressed(wavFileName: fileName) { result in
                if result != nil {
                    convertedCount += 1
                } else {
                    failedCount += 1
                    print("[RecordingService] ⚠️ Failed to convert: \(fileName) (keeping original)")
                }

                // Report progress
                progress?(convertedCount + failedCount, total)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            print("[RecordingService] 📊 Batch conversion complete: \(convertedCount) converted, \(failedCount) failed")
            completion(convertedCount, failedCount)
        }
    }

    /// Update sessions.json to reflect converted filenames
    func updateSessionsAfterConversion() {
        var sessions = storage.loadSessions()
        var updated = false

        for i in 0..<sessions.count {
            var session = sessions[i]

            // Check and update single audio file
            if let fileName = session.audioFileName, fileName.hasSuffix(".wav") {
                let webmName = fileName.replacingOccurrences(of: ".wav", with: ".webm")
                let m4aName = fileName.replacingOccurrences(of: ".wav", with: ".m4a")
                let sessionsFolder = RecordingSession.sessionsFolder

                if FileManager.default.fileExists(atPath: sessionsFolder.appendingPathComponent(webmName).path) {
                    session.audioFileName = webmName
                    updated = true
                } else if FileManager.default.fileExists(atPath: sessionsFolder.appendingPathComponent(m4aName).path) {
                    session.audioFileName = m4aName
                    updated = true
                }
            }

            // Check and update mic audio file
            if let fileName = session.micAudioFileName, fileName.hasSuffix(".wav") {
                let webmName = fileName.replacingOccurrences(of: ".wav", with: ".webm")
                let m4aName = fileName.replacingOccurrences(of: ".wav", with: ".m4a")
                let sessionsFolder = RecordingSession.sessionsFolder

                if FileManager.default.fileExists(atPath: sessionsFolder.appendingPathComponent(webmName).path) {
                    session.micAudioFileName = webmName
                    updated = true
                } else if FileManager.default.fileExists(atPath: sessionsFolder.appendingPathComponent(m4aName).path) {
                    session.micAudioFileName = m4aName
                    updated = true
                }
            }

            // Check and update system audio file
            if let fileName = session.systemAudioFileName, fileName.hasSuffix(".wav") {
                let webmName = fileName.replacingOccurrences(of: ".wav", with: ".webm")
                let m4aName = fileName.replacingOccurrences(of: ".wav", with: ".m4a")
                let sessionsFolder = RecordingSession.sessionsFolder

                if FileManager.default.fileExists(atPath: sessionsFolder.appendingPathComponent(webmName).path) {
                    session.systemAudioFileName = webmName
                    updated = true
                } else if FileManager.default.fileExists(atPath: sessionsFolder.appendingPathComponent(m4aName).path) {
                    session.systemAudioFileName = m4aName
                    updated = true
                }
            }

            sessions[i] = session
        }

        if updated {
            storage.saveSessions(sessions)
            print("[RecordingService] 📝 Updated sessions.json with new audio filenames")
        }
    }

    /// Convert all session audio files to compressed format and update session
    private func compressSessionAudio(_ session: RecordingSession, completion: @escaping (RecordingSession) -> Void) {
        var updatedSession = session
        let group = DispatchGroup()

        // Convert single audio file
        if let wavFileName = session.audioFileName, wavFileName.hasSuffix(".wav") {
            group.enter()
            convertWAVtoCompressed(wavFileName: wavFileName) { compressedFileName in
                if let compressed = compressedFileName {
                    updatedSession.audioFileName = compressed
                }
                group.leave()
            }
        }

        // Convert mic audio file
        if let wavFileName = session.micAudioFileName, wavFileName.hasSuffix(".wav") {
            group.enter()
            convertWAVtoCompressed(wavFileName: wavFileName) { compressedFileName in
                if let compressed = compressedFileName {
                    updatedSession.micAudioFileName = compressed
                }
                group.leave()
            }
        }

        // Convert system audio file
        if let wavFileName = session.systemAudioFileName, wavFileName.hasSuffix(".wav") {
            group.enter()
            convertWAVtoCompressed(wavFileName: wavFileName) { compressedFileName in
                if let compressed = compressedFileName {
                    updatedSession.systemAudioFileName = compressed
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(updatedSession)
        }
    }

    /// Stop session recording
    func stopSessionRecording() {
        guard currentMode == .sessionRecording else { return }

        print("[RecordingService] 🛑 Stopping session recording")
        print("[RecordingService] 📊 VAD saved: \(vadStats.tokensSaved) of audio not sent")

        autoSaveTimer?.invalidate()
        autoSaveTimer = nil

        // Finalize audio file
        finalizeAudioFile()

        // Finalize session
        currentSession?.endDate = Date()

        // Save final session first (with WAV filenames)
        if var session = currentSession {
            saveSession(session)

            // Auto-train profiles for long sessions if speakers are already linked
            let minDuration = storage.settings.autoTrainMinSessionDuration
            if minDuration > 0, session.duration >= minDuration {
                autoTrainProfilesIfPossible(for: session)
            }

            // IMPORTANT: If using Whisper, transcribe BEFORE compression (WebM is not supported by AVAudioFile)
            if isUsingWhisper {
                // Save the WAV URL before compression
                let wavURL = session.primaryAudioFileURL
                print("[RecordingService] 🎯 Will transcribe WAV file before compression: \(wavURL?.lastPathComponent ?? "nil")")

                // Trigger final transcription first, then compress
                triggerFinalWhisperTranscription(for: session, wavURL: wavURL) { [weak self] updatedSession in
                    guard let self = self else { return }

                    // Now compress audio files
                    print("[RecordingService] 🗜️ Starting audio compression after transcription...")
                    self.compressSessionAudio(updatedSession) { compressedSession in
                        self.saveSession(compressedSession)
                        print("[RecordingService] ✅ Session updated with compressed audio")

                        NotificationCenter.default.post(
                            name: .sessionRecordingDidFinish,
                            object: nil,
                            userInfo: ["session": compressedSession]
                        )
                    }
                }
            } else {
                // Deepgram mode: compress immediately
                print("[RecordingService] 🗜️ Starting audio compression...")
                compressSessionAudio(session) { [weak self] compressedSession in
                    guard let self = self else { return }

                    self.saveSession(compressedSession)
                    print("[RecordingService] ✅ Session updated with compressed audio")

                    NotificationCenter.default.post(
                        name: .sessionRecordingDidFinish,
                        object: nil,
                        userInfo: ["session": compressedSession]
                    )
                }
            }
        }

        stopRecording()
        currentSession = nil
    }

    private func autoSaveSession() {
        guard let session = currentSession else { return }
        print("[RecordingService] 💾 Auto-saving session...")
        saveSession(session)
    }

    private func saveSession(_ session: RecordingSession) {
        print("[RecordingService] 💾 Saving session \(session.id.uuidString.prefix(8))... audioFileName: \(session.audioFileName ?? "nil")")
        var sessions = storage.loadSessions()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
            print("[RecordingService] 💾 Updated existing session at index \(index)")
        } else {
            sessions.insert(session, at: 0)
            print("[RecordingService] 💾 Inserted new session")
        }
        storage.saveSessions(sessions)
    }

    private func autoTrainProfilesIfPossible(for session: RecordingSession) {
        let speakerLibrary = SpeakerLibrary.shared

        Task {
            var trained = 0

            for speaker in session.speakers {
                guard let name = speaker.name else { continue }
                guard let knownSpeaker = speakerLibrary.speakers.first(where: { $0.name.lowercased() == name.lowercased() }) else { continue }

                // Skip if already trained on this session
                let hasRecord = voiceProfileService
                    .getTrainingRecords(for: knownSpeaker.id)
                    .contains { $0.sessionID == session.id }
                if hasRecord { continue }

                if let audioURL = audioURLForSpeaker(speakerID: speaker.id, session: session) {
                    do {
                        let ok = try await voiceProfileService.trainFromAssignedSpeaker(
                            audioURL: audioURL,
                            speaker: speaker,
                            segments: session.transcriptSegments,
                            knownSpeaker: knownSpeaker,
                            session: session
                        )
                        if ok { trained += 1 }
                    } catch {
                        continue
                    }
                } else if let embedding = speaker.embedding, embedding.count == 256 {
                    voiceProfileService.trainWithEmbedding(
                        for: knownSpeaker.id,
                        embedding: embedding,
                        duration: 0,
                        session: session
                    )
                    trained += 1
                }
            }

            if trained > 0 {
                print("[RecordingService] ✅ Auto-trained \(trained) profile(s) from session \(session.id.uuidString.prefix(8))")
            }
        }
    }

    private func audioURLForSpeaker(speakerID: Int, session: RecordingSession) -> URL? {
        let speakerSegments = session.transcriptSegments.filter { $0.speakerID == speakerID }
        let micCount = speakerSegments.filter { $0.source == .microphone }.count
        let systemCount = speakerSegments.filter { $0.source == .system }.count

        if systemCount > micCount, let url = session.systemAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let url = session.micAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let url = session.audioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    // MARK: - Core Recording Logic

    private func startRecording(mode: RecordingMode, audioSource: AudioSource = .microphone) {
        print("[RecordingService] 🎬 startRecording(mode: \(mode), source: \(audioSource.displayName)) called")

        guard !isRecording else {
            print("[RecordingService] ⚠️ Already recording, ignoring")
            return
        }

        let settings = storage.settings
        print("[RecordingService] 🎯 Transcription provider: \(settings.transcriptionProvider.displayName)")
        print("[RecordingService] 🌍 Language: \(settings.language ?? "auto-detect")")

        // Only require Deepgram API key if using Deepgram provider
        if settings.transcriptionProvider == .deepgram {
            print("[RecordingService] 🔑 Deepgram API Key length: \(settings.apiKey.count)")
            guard !settings.apiKey.isEmpty else {
                print("[RecordingService] ❌ No Deepgram API key configured!")
                delegate?.recordingServiceDidEncounterError(RecordingError.noApiKey)

                // Show alert to user
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Deepgram API Key Required"
                    alert.informativeText = "Please configure your Deepgram API key in Settings before recording."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Open Settings")
                    alert.addButton(withTitle: "Cancel")

                    if alert.runModal() == .alertFirstButtonReturn {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.settings") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                return
            }
        } else {
            print("[RecordingService] 🤖 Using local Whisper - no API key needed")
        }

        currentMode = mode
        isRecording = true
        isAcceptingTranscripts = true
        currentTranscript = ""
        interimTranscript = ""
        recordingStartTime = Date()
        reconnectAttempts = 0

        // Reset VAD for new recording
        vadService.reset()

        // Capture app context for keyterm prompting
        currentAppContext = contextService.getActiveAppInfo()
        let keyterms = contextService.getKeytermsForApp(currentAppContext!)

        print("[RecordingService] 📱 Active app: \(currentAppContext?.name ?? "Unknown")")
        print("[RecordingService] 🔤 Keyterms count: \(keyterms.count)")

        // For session recording, enable diarization if configured
        let enableDiarization = (mode == .sessionRecording) && settings.enableDiarization
        if enableDiarization {
            print("[RecordingService] 👥 Diarization enabled for session")
        }

        // Choose transcription provider
        if isUsingWhisper {
            // LOCAL WHISPER MODE
            print("[RecordingService] 🤖 Using local Whisper for transcription")
            setupWhisperStreaming()
        } else {
            // CLOUD DEEPGRAM MODE
            print("[RecordingService] 🌐 Connecting to Deepgram Nova-3...")

            // Connect to Deepgram
            if isDualMode && mode == .sessionRecording {
                // DUAL MODE: Connect both Deepgram instances with diarization enabled for speaker identification
                print("[RecordingService] 🔄 Dual mode: Connecting separate Deepgram instances with diarization...")
                micDeepgram?.connect(apiKey: settings.apiKey, language: settings.language, keyterms: keyterms, enableDiarization: settings.enableDiarization)
                systemDeepgram?.connect(apiKey: settings.apiKey, language: settings.language, keyterms: keyterms, enableDiarization: settings.enableDiarization)
            } else {
                // SINGLE MODE: Use shared Deepgram
                deepgram.connect(
                    apiKey: settings.apiKey,
                    language: settings.language,
                    keyterms: keyterms,
                    enableDiarization: enableDiarization
                )
            }
        }

        // Start audio capture based on source
        do {
            print("[RecordingService] 🎤 Starting audio capture (source: \(audioSource.displayName))...")

            switch audioSource {
            case .microphone:
                try audioCapture.startCapture()

            case .systemAudio:
                Task {
                    do {
                        try await systemAudioCapture.startCapture()
                        print("[RecordingService] 🔊 System audio capture started")
                    } catch {
                        await MainActor.run {
                            self.isRecording = false
                            self.currentMode = .quickCapture
                            self.delegate?.recordingServiceDidEncounterError(error)
                            print("[RecordingService] ❌ System audio failed: \(error.localizedDescription)")
                        }
                    }
                }

            case .both:
                // DUAL MODE: Start both captures
                try audioCapture.startCapture()
                Task {
                    do {
                        try await systemAudioCapture.startCapture()
                        print("[RecordingService] 🔊 System audio capture started (dual mode)")
                    } catch {
                        print("[RecordingService] ⚠️ System audio failed, using mic only: \(error.localizedDescription)")
                    }
                }
            }

            delegate?.recordingServiceDidStartRecording()
            print("[RecordingService] ✅ Recording started successfully!")

            NotificationCenter.default.post(
                name: mode == .sessionRecording ? .sessionRecordingStarted : .recordingStarted,
                object: nil
            )

            // Start keep-alive timer (for all active Deepgram instances) or Whisper processing timer
            if isUsingWhisper {
                // For Whisper, start periodic processing timer
                startWhisperProcessingTimer()
            } else {
                keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    if self.isDualMode {
                        self.micDeepgram?.sendKeepAlive()
                        self.systemDeepgram?.sendKeepAlive()
                    } else {
                        self.deepgram.sendKeepAlive()
                    }
                }
            }
        } catch {
            isRecording = false
            currentMode = .quickCapture
            delegate?.recordingServiceDidEncounterError(error)
            print("[RecordingService] ❌ Failed to start: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        print("[RecordingService] ⏳ Stopping recording with delay to capture last words...")

        // Step 1: Keep recording for a delay to capture trailing audio
        let audioDelayMs = 600 // 600ms extra audio capture

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(audioDelayMs)) { [weak self] in
            guard let self = self else { return }

            // Step 2: Stop audio capture
            self.isRecording = false
            self.keepAliveTimer?.invalidate()
            self.keepAliveTimer = nil
            self.stopWhisperProcessingTimer()
            self.audioCapture.stopCapture()
            self.systemAudioCapture.stopCapture()

            print("[RecordingService] 🎤 Audio stopped, waiting for final transcription...")

            // Step 3: Process remaining audio
            if self.isUsingWhisper {
                // For Whisper: Force process remaining buffer
                self.forceProcessWhisperBuffer()
            }

            // Step 4: Wait for final results
            let transcriptionDelayMs = self.isUsingWhisper ? 1500 : 800 // Whisper needs more time

            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(transcriptionDelayMs)) { [weak self] in
                guard let self = self else { return }

                // NOW we stop accepting transcripts
                self.isAcceptingTranscripts = false

                // Cleanup based on provider
                if self.isUsingWhisper {
                    // Clear Whisper buffer
                    self.whisperAudioBufferLock.lock()
                    self.whisperAudioBuffer.removeAll()
                    self.whisperAudioBufferLock.unlock()
                } else {
                    // Disconnect Deepgram (all instances in dual mode)
                    if self.isDualMode {
                        self.micDeepgram?.disconnect()
                        self.systemDeepgram?.disconnect()
                    } else {
                        self.deepgram.disconnect()
                    }
                }

                self.delegate?.recordingServiceDidStopRecording()

                // Post notification with final transcript - this triggers save/paste
                let finalTranscript = self.getCurrentTranscript()
                print("[RecordingService] ✅ Stopped recording (total delay: \(audioDelayMs + transcriptionDelayMs)ms)")
                print("[RecordingService] 📤 Posting recordingDidFinish with transcript: '\(finalTranscript.prefix(50))...'")

                NotificationCenter.default.post(
                    name: .recordingDidFinish,
                    object: nil,
                    userInfo: ["transcript": finalTranscript]
                )
            }
        }
    }

    func getCurrentTranscript() -> String {
        let settings = storage.settings
        let dictionary = storage.dictionaryEntries
        let snippets = storage.snippets

        let fullTranscript = currentTranscript + (interimTranscript.isEmpty ? "" : " " + interimTranscript)
        return textCleanup.cleanText(fullTranscript, settings: settings, dictionary: dictionary, snippets: snippets)
    }

    func getRecordingDuration() -> TimeInterval {
        guard let startTime = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
}

// MARK: - AudioCaptureDelegate

extension RecordingService: AudioCaptureDelegate {
    func audioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer) {
        // Process MICROPHONE audio
        guard isRecording else { return }

        let settings = storage.settings

        // Write audio to file SYNCHRONOUSLY to maintain proper order
        if currentMode == .sessionRecording {
            // In dual mode, write to mic-specific file
            if isDualMode, let writer = micAudioFileWriter {
                writeAudioToWriter(buffer, writer: writer)
            } else {
                writeAudioToFile(buffer)
            }

            // Update speaker ID buffer
            if let channelData = buffer.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
                recentAudioSamplesLock.lock()
                _recentAudioSamples.append(contentsOf: samples)
                if _recentAudioSamples.count > recentAudioMaxSamples {
                    _recentAudioSamples.removeFirst(_recentAudioSamples.count - recentAudioMaxSamples)
                }
                recentAudioSamplesLock.unlock()
            }
        }

        // Track VAD statistics
        vadStats.totalFrames += 1

        // Apply client-side VAD if enabled (saves API tokens by not sending silence)
        if settings.useClientSideVAD {
            let hasSpeech = vadService.containsSpeech(buffer)

            if hasSpeech {
                vadStats.speechFrames += 1
            } else {
                vadStats.silenceFrames += 1
                return
            }
        }

        // Send to transcription service based on provider
        if isUsingWhisper {
            // LOCAL WHISPER: Add samples to buffer for processing
            if let channelData = buffer.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
                addSamplesToWhisperBuffer(samples)
            } else if let int16Data = buffer.int16ChannelData?[0] {
                // Convert Int16 to Float for Whisper
                let frameLength = Int(buffer.frameLength)
                var samples = [Float](repeating: 0, count: frameLength)
                for i in 0..<frameLength {
                    samples[i] = Float(int16Data[i]) / 32768.0
                }
                addSamplesToWhisperBuffer(samples)
            }

            // Check if we should process based on VAD
            if !vadService.isCurrentlySpeaking && whisperBufferDuration >= whisperMinChunkDuration {
                processWhisperAudioIfNeeded()
            }
        } else {
            // CLOUD DEEPGRAM: Send to Deepgram
            let gain = settings.microphoneSensitivity
            guard let data = buffer.toData(gain: gain) else {
                print("[RecordingService] ❌ Failed to convert mic buffer to data")
                return
            }

            // In dual mode, send to mic-specific Deepgram
            if isDualMode, let micDg = micDeepgram {
                micDg.sendAudio(data)
            } else {
                deepgram.sendAudio(data)
            }
        }
    }

    /// Write audio buffer to a specific file writer
    private func writeAudioToWriter(_ buffer: AVAudioPCMBuffer, writer: AVAudioFile) {
        let targetFormat = writer.processingFormat

        if buffer.format.commonFormat != targetFormat.commonFormat ||
           buffer.format.sampleRate != targetFormat.sampleRate ||
           buffer.format.channelCount != targetFormat.channelCount {
            if let convertedBuffer = convertBufferToFormat(buffer, targetFormat: targetFormat) {
                do {
                    try writer.write(from: convertedBuffer)
                } catch {
                    print("[RecordingService] ⚠️ Failed to write converted audio: \(error)")
                }
            }
        } else {
            do {
                try writer.write(from: buffer)
            } catch {
                print("[RecordingService] ⚠️ Failed to write audio: \(error)")
            }
        }
    }

    func audioCaptureDidEncounterError(_ error: Error) {
        print("[RecordingService] ❌ Audio capture error: \(error.localizedDescription)")
        delegate?.recordingServiceDidEncounterError(error)

        // For session recording, attempt reconnection
        if currentMode == .sessionRecording && reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            print("[RecordingService] 🔄 Attempting reconnection (\(reconnectAttempts)/\(maxReconnectAttempts))...")
            attemptReconnection()
        }
    }

    private func attemptReconnection() {
        let settings = storage.settings

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self, self.isRecording else { return }

            self.deepgram.connect(
                apiKey: settings.apiKey,
                language: settings.language,
                keyterms: [],
                enableDiarization: settings.enableDiarization
            )
        }
    }

    // MARK: - Real-time Voice Identification

    /// Try to identify a speaker using voice profiles
    private func tryIdentifySpeakerRealTime(speakerID: Int, session: inout RecordingSession) {
        // Don't try if no profiles exist
        guard !voiceProfileService.profiles.isEmpty else {
            print("[RecordingService] 🔍 Skipping real-time identification - no voice profiles available")
            return
        }

        // Log profile status
        let profilesWithEmbeddings = voiceProfileService.profiles.filter { $0.hasEmbedding }.count
        let profilesWithFeatures = voiceProfileService.profiles.filter { $0.features.pitchMean > 0 }.count
        print("[RecordingService] 🔍 Available profiles: \(voiceProfileService.profiles.count) total, \(profilesWithEmbeddings) with embeddings, \(profilesWithFeatures) with valid features")

        // Need at least 1 second of audio (16000 samples)
        guard recentAudioSamples.count >= 16000 else {
            print("[RecordingService] 🔍 Not enough audio yet for identification (\(recentAudioSamples.count) samples)")
            return
        }

        // Check audio buffer has actual content
        let maxAmplitude = recentAudioSamples.suffix(16000).map { abs($0) }.max() ?? 0
        guard maxAmplitude > 0.01 else {
            print("[RecordingService] 🔍 Audio too quiet for identification (max amplitude: \(String(format: "%.4f", maxAmplitude)))")
            return
        }
        print("[RecordingService] 🔊 Audio buffer stats: \(recentAudioSamples.count) samples, max amplitude: \(String(format: "%.4f", maxAmplitude))")

        pendingSpeakerIdentification.insert(speakerID)

        // Use the most recent 3 seconds of audio for better accuracy
        let samplesToUse = min(recentAudioSamples.count, 48000)  // 3 seconds at 16kHz
        let samples = Array(recentAudioSamples.suffix(samplesToUse))

        print("[RecordingService] 🔍 Attempting real-time identification for speaker \(speakerID) with \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16000.0))s)")

        // Run identification in background
        Task {
            var embeddingMatch: (speakerID: UUID, speakerName: String, confidence: Float)?
            let hasEmbeddingProfiles = voiceProfileService.profiles.contains { $0.hasEmbedding }

            if #available(macOS 14.0, *), LocalDiarizationService.shared.isAvailable, hasEmbeddingProfiles {
                let now = Date()
                if let lastTime = self.lastEmbeddingIdentificationTime,
                   now.timeIntervalSince(lastTime) < self.embeddingIdentificationCooldown {
                    print("[RecordingService] ⏳ Skipping embedding identification (cooldown)")
                } else {
                    self.lastEmbeddingIdentificationTime = now
                    do {
                        let diarization = try await LocalDiarizationService.shared.processSamples(samples)
                        if let bestProfile = diarization.speakerProfiles.values.max(by: { $0.totalDuration < $1.totalDuration }) {
                            embeddingMatch = voiceProfileService.identifyWithEmbedding(bestProfile.embedding, threshold: 0.45)
                            if let match = embeddingMatch {
                                print("[RecordingService] 🧬 Embedding match: \(match.speakerName) (confidence: \(String(format: "%.1f", match.confidence * 100))%)")
                            } else {
                                print("[RecordingService] 🧬 No embedding match found")
                            }
                        }
                    } catch {
                        print("[RecordingService] ⚠️ Embedding identification failed: \(error.localizedDescription)")
                    }
                }
            }

            let matches = embeddingMatch == nil ? voiceProfileService.identifySpeaker(from: samples) : []
            if embeddingMatch == nil {
                print("[RecordingService] 🔍 Feature identification returned \(matches.count) match(es)")
            }

            await MainActor.run {
                self.pendingSpeakerIdentification.remove(speakerID)

                let bestMatch = embeddingMatch ?? matches.first.map { (speakerID: $0.speakerID, speakerName: $0.speakerName, confidence: $0.confidence) }

                if let bestMatch = bestMatch {
                    print("[RecordingService] ✅ Identified speaker \(speakerID) as '\(bestMatch.speakerName)' (confidence: \(String(format: "%.1f", bestMatch.confidence * 100))%)")

                    // Update session with identified name
                    self.currentSession?.updateSpeakerName(speakerID: speakerID, name: bestMatch.speakerName)

                    // Update color from library
                    if let knownSpeaker = SpeakerLibrary.shared.getSpeaker(byID: bestMatch.speakerID) {
                        if let index = self.currentSession?.speakers.firstIndex(where: { $0.id == speakerID }) {
                            self.currentSession?.speakers[index].color = knownSpeaker.color
                        }
                        SpeakerLibrary.shared.markSpeakerUsed(knownSpeaker.id)
                    }

                    self.identifiedSpeakers.insert(speakerID)

                    // Notify UI
                    if let session = self.currentSession {
                        self.delegate?.recordingServiceSessionDidUpdate(session)
                        NotificationCenter.default.post(
                            name: .sessionSpeakerIdentified,
                            object: nil,
                            userInfo: [
                                "speakerID": speakerID,
                                "name": bestMatch.speakerName,
                                "confidence": bestMatch.confidence
                            ]
                        )
                    }
                } else {
                    print("[RecordingService] ❌ No match found for speaker \(speakerID)")
                }
            }
        }
    }

    // MARK: - Non-Speech Detection

    /// Check if text is a non-speech audio annotation like "(music)", "[applause]", "*buzzing*", etc.
    /// These are sound descriptions from Deepgram, not actual spoken words
    private func isNonSpeechAnnotation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // Check for text entirely in parentheses: (music), (upbeat music), (laughing)
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
            return true
        }

        // Check for text entirely in brackets: [Music], [Applause], [BLANK_AUDIO]
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            return true
        }

        // Check for text entirely in asterisks: *Buzzing*, *laughing*, *sighs*
        if trimmed.hasPrefix("*") && trimmed.hasSuffix("*") && trimmed.count > 2 {
            return true
        }

        // Check for common Deepgram non-speech markers
        let lowercased = trimmed.lowercased()
        let nonSpeechMarkers = [
            "blank_audio",
            "inaudible",
            "unintelligible",
            "crosstalk",
            "speaking in foreign language",
            "foreign language",
            "speaking in a foreign language"
        ]

        for marker in nonSpeechMarkers {
            if lowercased.contains(marker) {
                return true
            }
        }

        return false
    }
}

// MARK: - SystemAudioCaptureDelegate

extension RecordingService: SystemAudioCaptureDelegate {
    private static var systemAudioBufferCount = 0

    func systemAudioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer) {
        // Process system audio with PARALLEL processing on dedicated queues
        // This ensures audio capture doesn't block on any single operation
        guard isRecording else { return }

        RecordingService.systemAudioBufferCount += 1
        let bufferCount = RecordingService.systemAudioBufferCount

        // Debug logging every 50 buffers
        if bufferCount % 50 == 1 {
            print("[RecordingService] 🔊 System audio buffer #\(bufferCount): format=\(buffer.format.commonFormat.rawValue), frames=\(buffer.frameLength), channels=\(buffer.format.channelCount)")
        }

        // Write audio to file SYNCHRONOUSLY to maintain proper order (critical for playback)
        if currentMode == .sessionRecording {
            // In dual mode, write to system-specific file
            if isDualMode, let writer = systemAudioFileWriter {
                writeAudioToWriter(buffer, writer: writer)
            } else {
                writeAudioToFile(buffer)
            }

            // Extract samples for speaker identification (lightweight, keep inline)
            var samples: [Float] = []
            if let channelData = buffer.floatChannelData?[0] {
                samples = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
            } else if let int16Data = buffer.int16ChannelData?[0] {
                let frameLength = Int(buffer.frameLength)
                samples = [Float](repeating: 0, count: frameLength)
                for i in 0..<frameLength {
                    samples[i] = Float(int16Data[i]) / 32768.0
                }
            }

            // Update speaker ID buffer (thread-safe)
            if !samples.isEmpty {
                recentAudioSamplesLock.lock()
                _recentAudioSamples.append(contentsOf: samples)
                if _recentAudioSamples.count > recentAudioMaxSamples {
                    _recentAudioSamples.removeFirst(_recentAudioSamples.count - recentAudioMaxSamples)
                }
                recentAudioSamplesLock.unlock()
            }
        }

        // Send to transcription service based on provider
        if isUsingWhisper {
            // LOCAL WHISPER: Add samples to buffer for processing
            // System audio from ScreenCaptureKit is typically very quiet, needs boost
            let gain: Float = 8.0
            var samplesAdded = 0
            if let channelData = buffer.floatChannelData?[0] {
                let frameLength = Int(buffer.frameLength)
                var samples = [Float](repeating: 0, count: frameLength)
                for i in 0..<frameLength {
                    samples[i] = channelData[i] * gain
                }
                addSamplesToWhisperBuffer(samples)
                samplesAdded = frameLength
            } else if let int16Data = buffer.int16ChannelData?[0] {
                let frameLength = Int(buffer.frameLength)
                var samples = [Float](repeating: 0, count: frameLength)
                for i in 0..<frameLength {
                    samples[i] = (Float(int16Data[i]) / 32768.0) * gain
                }
                addSamplesToWhisperBuffer(samples)
                samplesAdded = frameLength
            }

            // Log periodically
            if bufferCount % 100 == 1 {
                print("[RecordingService] 🎤 Whisper buffer: added \(samplesAdded) samples, total duration: \(String(format: "%.1f", whisperBufferDuration))s")
            }

            // Trigger processing if we have enough audio
            if whisperBufferDuration >= whisperMinChunkDuration {
                processWhisperAudioIfNeeded()
            }
        } else {
            // CLOUD DEEPGRAM: Send to Deepgram
            // System audio from ScreenCaptureKit is typically very quiet, needs significant boost
            let gain: Float = 8.0  // Boost system audio significantly for better transcription
            guard let data = buffer.toData(gain: gain) else {
                if bufferCount < 5 {
                    print("[RecordingService] ❌ Failed to convert system audio buffer to data")
                }
                return
            }

            // Send directly - WebSocket.send is already async internally
            // In dual mode, send to system-specific Deepgram instance
            if isDualMode, let systemDg = systemDeepgram {
                systemDg.sendAudio(data)
            } else {
                deepgram.sendAudio(data)
            }

            // Log detailed info periodically
            if bufferCount % 100 == 1 {
                print("[RecordingService] 📤 System audio #\(bufferCount): \(data.count) bytes sent to Deepgram")
            }
        }

        // Track VAD statistics (lightweight)
        vadStats.totalFrames += 1
        vadStats.speechFrames += 1
    }

    func systemAudioCaptureDidEncounterError(_ error: Error) {
        print("[RecordingService] ❌ System audio capture error: \(error.localizedDescription)")
        delegate?.recordingServiceDidEncounterError(error)
    }

    private func postAudioLevels(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let bandCount = 12
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
            let normalized = CGFloat(min(average * 5, 1.0))
            levels.append(max(0.1, normalized))
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .audioLevelsUpdated,
                object: nil,
                userInfo: ["levels": levels]
            )
        }
    }
}

// MARK: - DeepgramServiceDelegate

extension RecordingService: DeepgramServiceDelegate {
    func deepgramDidReceiveTranscript(_ transcript: DeepgramTranscript, fromInstance instanceID: String) {
        print("[RecordingService] 📨 Received transcript from Deepgram (instance: \(instanceID))")
        print("[RecordingService] 📝 Text: '\(transcript.transcript)'")
        print("[RecordingService] ✓ Is final: \(transcript.isFinal)")

        // Use isAcceptingTranscripts to accept transcripts during stop delay
        guard isAcceptingTranscripts else {
            print("[RecordingService] ⚠️ Not accepting transcripts, ignoring")
            return
        }

        // Handle session recording with segments
        if currentMode == .sessionRecording, transcript.isFinal, !transcript.transcript.isEmpty {
            // Determine source based on instance ID (for dual mode) or audio source (for single mode)
            let source: TranscriptSource
            if isDualMode {
                source = (instanceID == "mic") ? .microphone : .system
            } else {
                // Single mode: determine source from audio source setting
                switch currentAudioSource {
                case .systemAudio:
                    source = .system
                case .microphone:
                    source = .microphone
                case .both:
                    source = .unknown  // Shouldn't happen in single mode
                }
            }
            handleSessionTranscript(transcript, source: source)
        }

        if transcript.isFinal {
            // Add to final transcript
            if !transcript.transcript.isEmpty {
                if !currentTranscript.isEmpty {
                    currentTranscript += " "
                }
                currentTranscript += transcript.transcript
                print("[RecordingService] 💾 Added to final transcript: '\(currentTranscript)'")
            }
            interimTranscript = ""
        } else {
            // Update interim transcript
            interimTranscript = transcript.transcript
            print("[RecordingService] ⏳ Interim transcript: '\(interimTranscript)'")
        }

        let cleanedTranscript = getCurrentTranscript()
        print("[RecordingService] 🧹 Cleaned transcript: '\(cleanedTranscript)'")

        delegate?.recordingServiceDidReceiveTranscript(cleanedTranscript, isFinal: transcript.isFinal)

        // Post notification for UI updates
        print("[RecordingService] 📡 Posting transcriptionReceived notification")
        NotificationCenter.default.post(
            name: .transcriptionReceived,
            object: nil,
            userInfo: [
                "text": cleanedTranscript,
                "isFinal": transcript.isFinal,
                "speaker": transcript.dominantSpeaker as Any
            ]
        )
    }

    private func handleSessionTranscript(_ transcript: DeepgramTranscript, source: TranscriptSource) {
        guard var session = currentSession else { return }

        // Filter out non-speech audio annotations like "(upbeat music)", "[Music]", etc.
        // These are sound descriptions, not actual voice transcriptions
        let trimmedText = transcript.transcript.trimmingCharacters(in: .whitespaces)
        if isNonSpeechAnnotation(trimmedText) {
            print("[RecordingService] 🎵 Skipping non-speech annotation: '\(trimmedText)'")
            return
        }

        // Convert Deepgram words to TranscriptWords
        let words = transcript.words.map { word in
            TranscriptWord(
                word: word.punctuatedWord,
                start: word.start,
                end: word.end,
                confidence: word.confidence,
                speakerID: word.speaker
            )
        }

        // Use the first word's start time as the segment timestamp
        // This is the actual time in the audio when this speech starts
        // Fallback to current duration if no words (shouldn't happen)
        let timestamp: TimeInterval
        if let firstWord = transcript.words.first {
            timestamp = firstWord.start
            print("[RecordingService] Segment timestamp from Deepgram: \(String(format: "%.2f", timestamp))s (source: \(source.displayName))")
        } else {
            timestamp = getRecordingDuration()
            print("[RecordingService] Segment timestamp fallback: \(String(format: "%.2f", timestamp))s (source: \(source.displayName))")
        }

        // Apply offset to system audio speaker IDs to avoid collision with mic speakers
        // Mic speakers: 0-999, System speakers: 1000+
        let systemSpeakerOffset = 1000

        // Determine speaker ID - use Deepgram's if available, otherwise assign a default
        // Default: 0 for mic (will be identified as "Me" or matched to profile)
        //          1000 for system audio (will attempt identification against profiles)
        let adjustedSpeakerID: Int
        if let deepgramSpeakerID = transcript.dominantSpeaker {
            adjustedSpeakerID = source == .system ? deepgramSpeakerID + systemSpeakerOffset : deepgramSpeakerID
        } else {
            // No speaker ID from Deepgram - assign default based on source
            // This enables real-time identification even without Deepgram diarization
            adjustedSpeakerID = source == .system ? systemSpeakerOffset : 0
        }

        // Adjust word speaker IDs as well
        let adjustedWords = words.map { word -> TranscriptWord in
            TranscriptWord(
                word: word.word,
                start: word.start,
                end: word.end,
                confidence: word.confidence,
                speakerID: word.speakerID.map { source == .system ? $0 + systemSpeakerOffset : $0 } ?? adjustedSpeakerID
            )
        }

        // Create segment with source information
        let segment = TranscriptSegment(
            timestamp: timestamp,
            text: transcript.transcript,
            speakerID: adjustedSpeakerID,
            confidence: transcript.confidence,
            isFinal: true,
            words: adjustedWords,
            source: source  // Tag with audio source for chat-like UI
        )

        // Ensure speaker exists in session
        session.ensureSpeakerExists(speakerID: adjustedSpeakerID, source: source)
        let sourceLabel = source == .system ? "system" : "mic"
        print("[RecordingService] 👤 Speaker \(adjustedSpeakerID) (\(sourceLabel)): '\(transcript.transcript.prefix(30))...'")

        // Try to identify speaker in real-time if not already identified
        // This now works even without Deepgram diarization
        if !identifiedSpeakers.contains(adjustedSpeakerID) && !pendingSpeakerIdentification.contains(adjustedSpeakerID) {
            tryIdentifySpeakerRealTime(speakerID: adjustedSpeakerID, session: &session)
        }

        // Add segment to session
        session.transcriptSegments.append(segment)
        currentSession = session

        // Notify delegate
        delegate?.recordingServiceDidReceiveSessionSegment(segment)
        delegate?.recordingServiceSessionDidUpdate(session)

        // Post notification for session updates
        NotificationCenter.default.post(
            name: .sessionTranscriptUpdated,
            object: nil,
            userInfo: ["segment": segment, "session": session]
        )
    }

    func deepgramDidReceiveUtteranceEnd(fromInstance instanceID: String) {
        print("[RecordingService] Utterance ended (instance: \(instanceID))")
    }

    func deepgramDidConnect(fromInstance instanceID: String) {
        print("[RecordingService] Deepgram connected (instance: \(instanceID))")
        reconnectAttempts = 0  // Reset on successful connection
    }

    func deepgramDidDisconnect(error: Error?, fromInstance instanceID: String) {
        if let error = error {
            print("[RecordingService] Deepgram (\(instanceID)) disconnected with error: \(error.localizedDescription)")

            // For session recording, attempt reconnection
            if currentMode == .sessionRecording && isRecording && reconnectAttempts < maxReconnectAttempts {
                reconnectAttempts += 1
                print("[RecordingService] 🔄 Attempting Deepgram reconnection (\(reconnectAttempts)/\(maxReconnectAttempts))...")
                attemptReconnection()
            } else if isRecording {
                delegate?.recordingServiceDidEncounterError(error)
            }
        } else {
            print("[RecordingService] Deepgram disconnected")
        }
    }
}

// MARK: - Whisper Streaming Support

extension RecordingService {

    /// Setup Whisper streaming for local transcription
    private func setupWhisperStreaming() {
        print("[RecordingService] 🤖 Setting up Whisper streaming...")

        // Reset Whisper state
        whisperAudioBufferLock.lock()
        whisperAudioBuffer.removeAll()
        whisperAudioBufferLock.unlock()

        whisperSessionTranscript = ""
        lastWhisperProcessTime = Date()
        isWhisperProcessing = false

        print("[RecordingService] 🤖 Whisper state reset, buffer cleared")

        // Check if streaming model is loaded
        Task { @MainActor in
            let modelSizeString = self.storage.settings.whisperStreamingModelSize
            let modelSize = WhisperModelSize(rawValue: modelSizeString) ?? .base
            print("[RecordingService] 🤖 Target streaming model: \(modelSize.displayName)")
            print("[RecordingService] 🤖 Streaming model loaded: \(self.whisperService.isStreamingModelLoaded)")
            print("[RecordingService] 🤖 Current streaming model: \(self.whisperService.streamingModelSize?.displayName ?? "none")")

            if !self.whisperService.isStreamingModelLoaded || self.whisperService.streamingModelSize != modelSize {
                print("[RecordingService] ⏳ Loading streaming model: \(modelSize.displayName)...")
                do {
                    try await self.whisperService.loadStreamingModel(modelSize)
                    print("[RecordingService] ✅ Streaming model loaded successfully: \(modelSize.displayName)")
                } catch {
                    print("[RecordingService] ❌ Failed to load streaming model: \(error.localizedDescription)")
                    print("[RecordingService] ⚠️ Real-time transcription will not work!")
                }
            } else {
                print("[RecordingService] ✅ Streaming model already loaded: \(modelSize.displayName)")
            }
        }
    }

    /// Start timer for periodic Whisper processing
    private func startWhisperProcessingTimer() {
        whisperProcessingTimer?.invalidate()

        // Process every 3 seconds or when VAD detects speech end
        whisperProcessingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording, self.isUsingWhisper else { return }
            self.processWhisperAudioIfNeeded()
        }

        print("[RecordingService] ⏱️ Whisper processing timer started")
    }

    /// Stop Whisper processing timer
    private func stopWhisperProcessingTimer() {
        whisperProcessingTimer?.invalidate()
        whisperProcessingTimer = nil
    }

    /// Add audio samples to Whisper buffer
    func addSamplesToWhisperBuffer(_ samples: [Float]) {
        guard isUsingWhisper else { return }

        whisperAudioBufferLock.lock()
        whisperAudioBuffer.append(contentsOf: samples)

        // Limit buffer size to prevent memory issues (max 60 seconds)
        let maxSamples = Int(60.0 * whisperSampleRate)
        if whisperAudioBuffer.count > maxSamples {
            whisperAudioBuffer.removeFirst(whisperAudioBuffer.count - maxSamples)
        }
        whisperAudioBufferLock.unlock()
    }

    /// Get current Whisper buffer duration
    private var whisperBufferDuration: TimeInterval {
        whisperAudioBufferLock.lock()
        let duration = TimeInterval(whisperAudioBuffer.count) / whisperSampleRate
        whisperAudioBufferLock.unlock()
        return duration
    }

    /// Process Whisper audio buffer if conditions are met
    private func processWhisperAudioIfNeeded() {
        guard !isWhisperProcessing else {
            return  // Silent skip - already processing
        }

        let bufferDuration = whisperBufferDuration

        // Check if we have enough audio or if VAD detected speech end
        let hasEnoughAudio = bufferDuration >= whisperMinChunkDuration
        let shouldForceProcess = bufferDuration >= whisperMaxChunkDuration

        guard hasEnoughAudio || shouldForceProcess else {
            return
        }

        // Process the buffer
        isWhisperProcessing = true

        // Get and clear the buffer
        whisperAudioBufferLock.lock()
        let samples = whisperAudioBuffer
        whisperAudioBuffer.removeAll()
        whisperAudioBufferLock.unlock()

        print("[RecordingService] 🎤 Processing Whisper buffer: \(String(format: "%.1f", bufferDuration))s (\(samples.count) samples)")

        // Process asynchronously on main actor (where WhisperService lives)
        Task { @MainActor in
            defer { self.isWhisperProcessing = false }

            // Check if streaming model is loaded (must check on main actor)
            guard self.whisperService.isStreamingModelLoaded else {
                print("[RecordingService] ⚠️ Cannot process: streaming model not loaded")
                return
            }

            let language = self.storage.settings.language
            print("[RecordingService] 🔄 Calling Whisper transcribeAudioSamples with \(samples.count) samples...")

            let transcriptStartTime = Date()
            let transcript = await self.whisperService.transcribeAudioSamples(samples, language: language)
            let transcriptElapsed = Date().timeIntervalSince(transcriptStartTime)
            print("[RecordingService] ⏱️ transcribeAudioSamples returned in \(String(format: "%.2f", transcriptElapsed))s")

            if let transcript = transcript {
                // Add to session transcript
                if !self.whisperSessionTranscript.isEmpty {
                    self.whisperSessionTranscript += " "
                }
                self.whisperSessionTranscript += transcript

                // Update current transcript
                if !self.currentTranscript.isEmpty {
                    self.currentTranscript += " "
                }
                self.currentTranscript += transcript

                print("[RecordingService] 📝 Whisper chunk: '\(transcript.prefix(50))...'")

                // Notify delegate
                self.delegate?.recordingServiceDidReceiveTranscript(self.getCurrentTranscript(), isFinal: true)

                // Post notification
                NotificationCenter.default.post(
                    name: .transcriptionReceived,
                    object: nil,
                    userInfo: [
                        "text": self.getCurrentTranscript(),
                        "isFinal": true,
                        "speaker": Optional<Int>.none as Any
                    ]
                )

                // For session recording, create a segment
                if self.currentMode == .sessionRecording, var session = self.currentSession {
                    let timestamp = self.getRecordingDuration()

                    // Determine source based on audio source setting
                    let source: TranscriptSource = self.currentAudioSource == .systemAudio ? .system : .microphone

                    // Assign speaker ID based on source (same logic as Deepgram path)
                    // Mic speakers: 0-999, System speakers: 1000+
                    let speakerID = source == .system ? 1000 : 0

                    let segment = TranscriptSegment(
                        timestamp: timestamp,
                        text: transcript,
                        speakerID: speakerID,  // Default speaker ID for real-time display
                        confidence: 0.8,  // Estimated confidence
                        isFinal: true,
                        words: [],
                        source: source
                    )

                    // Ensure speaker exists in session for real-time UI
                    session.ensureSpeakerExists(speakerID: speakerID, source: source)
                    print("[RecordingService] 👤 Whisper speaker \(speakerID) (\(source.displayName)): '\(transcript.prefix(30))...'")

                    // Try to identify speaker in real-time (embeddings/features)
                    if !self.identifiedSpeakers.contains(speakerID) && !self.pendingSpeakerIdentification.contains(speakerID) {
                        self.tryIdentifySpeakerRealTime(speakerID: speakerID, session: &session)
                    }

                    session.transcriptSegments.append(segment)
                    self.currentSession = session
                    self.delegate?.recordingServiceDidReceiveSessionSegment(segment)
                    self.delegate?.recordingServiceSessionDidUpdate(session)

                    // Post notification for UI update (this is what the SessionRecordingViewModel listens to)
                    NotificationCenter.default.post(
                        name: .sessionTranscriptUpdated,
                        object: nil,
                        userInfo: ["segment": segment, "session": session]
                    )
                }
            } else {
                print("[RecordingService] ⚠️ Whisper transcribeAudioSamples returned nil")
            }

            self.lastWhisperProcessTime = Date()
        }
    }

    /// Force process remaining Whisper buffer (called when stopping)
    func forceProcessWhisperBuffer() {
        guard isUsingWhisper else { return }

        let bufferDuration = whisperBufferDuration
        guard bufferDuration > 0.3 else { return }  // At least 0.3s of audio

        print("[RecordingService] 🎤 Force processing remaining Whisper buffer: \(String(format: "%.1f", bufferDuration))s")

        whisperAudioBufferLock.lock()
        let samples = whisperAudioBuffer
        whisperAudioBuffer.removeAll()
        whisperAudioBufferLock.unlock()

        // Process with forceProcess=true to allow shorter audio
        Task { @MainActor in
            let language = self.storage.settings.language
            if let transcript = await self.whisperService.transcribeAudioSamples(samples, language: language, forceProcess: true) {
                if !self.currentTranscript.isEmpty {
                    self.currentTranscript += " "
                }
                self.currentTranscript += transcript
                print("[RecordingService] 📝 Final Whisper chunk: '\(transcript)'")
            } else {
                print("[RecordingService] ⚠️ Final Whisper chunk returned nil")
            }
        }
    }

    /// Trigger full transcription with large model + diarization at end of session
    /// - Parameters:
    ///   - session: The recording session
    ///   - wavURL: Optional explicit WAV URL (use before compression converts to WebM)
    ///   - completion: Called with updated session when transcription completes
    func triggerFinalWhisperTranscription(for session: RecordingSession, wavURL: URL? = nil, completion: ((RecordingSession) -> Void)? = nil) {
        guard isUsingWhisper else {
            completion?(session)
            return
        }

        print("[RecordingService] 🎯 Triggering final Whisper transcription with large model + diarization")

        Task { @MainActor in
            // Use provided WAV URL or get from session
            let audioURL = wavURL ?? session.primaryAudioFileURL

            guard let audioURL = audioURL else {
                print("[RecordingService] ⚠️ No audio file for final transcription")
                completion?(session)
                return
            }

            print("[RecordingService] 📁 Audio file: \(audioURL.lastPathComponent)")

            // Verify it's a WAV file (not WebM/M4A which AVAudioFile can't read)
            let ext = audioURL.pathExtension.lowercased()
            guard ext == "wav" else {
                print("[RecordingService] ⚠️ Audio file is \(ext), not WAV - skipping final transcription (AVAudioFile only supports WAV)")
                completion?(session)
                return
            }

            // Check if large model is loaded
            let largeModelString = self.storage.settings.whisperModelSize
            let largeModel = WhisperModelSize(rawValue: largeModelString) ?? .largev3Turbo

            if !self.whisperService.isModelLoaded || self.whisperService.currentModelSize != largeModel {
                print("[RecordingService] 📦 Loading large model for final transcription: \(largeModel.displayName)")
                do {
                    try await self.whisperService.loadModel(largeModel)
                } catch {
                    print("[RecordingService] ❌ Failed to load large model: \(error.localizedDescription)")
                    completion?(session)
                    return
                }
            }

            // Check if diarization is enabled
            let enableDiarization = self.storage.settings.enableDiarization
            print("[RecordingService] 👥 Diarization enabled: \(enableDiarization)")

            var updatedSession = session

            do {
                let language = self.storage.settings.language

                if enableDiarization {
                    // Transcribe with diarization
                    let (segments, speakers) = try await self.whisperService.transcribeFileWithDiarization(
                        audioURL: audioURL,
                        language: language
                    ) { progress in
                        print("[RecordingService] 📊 Final transcription progress: \(String(format: "%.0f", progress.progress * 100))%")
                    }

                    // Update session with final transcription
                    updatedSession.transcriptSegments = segments
                    updatedSession.speakers = speakers
                    self.saveSession(updatedSession)

                    print("[RecordingService] ✅ Final transcription complete: \(segments.count) segments, \(speakers.count) speakers")

                    // Post notification
                    NotificationCenter.default.post(
                        name: .sessionTranscriptionCompleted,
                        object: nil,
                        userInfo: ["session": updatedSession]
                    )
                } else {
                    // Transcribe without diarization
                    let (segments, _) = try await self.whisperService.transcribeFile(
                        audioURL: audioURL,
                        language: language
                    )

                    // Update session with final transcription
                    updatedSession.transcriptSegments = segments
                    self.saveSession(updatedSession)

                    print("[RecordingService] ✅ Final transcription complete: \(segments.count) segments")

                    // Post notification
                    NotificationCenter.default.post(
                        name: .sessionTranscriptionCompleted,
                        object: nil,
                        userInfo: ["session": updatedSession]
                    )
                }
            } catch {
                print("[RecordingService] ❌ Final transcription failed: \(error.localizedDescription)")
            }

            completion?(updatedSession)
        }
    }
}

// MARK: - Errors

enum RecordingError: Error, LocalizedError {
    case noApiKey
    case audioCaptureFailed
    case deepgramConnectionFailed

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "Deepgram API key is not configured"
        case .audioCaptureFailed:
            return "Failed to capture audio from microphone"
        case .deepgramConnectionFailed:
            return "Failed to connect to Deepgram service"
        }
    }
}
