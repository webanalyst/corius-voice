import Foundation
import AVFoundation

#if canImport(FluidAudio)
import FluidAudio
#endif

/// Local wrapper for diarization results (to avoid conflict with FluidAudio's DiarizationResult)
struct LocalDiarizationResult {
    struct Segment {
        let speakerID: String
        let startTime: Double
        let endTime: Double
        let qualityScore: Double
        let embedding: [Float]  // 256-dim speaker embedding for this segment
    }

    /// Speaker profile with embedding
    struct SpeakerProfile {
        let speakerID: String
        let embedding: [Float]  // 256-dim averaged embedding
        var totalDuration: Double
    }

    let segments: [Segment]
    let speakerCount: Int
    let processingTime: TimeInterval
    let speakerProfiles: [String: SpeakerProfile]  // Embeddings per speaker
}

/// Protocol for receiving diarization results
protocol LocalDiarizationDelegate: AnyObject {
    func diarizationDidComplete(_ result: LocalDiarizationResult)
    func diarizationDidFail(_ error: Error)
    func diarizationProgress(_ progress: Float)
}

/// Service for local speaker diarization using FluidAudio
/// Runs entirely on-device using Apple Neural Engine
@available(macOS 14.0, *)
class LocalDiarizationService {
    static let shared = LocalDiarizationService()

    weak var delegate: LocalDiarizationDelegate?

    private(set) var isProcessing = false
    private(set) var isModelLoaded = false

    #if canImport(FluidAudio)
    private var diarizationManager: OfflineDiarizerManager?
    #endif

    private init() {}

    // MARK: - Model Management

    /// Check if FluidAudio is available
    var isAvailable: Bool {
        #if canImport(FluidAudio)
        return true
        #else
        return false
        #endif
    }

    /// Load diarization models (downloads if needed)
    func loadModels() async throws {
        guard !isModelLoaded else {
            print("[LocalDiarization] Models already loaded")
            return
        }

        print("[LocalDiarization] Loading diarization models...")

        #if canImport(FluidAudio)
        let config = OfflineDiarizerConfig()
        diarizationManager = OfflineDiarizerManager(config: config)

        do {
            try await diarizationManager?.prepareModels()
            isModelLoaded = true
            print("[LocalDiarization] Models loaded successfully")
        } catch {
            print("[LocalDiarization] Failed to load models: \(error)")
            throw LocalDiarizationError.modelLoadFailed(error)
        }
        #else
        throw LocalDiarizationError.fluidAudioNotAvailable
        #endif
    }

    /// Unload models to free memory
    func unloadModels() {
        #if canImport(FluidAudio)
        diarizationManager = nil
        #endif
        isModelLoaded = false
        print("[LocalDiarization] Models unloaded")
    }

    // MARK: - Audio Loading

    /// Load audio samples from file, handling compressed formats (M4A, WebM, etc.)
    /// - Parameter fileURL: URL of the audio file
    /// - Returns: Tuple of (samples, sampleRate)
    private func loadAudioSamples(from fileURL: URL) async throws -> (samples: [Float], sampleRate: Double) {
        let ext = fileURL.pathExtension.lowercased()
        print("[LocalDiarization] Loading audio file with extension: .\(ext)")

        // WebM requires special handling via WebKit decoder
        if ext == "webm" {
            print("[LocalDiarization] 🌐 Using WebKit decoder for WebM file")
            return try await WebMDecoder.shared.decode(fileURL)
        }

        // Try AVAudioFile first (works for WAV, AIFF, CAF)
        if ext == "wav" || ext == "aiff" || ext == "caf" {
            return try loadWithAVAudioFile(fileURL)
        }

        // For compressed formats (M4A, MP3, AAC, etc.), use AVAssetReader
        return try await loadWithAVAssetReader(fileURL)
    }

    /// Load audio using AVAudioFile (for uncompressed formats)
    private func loadWithAVAudioFile(_ fileURL: URL) throws -> (samples: [Float], sampleRate: Double) {
        let audioFile = try AVAudioFile(forReading: fileURL)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw LocalDiarizationError.audioLoadFailed
        }

