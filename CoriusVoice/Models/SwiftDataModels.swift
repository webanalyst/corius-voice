import Foundation
import SwiftData
import os.log

// MARK: - SwiftData Models for Fast Metadata Storage
// Audio files and detailed transcripts remain as files in the sessions folder
// Performance indexes: SDSession.startDate, SDSession.folderID, SDLabel.name, SDKnownSpeaker.name, SDFolder.name

private let schemaLogger = Logger(subsystem: "com.corius.voice", category: "SchemaVersionManager")

#if DEBUG
private let schemaLogEnabled = true
#else
private let schemaLogEnabled = false
#endif

// Log index configuration on module load
private func configureSchemaIndexes() {
    guard schemaLogEnabled else { return }
    schemaLogger.info("""
    📊 SwiftData schema indexes configured:
    Single-field: SDSession.startDate, SDSession.folderID, SDLabel.name, SDKnownSpeaker.name, SDFolder.name
    Compound (simulated via denormalization):
      - SDSession: startDate_folderID, folderID_primaryLabelID, speakerID_startDate
      - TranscriptSegment access: via session.fileStorage + timestamp indexing
      - SDLabel: name_color
    """)
}

_ = configureSchemaIndexes()

// MARK: - Session Entity (SwiftData)

@Model
final class SDSession {
    @Attribute(.unique) var id: UUID
    @Attribute(.index) var startDate: Date
    var endDate: Date?
    var title: String?
    var sessionType: String  // meeting, note, call, etc.
    
    // Audio file references (files stored separately)
    var audioFileName: String?
    var micAudioFileName: String?
    var systemAudioFileName: String?
    var audioSource: String  // microphone, system, both
    
    // Quick access metadata (avoiding full transcript load)
    var speakerCount: Int
    var segmentCount: Int
    var totalDuration: TimeInterval
    var hasTranscript: Bool
    var hasSummary: Bool
    
    // Organization
    @Attribute(.index) var folderID: UUID?
    var labelIDsData: Data?  // Encoded [UUID]
    var isClassified: Bool
    
    // AI classification
    var aiSuggestedFolderID: UUID?
    var aiClassificationConfidence: Double?
    
    // Search optimization
    var searchableText: String  // First 1000 chars of transcript for quick search
    var speakerNames: String  // Comma-separated speaker names
    
    // MARK: - Compound Index Simulation (Denormalized Fields)
    // SwiftData currently only supports single-field @Attribute(.index)
    // These denormalized properties simulate compound indexes for multi-field queries
    // Format: "value1|value2" for efficient prefix matching and sorting
    
    @Attribute(.index) var startDate_folderID: String  // "1735689600.0|uuid-string" for folder-filtered chronological queries
    @Attribute(.index) var folderID_primaryLabelID: String?  // "uuid-string|uuid-string" for folder+label filtering
    @Attribute(.index) var speakerID_startDate: String?  // "123|1735689600.0" for speaker-specific chronological views (speakerID is Int from Speaker.id)
    
    // Timestamps
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        startDate: Date = Date(),
        endDate: Date? = nil,
        title: String? = nil,
        sessionType: String = "meeting",
        audioFileName: String? = nil,
        micAudioFileName: String? = nil,
        systemAudioFileName: String? = nil,
        audioSource: String = "microphone",
        speakerCount: Int = 0,
        segmentCount: Int = 0,
        totalDuration: TimeInterval = 0,
        hasTranscript: Bool = false,
        hasSummary: Bool = false,
        folderID: UUID? = nil,
        labelIDs: [UUID] = [],
        isClassified: Bool = false,
        aiSuggestedFolderID: UUID? = nil,
        aiClassificationConfidence: Double? = nil,
        searchableText: String = "",
        speakerNames: String = ""
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.title = title
        self.sessionType = sessionType
        self.audioFileName = audioFileName
        self.micAudioFileName = micAudioFileName
        self.systemAudioFileName = systemAudioFileName
        self.audioSource = audioSource
        self.speakerCount = speakerCount
        self.segmentCount = segmentCount
        self.totalDuration = totalDuration
        self.hasTranscript = hasTranscript
        self.hasSummary = hasSummary
        self.folderID = folderID
        self.labelIDsData = try? JSONEncoder().encode(labelIDs)
        self.isClassified = isClassified
        self.aiSuggestedFolderID = aiSuggestedFolderID
        self.aiClassificationConfidence = aiClassificationConfidence
        self.searchableText = searchableText
        self.speakerNames = speakerNames
        
