import Foundation

protocol DeepgramServiceDelegate: AnyObject {
    func deepgramDidReceiveTranscript(_ transcript: DeepgramTranscript, fromInstance instanceID: String)
    func deepgramDidReceiveUtteranceEnd(fromInstance instanceID: String)
    func deepgramDidConnect(fromInstance instanceID: String)
    func deepgramDidDisconnect(error: Error?, fromInstance instanceID: String)
}

/// Configuration for Deepgram Nova-3 connection
struct DeepgramConfig {
    var language: String? = nil  // nil = auto-detect (Nova-3 multilingual)
    var keyterms: [String] = []  // Up to 100 words for boosting recognition
    var enableParagraphs: Bool = true
    var enableNumerals: Bool = true
    var enableSmartFormat: Bool = true
    var enablePunctuation: Bool = true
    var utteranceEndMs: Int = 1500  // Faster response than default
    var interimResults: Bool = true
    var enableMultichannel: Bool = false
    var enableDiarization: Bool = false  // Speaker identification

    static var `default`: DeepgramConfig {
        return DeepgramConfig()
    }

    /// Config optimized for session recording (longer, multi-speaker)
    static var sessionRecording: DeepgramConfig {
        var config = DeepgramConfig()
        config.enableDiarization = true
        config.utteranceEndMs = 3000  // Longer for natural conversation
        return config
    }
}

class DeepgramService {
    static let shared = DeepgramService()

    // MARK: - File Size Limits

    /// Maximum recommended file size for single request (100MB)
    static let maxRecommendedFileSize: Int64 = 100 * 1024 * 1024

    /// Maximum duration for single request (2 hours in seconds)
    static let maxRecommendedDuration: TimeInterval = 2 * 60 * 60

    /// Chunk size for splitting large files (30 minutes in seconds)
    static let chunkDurationSeconds: TimeInterval = 30 * 60

    weak var delegate: DeepgramServiceDelegate?

    /// Current configuration
    var config = DeepgramConfig.default

    /// Identifier for this instance (useful for dual-stream mode)
    var instanceID: String = "default"

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var sendCount = 0

    private init() {}

    /// Create a new instance (for dual-stream mode)
    init(instanceID: String) {
        self.instanceID = instanceID
    }

    // MARK: - Nova-3 Supported Languages (31 total)
    // Note: "multi" enables true multilingual auto-detection
    // Without it, Nova-3 may default to English

    static let supportedLanguages: [(code: String?, name: String, flag: String)] = [
        (nil, "Auto-detect (Multilingual)", "🌍"),  // Will use "multi" internally
        ("en", "English", "🇺🇸"),
        ("en-US", "English (US)", "🇺🇸"),
        ("en-GB", "English (UK)", "🇬🇧"),
        ("en-AU", "English (Australia)", "🇦🇺"),
        ("es", "Spanish", "🇪🇸"),
        ("es-419", "Spanish (Latin America)", "🇲🇽"),
        ("fr", "French", "🇫🇷"),
        ("fr-CA", "French (Canada)", "🇨🇦"),
        ("de", "German", "🇩🇪"),
        ("de-CH", "German (Swiss)", "🇨🇭"),
        ("it", "Italian", "🇮🇹"),
        ("pt", "Portuguese", "🇵🇹"),
        ("pt-BR", "Portuguese (Brazil)", "🇧🇷"),
        ("nl", "Dutch", "🇳🇱"),
        ("nl-BE", "Flemish", "🇧🇪"),
        ("ja", "Japanese", "🇯🇵"),
        ("zh", "Chinese (Mandarin)", "🇨🇳"),
        ("ko", "Korean", "🇰🇷"),
        ("ru", "Russian", "🇷🇺"),
        ("pl", "Polish", "🇵🇱"),
        ("uk", "Ukrainian", "🇺🇦"),
        ("sv", "Swedish", "🇸🇪"),
        ("da", "Danish", "🇩🇰"),
        ("no", "Norwegian", "🇳🇴"),
        ("fi", "Finnish", "🇫🇮"),
        ("el", "Greek", "🇬🇷"),
        ("ro", "Romanian", "🇷🇴"),
        ("cs", "Czech", "🇨🇿"),
        ("sk", "Slovak", "🇸🇰"),
        ("ca", "Catalan", "🏴"),
        ("lt", "Lithuanian", "🇱🇹"),
        ("lv", "Latvian", "🇱🇻"),
        ("et", "Estonian", "🇪🇪"),
        ("hi", "Hindi", "🇮🇳"),
        ("ta", "Tamil", "🇮🇳"),
        ("tr", "Turkish", "🇹🇷"),
        ("id", "Indonesian", "🇮🇩"),
        ("th", "Thai", "🇹🇭"),
        ("vi", "Vietnamese", "🇻🇳")
    ]

    func connect(apiKey: String, language: String? = nil, keyterms: [String] = [], enableDiarization: Bool = false) {
        print("[Deepgram Nova-3] 🌐 Connecting...")
        print("[Deepgram Nova-3] 🔑 API Key length: \(apiKey.count)")

        guard !apiKey.isEmpty else {
            print("[Deepgram Nova-3] ❌ API key is empty")
            return
        }

        disconnect()
        sendCount = 0

        // Update config
        config.language = language
        config.keyterms = keyterms
        config.enableDiarization = enableDiarization

        // Build WebSocket URL with Nova-3 parameters
        // Based on working URL: model=nova-3&language=es&smart_format=true&interim_results=true&utterance_end_ms=3000&vad_events=true&endpointing=300&punctuate=true&encoding=linear16&sample_rate=16000&channels=1
        var urlComponents = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        var queryItems: [URLQueryItem] = [
            // Nova-3 Model
            URLQueryItem(name: "model", value: "nova-3"),

            // Audio encoding - 16kHz mono PCM
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),

            // Real-time streaming features - optimized for low latency
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "utterance_end_ms", value: "1000"),  // Reduced from 3000 for faster response
            URLQueryItem(name: "vad_events", value: "true"),
            URLQueryItem(name: "endpointing", value: "200"),  // Faster endpointing

