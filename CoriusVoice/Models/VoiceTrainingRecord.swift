import Foundation

/// A record of training data used to build a voice profile
struct VoiceTrainingRecord: Codable, Identifiable {
    let id: UUID
    let speakerID: UUID           // Link to KnownSpeaker
    let sessionID: UUID           // Session used for training
    let segmentTimestamps: [SegmentTimeRange]  // Segments used from the session
    let extractedDuration: TimeInterval        // Total audio duration used
    let trainedAt: Date
    let featuresExtracted: Bool

    // Optional metadata
    var sessionTitle: String?
    var sessionDate: Date?

    init(
        id: UUID = UUID(),
        speakerID: UUID,
        sessionID: UUID,
        segmentTimestamps: [SegmentTimeRange],
        extractedDuration: TimeInterval,
        trainedAt: Date = Date(),
        featuresExtracted: Bool = true,
        sessionTitle: String? = nil,
        sessionDate: Date? = nil
    ) {
        self.id = id
        self.speakerID = speakerID
        self.sessionID = sessionID
        self.segmentTimestamps = segmentTimestamps
        self.extractedDuration = extractedDuration
        self.trainedAt = trainedAt
        self.featuresExtracted = featuresExtracted
        self.sessionTitle = sessionTitle
        self.sessionDate = sessionDate
    }

    /// Formatted duration string
    var formattedDuration: String {
        let minutes = Int(extractedDuration) / 60
        let seconds = Int(extractedDuration) % 60
        return "\(minutes)m \(seconds)s"
    }
}

/// Represents a time range in an audio segment
struct SegmentTimeRange: Codable {
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval {
        end - start
    }
}