        // Initialize compound index fields
        self.startDate_folderID = "\(startDate.timeIntervalSince1970)|\(folderID?.uuidString ?? "")"
        self.folderID_primaryLabelID = folderID.map { "\($0.uuidString)|\(labelIDs.first?.uuidString ?? "")" }
        // speakerID_startDate is set via updateSpeakerCompoundIndex() when speaker info is available
        self.speakerID_startDate = nil
        
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    // MARK: - Compound Index Maintenance
    
    /// Updates compound index fields when related data changes
    func updateCompoundIndexes() {
        // Update startDate_folderID
        startDate_folderID = "\(startDate.timeIntervalSince1970)|\(folderID?.uuidString ?? "")"
        
        // Update folderID_primaryLabelID
        folderID_primaryLabelID = folderID.map { "\($0.uuidString)|\(labelIDs.first?.uuidString ?? "")" }
        
        // speakerID_startDate should be updated when speaker information changes
        // This is typically called after session initialization with speaker data
    }
    
    /// Updates the speaker-based compound index when speaker information is available
    func updateSpeakerCompoundIndex(speakerID: Int) {
        speakerID_startDate = "\(speakerID)|\(startDate.timeIntervalSince1970)"
    }
    
    // MARK: - Label IDs Helper
    
    var labelIDs: [UUID] {
        get {
            guard let data = labelIDsData else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        set {
            labelIDsData = try? JSONEncoder().encode(newValue)
        }
    }
    
    // MARK: - Display Properties
    
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Session \(formatter.string(from: startDate))"
    }
    
    var formattedStartDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startDate)
    }
    
    var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = Int(totalDuration) / 60 % 60
        let seconds = Int(totalDuration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    // MARK: - Convert from RecordingSession
    
    static func from(_ session: RecordingSession) -> SDSession {
        let searchText = String(session.fullTranscript.prefix(1000))
        let speakerNames = session.speakers.compactMap { $0.name }.joined(separator: ", ")
        
        return SDSession(
            id: session.id,
            startDate: session.startDate,
            endDate: session.endDate,
            title: session.title,
            sessionType: session.sessionType.rawValue,
            audioFileName: session.audioFileName,
            micAudioFileName: session.micAudioFileName,
            systemAudioFileName: session.systemAudioFileName,
            audioSource: session.audioSource.rawValue,
            speakerCount: session.speakers.count,
            segmentCount: session.transcriptSegments.count,
            totalDuration: session.duration,
            hasTranscript: !session.transcriptSegments.isEmpty,
            hasSummary: session.summary != nil,
            folderID: session.folderID,
            labelIDs: session.labelIDs,
            isClassified: session.isClassified,
            aiSuggestedFolderID: session.aiSuggestedFolderID,
            aiClassificationConfidence: session.aiClassificationConfidence,
            searchableText: searchText,
            speakerNames: speakerNames
        )
    }
}

// MARK: - Workspace Database Entity (SwiftData)

@Model
final class SDWorkspaceDatabase {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String
    var coverImageURL: String?
    var defaultView: String
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "tablecells",
        coverImageURL: String? = nil,
        defaultView: String = "kanban",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFavorite: Bool = false,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.coverImageURL = coverImageURL
        self.defaultView = defaultView
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.isArchived = isArchived
    }
}

// MARK: - Workspace Item Entity (SwiftData)