            // Formatting options
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true")
        ]

        // Diarization - speaker identification
        if config.enableDiarization {
            queryItems.append(URLQueryItem(name: "diarize", value: "true"))
            print("[Deepgram Nova-3] 👥 Diarization: enabled")
        }

        // Language configuration
        // IMPORTANT: Without explicit language parameter, Nova-3 defaults to English!
        // Use "multi" for true multilingual auto-detection across 30+ languages
        if let lang = language, !lang.isEmpty {
            queryItems.append(URLQueryItem(name: "language", value: lang))
            print("[Deepgram Nova-3] 🌍 Language: \(lang)")
        } else {
            // Explicitly set "multi" for multilingual auto-detection
            // This enables Nova-3 to detect and transcribe any of its 30+ supported languages
            queryItems.append(URLQueryItem(name: "language", value: "multi"))
            print("[Deepgram Nova-3] 🌍 Language: multi (auto-detect any language)")
        }

        // Keyterm prompting - up to 100 words to boost recognition
        // NOTE: Disabled for now - may require specific API plan or cause connection issues
        // Each keyword must be a separate query parameter: keywords=word1&keywords=word2
        // if !keyterms.isEmpty {
        //     for keyword in keyterms.prefix(100) {
        //         queryItems.append(URLQueryItem(name: "keywords", value: keyword))
        //     }
        //     print("[Deepgram Nova-3] 🔤 Keyterms: \(keyterms.prefix(5).joined(separator: ", "))... (total: \(min(keyterms.count, 100)))")
        // }
        if !keyterms.isEmpty {
            print("[Deepgram Nova-3] 🔤 Keyterms available but disabled: \(keyterms.count) terms")
        }

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            print("[Deepgram Nova-3] ❌ Failed to create URL")
            return
        }

        print("[Deepgram Nova-3] 🔗 URL: \(url.absoluteString.prefix(100))...")

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        urlSession = URLSession(configuration: .default)
        webSocket = urlSession?.webSocketTask(with: request)
        webSocket?.resume()

        isConnected = true
        delegate?.deepgramDidConnect(fromInstance: instanceID)

        print("[Deepgram Nova-3] ✅ Connected (instance: \(instanceID))")

        receiveMessages()
    }

    func disconnect() {
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        if isConnected {
            isConnected = false
            delegate?.deepgramDidDisconnect(error: nil, fromInstance: instanceID)
            print("[Deepgram Nova-3] Disconnected (instance: \(instanceID))")
        }
    }

    func sendAudio(_ data: Data) {
        guard isConnected, let webSocket = webSocket else { return }

        sendCount += 1
        if sendCount <= 3 || sendCount % 100 == 0 {
            // Log first few bytes in hex and as Int16 samples
            let hexBytes = data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")

            // Interpret first 8 bytes as 4 Int16 samples
            let samples = data.prefix(8).withUnsafeBytes { ptr -> [Int16] in
                let int16Ptr = ptr.bindMemory(to: Int16.self)
                return Array(int16Ptr.prefix(4))
            }

            print("[Deepgram Nova-3] 📤 Audio packet #\(sendCount), \(data.count) bytes")
            print("[Deepgram Nova-3] 📤 First bytes (hex): \(hexBytes)")
            print("[Deepgram Nova-3] 📤 First samples (Int16): \(samples)")
        }

        webSocket.send(.data(data)) { error in
            if let error = error {
                print("[Deepgram Nova-3] ❌ Send error: \(error.localizedDescription)")
            }
        }
    }

    func sendKeepAlive() {
        guard isConnected else { return }

        let keepAlive = ["type": "KeepAlive"]
        if let data = try? JSONSerialization.data(withJSONObject: keepAlive) {
            webSocket?.send(.data(data)) { _ in }
        }
    }

    /// Update keyterms during an active session (for context changes)
    func updateKeyterms(_ keyterms: [String]) {
        config.keyterms = keyterms
        // Note: To apply new keyterms, reconnection is needed
        // For now, we'll use them on next connection
    }

    private func receiveMessages() {
        guard isConnected else { return }

        webSocket?.receive { [weak self] result in
            guard let self = self, self.isConnected else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessages()

            case .failure(let error):
                // Only report error if we were still connected (not a normal disconnect)
                if self.isConnected {
                    print("[Deepgram Nova-3] ❌ Receive error (instance: \(self.instanceID)): \(error.localizedDescription)")
                    self.isConnected = false
                    self.delegate?.deepgramDidDisconnect(error: error, fromInstance: self.instanceID)
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        // Log raw response for debugging (only first 500 chars)
        if text.contains("\"type\":\"Results\"") && text.contains("\"transcript\":\"\"") {
            print("[Deepgram Nova-3] 🔍 Raw empty result: \(text.prefix(500))")
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let type = json["type"] as? String {
                    switch type {
                    case "Results":
                        if let transcript = parseTranscript(json) {
                            if !transcript.transcript.isEmpty {
                                let langInfo = transcript.detectedLanguage.map { " [\($0)]" } ?? ""
                                print("[Deepgram Nova-3] 📝 '\(transcript.transcript.prefix(50))...'\(langInfo) (final: \(transcript.isFinal), confidence: \(String(format: "%.2f", transcript.confidence)))")
                            } else {
                                // Log empty transcripts to understand why
                                print("[Deepgram Nova-3] ⚠️ Empty transcript received (final: \(transcript.isFinal), confidence: \(String(format: "%.2f", transcript.confidence)))")
                            }
                            DispatchQueue.main.async {
                                self.delegate?.deepgramDidReceiveTranscript(transcript, fromInstance: self.instanceID)
                            }
                        } else {
                            // Log when parsing fails
                            if let channel = json["channel"] as? [String: Any],
                               let alternatives = channel["alternatives"] as? [[String: Any]] {
                                print("[Deepgram Nova-3] ⚠️ Results received but parse failed - alternatives count: \(alternatives.count)")
                            } else {
                                print("[Deepgram Nova-3] ⚠️ Results received but no channel/alternatives structure")
                            }
                        }

                    case "UtteranceEnd":
                        print("[Deepgram Nova-3] 🏁 Utterance end (instance: \(self.instanceID))")
                        DispatchQueue.main.async {
                            self.delegate?.deepgramDidReceiveUtteranceEnd(fromInstance: self.instanceID)
                        }

                    case "Metadata":
                        if let requestId = json["request_id"] as? String {
                            print("[Deepgram Nova-3] 📊 Session: \(requestId.prefix(8))...")
                        }
                        // Log full metadata for debugging
                        if let modelInfo = json["model_info"] as? [String: Any] {
                            print("[Deepgram Nova-3] 📊 Model: \(modelInfo)")
                        }

                    case "Error":
                        print("[Deepgram Nova-3] ❌ API Error: \(json)")

                    case "Warning":
                        print("[Deepgram Nova-3] ⚠️ API Warning: \(json)")

                    case "SpeechStarted":
                        print("[Deepgram Nova-3] 🎤 Speech detected")

                    default:
                        break
                    }
                }
            }
        } catch {
            print("[Deepgram Nova-3] ❌ Parse error: \(error.localizedDescription)")
        }
    }

    private func parseTranscript(_ json: [String: Any]) -> DeepgramTranscript? {
        guard let channel = (json["channel"] as? [String: Any]),
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let firstAlternative = alternatives.first,
              let transcript = firstAlternative["transcript"] as? String else {
            return nil
        }

        let isFinal = json["is_final"] as? Bool ?? false
        let speechFinal = json["speech_final"] as? Bool ?? false
        let confidence = firstAlternative["confidence"] as? Double ?? 0

        // Detected language (Nova-3 multilingual feature)
        let detectedLanguage = (json["metadata"] as? [String: Any])?["detected_language"] as? String

        // Parse words with timestamps and speaker info
        var words: [DeepgramWord] = []
        if let wordsArray = firstAlternative["words"] as? [[String: Any]] {
            words = wordsArray.compactMap { wordDict -> DeepgramWord? in
                guard let word = wordDict["word"] as? String,
                      let start = wordDict["start"] as? Double,
                      let end = wordDict["end"] as? Double else {
                    return nil
                }
                let wordConfidence = wordDict["confidence"] as? Double ?? 0
                let punctuatedWord = wordDict["punctuated_word"] as? String
                let speaker = wordDict["speaker"] as? Int  // Speaker ID from diarization
                return DeepgramWord(
                    word: word,
                    punctuatedWord: punctuatedWord ?? word,
                    start: start,
                    end: end,
                    confidence: wordConfidence,
                    speaker: speaker
                )
            }
        }

        // Parse paragraphs if available
        var paragraphs: [String] = []
        if let paragraphsData = firstAlternative["paragraphs"] as? [String: Any],
           let paragraphsList = paragraphsData["paragraphs"] as? [[String: Any]] {
            paragraphs = paragraphsList.compactMap { para in
                if let sentences = para["sentences"] as? [[String: Any]] {
                    return sentences.compactMap { $0["text"] as? String }.joined(separator: " ")
                }
                return nil
            }
        }

        // Calculate dominant speaker (most common speaker in this segment)
        let speakerCounts = words.compactMap { $0.speaker }.reduce(into: [:]) { counts, speaker in
            counts[speaker, default: 0] += 1
        }
        let dominantSpeaker = speakerCounts.max(by: { $0.value < $1.value })?.key

        return DeepgramTranscript(
            transcript: transcript,
            confidence: confidence,
            isFinal: isFinal,
            speechFinal: speechFinal,
            words: words,
            paragraphs: paragraphs,
            detectedLanguage: detectedLanguage,
            dominantSpeaker: dominantSpeaker
        )
    }
}

