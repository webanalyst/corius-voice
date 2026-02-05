import Foundation
import AVFoundation

// NOTE: AudioSource and SessionType are defined in Settings.swift to avoid circular dependencies

// MARK: - Recording Mode

enum RecordingMode: String, Codable {
    case quickCapture    // Existing: Fn hold for quick dictation
    case sessionRecording  // New: manual start/stop for long sessions
}

// MARK: - Speaker

struct Speaker: Codable, Identifiable {
    let id: Int  // Deepgram speaker ID (0, 1, 2...)
    var name: String?  // User-assigned name
    var color: String  // Hex color for UI
    var embedding: [Float]?  // 256-dim speaker embedding for voice matching

    init(id: Int, name: String? = nil, embedding: [Float]? = nil) {
        self.id = id
        self.name = name
        self.embedding = embedding
        // Assign a default color based on speaker ID
        self.color = Speaker.defaultColors[id % Speaker.defaultColors.count]
    }

    // Custom Codable for backwards compatibility
    private enum CodingKeys: String, CodingKey {
        case id, name, color, embedding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        color = try container.decode(String.self, forKey: .color)
        embedding = try container.decodeIfPresent([Float].self, forKey: .embedding)
    }

    var displayName: String {
        if let name = name {
            return name
        }
        // For system audio speakers (ID >= 1000), show the full ID for clarity
        if id >= 1000 {
            return "Speaker \(id)"
        }
        return "Speaker \(id + 1)"
    }

    static let defaultColors = [
        "#3B82F6",  // Blue
        "#10B981",  // Green
        "#F59E0B",  // Yellow
        "#EF4444",  // Red
        "#8B5CF6",  // Purple
        "#EC4899",  // Pink
        "#06B6D4",  // Cyan
        "#F97316",  // Orange
    ]
}

// MARK: - Transcript Source (for dual audio mode)

enum TranscriptSource: String, Codable {
    case microphone = "mic"      // User's voice from mic
    case system = "system"       // Remote participants from system audio
    case unknown = "unknown"     // Single source mode or unknown

    var displayName: String {
        switch self {
        case .microphone: return "Me"
        case .system: return "Others"
        case .unknown: return "Speaker"
        }
    }

    var color: String {
        switch self {
        case .microphone: return "#10B981"  // Green for "Me"
        case .system: return "#3B82F6"      // Blue for "Others"
        case .unknown: return "#6B7280"     // Gray
        }
    }
}

// MARK: - Transcript Segment

struct TranscriptSegment: Codable, Identifiable {
    let id: UUID
    var timestamp: TimeInterval  // Seconds from session start - editable
    var text: String  // Editable for corrections
    var speakerID: Int?  // Deepgram speaker ID (nil if diarization disabled) - editable for corrections
    let confidence: Double
    let isFinal: Bool
    let words: [TranscriptWord]
    var source: TranscriptSource  // Which audio source this came from

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        text: String,
        speakerID: Int? = nil,
        confidence: Double = 0,
        isFinal: Bool = true,
        words: [TranscriptWord] = [],
        source: TranscriptSource = .unknown
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.speakerID = speakerID
        self.confidence = confidence
        self.isFinal = isFinal
        self.words = words
        self.source = source
    }
}

// MARK: - Transcript Word

struct TranscriptWord: Codable {
    let word: String
    let start: TimeInterval
    let end: TimeInterval
    let confidence: Double
    let speakerID: Int?
}

// MARK: - Recording Session

struct RecordingSession: Codable, Identifiable, Hashable {
    static func == (lhs: RecordingSession, rhs: RecordingSession) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let id: UUID
    let startDate: Date
    var endDate: Date?
    var transcriptSegments: [TranscriptSegment]
    var speakers: [Speaker]
    var audioSource: AudioSource
    var title: String?
    var audioFileName: String?  // Filename of saved audio (single source mode)

    // Dual audio mode: separate files for mic and system
    var micAudioFileName: String?
    var systemAudioFileName: String?

    // Session type and AI summary
    var sessionType: SessionType = .meeting
    var summary: SessionSummary?

    // MARK: - Organization (Folders & Labels)

    /// The folder containing this session (nil = INBOX)
    var folderID: UUID?

    /// IDs of labels assigned to this session
    var labelIDs: [UUID] = []

    /// AI-suggested folder for classification (before user confirms)
    var aiSuggestedFolderID: UUID?

    /// Confidence level of AI classification (0.0 - 1.0)
    var aiClassificationConfidence: Double?

    /// Whether the user has confirmed/moved this session to a folder
    var isClassified: Bool = false

