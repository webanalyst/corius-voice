import Foundation
import Accelerate
import AVFoundation

// MARK: - Voice Features

/// Audio features extracted for speaker identification
struct VoiceFeatures: Codable {
    let mfccs: [Float]           // Mean MFCCs (13 coefficients)
    let mfccVariance: [Float]    // Variance of MFCCs
    let pitchMean: Float         // Average pitch (F0)
    let pitchVariance: Float     // Pitch variation
    let energyMean: Float        // Average energy/loudness
    let energyVariance: Float    // Energy variation
    let spectralCentroid: Float  // Brightness of voice
    let zeroCrossingRate: Float  // Voice texture

    /// Compare similarity with another voice profile (0-1, higher = more similar)
    func similarity(to other: VoiceFeatures) -> Float {
        // Cosine similarity for MFCCs (most important)
        let mfccSim = cosineSimilarity(mfccs, other.mfccs)

        // Euclidean distance for other features, normalized
        let pitchDiff = abs(pitchMean - other.pitchMean) / max(pitchMean, other.pitchMean, 1)
        let energyDiff = abs(energyMean - other.energyMean) / max(energyMean, other.energyMean, 1)
        let spectralDiff = abs(spectralCentroid - other.spectralCentroid) / max(spectralCentroid, other.spectralCentroid, 1)

        // Weighted combination (MFCCs are most important for speaker ID)
        let otherSim = 1.0 - (pitchDiff * 0.3 + energyDiff * 0.2 + spectralDiff * 0.2) / 0.7

        let finalSim = mfccSim * 0.7 + Float(otherSim) * 0.3

        // Debug logging
        print("[Similarity] MFCC cosine: \(String(format: "%.3f", mfccSim))")
        print("[Similarity] Pitch diff: \(String(format: "%.3f", pitchDiff)) (\(String(format: "%.1f", pitchMean))Hz vs \(String(format: "%.1f", other.pitchMean))Hz)")
        print("[Similarity] Energy diff: \(String(format: "%.3f", energyDiff))")
        print("[Similarity] Spectral diff: \(String(format: "%.3f", spectralDiff))")
        print("[Similarity] Other sim: \(String(format: "%.3f", otherSim)), Final: \(String(format: "%.3f", finalSim))")

        return finalSim
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }

    /// Empty features placeholder (used when embedding is the primary identification method)
    static var empty: VoiceFeatures {
        VoiceFeatures(
            mfccs: [Float](repeating: 0, count: 13),
            mfccVariance: [Float](repeating: 0, count: 13),
            pitchMean: 0,
            pitchVariance: 0,
            energyMean: 0,
            energyVariance: 0,
            spectralCentroid: 0,
            zeroCrossingRate: 0
        )
    }

    /// Combine multiple feature sets (for building a profile from multiple samples)
    static func average(_ features: [VoiceFeatures]) -> VoiceFeatures? {
        guard !features.isEmpty else { return nil }

        let count = Float(features.count)

        // Average MFCCs
        var avgMfccs = [Float](repeating: 0, count: 13)
        var avgMfccVar = [Float](repeating: 0, count: 13)
        for f in features {
            for i in 0..<min(13, f.mfccs.count) {
                avgMfccs[i] += f.mfccs[i] / count
                avgMfccVar[i] += f.mfccVariance[i] / count
            }
        }

        return VoiceFeatures(
            mfccs: avgMfccs,
            mfccVariance: avgMfccVar,
            pitchMean: features.map(\.pitchMean).reduce(0, +) / count,
            pitchVariance: features.map(\.pitchVariance).reduce(0, +) / count,
            energyMean: features.map(\.energyMean).reduce(0, +) / count,
            energyVariance: features.map(\.energyVariance).reduce(0, +) / count,
            spectralCentroid: features.map(\.spectralCentroid).reduce(0, +) / count,
            zeroCrossingRate: features.map(\.zeroCrossingRate).reduce(0, +) / count
        )
    }
}

// MARK: - Audio Feature Extractor

/// Extracts voice features from audio for speaker identification
class AudioFeatureExtractor {
    static let shared = AudioFeatureExtractor()

    private let sampleRate: Float = 16000  // Standard for speech
    private let frameSize: Int = 512       // ~32ms at 16kHz
    private let hopSize: Int = 256         // 50% overlap
    private let numMFCCs: Int = 13         // Standard for speaker ID
    private let numMelBands: Int = 26      // Mel filter banks