        try audioFile.read(into: buffer)

        guard let floatData = buffer.floatChannelData?[0] else {
            throw LocalDiarizationError.audioConversionFailed
        }

        let samples = Array(UnsafeBufferPointer(start: floatData, count: Int(buffer.frameLength)))
        return (samples, format.sampleRate)
    }

    /// Load audio using AVAssetReader (for compressed formats like M4A, MP3)
    private func loadWithAVAssetReader(_ fileURL: URL) async throws -> (samples: [Float], sampleRate: Double) {
        let asset = AVAsset(url: fileURL)

        // Load the asset's tracks
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else {
            print("[LocalDiarization] ❌ No audio track found in file")
            throw LocalDiarizationError.audioLoadFailed
        }

        // Create asset reader
        let assetReader = try AVAssetReader(asset: asset)

        // Output settings for PCM Float32
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 16000.0,  // FluidAudio expects 16kHz
            AVNumberOfChannelsKey: 1   // Mono
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false

        guard assetReader.canAdd(trackOutput) else {
            print("[LocalDiarization] ❌ Cannot add track output to reader")
            throw LocalDiarizationError.audioLoadFailed
        }
        assetReader.add(trackOutput)

        guard assetReader.startReading() else {
            print("[LocalDiarization] ❌ Failed to start reading: \(assetReader.error?.localizedDescription ?? "unknown")")
            throw LocalDiarizationError.audioLoadFailed
        }

        // Read all samples
        var allSamples: [Float] = []

        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?

            let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            if status == noErr, let data = dataPointer {
                let floatCount = length / MemoryLayout<Float>.size
                let floatPointer = UnsafeRawPointer(data).bindMemory(to: Float.self, capacity: floatCount)
                let buffer = UnsafeBufferPointer(start: floatPointer, count: floatCount)
                allSamples.append(contentsOf: buffer)
            }
        }

        guard assetReader.status == .completed else {
            print("[LocalDiarization] ❌ Asset reader failed: \(assetReader.error?.localizedDescription ?? "unknown")")
            throw LocalDiarizationError.audioConversionFailed
        }

        print("[LocalDiarization] ✅ Loaded \(allSamples.count) samples from compressed audio")
        return (allSamples, 16000.0)
    }

    // MARK: - Diarization

    /// Process audio file for speaker diarization
    /// - Parameter fileURL: URL of the audio file to process
    /// - Returns: LocalDiarizationResult with speaker segments
    func processAudioFile(_ fileURL: URL) async throws -> LocalDiarizationResult {
        if !isModelLoaded {
            try await loadModels()
        }

        guard !isProcessing else {
            throw LocalDiarizationError.alreadyProcessing
        }

        isProcessing = true
        defer { isProcessing = false }

        let startTime = Date()
        print("[LocalDiarization] Processing audio file: \(fileURL.lastPathComponent)")

        #if canImport(FluidAudio)
        guard let manager = diarizationManager else {
            throw LocalDiarizationError.modelNotLoaded
        }

        // Load audio file (handles both uncompressed and compressed formats)
        let (samples, sampleRate) = try await loadAudioSamples(from: fileURL)

        print("[LocalDiarization] Audio loaded: \(samples.count) samples, \(sampleRate)Hz")

        // Process with FluidAudio
        let result = try await manager.process(audio: samples)

        let processingTime = Date().timeIntervalSince(startTime)

        // Convert FluidAudio result to our LocalDiarizationResult
        let diarizationResult = convertToLocalResult(result, processingTime: processingTime)

        print("[LocalDiarization] Processed in \(String(format: "%.2f", processingTime))s")
        print("[LocalDiarization] Found \(diarizationResult.speakerCount) speakers, \(diarizationResult.segments.count) segments")
        print("[LocalDiarization] Speaker profiles: \(diarizationResult.speakerProfiles.keys.joined(separator: ", "))")

        await MainActor.run {
            delegate?.diarizationDidComplete(diarizationResult)
        }

        return diarizationResult
        #else
        throw LocalDiarizationError.fluidAudioNotAvailable
        #endif
    }

    /// Process audio samples directly
    /// - Parameter samples: Float array of audio samples (16kHz mono)
    /// - Returns: LocalDiarizationResult with speaker segments
    func processSamples(_ samples: [Float]) async throws -> LocalDiarizationResult {
        if !isModelLoaded {
            try await loadModels()
        }

        guard !isProcessing else {
            throw LocalDiarizationError.alreadyProcessing
        }

        isProcessing = true
        defer { isProcessing = false }

        let startTime = Date()
        print("[LocalDiarization] Processing \(samples.count) samples")

        #if canImport(FluidAudio)
        guard let manager = diarizationManager else {
            throw LocalDiarizationError.modelNotLoaded
        }

        // Process with FluidAudio
        let result = try await manager.process(audio: samples)

        let processingTime = Date().timeIntervalSince(startTime)

        // Convert FluidAudio result to our LocalDiarizationResult
        let diarizationResult = convertToLocalResult(result, processingTime: processingTime)

        print("[LocalDiarization] Processed in \(String(format: "%.2f", processingTime))s")
        print("[LocalDiarization] Found \(diarizationResult.speakerCount) speakers, \(diarizationResult.segments.count) segments")
        print("[LocalDiarization] Speaker profiles: \(diarizationResult.speakerProfiles.keys.joined(separator: ", "))")

        await MainActor.run {
            delegate?.diarizationDidComplete(diarizationResult)
        }

        return diarizationResult
        #else
        throw LocalDiarizationError.fluidAudioNotAvailable
        #endif
    }

    // MARK: - Helper Methods

    #if canImport(FluidAudio)
    /// Convert FluidAudio DiarizationResult to LocalDiarizationResult
    private func convertToLocalResult(_ result: DiarizationResult, processingTime: TimeInterval) -> LocalDiarizationResult {
        var segments: [LocalDiarizationResult.Segment] = []
        var speakerIDs = Set<String>()
        var speakerProfiles: [String: LocalDiarizationResult.SpeakerProfile] = [:]

        // Accumulators for weighted-average embeddings
        var embeddingSums: [String: [Float]] = [:]
        var embeddingWeights: [String: Float] = [:]

        for segment in result.segments {
            let seg = LocalDiarizationResult.Segment(
                speakerID: segment.speakerId,
                startTime: Double(segment.startTimeSeconds),
                endTime: Double(segment.endTimeSeconds),
                qualityScore: Double(segment.qualityScore),
                embedding: segment.embedding
            )
            segments.append(seg)
            speakerIDs.insert(segment.speakerId)

            let duration = max(0, Double(segment.endTimeSeconds - segment.startTimeSeconds))
            let weight = Float(duration)

            // Accumulate speaker profile duration
            if var profile = speakerProfiles[segment.speakerId] {
                profile.totalDuration += duration
                speakerProfiles[segment.speakerId] = profile
            } else {
                speakerProfiles[segment.speakerId] = LocalDiarizationResult.SpeakerProfile(
                    speakerID: segment.speakerId,
                    embedding: segment.embedding,
                    totalDuration: duration
                )
            }

            // Accumulate weighted embedding for averaging
            if segment.embedding.count == 256, weight > 0 {
                if embeddingSums[segment.speakerId] == nil {
                    embeddingSums[segment.speakerId] = [Float](repeating: 0, count: 256)
                    embeddingWeights[segment.speakerId] = 0
                }
                var sum = embeddingSums[segment.speakerId] ?? [Float](repeating: 0, count: 256)
                for i in 0..<256 {
                    sum[i] += segment.embedding[i] * weight
                }
                embeddingSums[segment.speakerId] = sum
                embeddingWeights[segment.speakerId, default: 0] += weight
            }
        }

        // Use speaker database if available (averaged embeddings from FluidAudio)
        if let database = result.speakerDatabase {
            for (speakerID, embedding) in database {
                if let profile = speakerProfiles[speakerID] {
                    speakerProfiles[speakerID] = LocalDiarizationResult.SpeakerProfile(
                        speakerID: speakerID,
                        embedding: l2Normalize(embedding),
                        totalDuration: profile.totalDuration
                    )
                }
            }
        } else {
            // Otherwise, compute weighted-average embeddings from segments
            for (speakerID, sum) in embeddingSums {
                let weight = embeddingWeights[speakerID] ?? 0
                guard weight > 0 else { continue }
                let avg = sum.map { $0 / weight }
                if let profile = speakerProfiles[speakerID] {
                    speakerProfiles[speakerID] = LocalDiarizationResult.SpeakerProfile(
                        speakerID: speakerID,
                        embedding: l2Normalize(avg),
                        totalDuration: profile.totalDuration
                    )
                }
            }
        }

        return LocalDiarizationResult(
            segments: segments,
            speakerCount: speakerIDs.count,
            processingTime: processingTime,
            speakerProfiles: speakerProfiles
        )
    }

    private func l2Normalize(_ embedding: [Float]) -> [Float] {
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return embedding }
        return embedding.map { $0 / norm }
    }
    #endif

    /// Get speaker ID for a specific timestamp with tolerance for gaps
    /// - Parameters:
    ///   - result: Diarization result containing segments
    ///   - time: Timestamp to look up
    ///   - tolerance: Maximum gap (in seconds) to bridge when no exact match (default 1.0s)
    /// - Returns: Speaker ID if found, nil otherwise
    func getSpeakerAtTime(_ result: LocalDiarizationResult, time: Double, tolerance: Double = 1.0) -> String? {
        // First, try exact match
        for segment in result.segments {
            if time >= segment.startTime && time <= segment.endTime {
                return segment.speakerID
            }
        }

        // If no exact match, find the nearest segment within tolerance
        var nearestSegment: LocalDiarizationResult.Segment?
        var nearestDistance = Double.infinity

        for segment in result.segments {
            // Check distance to segment start
            let distanceToStart = abs(time - segment.startTime)
            // Check distance to segment end
            let distanceToEnd = abs(time - segment.endTime)
            // Use the smaller distance
            let minDistance = min(distanceToStart, distanceToEnd)

            if minDistance < nearestDistance && minDistance <= tolerance {
                nearestDistance = minDistance
                nearestSegment = segment
            }
        }

        if let segment = nearestSegment {
            return segment.speakerID
        }

        return nil
    }

    /// Get speaker ID with carry-forward for continuous speech
    /// If timestamp falls in a gap, uses the speaker from the most recent segment before it
    func getSpeakerAtTimeWithCarryForward(_ result: LocalDiarizationResult, time: Double) -> String? {
        // First try with tolerance
        if let speaker = getSpeakerAtTime(result, time: time, tolerance: 0.5) {
            return speaker
        }

        // If still no match, find the most recent segment that ended before this time
        let sortedSegments = result.segments.sorted { $0.endTime < $1.endTime }
        for segment in sortedSegments.reversed() {
            if segment.endTime <= time {
                return segment.speakerID
            }
        }

        // Last resort: return the first speaker if time is before all segments
        return result.segments.first?.speakerID
    }

    /// Get speaker assignments for transcript segments based on timestamps
    /// Returns a dictionary mapping segment ID to speaker ID
    func getSpeakerAssignments(
        diarization: LocalDiarizationResult,
        segmentTimestamps: [(id: UUID, timestamp: Double)]
    ) -> [UUID: String] {
        var assignments: [UUID: String] = [:]

        for (id, timestamp) in segmentTimestamps {
            // Use carry-forward logic for better coverage
            if let speakerID = getSpeakerAtTimeWithCarryForward(diarization, time: timestamp) {
                assignments[id] = speakerID
            }
        }

        return assignments
    }

    // MARK: - Speaker Embedding Comparison

    /// Compute cosine similarity between two embeddings (0 = identical, 2 = opposite)
    func cosineDistance(_ embedding1: [Float], _ embedding2: [Float]) -> Float {
        guard embedding1.count == embedding2.count, embedding1.count == 256 else {
            return Float.infinity
        }

        // L2 normalize both embeddings first
        let norm1 = sqrt(embedding1.reduce(0) { $0 + $1 * $1 })
        let norm2 = sqrt(embedding2.reduce(0) { $0 + $1 * $1 })

        guard norm1 > 0, norm2 > 0 else {
            return Float.infinity
        }

        // Compute dot product of normalized vectors
        var dotProduct: Float = 0
        for i in 0..<256 {
            dotProduct += (embedding1[i] / norm1) * (embedding2[i] / norm2)
        }

        // Cosine distance = 1 - cosine similarity
        return 1.0 - dotProduct
    }

    /// Find the best matching known speaker for an embedding
    /// Returns (speakerID, distance) or nil if no match within threshold
    func findMatchingSpeaker(
        embedding: [Float],
        knownProfiles: [String: [Float]],
        threshold: Float = 0.4  // Lower = stricter matching
    ) -> (speakerID: String, distance: Float)? {
        var bestMatch: (String, Float)?

        for (speakerID, knownEmbedding) in knownProfiles {
            let distance = cosineDistance(embedding, knownEmbedding)

            if distance < threshold {
                if bestMatch == nil || distance < bestMatch!.1 {
                    bestMatch = (speakerID, distance)
                }
            }
        }

        return bestMatch
    }

    /// Match diarization speakers to known speaker profiles
    /// Returns a mapping from diarization speaker ID to known speaker ID
    func matchSpeakersToKnown(
        diarization: LocalDiarizationResult,
        knownProfiles: [String: [Float]],
        threshold: Float = 0.4
    ) -> [String: String] {
        var mapping: [String: String] = [:]

        for (diarizationSpeakerID, profile) in diarization.speakerProfiles {
            if let match = findMatchingSpeaker(
                embedding: profile.embedding,
                knownProfiles: knownProfiles,
                threshold: threshold
            ) {
                mapping[diarizationSpeakerID] = match.speakerID
                print("[LocalDiarization] Matched \(diarizationSpeakerID) → \(match.speakerID) (distance: \(String(format: "%.3f", match.distance)))")
            }
        }

        return mapping
    }
}

