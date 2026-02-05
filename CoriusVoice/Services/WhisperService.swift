import Foundation
import WhisperKit

// MARK: - Whisper Configuration

struct WhisperConfig {
    var modelSize: WhisperModelSize = .largev3Turbo
    var language: String? = nil  // nil = auto-detect
    var task: DecodingTask = .transcribe
    var enableTimestamps: Bool = true
    var enableWordTimestamps: Bool = true

    static var `default`: WhisperConfig {
        return WhisperConfig()
    }
}

enum WhisperModelSize: String, CaseIterable, Identifiable {
    case tiny = "openai_whisper-tiny"
    case base = "openai_whisper-base"
    case small = "openai_whisper-small"
    case medium = "openai_whisper-medium"
    case largev3 = "openai_whisper-large-v3"
    case largev3Turbo = "openai_whisper-large-v3_turbo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny (~75MB)"
        case .base: return "Base (~150MB)"
        case .small: return "Small (~220MB)"
        case .medium: return "Medium (~500MB)"
        case .largev3: return "Large v3 (~950MB)"
        case .largev3Turbo: return "Large v3 Turbo (~950MB) ⚡"
        }
    }

    var description: String {
        switch self {
        case .tiny: return "Fastest, lowest quality"
        case .base: return "Fast, basic quality"
        case .small: return "Balanced speed/quality"
        case .medium: return "Good quality, slower"
        case .largev3: return "Best quality, slowest"
        case .largev3Turbo: return "Best quality, optimized speed"
        }
    }

    /// Estimated VRAM/Memory usage in GB
    var memoryUsage: Double {
        switch self {
        case .tiny: return 0.5
        case .base: return 0.5
        case .small: return 1.0
        case .medium: return 2.0
        case .largev3: return 4.0
        case .largev3Turbo: return 4.0
        }
    }
}

// MARK: - Whisper Progress

struct WhisperProgressInfo {
    var phase: WhisperPhase
    var progress: Double  // 0.0 to 1.0
    var currentTime: TimeInterval?
    var totalDuration: TimeInterval?
    var modelName: String?

    enum WhisperPhase: String {
        case loadingModel = "Loading Model"
        case downloadingModel = "Downloading Model"
        case processing = "Transcribing"
        case completed = "Completed"
        case failed = "Failed"

        var icon: String {
            switch self {
            case .loadingModel: return "cpu"
            case .downloadingModel: return "arrow.down.circle"
            case .processing: return "waveform"
            case .completed: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }
    }
}

// MARK: - Whisper Service

class WhisperService: ObservableObject {
    static let shared = WhisperService()

    @Published var isModelLoaded = false
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var currentModelSize: WhisperModelSize?
    @Published var availableModels: [String] = []
    @Published var downloadedModels: [String] = []

    private var whisperKit: WhisperKit?
    private var config = WhisperConfig.default

    private init() {
        Task {
            await checkDownloadedModels()
        }
    }

    // MARK: - Model Management

    /// Check which models are already downloaded
    func checkDownloadedModels() async {
        do {
            let models = try await WhisperKit.fetchAvailableModels()
            await MainActor.run {
                self.availableModels = models
            }
            print("[WhisperKit] Available models: \(models)")

            // Check local models
            let localModels = getLocalModels()
            await MainActor.run {
                self.downloadedModels = localModels
            }
            print("[WhisperKit] Downloaded models: \(localModels)")
        } catch {
            print("[WhisperKit] Failed to fetch models: \(error.localizedDescription)")
        }
    }

    /// Get list of locally downloaded models
    private func getLocalModels() -> [String] {
        let fileManager = FileManager.default
        let modelsDir = getModelsDirectory()

        guard let contents = try? fileManager.contentsOfDirectory(atPath: modelsDir.path) else {
            return []
        }

        return contents.filter { $0.hasPrefix("openai_whisper") }
    }

    /// Get the models directory
    private func getModelsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("CoriusVoice/WhisperModels")
    }