// MARK: - Models

struct DeepgramTranscript {
    let transcript: String
    let confidence: Double
    let isFinal: Bool
    let speechFinal: Bool
    let words: [DeepgramWord]
    let paragraphs: [String]
    let detectedLanguage: String?
    let dominantSpeaker: Int?  // Most common speaker ID in this segment

    init(transcript: String, confidence: Double, isFinal: Bool, speechFinal: Bool, words: [DeepgramWord], paragraphs: [String] = [], detectedLanguage: String? = nil, dominantSpeaker: Int? = nil) {
        self.transcript = transcript
        self.confidence = confidence
        self.isFinal = isFinal
        self.speechFinal = speechFinal
        self.words = words
        self.paragraphs = paragraphs
        self.detectedLanguage = detectedLanguage
        self.dominantSpeaker = dominantSpeaker
    }

    /// Get unique speakers in this transcript
    var speakers: [Int] {
        Array(Set(words.compactMap { $0.speaker })).sorted()
    }
}

struct DeepgramWord {
    let word: String
    let punctuatedWord: String
    let start: Double
    let end: Double
    let confidence: Double
    let speaker: Int?  // Speaker ID from diarization (0, 1, 2...)
}

// MARK: - Pre-recorded Transcription Response

struct DeepgramPreRecordedResponse: Codable {
    let metadata: Metadata?
    let results: Results?