    private var melFilterBank: [Float] = []
    private var dctMatrix: [Float] = []

    private init() {
        setupMelFilterBank()
        setupDCTMatrix()
    }

    // MARK: - Public Methods

    /// Extract voice features from an audio file
    func extractFeatures(from url: URL) async throws -> VoiceFeatures {
        let audioData = try await loadAudio(from: url)
        return extractFeatures(from: audioData)
    }

    /// Extract voice features from raw audio samples (16kHz mono Float32)
    func extractFeatures(from samples: [Float]) -> VoiceFeatures {
        guard samples.count >= frameSize else {
            print("[AudioFeature] ⚠️ Not enough samples: \(samples.count) < \(frameSize)")
            return emptyFeatures()
        }

        // Check if audio has actual content (not silence)
        let maxSample = samples.map { abs($0) }.max() ?? 0
        print("[AudioFeature] 🔊 Sample count: \(samples.count), max amplitude: \(String(format: "%.4f", maxSample))")

        if maxSample < 0.001 {
            print("[AudioFeature] ⚠️ Audio appears to be silence (max amplitude < 0.001)")
        }

        // Extract frame-level features
        var allMfccs: [[Float]] = []
        var allEnergies: [Float] = []
        var allPitches: [Float] = []
        var allSpectralCentroids: [Float] = []
        var allZCRs: [Float] = []

        var offset = 0
        while offset + frameSize <= samples.count {
            let frame = Array(samples[offset..<(offset + frameSize)])

            // Apply Hamming window
            let windowedFrame = applyHammingWindow(frame)

            // Extract MFCCs
            let mfccs = extractMFCCs(from: windowedFrame)
            allMfccs.append(mfccs)

            // Extract energy
            let energy = calculateEnergy(windowedFrame)
            allEnergies.append(energy)

            // Extract pitch (simple autocorrelation method)
            let pitch = estimatePitch(windowedFrame)
            if pitch > 50 && pitch < 500 {  // Valid speech range
                allPitches.append(pitch)
            }

            // Spectral centroid
            let centroid = calculateSpectralCentroid(windowedFrame)
            allSpectralCentroids.append(centroid)

            // Zero crossing rate
            let zcr = calculateZeroCrossingRate(windowedFrame)
            allZCRs.append(zcr)

            offset += hopSize
        }

        // Aggregate features
        let meanMfccs = averageColumns(allMfccs)
        let varMfccs = varianceColumns(allMfccs)

        return VoiceFeatures(
            mfccs: meanMfccs,
            mfccVariance: varMfccs,
            pitchMean: mean(allPitches),
            pitchVariance: variance(allPitches),
            energyMean: mean(allEnergies),
            energyVariance: variance(allEnergies),
            spectralCentroid: mean(allSpectralCentroids),
            zeroCrossingRate: mean(allZCRs)
        )
    }

    /// Extract features from a specific time range in an audio file
    func extractFeatures(from url: URL, startTime: TimeInterval, duration: TimeInterval) async throws -> VoiceFeatures {
        print("[AudioFeature] 🎯 Extracting features from file segment: start=\(String(format: "%.2f", startTime))s, duration=\(String(format: "%.2f", duration))s")
        let audioData = try await loadAudio(from: url, startTime: startTime, duration: duration)
        print("[AudioFeature] 📊 Loaded \(audioData.count) samples from file")
        let features = extractFeatures(from: audioData)
        print("[AudioFeature] 📈 Extracted features: pitch=\(String(format: "%.1f", features.pitchMean))Hz, energy=\(String(format: "%.4f", features.energyMean))")
        return features
    }

    // MARK: - Audio Loading

    /// Cache of converted WebM files to avoid repeated conversions
    private static var convertedFileCache: [URL: URL] = [:]

