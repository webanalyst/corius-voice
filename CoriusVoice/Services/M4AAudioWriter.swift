import Foundation
import AVFoundation
import CoreMedia

/// Writes audio directly to M4A (AAC) format using AVAssetWriter
/// This provides compression during recording, reducing disk usage compared to WAV
class M4AAudioWriter {
    private var assetWriter: AVAssetWriter?
    private var audioInput: AVAssetWriterInput?
    private var isWriting = false
    private var startTime: CMTime?

    private let outputURL: URL
    private let sampleRate: Double
    private let channels: Int
    private let bitRate: Int

    /// Initialize the M4A writer
    /// - Parameters:
    ///   - url: Output file URL (should have .m4a extension)
    ///   - sampleRate: Audio sample rate (default 16000 for speech)
    ///   - channels: Number of channels (default 1 for mono)
    ///   - bitRate: AAC bit rate in bps (default 64000 for speech quality)
    init(url: URL, sampleRate: Double = 16000, channels: Int = 1, bitRate: Int = 64000) {
        self.outputURL = url
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitRate = bitRate
    }

    /// Start writing to the M4A file
    func startWriting() throws {
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)

        // Create asset writer
        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)

        // Configure audio output settings for AAC
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true

        guard let assetWriter = assetWriter, let audioInput = audioInput else {
            throw M4AWriterError.setupFailed
        }

        if assetWriter.canAdd(audioInput) {
            assetWriter.add(audioInput)
        } else {
            throw M4AWriterError.cannotAddInput
        }

        assetWriter.startWriting()
        isWriting = true
        startTime = nil

        print("[M4AAudioWriter] Started writing to: \(outputURL.lastPathComponent)")
    }

    /// Write an audio buffer to the M4A file
    func writeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isWriting, let audioInput = audioInput, audioInput.isReadyForMoreMediaData else {
            return
        }

        // Convert AVAudioPCMBuffer to CMSampleBuffer
        guard let sampleBuffer = createSampleBuffer(from: buffer) else {
            print("[M4AAudioWriter] Failed to create sample buffer")
            return
        }

        // Start session on first buffer
        if startTime == nil {
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter?.startSession(atSourceTime: time)
            startTime = time
        }

        audioInput.append(sampleBuffer)
    }

    /// Finish writing and close the file
    func finishWriting(completion: @escaping (Bool) -> Void) {
        guard isWriting, let assetWriter = assetWriter else {
            completion(false)
            return
        }

        isWriting = false
        audioInput?.markAsFinished()

        assetWriter.finishWriting {
            let success = assetWriter.status == .completed
            if success {
                print("[M4AAudioWriter] Finished writing successfully")
            } else if let error = assetWriter.error {
                print("[M4AAudioWriter] Finish writing error: \(error)")
            }
            completion(success)
        }
    }

    /// Synchronously finish writing
    func finishWritingSync() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        finishWriting { result in
            success = result
            semaphore.signal()
        }

        semaphore.wait()
        return success
    }

    /// Cancel writing and delete partial file
    func cancelWriting() {
        isWriting = false
        assetWriter?.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
        print("[M4AAudioWriter] Writing cancelled")
    }

    // MARK: - Private Methods

    /// Convert AVAudioPCMBuffer to CMSampleBuffer
    private func createSampleBuffer(from buffer: AVAudioPCMBuffer) -> CMSampleBuffer? {
        let format = buffer.format
        let frameCount = buffer.frameLength

        // Create format description
        var formatDescription: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: format.streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        guard status == noErr, let formatDesc = formatDescription else {
            print("[M4AAudioWriter] Failed to create format description: \(status)")
            return nil
        }

        // Calculate timing
        let frameDuration = CMTimeMake(value: 1, timescale: Int32(format.sampleRate))
        var timing = CMSampleTimingInfo(
            duration: frameDuration,
            presentationTimeStamp: startTime ?? CMTime.zero,
            decodeTimeStamp: CMTime.invalid
        )

        // Update start time for next buffer
        if let currentStart = startTime {
            let bufferDuration = CMTimeMake(value: Int64(frameCount), timescale: Int32(format.sampleRate))
            startTime = CMTimeAdd(currentStart, bufferDuration)
        }

        // Create sample buffer
        var sampleBuffer: CMSampleBuffer?

        guard let channelData = buffer.floatChannelData else {
            return nil
        }

        // Convert Float32 to Int16 for better compatibility
        let int16Data = UnsafeMutablePointer<Int16>.allocate(capacity: Int(frameCount))
        defer { int16Data.deallocate() }

        for i in 0..<Int(frameCount) {
            let sample = max(-1.0, min(1.0, channelData[0][i]))
            int16Data[i] = Int16(sample * Float(Int16.max))
        }

        let dataSize = Int(frameCount) * MemoryLayout<Int16>.size

        // Create block buffer
        var blockBuffer: CMBlockBuffer?
        var blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard blockStatus == noErr, let block = blockBuffer else {
            print("[M4AAudioWriter] Failed to create block buffer: \(blockStatus)")
            return nil
        }

        blockStatus = CMBlockBufferReplaceDataBytes(
            with: int16Data,
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )

        guard blockStatus == noErr else {
            print("[M4AAudioWriter] Failed to copy data to block buffer: \(blockStatus)")
            return nil
        }

        // Create audio sample buffer for PCM Int16
        var pcmFormatDesc: CMAudioFormatDescription?
        var asbd = AudioStreamBasicDescription(
            mSampleRate: format.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &pcmFormatDesc
        )

        guard let pcmFormat = pcmFormatDesc else {
            return nil
        }

        let createStatus = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: pcmFormat,
            sampleCount: CMItemCount(frameCount),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard createStatus == noErr else {
            print("[M4AAudioWriter] Failed to create sample buffer: \(createStatus)")
            return nil
        }

        return sampleBuffer
    }
}

// MARK: - Errors

enum M4AWriterError: LocalizedError {
    case setupFailed
    case cannotAddInput
    case writingFailed

    var errorDescription: String? {
        switch self {
        case .setupFailed:
            return "Failed to set up M4A writer"
        case .cannotAddInput:
            return "Cannot add audio input to asset writer"
        case .writingFailed:
            return "Failed to write audio data"
        }
    }
}