    /// Load a Whisper model
    func loadModel(
        _ modelSize: WhisperModelSize,
        onProgress: ((WhisperProgressInfo) -> Void)? = nil
    ) async throws {
        let alreadyLoading = await MainActor.run { isLoading }
        guard !alreadyLoading else { return }

        await MainActor.run {
            isLoading = true
            loadingProgress = 0
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        print("[WhisperKit] 📦 Loading model: \(modelSize.rawValue)")
        onProgress?(WhisperProgressInfo(phase: .loadingModel, progress: 0, modelName: modelSize.rawValue))

        do {
            // Find the best matching model variant
            let modelVariant = findModelVariant(for: modelSize)
            print("[WhisperKit] 🔍 Using variant: \(modelVariant)")

            // Initialize WhisperKit with the model
            let whisper = try await WhisperKit(
                model: modelVariant,
                downloadBase: nil,
                modelFolder: nil,
                download: true
            )

            self.whisperKit = whisper

            await MainActor.run {
                self.isModelLoaded = true
                self.currentModelSize = modelSize
                self.loadingProgress = 1.0
            }

            onProgress?(WhisperProgressInfo(phase: .completed, progress: 1.0, modelName: modelVariant))
            print("[WhisperKit] ✅ Model loaded successfully")

            // Refresh downloaded models list
            await checkDownloadedModels()

        } catch {
            onProgress?(WhisperProgressInfo(phase: .failed, progress: 0, modelName: modelSize.rawValue))
            print("[WhisperKit] ❌ Failed to load model: \(error.localizedDescription)")
            throw WhisperError.modelLoadFailed(details: error.localizedDescription)
        }
    }

    /// Find the best model variant for a given size
    private func findModelVariant(for size: WhisperModelSize) -> String {
        // rawValue now contains the full model name (e.g., "openai_whisper-large-v3_turbo")
        return size.rawValue
    }

    /// Unload the current model to free memory
    func unloadModel() {
        whisperKit = nil
        Task { @MainActor in
            isModelLoaded = false
            currentModelSize = nil
        }
        print("[WhisperKit] 🗑️ Model unloaded")
    }

    // MARK: - Audio Format Conversion

    /// Convert WebM/OGG to WAV for WhisperKit compatibility
    /// - Parameter url: Source audio file URL
    /// - Returns: URL to converted WAV file (temp directory), or original URL if no conversion needed
    private func ensureCompatibleFormat(_ url: URL) async throws -> (url: URL, isTemporary: Bool) {
        let ext = url.pathExtension.lowercased()

        // WebM and OGG need conversion - WhisperKit uses AVAudioFile which doesn't support these
        guard ext == "webm" || ext == "ogg" else {
            return (url, false)
        }

        print("[WhisperKit] 🔄 Converting \(ext.uppercased()) to WAV for transcription...")

        guard let ffmpegPath = findFFmpegPath() else {
            throw WhisperError.transcriptionFailed(details: "ffmpeg not found - required for \(ext.uppercased()) files. Install with: brew install ffmpeg")
        }

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("whisper_\(UUID().uuidString).wav")

        // Convert using ffmpeg
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-i", url.path,
            "-acodec", "pcm_f32le",  // Float32 PCM (WhisperKit prefers this)
            "-ar", "16000",           // 16kHz sample rate (Whisper's native rate)
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
                        // Verify the file was created and has content
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: tempFile.path),
                           let size = attrs[.size] as? Int64, size > 1000 {
                            print("[WhisperKit] ✅ Converted to WAV: \(size / 1024)KB")
                            continuation.resume(returning: (tempFile, true))
                        } else {
                            continuation.resume(throwing: WhisperError.transcriptionFailed(details: "Converted WAV file is too small or empty"))
                        }
                    } else {
                        continuation.resume(throwing: WhisperError.transcriptionFailed(details: "ffmpeg conversion failed with exit code: \(process.terminationStatus)"))
                    }
                }
            } catch {
                continuation.resume(throwing: WhisperError.transcriptionFailed(details: "Failed to run ffmpeg: \(error.localizedDescription)"))
            }
        }
    }

    /// Find ffmpeg binary
    private func findFFmpegPath() -> String? {
        let fm = FileManager.default

        // Check for bundled ffmpeg in app Resources
        if let bundledPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil),
           fm.fileExists(atPath: bundledPath) {
            return bundledPath
        }

        // Check common system paths
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

    // MARK: - Transcription

    /// Transcribe an audio file
    func transcribeFile(
        audioURL: URL,
        language: String? = nil,
        onProgress: ((WhisperProgressInfo) -> Void)? = nil
    ) async throws -> (segments: [TranscriptSegment], detectedLanguage: String?) {
        let whisper = whisperKit
        let localConfig = config

        return try await Task.detached(priority: .userInitiated) { [self] in
            guard let whisper else {
                throw WhisperError.modelNotLoaded
            }

            let reportProgress: (WhisperProgressInfo) -> Void = { info in
                guard let onProgress else { return }
                Task { @MainActor in
                    onProgress(info)
                }
            }

            print("[WhisperKit] 📁 Transcribing: \(audioURL.lastPathComponent)")
            reportProgress(WhisperProgressInfo(phase: .processing, progress: 0, modelName: "Decoding audio..."))

            // Convert WebM/OGG to WAV if needed
            let ext = audioURL.pathExtension.lowercased()
            let needsConversion = ext == "webm" || ext == "ogg"

            if needsConversion {
                reportProgress(WhisperProgressInfo(phase: .processing, progress: 0.02, modelName: "Decoding: Converting \(ext.uppercased())..."))
            } else {
                reportProgress(WhisperProgressInfo(phase: .processing, progress: 0.02, modelName: "Decoding: Loading audio..."))
            }

            let (processURL, isTemporary) = try await ensureCompatibleFormat(audioURL)
            defer {
                // Clean up temporary file
                if isTemporary {
                    try? FileManager.default.removeItem(at: processURL)
                    print("[WhisperKit] 🗑️ Cleaned up temporary WAV file")
                }
            }

            reportProgress(WhisperProgressInfo(phase: .processing, progress: 0.05, modelName: "Decoding: Analyzing audio..."))

            // Get audio duration for progress tracking
            let _ = getAudioDuration(url: processURL)

            reportProgress(WhisperProgressInfo(phase: .processing, progress: 0.08, modelName: "Decoding: Ready"))

            do {
                // If no language specified, detect it first for better multilingual accuracy
                var effectiveLanguage = language
                if language == nil {
                    reportProgress(WhisperProgressInfo(phase: .processing, progress: 0.10, modelName: "Decoding: Detecting language..."))
                    print("[WhisperKit] 🌍 Auto-detecting language from file...")
                    let (detectedLang, probabilities) = try await whisper.detectLanguage(audioPath: processURL.path)
                    effectiveLanguage = detectedLang

                    // Log top 3 language probabilities
                    let topLangs = probabilities.sorted { $0.value > $1.value }.prefix(3)
                    let langInfo = topLangs.map { "\($0.key): \(String(format: "%.1f%%", $0.value * 100))" }.joined(separator: ", ")
                    print("[WhisperKit] 🌍 Detected language: \(detectedLang) (probabilities: \(langInfo))")
                }

                reportProgress(WhisperProgressInfo(phase: .processing, progress: 0.15, modelName: "Transcribing..."))

                // Configure decoding options
                let options = DecodingOptions(
                    task: localConfig.task,
                    language: effectiveLanguage,
                    temperature: 0.0,
                    temperatureFallbackCount: 5,
                    sampleLength: 224,
                    usePrefillPrompt: true,
                    usePrefillCache: true,
                    skipSpecialTokens: true,
                    withoutTimestamps: !localConfig.enableTimestamps,
                    wordTimestamps: localConfig.enableWordTimestamps,
                    suppressBlank: true,
                    compressionRatioThreshold: 2.4,
                    logProbThreshold: -1.0,
                    firstTokenLogProbThreshold: -1.5,
                    noSpeechThreshold: 0.6
                )

                // Start progress animation for transcription phase
                let progressTask = Task {
                    var progress = 0.20
                while !Task.isCancelled && progress < 0.80 {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    progress += 0.05
                    reportProgress(WhisperProgressInfo(phase: .processing, progress: min(progress, 0.80), modelName: "Transcribing..."))
                }
            }

                // Transcribe (use processURL which may be converted WAV)
                let results = try await whisper.transcribe(
                    audioPath: processURL.path,
                    decodeOptions: options
                )

                // Cancel progress animation
                progressTask.cancel()
            reportProgress(WhisperProgressInfo(phase: .processing, progress: 0.85, modelName: "Parsing results..."))

                // Convert to TranscriptSegments
                var segments: [TranscriptSegment] = []
                var detectedLanguage: String?

                for result in results {
                    detectedLanguage = result.language

                    for segment in result.segments {
                        var words: [TranscriptWord] = []
                        if let segmentWords = segment.words {
                            for word in segmentWords {
                                let tw = TranscriptWord(
                                    word: word.word,
                                    start: Double(word.start),
                                    end: Double(word.end),
                                    confidence: Double(word.probability),
                                    speakerID: nil
                                )
                                words.append(tw)
                            }
                        }

                        let trimmedText = segment.text.trimmingCharacters(in: CharacterSet.whitespaces)
                        let transcriptSegment = TranscriptSegment(
                            timestamp: Double(segment.start),
                            text: trimmedText,
                            speakerID: nil,
                            confidence: Double(segment.avgLogprob),
                            isFinal: true,
                            words: words,
                            source: .microphone
                        )

                        if !transcriptSegment.text.isEmpty {
                            segments.append(transcriptSegment)
                        }
                    }
                }

                reportProgress(WhisperProgressInfo(phase: .completed, progress: 1.0))
                print("[WhisperKit] ✅ Transcription complete: \(segments.count) segments")

                return (segments, detectedLanguage)

            } catch {
                reportProgress(WhisperProgressInfo(phase: .failed, progress: 0))
                print("[WhisperKit] ❌ Transcription failed: \(error.localizedDescription)")
                throw WhisperError.transcriptionFailed(details: error.localizedDescription)
            }
        }.value
    }

    /// Get audio duration using AVFoundation
    private func getAudioDuration(url: URL) -> TimeInterval? {
        // Use ffprobe if available, similar to DeepgramService
        guard let ffprobePath = findFFprobe() else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            url.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let duration = Double(output), duration > 0 {
                return duration
            }
        } catch {
            print("[WhisperKit] ⚠️ ffprobe failed: \(error.localizedDescription)")
        }

        return nil
    }

    /// Find ffprobe binary
    private func findFFprobe() -> String? {
        let fm = FileManager.default
        let systemPaths = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        for path in systemPaths {
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    // MARK: - Transcription with Local Diarization

    /// Transcribe an audio file with local speaker diarization (Whisper + FluidAudio)
    /// This is a fully local solution - no cloud APIs needed
    func transcribeFileWithDiarization(
        audioURL: URL,
        language: String? = nil,
        onProgress: ((WhisperProgressInfo) -> Void)? = nil
    ) async throws -> (segments: [TranscriptSegment], speakers: [Speaker]) {
        return try await Task.detached(priority: .userInitiated) { [self] in
            print("[WhisperKit] 🎯 Starting hybrid transcription + diarization")

            let reportProgress: (WhisperProgressInfo) -> Void = { info in
                guard let onProgress else { return }
                Task { @MainActor in
                    onProgress(info)
                }
            }

            // Step 1: Transcribe with Whisper
            reportProgress(WhisperProgressInfo(phase: .processing, progress: 0.1, modelName: "Transcribing..."))

            let (transcriptSegments, detectedLanguage) = try await transcribeFile(
                audioURL: audioURL,
                language: language,
                onProgress: { info in
                    // Scale progress to 0-50% for transcription
                    var scaledInfo = info
                    scaledInfo.progress = info.progress * 0.5
                    reportProgress(scaledInfo)
                }
            )

            print("[WhisperKit] ✅ Transcription complete: \(transcriptSegments.count) segments, language: \(detectedLanguage ?? "unknown")")

            // Step 2: Run speaker diarization with FluidAudio
            reportProgress(WhisperProgressInfo(phase: .processing, progress: 0.55, modelName: "Diarizing speakers..."))

            let diarizationResult: LocalDiarizationResult
            if #available(macOS 14.0, *) {
                do {
                    diarizationResult = try await LocalDiarizationService.shared.processAudioFile(audioURL)
                    print("[WhisperKit] ✅ Diarization complete: \(diarizationResult.speakerCount) speakers, \(diarizationResult.segments.count) segments")
                } catch {
                    print("[WhisperKit] ⚠️ Diarization failed, continuing without speakers: \(error.localizedDescription)")
                    // Return transcription without speaker info
                    reportProgress(WhisperProgressInfo(phase: .completed, progress: 1.0))
                    return (transcriptSegments, [])
                }
            } else {
                print("[WhisperKit] ⚠️ Diarization requires macOS 14.0+, continuing without speakers")
                reportProgress(WhisperProgressInfo(phase: .completed, progress: 1.0))
                return (transcriptSegments, [])
            }

            reportProgress(WhisperProgressInfo(phase: .processing, progress: 0.85, modelName: "Matching speakers..."))

            // Step 2.5: Match diarization speakers to known profiles using embeddings
            var speakerNameMap: [String: String] = [:]  // Map FluidAudio speaker IDs to known speaker names
            var speakerColorMap: [String: String] = [:] // Map FluidAudio speaker IDs to known speaker colors

            if #available(macOS 14.0, *) {
                let voiceProfileService = await MainActor.run { VoiceProfileService.shared }
                let speakerLibrary = await MainActor.run { SpeakerLibrary.shared }

                // Try to match each diarization speaker to a known profile
                for (diarizationID, profile) in diarizationResult.speakerProfiles {
                    // Use embedding-based matching if the profile has an embedding
                    if let match = await MainActor.run(body: {
                        voiceProfileService.identifyWithEmbedding(profile.embedding, threshold: 0.45)
                    }) {
                        speakerNameMap[diarizationID] = match.speakerName
                        print("[WhisperKit] 🎯 Matched speaker '\(diarizationID)' → '\(match.speakerName)' (confidence: \(String(format: "%.1f%%", match.confidence * 100)))")

                        // Also get the color from the library
                        if let knownSpeaker = await MainActor.run(body: { speakerLibrary.getSpeaker(byID: match.speakerID) }) {
                            speakerColorMap[diarizationID] = knownSpeaker.color
                        }
                    } else {
                        print("[WhisperKit] 👤 Speaker '\(diarizationID)' - no matching profile found")
                    }
                }

                print("[WhisperKit] 📊 Auto-identified \(speakerNameMap.count)/\(diarizationResult.speakerCount) speakers")
            }

            reportProgress(WhisperProgressInfo(phase: .processing, progress: 0.9, modelName: "Merging results..."))

            // Step 3: Assign speakers to transcript segments
            var segmentsWithSpeakers: [TranscriptSegment] = []
            var speakerIDMap: [String: Int] = [:]  // Map FluidAudio speaker IDs to numeric IDs
            var nextSpeakerID = 0

            for segment in transcriptSegments {
                var assignedSpeakerID: Int? = nil

                // Find the speaker for this segment's timestamp (with carry-forward for gaps)
                if #available(macOS 14.0, *) {
                    if let speakerIDString = LocalDiarizationService.shared.getSpeakerAtTimeWithCarryForward(diarizationResult, time: segment.timestamp) {
                        // Convert string speaker ID to numeric
                        if speakerIDMap[speakerIDString] == nil {
                            speakerIDMap[speakerIDString] = nextSpeakerID
                            nextSpeakerID += 1
                        }
                        assignedSpeakerID = speakerIDMap[speakerIDString]
                    }
                }

                // Create updated words with speaker IDs
                let updatedWords: [TranscriptWord]
                if #available(macOS 14.0, *) {
                    updatedWords = segment.words.map { word in
                        var wordSpeakerID = assignedSpeakerID
                        // For words, use the segment's speaker by default (more consistent)
                        // Only override if word falls clearly in a different speaker's segment
                        if let wordSpeaker = LocalDiarizationService.shared.getSpeakerAtTime(diarizationResult, time: word.start, tolerance: 0.2) {
                            if speakerIDMap[wordSpeaker] == nil {
                                speakerIDMap[wordSpeaker] = nextSpeakerID
                                nextSpeakerID += 1
                            }
                            wordSpeakerID = speakerIDMap[wordSpeaker]
                        }
                        return TranscriptWord(
                            word: word.word,
                            start: word.start,
                            end: word.end,
                            confidence: word.confidence,
                            speakerID: wordSpeakerID ?? assignedSpeakerID
                        )
                    }
                } else {
                    updatedWords = segment.words
                }

                // Create new segment with speaker info
                let updatedSegment = TranscriptSegment(
                    id: segment.id,
                    timestamp: segment.timestamp,
                    text: segment.text,
                    speakerID: assignedSpeakerID,
                    confidence: segment.confidence,
                    isFinal: segment.isFinal,
                    words: updatedWords,
                    source: segment.source
                )

                segmentsWithSpeakers.append(updatedSegment)
            }

            // Create Speaker objects with matched names, colors, and embeddings
            let speakers = speakerIDMap.sorted { $0.value < $1.value }.map { (diarizationID, numericID) -> Speaker in
                // Get embedding from diarization result
                let embedding = diarizationResult.speakerProfiles[diarizationID]?.embedding
                var speaker = Speaker(id: numericID, name: speakerNameMap[diarizationID], embedding: embedding)
                if let color = speakerColorMap[diarizationID] {
                    speaker.color = color
                }
                return speaker
            }

            reportProgress(WhisperProgressInfo(phase: .completed, progress: 1.0))

            print("[WhisperKit] ✅ Hybrid transcription complete: \(segmentsWithSpeakers.count) segments, \(speakers.count) speakers")

            return (segmentsWithSpeakers, speakers)
        }.value
    }

    // MARK: - Real-time Streaming (Chunked Processing)

    /// Secondary WhisperKit instance for streaming (tiny/base model)
    private var streamingWhisperKit: WhisperKit?
    @Published private(set) var streamingModelSize: WhisperModelSize?

    /// Audio buffer for chunked processing
    private var audioBuffer: [Float] = []
    private let audioBufferLock = NSLock()

    /// Minimum audio duration for processing (seconds)
    private let minChunkDuration: TimeInterval = 2.0

    /// Sample rate for audio (16kHz for Whisper)
    private let sampleRate: Double = 16000

    @Published var isStreamingModelLoaded = false
    @Published var isStreamingLoading = false

    /// Load a fast model for real-time streaming (tiny or base recommended)
    func loadStreamingModel(
        _ modelSize: WhisperModelSize = .base,
        onProgress: ((WhisperProgressInfo) -> Void)? = nil
    ) async throws {
        let alreadyLoading = await MainActor.run { isStreamingLoading }
        guard !alreadyLoading else { return }

        await MainActor.run {
            isStreamingLoading = true
        }

        defer {
            Task { @MainActor in
                isStreamingLoading = false
            }
        }

        print("[WhisperKit] 🚀 Loading streaming model: \(modelSize.rawValue)")
        onProgress?(WhisperProgressInfo(phase: .loadingModel, progress: 0, modelName: modelSize.rawValue))

        do {
            let modelVariant = modelSize.rawValue

            let whisper = try await WhisperKit(
                model: modelVariant,
                downloadBase: nil,
                modelFolder: nil,
                download: true
            )

            self.streamingWhisperKit = whisper

            await MainActor.run {
                self.streamingModelSize = modelSize
                self.isStreamingModelLoaded = true
            }

            onProgress?(WhisperProgressInfo(phase: .completed, progress: 1.0, modelName: modelVariant))
            print("[WhisperKit] ✅ Streaming model loaded: \(modelSize.displayName)")

        } catch {
            onProgress?(WhisperProgressInfo(phase: .failed, progress: 0, modelName: modelSize.rawValue))
            print("[WhisperKit] ❌ Failed to load streaming model: \(error.localizedDescription)")
            throw WhisperError.modelLoadFailed(details: error.localizedDescription)
        }
    }

    /// Unload streaming model to free memory
    func unloadStreamingModel() {
        streamingWhisperKit = nil
        clearAudioBuffer()
        Task { @MainActor in
            streamingModelSize = nil
            isStreamingModelLoaded = false
        }
        print("[WhisperKit] 🗑️ Streaming model unloaded")
    }

    /// Add audio samples to the buffer for processing
    func addAudioSamples(_ samples: [Float]) {
        audioBufferLock.lock()
        audioBuffer.append(contentsOf: samples)
        audioBufferLock.unlock()
    }

    /// Clear the audio buffer
    func clearAudioBuffer() {
        audioBufferLock.lock()
        audioBuffer.removeAll()
        audioBufferLock.unlock()
    }

    /// Get current buffer duration in seconds
    var currentBufferDuration: TimeInterval {
        audioBufferLock.lock()
        let duration = TimeInterval(audioBuffer.count) / sampleRate
        audioBufferLock.unlock()
        return duration
    }

    /// Check if buffer has enough audio for processing
    var hasEnoughAudioForProcessing: Bool {
        return currentBufferDuration >= minChunkDuration
    }

    /// Process accumulated audio buffer and return transcription
    /// Returns nil if not enough audio or no streaming model loaded
    func processAudioBuffer(
        language: String? = nil,
        clearAfterProcessing: Bool = true
    ) async -> String? {
        guard let whisper = streamingWhisperKit else {
            print("[WhisperKit] ⚠️ No streaming model loaded")
            return nil
        }

        audioBufferLock.lock()
        let samples = audioBuffer
        if clearAfterProcessing {
            audioBuffer.removeAll()
        }
        audioBufferLock.unlock()

        guard samples.count >= Int(minChunkDuration * sampleRate) else {
            print("[WhisperKit] ⚠️ Not enough audio: \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / sampleRate))s)")
            return nil
        }

        print("[WhisperKit] 🎤 Processing \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / sampleRate))s)")

        do {
            let options = DecodingOptions(
                task: .transcribe,
                language: language,
                temperature: 0.0,
                temperatureFallbackCount: 2,  // Less fallbacks for speed
                sampleLength: 224,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: true,  // No timestamps needed for streaming
                wordTimestamps: false,
                suppressBlank: true,
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                firstTokenLogProbThreshold: -1.5,
                noSpeechThreshold: 0.6
            )

            // Transcribe audio samples directly
            let results = try await whisper.transcribe(
                audioArray: samples,
                decodeOptions: options
            )

            // Combine all segment texts
            var transcriptText = ""
            for result in results {
                for segment in result.segments {
                    let text = segment.text.trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        if !transcriptText.isEmpty {
                            transcriptText += " "
                        }
                        transcriptText += text
                    }
                }
            }

            if !transcriptText.isEmpty {
                print("[WhisperKit] 📝 Chunk transcription: '\(transcriptText.prefix(50))...'")
            }

            return transcriptText.isEmpty ? nil : transcriptText

        } catch {
            print("[WhisperKit] ❌ Chunk transcription failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Process audio samples directly (without buffering)
    /// - Parameters:
    ///   - samples: Audio samples at 16kHz
    ///   - language: Optional language code (nil = auto-detect per segment)
    ///   - forceProcess: If true, process even with less than minimum duration (for final buffers)
    func transcribeAudioSamples(
        _ samples: [Float],
        language: String? = nil,
        forceProcess: Bool = false
    ) async -> String? {
        guard let whisper = streamingWhisperKit else {
            print("[WhisperKit] ⚠️ No streaming model loaded")
            return nil
        }

        // Minimum samples: 2.0s normally, 0.5s when forced (for final buffer)
        let minSamples = forceProcess ? Int(0.5 * sampleRate) : Int(minChunkDuration * sampleRate)

        guard samples.count >= minSamples else {
            print("[WhisperKit] ⚠️ Not enough samples: \(samples.count) < \(minSamples) (force=\(forceProcess))")
            return nil
        }

        // Check audio content
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0
        let avgAmplitude = samples.reduce(0) { $0 + abs($1) } / Float(samples.count)
        print("[WhisperKit] 🎤 Audio stats: \(samples.count) samples, max=\(String(format: "%.4f", maxAmplitude)), avg=\(String(format: "%.6f", avgAmplitude))")

        // Skip if audio is too quiet (likely silence)
        if maxAmplitude < 0.001 {
            print("[WhisperKit] ⚠️ Audio too quiet (max amplitude \(maxAmplitude)), skipping")
            return nil
        }

        let startTime = Date()
        print("[WhisperKit] 🚀 Starting transcription of \(samples.count) samples...")

        do {
            // If no language specified, detect it first for better accuracy
            var effectiveLanguage = language
            if language == nil {
                print("[WhisperKit] 🌍 Auto-detecting language...")
                // Note: WhisperKit has a typo in the method name: "detectLangauge" instead of "detectLanguage"
                let (detectedLang, probabilities) = try await whisper.detectLangauge(audioArray: samples)
                effectiveLanguage = detectedLang

                // Log top 3 language probabilities
                let topLangs = probabilities.sorted { $0.value > $1.value }.prefix(3)
                let langInfo = topLangs.map { "\($0.key): \(String(format: "%.1f%%", $0.value * 100))" }.joined(separator: ", ")
                print("[WhisperKit] 🌍 Detected language: \(detectedLang) (probabilities: \(langInfo))")
            }

            let options = DecodingOptions(
                task: .transcribe,
                language: effectiveLanguage,
                temperature: 0.0,
                temperatureFallbackCount: 2,
                sampleLength: 224,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                wordTimestamps: false,
                suppressBlank: true,
                compressionRatioThreshold: 2.4,
                logProbThreshold: -1.0,
                firstTokenLogProbThreshold: -1.5,
                noSpeechThreshold: 0.6
            )

            let results = try await whisper.transcribe(
                audioArray: samples,
                decodeOptions: options
            )

            let elapsed = Date().timeIntervalSince(startTime)
            print("[WhisperKit] ⏱️ Transcription completed in \(String(format: "%.2f", elapsed))s")
            print("[WhisperKit] 📊 Results count: \(results.count)")

            var transcriptText = ""
            for (index, result) in results.enumerated() {
                print("[WhisperKit] 📝 Result \(index): \(result.segments.count) segments, language=\(result.language ?? "unknown")")
                for segment in result.segments {
                    let text = segment.text.trimmingCharacters(in: .whitespaces)
                    print("[WhisperKit] 📝 Segment: '\(text.prefix(100))'")
                    if !text.isEmpty {
                        if !transcriptText.isEmpty {
                            transcriptText += " "
                        }
                        transcriptText += text
                    }
                }
            }

            if transcriptText.isEmpty {
                print("[WhisperKit] ⚠️ Transcription returned empty text")
            } else {
                print("[WhisperKit] ✅ Final transcript: '\(transcriptText.prefix(100))...'")
            }

            return transcriptText.isEmpty ? nil : transcriptText

        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            print("[WhisperKit] ❌ Audio transcription failed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
            print("[WhisperKit] ❌ Error details: \(error)")
            return nil
        }
    }

    /// Check if both models are loaded (streaming + main)
    var isBothModelsLoaded: Bool {
        return isModelLoaded && isStreamingModelLoaded
    }

    /// Get recommended streaming model based on device
    static var recommendedStreamingModel: WhisperModelSize {
        // Use base for Apple Silicon Macs (good balance)
        // Use tiny for older devices or memory constrained situations
        return .base
    }
}

// MARK: - Whisper Errors

enum WhisperError: LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(details: String)
    case transcriptionFailed(details: String)
    case unsupportedFormat
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No Whisper model loaded. Please load a model first."
        case .modelLoadFailed(let details):
            return "Failed to load Whisper model: \(details)"
        case .transcriptionFailed(let details):
            return "Transcription failed: \(details)"
        case .unsupportedFormat:
            return "Unsupported audio format"
        case .fileNotFound:
            return "Audio file not found"
        }
    }
}