    private func loadAudio(from url: URL, startTime: TimeInterval = 0, duration: TimeInterval? = nil) async throws -> [Float] {
        print("[AudioFeature] 📂 Loading audio from: \(url.lastPathComponent)")
        print("[AudioFeature] ⏱️ Start time: \(String(format: "%.2f", startTime))s, duration: \(duration.map { String(format: "%.2f", $0) } ?? "all")s")

        // Handle WebM/OGG files by converting to WAV first
        let ext = url.pathExtension.lowercased()
        let processURL: URL
        if ext == "webm" || ext == "ogg" {
            processURL = try await ensureWAVFormat(url)
        } else {
            processURL = url
        }

        let file = try AVAudioFile(forReading: processURL)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!

        let sourceFormat = file.processingFormat
        let sourceSampleRate = sourceFormat.sampleRate
        let fileDuration = Double(file.length) / sourceSampleRate

        print("[AudioFeature] 📊 File: \(sourceSampleRate)Hz, \(file.length) frames, duration: \(String(format: "%.2f", fileDuration))s")

        // Calculate frame positions
        var startFrame = AVAudioFramePosition(startTime * sourceSampleRate)

        // Clamp to valid range
        if startFrame < 0 {
            print("[AudioFeature] ⚠️ Start frame negative, clamping to 0")
            startFrame = 0
        }
        if startFrame >= file.length {
            print("[AudioFeature] ⚠️ Start frame past end of file (\(startFrame) >= \(file.length)), clamping")
            startFrame = max(0, file.length - AVAudioFramePosition(sourceSampleRate)) // Last 1 second
        }

        var totalFrames: AVAudioFrameCount
        if let dur = duration {
            totalFrames = AVAudioFrameCount(dur * sourceSampleRate)
        } else {
            totalFrames = AVAudioFrameCount(file.length - startFrame)
        }

        // Make sure we don't read past the end
        let availableFrames = AVAudioFrameCount(file.length - startFrame)
        if totalFrames > availableFrames {
            print("[AudioFeature] ⚠️ Requested \(totalFrames) frames but only \(availableFrames) available")
            totalFrames = availableFrames
        }

        if totalFrames < 100 {
            print("[AudioFeature] ❌ Not enough frames to extract features: \(totalFrames)")
            throw AudioFeatureError.bufferCreationFailed
        }

        file.framePosition = startFrame
        print("[AudioFeature] 📍 Reading \(totalFrames) frames from position \(startFrame)")

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: totalFrames) else {
            throw AudioFeatureError.bufferCreationFailed
        }

        try file.read(into: sourceBuffer, frameCount: totalFrames)
        print("[AudioFeature] ✅ Read \(sourceBuffer.frameLength) frames")

        // Convert to mono 16kHz if needed
        if sourceFormat.sampleRate != Double(sampleRate) || sourceFormat.channelCount != 1 {
            guard let converter = AVAudioConverter(from: sourceFormat, to: format) else {
                throw AudioFeatureError.converterCreationFailed
            }

            let ratio = sampleRate / Float(sourceSampleRate)
            let outputFrameCount = AVAudioFrameCount(Float(sourceBuffer.frameLength) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputFrameCount) else {
                throw AudioFeatureError.bufferCreationFailed
            }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return sourceBuffer
            }

            if let error = error {
                throw error
            }

