import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

/// Protocol for receiving system audio data
protocol SystemAudioCaptureDelegate: AnyObject {
    func systemAudioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer)
    func systemAudioCaptureDidEncounterError(_ error: Error)
}

/// Service for capturing system audio using ScreenCaptureKit (macOS 13+)
/// This allows capturing audio from apps like Teams, Zoom, etc.
@available(macOS 13.0, *)
class SystemAudioCaptureService: NSObject {
    static let shared = SystemAudioCaptureService()

    weak var delegate: SystemAudioCaptureDelegate?

    // MARK: - Properties

    private var stream: SCStream?
    private var streamOutput: SystemAudioStreamOutput?
    private(set) var availableApps: [SCRunningApplication] = []
    private(set) var isCapturing = false

    // Target audio format for Deepgram (16kHz, mono, 16-bit)
    private let targetSampleRate: Double = 16000
    private let targetChannels: AVAudioChannelCount = 1

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Permission Check

    /// Check if screen recording permission is granted
    func hasPermission() async -> Bool {
        do {
            // Attempting to get shareable content will prompt for permission if not granted
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch {
            print("[SystemAudio] Permission check failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Request screen recording permission by triggering the system prompt
    func requestPermission() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            print("[SystemAudio] Permission request failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Available Apps

    /// Get list of running applications that can be captured
    func getAvailableApps() async -> [SCRunningApplication] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            // Filter to apps that likely have audio (exclude system apps)
            let audioApps = content.applications.filter { app in
                let bundleID = app.bundleIdentifier
                // Include common audio/video apps
                let audioAppPatterns = [
                    "com.microsoft.teams",
                    "us.zoom.xos",
                    "com.google.Chrome",
                    "com.apple.Safari",
                    "com.microsoft.Outlook",
                    "com.slack.Slack",
                    "com.spotify.client",
                    "com.apple.Music",
                    "com.apple.FaceTime",
                    "com.discord.Discord",
                    "tv.twitch.studio"
                ]
                // Also include any app with "meet", "call", "video", "audio" in bundle ID
                let hasAudioKeyword = bundleID.lowercased().contains("meet") ||
                bundleID.lowercased().contains("call") ||
                bundleID.lowercased().contains("video") ||
                bundleID.lowercased().contains("audio") ||
                bundleID.lowercased().contains("voice")

                return audioAppPatterns.contains(bundleID) || hasAudioKeyword
            }

            self.availableApps = audioApps
            print("[SystemAudio] Found \(audioApps.count) audio-capable apps")
            return audioApps
        } catch {
            print("[SystemAudio] Failed to get available apps: \(error.localizedDescription)")
            return []
        }
    }

    /// Get all running applications
    func getAllApps() async -> [SCRunningApplication] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            self.availableApps = content.applications
            return content.applications
        } catch {
            print("[SystemAudio] Failed to get all apps: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Capture Control

    /// Start capturing system audio
    /// - Parameter appBundleID: Bundle ID of specific app to capture, or nil for all system audio
    func startCapture(appBundleID: String? = nil) async throws {
        guard !isCapturing else {
            print("[SystemAudio] Already capturing")
            return
        }

        print("[SystemAudio] 🎬 Starting system audio capture...")

        // Check permission first
        let hasPermission = await self.hasPermission()
        if !hasPermission {
            print("[SystemAudio] ❌ Screen Recording permission not granted")
            throw SystemAudioError.noPermission
        }
        print("[SystemAudio] ✅ Screen Recording permission granted")

        // Get shareable content
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            print("[SystemAudio] 📋 Found \(content.displays.count) displays, \(content.applications.count) apps")
        } catch {
            print("[SystemAudio] ❌ Failed to get shareable content: \(error)")
            throw error
        }

        // Find the display (required even for audio-only capture)
        guard let display = content.displays.first else {
            throw SystemAudioError.noDisplayFound
        }

        // Create stream configuration
        let config = SCStreamConfiguration()

        // We only want audio, but ScreenCaptureKit requires a display
        // Set minimal video settings to reduce overhead
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 fps (minimum)
        config.showsCursor = false

        // Enable audio capture - request 16kHz mono directly
        // This avoids complex resampling that can cause audio gaps
        config.capturesAudio = true
        config.sampleRate = 16000  // Request 16kHz for Deepgram compatibility
        config.channelCount = 1    // Mono

        // Exclude our own app from capture to avoid feedback
        let excludedApps = content.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        // Create content filter
        let filter: SCContentFilter
        if let bundleID = appBundleID,
           content.applications.contains(where: { $0.bundleIdentifier == bundleID }) {
            // Capture specific app
            filter = SCContentFilter(desktopIndependentWindow: content.windows.first(where: { $0.owningApplication?.bundleIdentifier == bundleID }) ?? content.windows.first!)
            print("[SystemAudio] Starting capture for app: \(bundleID)")
        } else {
            // Capture all system audio (excluding our app)
            filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
            print("[SystemAudio] Starting capture for all system audio")
        }

        // Create stream
        let stream = SCStream(filter: filter, configuration: config, delegate: self)

        // Create and set output handler
        let output = SystemAudioStreamOutput(delegate: self)
        self.streamOutput = output

        // Add stream output for audio
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        // Start the stream
        try await stream.startCapture()

        self.stream = stream
        self.isCapturing = true

        print("[SystemAudio] Capture started successfully")
    }

    /// Stop capturing system audio
    func stopCapture() {
        guard isCapturing else { return }

        Task {
            do {
                try await stream?.stopCapture()
            } catch {
                print("[SystemAudio] Error stopping capture: \(error.localizedDescription)")
            }

            await MainActor.run {
                self.stream = nil
                self.streamOutput = nil
                self.isCapturing = false
                print("[SystemAudio] Capture stopped")
            }
        }
    }
}

// MARK: - SCStreamDelegate

@available(macOS 13.0, *)
extension SystemAudioCaptureService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[SystemAudio] Stream stopped with error: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isCapturing = false
            self.delegate?.systemAudioCaptureDidEncounterError(error)
        }
    }
}