// MARK: - Errors

enum LocalDiarizationError: Error, LocalizedError {
    case fluidAudioNotAvailable
    case modelLoadFailed(Error)
    case modelNotLoaded
    case alreadyProcessing
    case audioLoadFailed
    case audioConversionFailed
    case processingFailed(Error)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .fluidAudioNotAvailable:
            return "FluidAudio is not available. Please add the FluidAudio package dependency."
        case .modelLoadFailed(let error):
            return "Failed to load diarization models: \(error.localizedDescription)"
        case .modelNotLoaded:
            return "Diarization models not loaded"
        case .alreadyProcessing:
            return "Already processing audio"
        case .audioLoadFailed:
            return "Failed to load audio file"
        case .audioConversionFailed:
            return "Failed to convert audio format"
        case .processingFailed(let error):
            return "Diarization failed: \(error.localizedDescription)"
        case .unsupportedFormat(let format):
            return "Unsupported audio format: \(format). Please use WAV or M4A format."
        }
    }
}

// MARK: - Fallback for older macOS versions

class LocalDiarizationServiceLegacy {
    static let shared = LocalDiarizationServiceLegacy()

    var isAvailable: Bool { false }

    func loadModels() async throws {
        throw LocalDiarizationError.fluidAudioNotAvailable
    }

    func processAudioFile(_ fileURL: URL) async throws -> LocalDiarizationResult {
        throw LocalDiarizationError.fluidAudioNotAvailable
    }
}