    struct Metadata: Codable {
        let requestId: String?
        let duration: Double?

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case duration
        }
    }

    struct Results: Codable {
        let channels: [Channel]?
        let utterances: [Utterance]?
    }

    struct Channel: Codable {
        let alternatives: [Alternative]?
        let detectedLanguage: String?

        enum CodingKeys: String, CodingKey {
            case alternatives
            case detectedLanguage = "detected_language"
        }
    }

    struct Alternative: Codable {
        let transcript: String?
        let confidence: Double?
        let words: [Word]?
        let paragraphs: Paragraphs?
    }

    struct Word: Codable {
        let word: String
        let start: Double
        let end: Double
        let confidence: Double
        let speaker: Int?
        let punctuatedWord: String?

        enum CodingKeys: String, CodingKey {
            case word, start, end, confidence, speaker
            case punctuatedWord = "punctuated_word"
        }
    }

    struct Paragraphs: Codable {
        let paragraphs: [Paragraph]?
    }

    struct Paragraph: Codable {
        let sentences: [Sentence]?
        let speaker: Int?
        let start: Double?
        let end: Double?
    }

    struct Sentence: Codable {
        let text: String?
        let start: Double?
        let end: Double?
    }

    struct Utterance: Codable {
        let start: Double
        let end: Double
        let confidence: Double
        let channel: Int
        let transcript: String
        let words: [Word]?
        let speaker: Int?
        let id: String
    }
}

// MARK: - Transcription Progress

/// Progress for a single chunk upload
struct ChunkUploadProgress: Identifiable {
    let id: Int  // Chunk index
    var progress: Double  // 0.0 to 1.0
    var phase: ChunkPhase

    enum ChunkPhase: String {
        case pending = "Pending"
        case uploading = "Uploading"
        case processing = "Processing"
        case completed = "Completed"
        case failed = "Failed"
    }
}

/// Progress information for file transcription
struct TranscriptionProgressInfo {
    var phase: TranscriptionPhase
    var uploadProgress: Double  // 0.0 to 1.0 (overall progress)
    var fileName: String
    var fileSize: Int64

    // Parallel chunk tracking
    var totalChunks: Int = 1
    var completedChunks: Int = 0
    var chunkProgresses: [ChunkUploadProgress] = []

    /// Calculate overall upload progress from chunks
    var overallUploadProgress: Double {
        guard totalChunks > 0 else { return uploadProgress }
        if chunkProgresses.isEmpty { return uploadProgress }

        let completedWeight = Double(completedChunks)
        let activeProgress = chunkProgresses
            .filter { $0.phase == .uploading || $0.phase == .processing }
            .reduce(0.0) { $0 + $1.progress }

        return (completedWeight + activeProgress) / Double(totalChunks)
    }

    var fileSizeFormatted: String {
        if fileSize < 1024 {
            return "\(fileSize) B"
        } else if fileSize < 1024 * 1024 {
            return String(format: "%.1f KB", Double(fileSize) / 1024)
        } else {
            return String(format: "%.1f MB", Double(fileSize) / (1024 * 1024))
        }
    }

    enum TranscriptionPhase: String {
        case preparing = "Preparing"
        case uploading = "Uploading"
        case processing = "Processing"
        case parsing = "Parsing"
        case completed = "Completed"
        case failed = "Failed"

        var icon: String {
            switch self {
            case .preparing: return "doc.fill"
            case .uploading: return "arrow.up.circle.fill"
            case .processing: return "waveform"
            case .parsing: return "text.magnifyingglass"
            case .completed: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }
    }
}

// MARK: - Upload Progress Delegate

private class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    var onProgress: ((Double) -> Void)?

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async { [weak self] in
            self?.onProgress?(progress)
        }
    }
}

// MARK: - Pre-recorded Transcription Extension

extension DeepgramService {

    /// Transcribe an audio file using Deepgram's pre-recorded API with progress tracking
    /// - Parameters:
    ///   - audioURL: URL to the audio file
    ///   - apiKey: Deepgram API key
    ///   - language: Language code (nil for auto-detect)
    ///   - enableDiarization: Enable speaker diarization
    ///   - onProgress: Progress callback (called on main thread)
    /// - Returns: Array of transcript segments with speaker info
    func transcribeFile(
        audioURL: URL,
        apiKey: String,
        language: String? = nil,
        enableDiarization: Bool = true,
        onProgress: ((TranscriptionProgressInfo) -> Void)? = nil
    ) async throws -> (segments: [TranscriptSegment], speakers: [Speaker]) {
        let fileName = audioURL.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64) ?? 0

        // Helper to report progress
        func reportProgress(_ phase: TranscriptionProgressInfo.TranscriptionPhase, upload: Double = 0) {
            let info = TranscriptionProgressInfo(phase: phase, uploadProgress: upload, fileName: fileName, fileSize: fileSize)
            DispatchQueue.main.async {
                onProgress?(info)
            }
        }

        print("[Deepgram Pre-recorded] 📁 Transcribing file: \(fileName)")
        reportProgress(.preparing)

        guard !apiKey.isEmpty else {
            reportProgress(.failed)
            throw DeepgramError.missingApiKey
        }