    init(
        id: UUID = UUID(),
        startDate: Date = Date(),
        endDate: Date? = nil,
        transcriptSegments: [TranscriptSegment] = [],
        speakers: [Speaker] = [],
        audioSource: AudioSource = .microphone,
        title: String? = nil,
        audioFileName: String? = nil,
        micAudioFileName: String? = nil,
        systemAudioFileName: String? = nil,
        sessionType: SessionType = .meeting,
        summary: SessionSummary? = nil,
        folderID: UUID? = nil,
        labelIDs: [UUID] = [],
        aiSuggestedFolderID: UUID? = nil,
        aiClassificationConfidence: Double? = nil,
        isClassified: Bool = false
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.transcriptSegments = transcriptSegments
        self.speakers = speakers
        self.audioSource = audioSource
        self.title = title
        self.audioFileName = audioFileName
        self.micAudioFileName = micAudioFileName
        self.systemAudioFileName = systemAudioFileName
        self.sessionType = sessionType
        self.summary = summary
        self.folderID = folderID
        self.labelIDs = labelIDs
        self.aiSuggestedFolderID = aiSuggestedFolderID
        self.aiClassificationConfidence = aiClassificationConfidence
        self.isClassified = isClassified
    }

    // MARK: - Custom Codable (for backwards compatibility)

    private enum CodingKeys: String, CodingKey {
        case id, startDate, endDate, transcriptSegments, speakers, audioSource
        case title, audioFileName, micAudioFileName, systemAudioFileName
        case sessionType, summary
        case folderID, labelIDs, aiSuggestedFolderID, aiClassificationConfidence, isClassified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required properties
        id = try container.decode(UUID.self, forKey: .id)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        transcriptSegments = try container.decode([TranscriptSegment].self, forKey: .transcriptSegments)
        speakers = try container.decode([Speaker].self, forKey: .speakers)
        audioSource = try container.decode(AudioSource.self, forKey: .audioSource)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
        micAudioFileName = try container.decodeIfPresent(String.self, forKey: .micAudioFileName)
        systemAudioFileName = try container.decodeIfPresent(String.self, forKey: .systemAudioFileName)

        // Properties with defaults for backwards compatibility
        sessionType = try container.decodeIfPresent(SessionType.self, forKey: .sessionType) ?? .meeting
        summary = try container.decodeIfPresent(SessionSummary.self, forKey: .summary)

        // Organization properties (new - provide defaults for old sessions)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        labelIDs = try container.decodeIfPresent([UUID].self, forKey: .labelIDs) ?? []
        aiSuggestedFolderID = try container.decodeIfPresent(UUID.self, forKey: .aiSuggestedFolderID)
        aiClassificationConfidence = try container.decodeIfPresent(Double.self, forKey: .aiClassificationConfidence)
        isClassified = try container.decodeIfPresent(Bool.self, forKey: .isClassified) ?? false
    }

    /// Full URL to the audio file (if exists)
    var audioFileURL: URL? {
        guard let fileName = audioFileName else { return nil }
        return Self.sessionsFolder.appendingPathComponent(fileName)
    }

    /// URL to mic audio file (dual mode)
    var micAudioFileURL: URL? {
        guard let fileName = micAudioFileName else { return nil }
        return Self.sessionsFolder.appendingPathComponent(fileName)
    }

    /// URL to system audio file (dual mode)
    var systemAudioFileURL: URL? {
        guard let fileName = systemAudioFileName else { return nil }
        return Self.sessionsFolder.appendingPathComponent(fileName)
    }