            return Array(UnsafeBufferPointer(start: outputBuffer.floatChannelData?[0], count: Int(outputBuffer.frameLength)))
        }

        return Array(UnsafeBufferPointer(start: sourceBuffer.floatChannelData?[0], count: Int(sourceBuffer.frameLength)))
    }

    // MARK: - WebM Conversion

    /// Convert WebM/OGG to WAV format for AVAudioFile compatibility
    /// Uses caching to avoid repeated conversions of the same file
    private func ensureWAVFormat(_ url: URL) async throws -> URL {
        // Check cache first
        if let cachedURL = Self.convertedFileCache[url],
           FileManager.default.fileExists(atPath: cachedURL.path) {
            print("[AudioFeature] 📦 Using cached WAV: \(cachedURL.lastPathComponent)")
            return cachedURL
        }

        print("[AudioFeature] 🔄 Converting WebM to WAV...")

        guard let ffmpegPath = findFFmpegPath() else {
            throw AudioFeatureError.ffmpegNotFound
        }

        // Create temp file with unique name based on source file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("audiofeature_\(url.deletingPathExtension().lastPathComponent)_\(UUID().uuidString.prefix(8)).wav")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-i", url.path,
            "-acodec", "pcm_f32le",  // Float32 PCM
            "-ar", "16000",           // 16kHz
            "-ac", "1",               // Mono
            "-y",                     // Overwrite
            tempFile.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()

                DispatchQueue.global(qos: .userInitiated).async {
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        // Verify the file was created
                        if FileManager.default.fileExists(atPath: tempFile.path) {
                            print("[AudioFeature] ✅ Converted to WAV: \(tempFile.lastPathComponent)")
                            // Cache for future use
                            Self.convertedFileCache[url] = tempFile
                            continuation.resume(returning: tempFile)
                        } else {
                            continuation.resume(throwing: AudioFeatureError.conversionFailed)
                        }
                    } else {
                        continuation.resume(throwing: AudioFeatureError.conversionFailed)
                    }
                }
            } catch {
                continuation.resume(throwing: AudioFeatureError.conversionFailed)
            }
        }
    }

    /// Find ffmpeg binary
    private func findFFmpegPath() -> String? {
        let fm = FileManager.default

        // Check for bundled ffmpeg
        if let bundledPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil),
           fm.fileExists(atPath: bundledPath) {
            return bundledPath
        }

        // Check system paths
        let systemPaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for path in systemPaths {
            if fm.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    // MARK: - Feature Extraction

    private func extractMFCCs(from frame: [Float]) -> [Float] {
        // Compute FFT
        let fftMagnitudes = computeFFTMagnitudes(frame)

        // Apply mel filter bank
        let melEnergies = applyMelFilterBank(fftMagnitudes)

        // Log compression
        var logMelEnergies = melEnergies.map { max(log($0 + 1e-10), -10) }

        // DCT to get MFCCs
        var mfccs = [Float](repeating: 0, count: numMFCCs)
        vDSP_mmul(dctMatrix, 1, &logMelEnergies, 1, &mfccs, 1, vDSP_Length(numMFCCs), 1, vDSP_Length(numMelBands))

        return mfccs
    }

    private func computeFFTMagnitudes(_ frame: [Float]) -> [Float] {
        let log2n = vDSP_Length(log2(Float(frameSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return [Float](repeating: 0, count: frameSize / 2)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var realPart = frame
        var imagPart = [Float](repeating: 0, count: frameSize)

        var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)

        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }

        // Compute magnitudes
        var magnitudes = [Float](repeating: 0, count: frameSize / 2)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(frameSize / 2))

        // Square root to get actual magnitudes
        var sqrtMagnitudes = magnitudes
        vvsqrtf(&sqrtMagnitudes, &magnitudes, [Int32(magnitudes.count)])

        return sqrtMagnitudes
    }

    private func applyMelFilterBank(_ fftMagnitudes: [Float]) -> [Float] {
        var melEnergies = [Float](repeating: 0, count: numMelBands)
        let fftSize = fftMagnitudes.count

        for i in 0..<numMelBands {
            var sum: Float = 0
            for j in 0..<fftSize {
                sum += melFilterBank[i * fftSize + j] * fftMagnitudes[j]
            }
            melEnergies[i] = sum
        }

        return melEnergies
    }

    private func estimatePitch(_ frame: [Float]) -> Float {
        // Simple autocorrelation-based pitch estimation
        let minLag = Int(sampleRate / 500)  // 500 Hz max
        let maxLag = Int(sampleRate / 50)   // 50 Hz min

        guard maxLag < frame.count else { return 0 }

        var maxCorr: Float = 0
        var bestLag = 0

        for lag in minLag..<min(maxLag, frame.count - 1) {
            var corr: Float = 0
            vDSP_dotpr(frame, 1, Array(frame[lag...]), 1, &corr, vDSP_Length(frame.count - lag))

            if corr > maxCorr {
                maxCorr = corr
                bestLag = lag
            }
        }

        return bestLag > 0 ? sampleRate / Float(bestLag) : 0
    }

    private func calculateEnergy(_ frame: [Float]) -> Float {
        var energy: Float = 0
        vDSP_dotpr(frame, 1, frame, 1, &energy, vDSP_Length(frame.count))
        return sqrt(energy / Float(frame.count))
    }

    private func calculateSpectralCentroid(_ frame: [Float]) -> Float {
        let magnitudes = computeFFTMagnitudes(frame)

        var weightedSum: Float = 0
        var sum: Float = 0

        for (i, mag) in magnitudes.enumerated() {
            let frequency = Float(i) * sampleRate / Float(frameSize)
            weightedSum += frequency * mag
            sum += mag
        }

        return sum > 0 ? weightedSum / sum : 0
    }

    private func calculateZeroCrossingRate(_ frame: [Float]) -> Float {
        var crossings = 0
        for i in 1..<frame.count {
            if (frame[i] >= 0) != (frame[i-1] >= 0) {
                crossings += 1
            }
        }
        return Float(crossings) / Float(frame.count - 1)
    }

    // MARK: - Setup

    private func setupMelFilterBank() {
        let fftSize = frameSize / 2
        melFilterBank = [Float](repeating: 0, count: numMelBands * fftSize)

        // Mel scale conversion
        func hzToMel(_ hz: Float) -> Float {
            return 2595 * log10(1 + hz / 700)
        }

        func melToHz(_ mel: Float) -> Float {
            return 700 * (pow(10, mel / 2595) - 1)
        }

        let lowMel = hzToMel(0)
        let highMel = hzToMel(sampleRate / 2)

        // Create mel points
        var melPoints = [Float]()
        for i in 0...(numMelBands + 1) {
            let mel = lowMel + Float(i) * (highMel - lowMel) / Float(numMelBands + 1)
            melPoints.append(melToHz(mel))
        }

        // Convert to FFT bins
        let binPoints = melPoints.map { Int($0 * Float(frameSize) / sampleRate) }

        // Create triangular filters
        for i in 0..<numMelBands {
            for j in binPoints[i]..<binPoints[i + 1] {
                if j < fftSize {
                    melFilterBank[i * fftSize + j] = Float(j - binPoints[i]) / Float(binPoints[i + 1] - binPoints[i])
                }
            }
            for j in binPoints[i + 1]..<binPoints[i + 2] {
                if j < fftSize {
                    melFilterBank[i * fftSize + j] = Float(binPoints[i + 2] - j) / Float(binPoints[i + 2] - binPoints[i + 1])
                }
            }
        }
    }

    private func setupDCTMatrix() {
        dctMatrix = [Float](repeating: 0, count: numMFCCs * numMelBands)

        for i in 0..<numMFCCs {
            for j in 0..<numMelBands {
                dctMatrix[i * numMelBands + j] = cos(Float.pi * Float(i) * (Float(j) + 0.5) / Float(numMelBands))
            }
        }
    }

    private func applyHammingWindow(_ frame: [Float]) -> [Float] {
        var windowed = frame
        var window = [Float](repeating: 0, count: frame.count)
        vDSP_hamm_window(&window, vDSP_Length(frame.count), 0)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(frame.count))
        return windowed
    }

    // MARK: - Utilities

    private func mean(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_meanv(values, 1, &result, vDSP_Length(values.count))
        return result
    }

    private func variance(_ values: [Float]) -> Float {
        guard values.count > 1 else { return 0 }
        let m = mean(values)
        var sum: Float = 0
        for v in values {
            sum += (v - m) * (v - m)
        }
        return sum / Float(values.count - 1)
    }

    private func averageColumns(_ matrix: [[Float]]) -> [Float] {
        guard let first = matrix.first else { return [] }
        var result = [Float](repeating: 0, count: first.count)

        for row in matrix {
            for (i, val) in row.enumerated() where i < result.count {
                result[i] += val
            }
        }

        let count = Float(matrix.count)
        return result.map { $0 / count }
    }

    private func varianceColumns(_ matrix: [[Float]]) -> [Float] {
        let means = averageColumns(matrix)
        guard let first = matrix.first else { return [] }
        var result = [Float](repeating: 0, count: first.count)

        for row in matrix {
            for (i, val) in row.enumerated() where i < result.count {
                result[i] += (val - means[i]) * (val - means[i])
            }
        }

        let count = Float(matrix.count - 1)
        return count > 0 ? result.map { $0 / count } : result
    }

    private func emptyFeatures() -> VoiceFeatures {
        VoiceFeatures(
            mfccs: [Float](repeating: 0, count: numMFCCs),
            mfccVariance: [Float](repeating: 0, count: numMFCCs),
            pitchMean: 0,
            pitchVariance: 0,
            energyMean: 0,
            energyVariance: 0,
            spectralCentroid: 0,
            zeroCrossingRate: 0
        )
    }
}

// MARK: - Errors

enum AudioFeatureError: Error, LocalizedError {
    case bufferCreationFailed
    case converterCreationFailed
    case fileReadFailed
    case invalidAudioFormat
    case ffmpegNotFound
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        case .fileReadFailed:
            return "Failed to read audio file"
        case .invalidAudioFormat:
            return "Invalid audio format"
        case .ffmpegNotFound:
            return "ffmpeg not found - required for WebM files. Install with: brew install ffmpeg"
        case .conversionFailed:
            return "Failed to convert audio file"
        }
    }
}