        // Read audio file data
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            reportProgress(.failed)
            throw DeepgramError.fileReadError(fileName: fileName, details: error.localizedDescription)
        }
        print("[Deepgram Pre-recorded] 📊 Audio size: \(audioData.count / 1024) KB")

        // Build URL with query parameters
        var urlComponents = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "utterances", value: "true"),  // Get utterances for better segment splitting
            URLQueryItem(name: "utt_split", value: "0.8"),  // Split utterances on 800ms silence
        ]

        // Diarization
        if enableDiarization {
            queryItems.append(URLQueryItem(name: "diarize", value: "true"))
            print("[Deepgram Pre-recorded] 👥 Diarization: enabled")
        }

        // Language
        if let lang = language, !lang.isEmpty {
            queryItems.append(URLQueryItem(name: "language", value: lang))
            print("[Deepgram Pre-recorded] 🌍 Language: \(lang)")
        } else {
            queryItems.append(URLQueryItem(name: "language", value: "multi"))
            print("[Deepgram Pre-recorded] 🌍 Language: multi (auto-detect)")
        }

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            reportProgress(.failed)
            throw DeepgramError.invalidURL
        }

        // Determine content type based on file extension
        let contentType = Self.mimeType(for: audioURL)
        print("[Deepgram Pre-recorded] 📝 Content-Type: \(contentType)")

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300  // 5 minutes for long files

        // Create session with optimized configuration for faster uploads
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        let progressDelegate = UploadProgressDelegate()
        progressDelegate.onProgress = { progress in
            reportProgress(.uploading, upload: progress)
        }

        let session = URLSession(configuration: config, delegate: progressDelegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        // Send request with upload task for progress tracking
        print("[Deepgram Pre-recorded] 🚀 Sending request...")
        reportProgress(.uploading, upload: 0)

        let (data, response) = try await session.upload(for: request, from: audioData)

        // Now processing on Deepgram side
        reportProgress(.processing)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            reportProgress(.failed)
            throw DeepgramError.invalidResponse
        }

        print("[Deepgram Pre-recorded] 📬 Response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            reportProgress(.failed)

            // Try to parse error message from response
            var errorMessage = "Request failed"
            var responseBody: String? = nil

            if let bodyString = String(data: data, encoding: .utf8) {
                responseBody = bodyString
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let msg = errorJson["error"] as? String {
                        errorMessage = msg
                    } else if let msg = errorJson["err_msg"] as? String {
                        errorMessage = msg
                    } else if let msg = errorJson["message"] as? String {
                        errorMessage = msg
                    }
                }
            }

            throw DeepgramError.apiError(
                message: errorMessage,
                statusCode: httpResponse.statusCode,
                responseBody: responseBody,
                fileName: fileName
            )
        }

        // Parse response
        reportProgress(.parsing)
        let decoder = JSONDecoder()
        let deepgramResponse = try decoder.decode(DeepgramPreRecordedResponse.self, from: data)

        // Convert to TranscriptSegments
        let result = parsePreRecordedResponse(deepgramResponse)
        reportProgress(.completed)

        return result
    }

    /// Parse Deepgram pre-recorded response into TranscriptSegments and Speakers
    private func parsePreRecordedResponse(_ response: DeepgramPreRecordedResponse) -> (segments: [TranscriptSegment], speakers: [Speaker]) {
        var segments: [TranscriptSegment] = []
        var speakerSet = Set<Int>()

        // Prefer utterances if available (better segment splitting)
        if let utterances = response.results?.utterances, !utterances.isEmpty {
            print("[Deepgram Pre-recorded] 📝 Using utterances: \(utterances.count)")

            for utterance in utterances {
                let words = utterance.words?.map { word in
                    TranscriptWord(
                        word: word.word,
                        start: word.start,
                        end: word.end,
                        confidence: word.confidence,
                        speakerID: word.speaker
                    )
                } ?? []

                let segment = TranscriptSegment(
                    timestamp: utterance.start,
                    text: utterance.transcript,
                    speakerID: utterance.speaker,
                    confidence: utterance.confidence,
                    isFinal: true,
                    words: words,
                    source: .unknown
                )
                segments.append(segment)

                if let speaker = utterance.speaker {
                    speakerSet.insert(speaker)
                }
            }
        }
        // Fallback to channel alternatives
        else if let channels = response.results?.channels, let firstChannel = channels.first,
                let alternatives = firstChannel.alternatives, let firstAlt = alternatives.first {
            print("[Deepgram Pre-recorded] 📝 Using channel alternative")

            // Try to split by paragraphs
            if let paragraphs = firstAlt.paragraphs?.paragraphs, !paragraphs.isEmpty {
                for paragraph in paragraphs {
                    if let sentences = paragraph.sentences {
                        for sentence in sentences {
                            let segment = TranscriptSegment(
                                timestamp: sentence.start ?? 0,
                                text: sentence.text ?? "",
                                speakerID: paragraph.speaker,
                                confidence: firstAlt.confidence ?? 0,
                                isFinal: true,
                                words: [],
                                source: .unknown
                            )
                            segments.append(segment)

                            if let speaker = paragraph.speaker {
                                speakerSet.insert(speaker)
                            }
                        }
                    }
                }
            }
            // Fallback to single segment
            else if let transcript = firstAlt.transcript, !transcript.isEmpty {
                let words = firstAlt.words?.map { word in
                    TranscriptWord(
                        word: word.word,
                        start: word.start,
                        end: word.end,
                        confidence: word.confidence,
                        speakerID: word.speaker
                    )
                } ?? []

                // Group words by speaker for better segments
                if !words.isEmpty {
                    var currentSpeaker: Int? = words.first?.speakerID
                    var currentWords: [TranscriptWord] = []
                    var currentStart: Double = 0

                    for word in words {
                        if word.speakerID != currentSpeaker && !currentWords.isEmpty {
                            // Create segment for previous speaker
                            let text = currentWords.map { $0.word }.joined(separator: " ")
                            let segment = TranscriptSegment(
                                timestamp: currentStart,
                                text: text,
                                speakerID: currentSpeaker,
                                confidence: firstAlt.confidence ?? 0,
                                isFinal: true,
                                words: currentWords,
                                source: .unknown
                            )
                            segments.append(segment)

                            if let speaker = currentSpeaker {
                                speakerSet.insert(speaker)
                            }

                            currentWords = []
                            currentStart = word.start
                            currentSpeaker = word.speakerID
                        }
                        currentWords.append(word)
                    }

                    // Add final segment
                    if !currentWords.isEmpty {
                        let text = currentWords.map { $0.word }.joined(separator: " ")
                        let segment = TranscriptSegment(
                            timestamp: currentStart,
                            text: text,
                            speakerID: currentSpeaker,
                            confidence: firstAlt.confidence ?? 0,
                            isFinal: true,
                            words: currentWords,
                            source: .unknown
                        )
                        segments.append(segment)

                        if let speaker = currentSpeaker {
                            speakerSet.insert(speaker)
                        }
                    }
                } else {
                    // No words, just use transcript
                    let segment = TranscriptSegment(
                        timestamp: 0,
                        text: transcript,
                        speakerID: nil,
                        confidence: firstAlt.confidence ?? 0,
                        isFinal: true,
                        words: [],
                        source: .unknown
                    )
                    segments.append(segment)
                }
            }
        }

        // Create speakers array
        let speakers = speakerSet.sorted().map { Speaker(id: $0) }

        print("[Deepgram Pre-recorded] ✅ Parsed \(segments.count) segments, \(speakers.count) speakers")
        return (segments, speakers)
    }

    /// Get MIME type for audio file
    private static func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "wav":
            return "audio/wav"
        case "mp3":
            return "audio/mpeg"
        case "m4a", "aac":
            return "audio/mp4"
        case "ogg":
            return "audio/ogg"
        case "flac":
            return "audio/flac"
        case "webm":
            return "audio/webm"
        default:
            return "audio/wav"
        }
    }
}