    /// Sessions folder path
    static var sessionsFolder: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("CoriusVoice/Sessions", isDirectory: true)
    }

    /// Check if audio file exists
    var hasAudioFile: Bool {
        if let url = audioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        // Check dual mode files
        if let micURL = micAudioFileURL, FileManager.default.fileExists(atPath: micURL.path) {
            return true
        }
        if let sysURL = systemAudioFileURL, FileManager.default.fileExists(atPath: sysURL.path) {
            return true
        }
        return false
    }

    /// Check if this session uses dual audio mode
    var isDualAudioMode: Bool {
        return micAudioFileName != nil || systemAudioFileName != nil
    }

    /// Returns all available audio file URLs (for dual mode may return multiple)
    var availableAudioURLs: [URL] {
        var urls: [URL] = []
        if let url = audioFileURL, FileManager.default.fileExists(atPath: url.path) {
            urls.append(url)
        }
        if let url = micAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            urls.append(url)
        }
        if let url = systemAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            urls.append(url)
        }
        return urls
    }

    /// Returns the primary audio URL (for compatibility - prefers system audio for voice training)
    var primaryAudioFileURL: URL? {
        // For single mode, return the single file
        if let url = audioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // For dual mode, prefer system audio (has other speakers for training)
        if let url = systemAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        // Fall back to mic audio
        if let url = micAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    // MARK: - Computed Properties

    /// Duration based on transcript timestamps (more accurate than session time)
    var duration: TimeInterval {
        // First, try to get duration from the last transcript segment
        if let lastSegment = transcriptSegments.last {
            // Get the end time of the last segment
            if let lastWord = lastSegment.words.last {
                return lastWord.end
            }
            // Fallback: use timestamp + estimated duration
            return lastSegment.timestamp + 5.0  // Add buffer for segment duration
        }
        
        // Fallback to session time difference
        let end = endDate ?? Date()
        return end.timeIntervalSince(startDate)
    }
    
    /// Get actual audio file duration using AVFoundation
    var audioDuration: TimeInterval? {
        guard let url = primaryAudioFileURL ?? micAudioFileURL ?? systemAudioFileURL ?? audioFileURL else {
            return nil
        }
        return RecordingSession.getAudioDuration(url: url)
    }
    
    /// Helper to get audio duration from file
    static func getAudioDuration(url: URL) -> TimeInterval? {
        // Try ffprobe first (more reliable for various formats)
        if let duration = getAudioDurationWithFFprobe(url: url) {
            return duration
        }
        
        // Fallback to AVAsset
        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        return duration.isNaN || duration <= 0 ? nil : duration
    }
    
    /// Get duration using ffprobe (handles WebM, OGG, etc.)
    private static func getAudioDurationWithFFprobe(url: URL) -> TimeInterval? {
        let ffprobePaths = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        
        guard let ffprobePath = ffprobePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
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
            // Silently fail
        }
        
        return nil
    }

    var formattedDuration: String {
        // Prefer audio duration if available
        let dur = audioDuration ?? duration
        let hours = Int(dur) / 3600
        let minutes = (Int(dur) % 3600) / 60
        let seconds = Int(dur) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var formattedStartDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startDate)
    }

    var fullTranscript: String {
        transcriptSegments
            .filter { $0.isFinal }
            .map { $0.text }
            .joined(separator: " ")
    }

    var wordCount: Int {
        fullTranscript.split(separator: " ").count
    }
    
    /// Number of unique speakers (by name, not by ID)
    var uniqueSpeakerCount: Int {
        let uniqueNames = Set(speakers.map { $0.name ?? $0.displayName })
        return uniqueNames.count
    }

    var displayTitle: String {
        title ?? "Session \(formattedStartDate)"
    }

    var isRecording: Bool {
        endDate == nil
    }

    // MARK: - Speaker Management

    mutating func updateSpeakerName(speakerID: Int, name: String) {
        if let index = speakers.firstIndex(where: { $0.id == speakerID }) {
            speakers[index].name = name
        }
    }

    mutating func ensureSpeakerExists(speakerID: Int, source: TranscriptSource = .unknown) {
        if !speakers.contains(where: { $0.id == speakerID }) {
            // Assign a default name based on the source for better UX
            let defaultName: String?
            switch source {
            case .microphone:
                defaultName = "Me"
            case .system:
                // For system audio, use "Speaker N" based on the original Deepgram ID
                let originalID = speakerID >= 1000 ? speakerID - 1000 : speakerID
                defaultName = originalID == 0 ? nil : nil  // Let it use default "Speaker N"
            case .unknown:
                defaultName = nil
            }
            speakers.append(Speaker(id: speakerID, name: defaultName))
        }
    }

    func speaker(for id: Int?) -> Speaker? {
        guard let id = id else { return nil }
        return speakers.first(where: { $0.id == id })
    }

    // MARK: - Transcript Editing

    mutating func updateSegmentText(segmentID: UUID, newText: String) {
        if let index = transcriptSegments.firstIndex(where: { $0.id == segmentID }) {
            transcriptSegments[index].text = newText
        }
    }

    /// Update the timestamp of a segment
    mutating func updateSegmentTimestamp(segmentID: UUID, newTimestamp: TimeInterval) {
        if let index = transcriptSegments.firstIndex(where: { $0.id == segmentID }) {
            transcriptSegments[index].timestamp = newTimestamp
        }
    }

    /// Change the speaker of a segment
    mutating func updateSegmentSpeaker(segmentID: UUID, newSpeakerID: Int?) {
        if let index = transcriptSegments.firstIndex(where: { $0.id == segmentID }) {
            transcriptSegments[index].speakerID = newSpeakerID
            // Ensure the speaker exists
            if let speakerID = newSpeakerID {
                ensureSpeakerExists(speakerID: speakerID)
            }
        }
    }

    /// Insert a new manual transcript segment
    mutating func insertSegment(text: String, timestamp: TimeInterval, speakerID: Int?, source: TranscriptSource = .unknown) {
        let segment = TranscriptSegment(
            timestamp: timestamp,
            text: text,
            speakerID: speakerID,
            confidence: 1.0,  // Manual entry = 100% confidence
            isFinal: true,
            words: [],
            source: source
        )
        transcriptSegments.append(segment)

        // Ensure the speaker exists
        if let speakerID = speakerID {
            ensureSpeakerExists(speakerID: speakerID)
        }
    }

    /// Delete a segment
    mutating func deleteSegment(segmentID: UUID) {
        transcriptSegments.removeAll { $0.id == segmentID }
    }
}