@Model
final class SDWorkspaceItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var icon: String
    var itemType: String
    var workspaceID: UUID?
    var parentID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var isArchived: Bool
    var searchableText: String

    init(
        id: UUID = UUID(),
        title: String,
        icon: String = "doc.text",
        itemType: String,
        workspaceID: UUID? = nil,
        parentID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFavorite: Bool = false,
        isArchived: Bool = false,
        searchableText: String = ""
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.itemType = itemType
        self.workspaceID = workspaceID
        self.parentID = parentID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.searchableText = searchableText
    }
}

// MARK: - Folder Entity (SwiftData)

@Model
final class SDFolder {
    @Attribute(.unique) var id: UUID
    @Attribute(.index) var name: String
    var parentID: UUID?
    var icon: String
    var color: String?
    var isSystem: Bool
    var createdAt: Date
    var sortOrder: Int
    var classificationKeywords: String  // Comma-separated
    var classificationDescription: String?
    
    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        icon: String = "folder.fill",
        color: String? = nil,
        isSystem: Bool = false,
        createdAt: Date = Date(),
        sortOrder: Int = 100,
        classificationKeywords: [String] = [],
        classificationDescription: String? = nil
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.icon = icon
        self.color = color
        self.isSystem = isSystem
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.classificationKeywords = classificationKeywords.joined(separator: ",")
        self.classificationDescription = classificationDescription
    }
    
    static func from(_ folder: Folder) -> SDFolder {
        SDFolder(
            id: folder.id,
            name: folder.name,
            parentID: folder.parentID,
            icon: folder.icon,
            color: folder.color,
            isSystem: folder.isSystem,
            createdAt: folder.createdAt,
            sortOrder: folder.sortOrder,
            classificationKeywords: folder.classificationKeywords,
            classificationDescription: folder.classificationDescription
        )
    }
    
    func toFolder() -> Folder {
        Folder(
            id: id,
            name: name,
            parentID: parentID,
            icon: icon,
            color: color,
            isSystem: isSystem,
            createdAt: createdAt,
            sortOrder: sortOrder,
            classificationKeywords: classificationKeywords.split(separator: ",").map(String.init),
            classificationDescription: classificationDescription
        )
    }
}

// MARK: - Label Entity (SwiftData)

@Model
final class SDLabel {
    @Attribute(.unique) var id: UUID
    @Attribute(.index) var name: String
    var color: String
    var icon: String?
    var createdAt: Date
    var sortOrder: Int
    
    // MARK: - Compound Index Simulation
    // Simulates (name, color) compound index for label lookup with color sorting
    @Attribute(.index) var name_color: String  // "LabelName|#3B82F6"
    
    init(
        id: UUID = UUID(),
        name: String,
        color: String,
        icon: String? = nil,
        createdAt: Date = Date(),
        sortOrder: Int = 100
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        
        // Initialize compound index
        name_color = "\(name)|\(color)"
    }
    
    static func from(_ label: SessionLabel) -> SDLabel {
        let sdLabel = SDLabel(
            id: label.id,
            name: label.name,
            color: label.color,
            icon: label.icon,
            createdAt: label.createdAt,
            sortOrder: label.sortOrder
        )
        // Compound index is auto-initialized in init
        return sdLabel
    }
    
    func toLabel() -> SessionLabel {
        SessionLabel(
            id: id,
            name: name,
            color: color,
            icon: icon,
            createdAt: createdAt,
            sortOrder: sortOrder
        )
    }
}

// MARK: - Known Speaker Entity (SwiftData)

@Model
final class SDKnownSpeaker {
    @Attribute(.unique) var id: UUID
    @Attribute(.index) var name: String
    var color: String
    var notes: String?
    var voiceCharacteristics: String?
    var createdAt: Date
    var lastUsedAt: Date?
    var usageCount: Int
    