// MARK: - Chunk Progress Tracker (Thread-Safe)

/// Actor for thread-safe chunk progress tracking
actor ChunkProgressTracker {
    private var chunkProgresses: [Int: ChunkUploadProgress] = [:]
    private var completedChunks: Int = 0
    private let totalChunks: Int
    private let fileName: String
    private let fileSize: Int64

    init(totalChunks: Int, fileName: String, fileSize: Int64) {
        self.totalChunks = totalChunks
        self.fileName = fileName
        self.fileSize = fileSize

        // Initialize all chunks as pending
        for i in 0..<totalChunks {
            chunkProgresses[i] = ChunkUploadProgress(id: i, progress: 0, phase: .pending)
        }
    }

    func updateChunk(index: Int, phase: ChunkUploadProgress.ChunkPhase, progress: Double) {
        chunkProgresses[index] = ChunkUploadProgress(id: index, progress: progress, phase: phase)
    }

    func markChunkCompleted(index: Int) {
        chunkProgresses[index] = ChunkUploadProgress(id: index, progress: 1.0, phase: .completed)
        completedChunks += 1
    }

    func getProgressInfo() -> TranscriptionProgressInfo {
        let activeChunks = chunkProgresses.values
            .filter { $0.phase == .uploading || $0.phase == .processing }
            .sorted { $0.id < $1.id }

        // Calculate overall progress
        let completedWeight = Double(completedChunks)
        let activeProgress = activeChunks.reduce(0.0) { $0 + $1.progress }
        let overallProgress = (completedWeight + activeProgress) / Double(totalChunks)

        // Determine phase
        let phase: TranscriptionProgressInfo.TranscriptionPhase
        if completedChunks == totalChunks {
            phase = .completed
        } else if activeChunks.contains(where: { $0.phase == .processing }) {
            phase = .processing
        } else if activeChunks.contains(where: { $0.phase == .uploading }) || completedChunks > 0 {
            phase = .uploading
        } else {
            phase = .preparing
        }

        return TranscriptionProgressInfo(
            phase: phase,
            uploadProgress: overallProgress,
            fileName: fileName,
            fileSize: fileSize,
            totalChunks: totalChunks,
            completedChunks: completedChunks,
            chunkProgresses: Array(chunkProgresses.values).sorted { $0.id < $1.id }
        )
    }

    func reportProgress(_ onProgress: ((TranscriptionProgressInfo, Int, Int) -> Void)?) {
        let info = getProgressInfo()
        let completed = completedChunks
        let total = totalChunks
        DispatchQueue.main.async {
            onProgress?(info, completed + 1, total)
        }
    }
}

// MARK: - Chunked Transcription

extension DeepgramService {

    /// Transcribe a large audio file by splitting it into chunks
    /// - Parameters:
    ///   - audioURL: URL to the audio file
    ///   - apiKey: Deepgram API key
    ///   - language: Language code (nil for auto-detect)
    ///   - enableDiarization: Enable speaker diarization
    ///   - onProgress: Progress callback with chunk info
    /// - Returns: Array of transcript segments with speaker info
    func transcribeFileChunked(
        audioURL: URL,
        apiKey: String,
        language: String? = nil,
        enableDiarization: Bool = true,
        onProgress: ((TranscriptionProgressInfo, Int, Int) -> Void)? = nil
    ) async throws -> (segments: [TranscriptSegment], speakers: [Speaker]) {
        let fileName = audioURL.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64) ?? 0
        print("[Deepgram Chunked] 📁 Starting chunked transcription: \(fileName)")