// MARK: - Stream Output Handler

@available(macOS 13.0, *)
private class SystemAudioStreamOutput: NSObject, SCStreamOutput {
    weak var serviceDelegate: SystemAudioCaptureService?
    private var bufferCount = 0

    // Audio converter for format conversion
    private var audioConverter: AVAudioConverter?
    private let targetFormat: AVAudioFormat

    // Dedicated queue for audio processing (avoid main thread)
    private let audioProcessingQueue = DispatchQueue(label: "com.corius.systemAudioProcessing", qos: .userInteractive)

    // Throttle level notifications to reduce main thread load
    private var lastLevelNotificationTime: CFAbsoluteTime = 0
    private let levelNotificationInterval: CFAbsoluteTime = 0.05 // 50ms = 20 updates/sec

    init(delegate: SystemAudioCaptureService) {
        self.serviceDelegate = delegate
        // Create target format (16kHz, mono, 16-bit PCM, NON-interleaved)
        // Non-interleaved is more compatible with AVAudioPCMBuffer channel data access
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Only process audio samples
        guard type == .audio else { return }

        bufferCount += 1
        if bufferCount % 100 == 0 {
            print("[SystemAudio] Processed \(bufferCount) audio buffers")
        }

        // Check if buffer is valid and has data
        guard CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferGetNumSamples(sampleBuffer) > 0 else {
            if bufferCount < 10 {
                print("[SystemAudio] ⚠️ Invalid or empty buffer #\(bufferCount)")
            }
            return
        }

        // Convert CMSampleBuffer to AVAudioPCMBuffer
        guard let audioBuffer = convertToAudioBuffer(sampleBuffer) else {
            if bufferCount < 10 {
                print("[SystemAudio] ⚠️ Failed to convert buffer #\(bufferCount)")
            }
            return
        }

        if bufferCount < 5 {
            print("[SystemAudio] ✅ Sending buffer #\(bufferCount) to delegate, frames: \(audioBuffer.frameLength)")
        }

        // CRITICAL: Send audio buffer to delegate immediately on audio queue (NOT main thread)
        // This prevents gaps caused by main thread blocking
        self.serviceDelegate?.delegate?.systemAudioCaptureDidReceiveBuffer(audioBuffer)

        // Throttle level notifications to avoid overwhelming main thread
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastLevelNotificationTime >= levelNotificationInterval {
            lastLevelNotificationTime = now
            let systemLevel = calculateRMSLevel(buffer: audioBuffer)

            // Only UI updates go to main thread (throttled)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .audioLevelsUpdated,
                    object: nil,
                    userInfo: ["systemLevel": systemLevel]
                )
            }
        }
    }

    /// Calculate simple RMS level for meter display (supports both Float32 and Int16 formats)
    /// Applies boost to make system audio levels more visible
    private func calculateRMSLevel(buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return 0
        }

        var rms: Float = 0

        // Try Float32 format first
        if let channelData = buffer.floatChannelData?[0] {
            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            rms = sqrt(sum / Float(frameLength))
        }
        // Try Int16 format (common for system audio after conversion)
        else if let int16Data = buffer.int16ChannelData?[0] {
            var sum: Float = 0
            for i in 0..<frameLength {
                let normalized = Float(int16Data[i]) / 32768.0
                sum += normalized * normalized
            }
            rms = sqrt(sum / Float(frameLength))
        }
        else {
            return 0
        }

        // Apply very low noise gate (system audio is often quiet)
        let noiseThreshold: Float = 0.0005
        if rms < noiseThreshold { return 0 }

        // Apply significant boost for display (system audio is typically very quiet)
        // 15x multiplier to make levels visible on meter
        return min(1.0, rms * 15.0)
    }

    private func convertToAudioBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            print("[SystemAudio] ⚠️ No format description")
            return nil
        }

        guard let sourceFormat = AVAudioFormat(streamDescription: streamBasicDescription) else {
            print("[SystemAudio] ⚠️ Failed to create source format")
            return nil
        }

        // Log source format info on first buffer
        if bufferCount == 1 {
            print("[SystemAudio] 📊 Source format: \(sourceFormat.sampleRate)Hz, \(sourceFormat.channelCount) channels, format: \(sourceFormat.commonFormat.rawValue), interleaved: \(sourceFormat.isInterleaved)")
            print("[SystemAudio] 📊 Target format: \(targetFormat.sampleRate)Hz, \(targetFormat.channelCount) channels, format: \(targetFormat.commonFormat.rawValue), interleaved: \(targetFormat.isInterleaved)")
        }

        // Create or update converter if needed
        if audioConverter == nil || audioConverter?.inputFormat != sourceFormat {
            audioConverter = AVAudioConverter(from: sourceFormat, to: targetFormat)
            if audioConverter == nil {
                print("[SystemAudio] ⚠️ Failed to create audio converter")
                return nil
            }
        }

        guard let converter = audioConverter else { return nil }

        // Get audio buffer list
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("[SystemAudio] ⚠️ No data buffer")
            return nil
        }

        var dataLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &dataLength, dataPointerOut: &dataPointer)

        guard status == kCMBlockBufferNoErr, let data = dataPointer, dataLength > 0 else {
            print("[SystemAudio] ⚠️ Failed to get data pointer: status=\(status), length=\(dataLength)")
            return nil
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return nil }

        // More debug info on first buffer
        if bufferCount == 1 {
            print("[SystemAudio] 📊 Data: \(dataLength) bytes, \(frameCount) frames, bytesPerFrame: \(Int(sourceFormat.streamDescription.pointee.mBytesPerFrame))")
        }

        // Create source buffer matching the source format
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            print("[SystemAudio] ⚠️ Failed to create source buffer")
            return nil
        }

        sourceBuffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy data to source buffer based on format
        let bytesPerFrame = Int(sourceFormat.streamDescription.pointee.mBytesPerFrame)
        let bytesToCopy = min(dataLength, frameCount * bytesPerFrame)

        if sourceFormat.commonFormat == .pcmFormatFloat32 {
            if let channelData = sourceBuffer.floatChannelData {
                // For interleaved float data
                if sourceFormat.isInterleaved {
                    memcpy(channelData[0], data, bytesToCopy)
                } else {
                    // Non-interleaved - copy to first channel
                    let bytesPerChannel = bytesToCopy / Int(sourceFormat.channelCount)
                    memcpy(channelData[0], data, bytesPerChannel)
                }
            }
        } else if sourceFormat.commonFormat == .pcmFormatInt16 {
            if let channelData = sourceBuffer.int16ChannelData {
                memcpy(channelData[0], data, bytesToCopy)
            }
        } else if sourceFormat.commonFormat == .pcmFormatInt32 {
            if let channelData = sourceBuffer.int32ChannelData {
                memcpy(channelData[0], data, bytesToCopy)
            }
        } else {
            // Fallback: just copy the raw bytes
            if let channelData = sourceBuffer.floatChannelData {
                memcpy(channelData[0], data, bytesToCopy)
            }
        }

        // Debug: print first few samples of source buffer
        if bufferCount <= 3 {
            if let floatData = sourceBuffer.floatChannelData?[0] {
                let samples = (0..<min(10, Int(sourceBuffer.frameLength))).map { floatData[$0] }
                print("[SystemAudio] 🔍 Source samples (Float32, first 10): \(samples)")
            } else if let int16Data = sourceBuffer.int16ChannelData?[0] {
                let samples = (0..<min(10, Int(sourceBuffer.frameLength))).map { int16Data[$0] }
                print("[SystemAudio] 🔍 Source samples (Int16, first 10): \(samples)")
            } else {
                print("[SystemAudio] ⚠️ Source buffer has no accessible channel data")
            }
        }

        // MANUAL CONVERSION: Float32 to Int16
        // IMPORTANT: Only use manual conversion when sample rates match!
        // If sample rates differ, we MUST use AVAudioConverter for proper resampling
        let sampleRatesMatch = abs(sourceFormat.sampleRate - targetFormat.sampleRate) < 1.0
        let channelCountsMatch = sourceFormat.channelCount == targetFormat.channelCount

        if bufferCount == 1 {
            print("[SystemAudio] 🔧 Sample rate match: \(sampleRatesMatch) (source: \(sourceFormat.sampleRate), target: \(targetFormat.sampleRate))")
            print("[SystemAudio] 🔧 Channel count match: \(channelCountsMatch) (source: \(sourceFormat.channelCount), target: \(targetFormat.channelCount))")
        }

        if sourceFormat.commonFormat == .pcmFormatFloat32 && targetFormat.commonFormat == .pcmFormatInt16 && sampleRatesMatch && channelCountsMatch {
            guard let floatData = sourceBuffer.floatChannelData?[0] else {
                print("[SystemAudio] ⚠️ No float channel data for manual conversion")
                return nil
            }

            let frameLen = Int(sourceBuffer.frameLength)

            // Create output buffer with same frame count (same sample rate)
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(frameLen)
            ) else {
                print("[SystemAudio] ⚠️ Failed to create output buffer")
                return nil
            }

            outputBuffer.frameLength = AVAudioFrameCount(frameLen)

            guard let int16Data = outputBuffer.int16ChannelData?[0] else {
                print("[SystemAudio] ⚠️ No int16 channel data in output buffer")
                return nil
            }

            // Convert Float32 (-1.0 to 1.0) to Int16 (-32768 to 32767)
            for i in 0..<frameLen {
                let floatSample = floatData[i]
                // Clamp to valid range and convert
                let clampedSample = max(-1.0, min(1.0, floatSample))
                int16Data[i] = Int16(clampedSample * 32767.0)
            }

            // Debug: verify conversion quality
            if bufferCount <= 5 || bufferCount % 100 == 0 {
                // Calculate actual stats from converted samples
                var minSample: Int16 = 0
                var maxSample: Int16 = 0
                var sumAbs: Int64 = 0

                for i in 0..<frameLen {
                    let sample = int16Data[i]
                    if sample < minSample { minSample = sample }
                    if sample > maxSample { maxSample = sample }
                    sumAbs += Int64(abs(Int32(sample)))
                }

                let avgAbs = frameLen > 0 ? Float(sumAbs) / Float(frameLen) : 0
                let normalizedAvg = avgAbs / 32768.0

                // Also get source stats
                var srcMin: Float = 0
                var srcMax: Float = 0
                for i in 0..<frameLen {
                    let sample = floatData[i]
                    if sample < srcMin { srcMin = sample }
                    if sample > srcMax { srcMax = sample }
                }

                print("[SystemAudio] 🔍 Buffer #\(bufferCount): src=[\(String(format: "%.4f", srcMin)), \(String(format: "%.4f", srcMax))], out=[\(minSample), \(maxSample)], avgAmp=\(String(format: "%.4f", normalizedAvg))")

                // Check for clipping
                if minSample == -32768 || maxSample == 32767 {
                    print("[SystemAudio] ⚠️ CLIPPING detected - source audio too loud")
                }

                // Check for silence
                if normalizedAvg < 0.001 {
                    print("[SystemAudio] ⚠️ Very low audio level - might be silence")
                }
            }

            return outputBuffer
        }

        // Fallback: use AVAudioConverter for sample rate conversion and/or channel mixing
        if bufferCount == 1 {
            print("[SystemAudio] 🔄 Using AVAudioConverter for resampling/channel conversion")
        }

        let outputFrameCount = AVAudioFrameCount(
            Double(frameCount) * targetFormat.sampleRate / sourceFormat.sampleRate
        )

        guard outputFrameCount > 0 else {
            print("[SystemAudio] ⚠️ Calculated output frame count is 0")
            return nil
        }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount + 100
        ) else {
            print("[SystemAudio] ⚠️ Failed to create output buffer")
            return nil
        }

        var conversionError: NSError?
        let conversionStatus = converter.convert(to: outputBuffer, error: &conversionError) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if let error = conversionError {
            print("[SystemAudio] ⚠️ AVAudioConverter error: \(error.localizedDescription)")
            return nil
        }

        if conversionStatus == .haveData || conversionStatus == .endOfStream {
            // Debug: verify conversion output
            if bufferCount <= 5 || bufferCount % 100 == 0 {
                if let int16Data = outputBuffer.int16ChannelData?[0] {
                    let frameLen = Int(outputBuffer.frameLength)
                    var minSample: Int16 = 0
                    var maxSample: Int16 = 0
                    var sumAbs: Int64 = 0

                    for i in 0..<frameLen {
                        let sample = int16Data[i]
                        if sample < minSample { minSample = sample }
                        if sample > maxSample { maxSample = sample }
                        sumAbs += Int64(abs(Int32(sample)))
                    }

                    let avgAbs = frameLen > 0 ? Float(sumAbs) / Float(frameLen) : 0
                    let normalizedAvg = avgAbs / 32768.0

                    print("[SystemAudio] 🔄 AVAudioConverter output #\(bufferCount): frames=\(outputBuffer.frameLength), range=[\(minSample), \(maxSample)], avgAmp=\(String(format: "%.4f", normalizedAvg))")
                }
            }
            return outputBuffer
        }

        print("[SystemAudio] ⚠️ AVAudioConverter returned unexpected status: \(conversionStatus)")
        return nil
    }
}

// MARK: - Errors

enum SystemAudioError: Error, LocalizedError {
    case noDisplayFound
    case noPermission
    case streamCreationFailed
    case captureNotSupported

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found for audio capture"
        case .noPermission:
            return "Screen recording permission not granted"
        case .streamCreationFailed:
            return "Failed to create audio capture stream"
        case .captureNotSupported:
            return "System audio capture requires macOS 13 or later"
        }
    }
}