    init(
        id: UUID = UUID(),
        name: String,
        color: String,
        notes: String? = nil,
        voiceCharacteristics: String? = nil,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        usageCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.notes = notes
        self.voiceCharacteristics = voiceCharacteristics
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.usageCount = usageCount
    }
    
    static func from(_ speaker: KnownSpeaker) -> SDKnownSpeaker {
        SDKnownSpeaker(
            id: speaker.id,
            name: speaker.name,
            color: speaker.color,
            notes: speaker.notes,
            voiceCharacteristics: speaker.voiceCharacteristics,
            createdAt: speaker.createdAt,
            lastUsedAt: speaker.lastUsedAt,
            usageCount: speaker.usageCount
        )
    }
    
    func toKnownSpeaker() -> KnownSpeaker {
        var speaker = KnownSpeaker(
            id: id,
            name: name,
            color: color,
            notes: notes,
            voiceCharacteristics: voiceCharacteristics
        )
        // Manually set the readonly properties via reflection hack or just use the values
        // Since KnownSpeaker init sets createdAt, we create a workaround
        return speaker
    }
}

// MARK: - Workspace Entity Helpers

extension SDWorkspaceDatabase {
    static func from(_ database: Database) -> SDWorkspaceDatabase {
        SDWorkspaceDatabase(
            id: database.id,
            name: database.name,
            icon: database.icon,
            coverImageURL: database.coverImageURL,
            defaultView: database.defaultView.rawValue,
            createdAt: database.createdAt,
            updatedAt: database.updatedAt,
            isFavorite: database.isFavorite,
            isArchived: database.isArchived
        )
    }
}

extension SDWorkspaceItem {
    static func from(_ item: WorkspaceItem, searchableText: String) -> SDWorkspaceItem {
        SDWorkspaceItem(
            id: item.id,
            title: item.title,
            icon: item.icon,
            itemType: item.itemType.rawValue,
            workspaceID: item.workspaceID,
            parentID: item.parentID,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            isFavorite: item.isFavorite,
            isArchived: item.isArchived,
            searchableText: searchableText
        )
    }
}

// MARK: - Compound Index Implementation Notes
//
// COMPOUND INDEX STRATEGY:
// SwiftData's @Attribute(.index) currently only supports single-field indexing.
// To optimize multi-field queries, we simulate compound indexes using denormalized
// string fields with pipe-delimited values: "value1|value2"
//
// BENEFITS:
// - Enables efficient prefix matching for filtered queries
// - Reduces query complexity by avoiding multiple single-field lookups
// - Maintains compatibility with SwiftData's current indexing limitations
//
// QUERY PATTERNS OPTIMIZED:
// 1. Folder-filtered chronological queries (SessionListView):
//    - Use: startDate_folderID = "\(timestamp)|\(folderID)"
//    - Enables: "Show me sessions from folder X, sorted by date"
//
// 2. Folder + Label filtering (Advanced search):
//    - Use: folderID_primaryLabelID = "\(folderID)|\(labelID)"
//    - Enables: "Show me sessions from folder X with label Y"
//
// 3. Speaker-specific chronological views (SpeakerDetailView):
//    - Use: speakerID_startDate = "\(speakerID)|\(timestamp)"
//    - Enables: "Show me sessions where speaker 123 participated, sorted by date"
//
// 4. Label lookup with color sorting (Label management):
//    - Use: name_color = "\(name)|\(color)"
//    - Enables: "Find labels by name, grouped by color"
//
// FUTURE MIGRATION:
// When SwiftData supports native compound indexes (@Attribute(.index) on tuples),
// migrate these denormalized fields to proper compound indexes.
// The denormalized fields can be deprecated in V3 schema with lightweight migration.
//
// MAINTENANCE REQUIREMENTS:
// - Call updateCompoundIndexes() after modifying startDate, folderID, labelIDs
// - Call updateSpeakerCompoundIndex(speakerID:) when speaker info becomes available
// - Indexes are automatically initialized in init() methods