        // Get audio duration using ffprobe
        guard let duration = getAudioDuration(url: audioURL) else {
            print("[Deepgram Chunked] ⚠️ Could not get duration, falling back to single file")
            return try await transcribeFile(
                audioURL: audioURL,
                apiKey: apiKey,
                language: language,
                enableDiarization: enableDiarization,
                onProgress: { info in onProgress?(info, 1, 1) }
            )
        }

        print("[Deepgram Chunked] ⏱️ Total duration: \(String(format: "%.0f", duration))s (\(String(format: "%.1f", duration / 3600))h)")

        // If under limit, use single file
        if duration <= Self.maxRecommendedDuration {
            print("[Deepgram Chunked] ✅ Duration within limits, using single file")
            return try await transcribeFile(
                audioURL: audioURL,
                apiKey: apiKey,
                language: language,
                enableDiarization: enableDiarization,
                onProgress: { info in onProgress?(info, 1, 1) }
            )
        }

        // Calculate number of chunks
        let chunkDuration = Self.chunkDurationSeconds
        let numChunks = Int(ceil(duration / chunkDuration))
        print("[Deepgram Chunked] 📦 Splitting into \(numChunks) chunks of \(Int(chunkDuration / 60)) minutes each")

        // Create temp directory for chunks
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("deepgram_chunks_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Split audio file using ffmpeg
        let chunkURLs = try splitAudioFile(audioURL: audioURL, outputDir: tempDir, chunkDuration: chunkDuration, numChunks: numChunks)

        print("[Deepgram Chunked] ✅ Created \(chunkURLs.count) chunks")

        // Thread-safe progress tracker
        let progressTracker = ChunkProgressTracker(totalChunks: chunkURLs.count, fileName: fileName, fileSize: fileSize)

        // Report initial state
        await progressTracker.reportProgress(onProgress)

        // Transcribe chunks in parallel (max 4 concurrent uploads for better throughput)
        let maxConcurrent = 4
        var allResults: [(index: Int, segments: [TranscriptSegment], speakers: [Speaker])] = []

        // Process chunks in batches for parallel upload
        for batchStart in stride(from: 0, to: chunkURLs.count, by: maxConcurrent) {
            let batchEnd = min(batchStart + maxConcurrent, chunkURLs.count)
            let batch = Array(batchStart..<batchEnd)

            print("[Deepgram Chunked] 📤 Uploading chunks \(batchStart + 1)-\(batchEnd) of \(chunkURLs.count) in parallel")

            // Mark batch chunks as uploading
            for index in batch {
                await progressTracker.updateChunk(index: index, phase: .uploading, progress: 0)
            }
            await progressTracker.reportProgress(onProgress)

            let batchResults = await withTaskGroup(of: (Int, [TranscriptSegment], [Speaker])?.self) { group in
                for index in batch {
                    group.addTask {
                        let chunkURL = chunkURLs[index]
                        let chunkOffset = Double(index) * chunkDuration

                        do {
                            let (segments, speakers) = try await self.transcribeFile(
                                audioURL: chunkURL,
                                apiKey: apiKey,
                                language: language,
                                enableDiarization: enableDiarization,
                                onProgress: { info in
                                    // Update individual chunk progress
                                    Task {
                                        if info.phase == .uploading {
                                            await progressTracker.updateChunk(index: index, phase: .uploading, progress: info.uploadProgress)
                                        } else if info.phase == .processing {
                                            await progressTracker.updateChunk(index: index, phase: .processing, progress: 1.0)
                                        }
                                        await progressTracker.reportProgress(onProgress)
                                    }
                                }
                            )

                            // Mark chunk as completed
                            await progressTracker.markChunkCompleted(index: index)
                            await progressTracker.reportProgress(onProgress)

                            // Adjust timestamps with chunk offset
                            let offsetSegments = segments.map { segment -> TranscriptSegment in
                                let adjustedWords = segment.words.map { word in
                                    TranscriptWord(
                                        word: word.word,
                                        start: word.start + chunkOffset,
                                        end: word.end + chunkOffset,
                                        confidence: word.confidence,
                                        speakerID: word.speakerID
                                    )
                                }
                                return TranscriptSegment(
                                    id: segment.id,
                                    timestamp: segment.timestamp + chunkOffset,
                                    text: segment.text,
                                    speakerID: segment.speakerID,
                                    confidence: segment.confidence,
                                    isFinal: segment.isFinal,
                                    words: adjustedWords,
                                    source: segment.source
                                )
                            }

                            print("[Deepgram Chunked] ✅ Chunk \(index + 1): \(segments.count) segments")
                            return (index, offsetSegments, speakers)
                        } catch {
                            await progressTracker.updateChunk(index: index, phase: .failed, progress: 0)
                            await progressTracker.reportProgress(onProgress)
                            print("[Deepgram Chunked] ❌ Chunk \(index + 1) failed: \(error.localizedDescription)")
                            return nil
                        }
                    }
                }

                var results: [(Int, [TranscriptSegment], [Speaker])] = []
                for await result in group {
                    if let r = result {
                        results.append(r)
                    }
                }
                return results
            }

            allResults.append(contentsOf: batchResults)
        }

        // Combine all results (sorted by chunk index to maintain order)
        allResults.sort { $0.index < $1.index }

        var allSegments: [TranscriptSegment] = []
        var allSpeakers = Set<Int>()

        for result in allResults {
            allSegments.append(contentsOf: result.segments)
            for speaker in result.speakers {
                allSpeakers.insert(speaker.id)
            }
        }

        // Sort by timestamp
        allSegments.sort { $0.timestamp < $1.timestamp }

        let speakers = allSpeakers.sorted().map { Speaker(id: $0) }

        print("[Deepgram Chunked] ✅ Total: \(allSegments.count) segments, \(speakers.count) speakers")

        return (allSegments, speakers)
    }

    /// Get audio duration using ffprobe
    private func getAudioDuration(url: URL) -> Double? {
        guard let ffprobePath = Self.findFFprobe() else {
            print("[Deepgram] ⚠️ ffprobe not found")
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
            print("[Deepgram] ⚠️ ffprobe failed: \(error.localizedDescription)")
        }

        return nil
    }

    /// Split audio file into chunks using ffmpeg
    private func splitAudioFile(audioURL: URL, outputDir: URL, chunkDuration: TimeInterval, numChunks: Int) throws -> [URL] {
        guard let ffmpegPath = Self.findFFmpeg() else {
            throw DeepgramError.fileReadError(fileName: audioURL.lastPathComponent, details: "ffmpeg not found - required for splitting large files")
        }

        var chunkURLs: [URL] = []
        let ext = audioURL.pathExtension

        for i in 0..<numChunks {
            let startTime = Double(i) * chunkDuration
            let outputPath = outputDir.appendingPathComponent("chunk_\(String(format: "%03d", i)).\(ext)")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = [
                "-y",  // Overwrite
                "-ss", String(format: "%.2f", startTime),  // Start time
                "-i", audioURL.path,
                "-t", String(format: "%.2f", chunkDuration),  // Duration
                "-c", "copy",  // Copy without re-encoding (fast)
                "-avoid_negative_ts", "make_zero",
                outputPath.path
            ]

            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: outputPath.path) {
                chunkURLs.append(outputPath)
            } else {
                print("[Deepgram] ⚠️ Failed to create chunk \(i)")
            }
        }

        return chunkURLs
    }

    /// Find ffprobe binary
    private static func findFFprobe() -> String? {
        let fm = FileManager.default

        // Check bundled
        if let bundledPath = Bundle.main.path(forResource: "ffprobe", ofType: nil),
           fm.fileExists(atPath: bundledPath) {
            return bundledPath
        }

        // Check system paths
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

    /// Find ffmpeg binary
    private static func findFFmpeg() -> String? {
        let fm = FileManager.default

        // Check bundled
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
}

// MARK: - Deepgram Errors

enum DeepgramError: LocalizedError {
    case missingApiKey
    case invalidURL
    case invalidResponse
    case apiError(message: String, statusCode: Int?, responseBody: String?, fileName: String?)
    case noAudioFile
    case fileReadError(fileName: String, details: String)
    case networkError(details: String)

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Deepgram API key is missing. Please configure it in Settings."
        case .invalidURL:
            return "Invalid URL configuration"
        case .invalidResponse:
            return "Invalid response from Deepgram server"
        case .apiError(let message, _, _, _):
            return message
        case .noAudioFile:
            return "No audio file available for transcription"
        case .fileReadError(let fileName, let details):
            return "Could not read file '\(fileName)': \(details)"
        case .networkError(let details):
            return "Network error: \(details)"
        }
    }

    /// Detailed error description for debugging
    var detailedDescription: String {
        switch self {
        case .missingApiKey:
            return "Deepgram API key is missing.\n\nGo to Settings → Deepgram API Key and enter your key.\n\nGet a key at: https://console.deepgram.com"

        case .invalidURL:
            return "Could not construct a valid URL for the Deepgram API request."

        case .invalidResponse:
            return "The server returned a response that could not be parsed. This might be a temporary server issue."

        case .apiError(let message, let statusCode, let responseBody, let fileName):
            var details = "Error: \(message)"
            if let code = statusCode {
                details += "\n\nHTTP Status: \(code)"
                details += "\n\(httpStatusExplanation(code))"
            }
            if let file = fileName {
                details += "\n\nFile: \(file)"
            }
            if let body = responseBody, !body.isEmpty {
                details += "\n\nServer Response:\n\(body.prefix(500))"
            }
            return details

        case .noAudioFile:
            return "No audio file found for this session. The file may have been deleted or moved."

        case .fileReadError(let fileName, let details):
            return "Could not read the audio file.\n\nFile: \(fileName)\nDetails: \(details)"

        case .networkError(let details):
            return "Network connection failed.\n\nDetails: \(details)\n\nPlease check your internet connection and try again."
        }
    }

    /// Human-readable explanation for HTTP status codes
    private func httpStatusExplanation(_ code: Int) -> String {
        switch code {
        case 400:
            return "Bad Request - The audio file format may not be supported or the file is corrupted."
        case 401:
            return "Unauthorized - Your API key is invalid or expired. Please check your Deepgram API key in Settings."
        case 402:
            return "Payment Required - Your Deepgram account may have run out of credits. Check your account at console.deepgram.com"
        case 403:
            return "Forbidden - Your API key doesn't have permission for this operation."
        case 404:
            return "Not Found - The API endpoint was not found."
        case 413:
            return "File Too Large - The audio file exceeds Deepgram's size limit. Try a shorter recording or compress the file."
        case 429:
            return "Too Many Requests - Rate limit exceeded. Please wait a moment and try again."
        case 500:
            return "Server Error - Deepgram is experiencing issues. Please try again later."
        case 502, 503:
            return "Service Unavailable - Deepgram servers are temporarily unavailable. Please try again later."
        case 504:
            return "Gateway Timeout - The audio file took too long to process. This usually happens with very long recordings (>2 hours). Try splitting the file into smaller chunks."
        default:
            return "Unexpected error occurred."
        }
    }
}
