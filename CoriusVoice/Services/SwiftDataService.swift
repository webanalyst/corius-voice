import Foundation
import SwiftData
import os.log
#if canImport(AppKit)
import AppKit
#endif

// Transcript search index for fast full-text search (accessed via shared singleton)
// Note: Incremental index updates are now called via TranscriptSearchIndex.shared

// MARK: - SwiftData Service
// Provides fast metadata access via SwiftData while keeping full data in JSON files
// Integrated with versioned schema management and caching layers for optimal performance

@MainActor
final class SwiftDataService {
    static let shared = SwiftDataService()
    
    private let logger = Logger(subsystem: "com.corius.voice", category: "SwiftData")
    
    let modelContainer: ModelContainer
    let modelContext: ModelContext
    
    // MARK: - Cache and Index Services
    
    private let sessionIndex = SessionIndexService.shared
    private let sessionCache = SessionCacheService.shared
    private let queryCache = SessionQueryCache.shared
    private let metrics = CacheMetrics.shared
    
    private init() {
        do {
            // Use versioned schema from SchemaVersionManager
            let schemaVersionManager = SchemaVersionManager.shared
            schemaVersionManager.checkSchemaVersion(onLaunch: true)
            
            let schema = schemaVersionManager.getCurrentSchema()
            
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            
            modelContainer = try ModelContainer.createWithVersionedSchema()
            modelContext = modelContainer.mainContext
            modelContext.autosaveEnabled = true
            
            logger.info("✅ SwiftData initialized successfully with schema V\(schemaVersionManager.currentSchemaVersion.rawValue)")
            
            // Log migration statistics for debugging
            schemaVersionManager.logMigrationStatistics()
        } catch {
            logger.error("❌ Failed to initialize SwiftData: \(error.localizedDescription)")
            fatalError("Failed to initialize SwiftData: \(error)")
        }
    }
    
    // MARK: - Migration from JSON
    
    private var hasMigrated: Bool {
        get { UserDefaults.standard.bool(forKey: "swiftdata_migration_complete_v1") }
        set { UserDefaults.standard.set(newValue, forKey: "swiftdata_migration_complete_v1") }
    }

    private var hasMigratedWorkspace: Bool {
        get { UserDefaults.standard.bool(forKey: "swiftdata_workspace_migration_complete_v1") }
        set { UserDefaults.standard.set(newValue, forKey: "swiftdata_workspace_migration_complete_v1") }
    }
    
    func migrateFromJSONIfNeeded() async {
        // Check schema version before migration
        let schemaVersionManager = SchemaVersionManager.shared
        schemaVersionManager.checkSchemaVersion(onLaunch: true)
        
        guard !hasMigrated else {
            logger.info("📦 SwiftData already migrated")
            return
        }
        
        logger.info("📦 Starting SwiftData migration from JSON...")
        
        do {
            await migrateFolders()
            await migrateLabels()
            await migrateSessions()
            await migrateSpeakers()
            await migrateWorkspace()
            
            hasMigrated = true
            
            // Mark schema migration as complete
            schemaVersionManager.markMigrationComplete(to: .v1)
            
            // Perform post-migration tasks (rebuild indexes)
            try await schemaVersionManager.performPostMigrationTasks(
                fromVersion: 0,
                toVersion: schemaVersionManager.currentSchemaVersion.rawValue
            )
            
            // Rebuild transcript search index after migration
            await rebuildTranscriptSearchIndex()
            
            logger.info("✅ SwiftData migration complete with schema V\(schemaVersionManager.currentSchemaVersion.rawValue)")
        } catch {
            logger.error("❌ Migration failed: \(error.localizedDescription)")
            schemaVersionManager.handleMigrationError(
                error,
                fromVersion: 0,
                toVersion: schemaVersionManager.currentSchemaVersion.rawValue
            )
        }
    }

    func migrateWorkspaceIfNeeded() async {
        guard !hasMigratedWorkspace else { return }
        
        do {
            await migrateWorkspace()
            hasMigratedWorkspace = true
            logger.info("✅ Workspace migration complete")
        } catch {
            logger.error("❌ Workspace migration failed: \(error.localizedDescription)")
        }
    }
    
    private func migrateFolders() async {
        let folders = StorageService.shared.loadFolders()
        logger.info("📁 Migrating \(folders.count) folders...")
        
        for folder in folders {
            let sdFolder = SDFolder.from(folder)
            modelContext.insert(sdFolder)
        }
        
        try? modelContext.save()
    }
    
    private func migrateLabels() async {
        let labels = StorageService.shared.loadLabels()
        logger.info("🏷️ Migrating \(labels.count) labels...")
        
        for label in labels {
            let sdLabel = SDLabel.from(label)
            modelContext.insert(sdLabel)
        }
        
        try? modelContext.save()
    }
    
    private func migrateSessions() async {
        let sessions = StorageService.shared.loadSessionsFromDisk()
        logger.info("📝 Migrating \(sessions.count) sessions...")
        
        for session in sessions {
            let sdSession = SDSession.from(session)
            modelContext.insert(sdSession)
        }
        
        try? modelContext.save()
    }
    
    private func migrateSpeakers() async {
        let library = StorageService.shared.loadSpeakerLibrary()
        logger.info("🎤 Migrating \(library.speakers.count) speakers...")
        
        for speaker in library.speakers {
            let sdSpeaker = SDKnownSpeaker.from(speaker)
            modelContext.insert(sdSpeaker)
        }
        
        try? modelContext.save()
    }

    private func migrateWorkspace() async {
        guard !hasMigratedWorkspace else { return }
        let storage = WorkspaceStorageServiceOptimized.shared
        logger.info("🧱 Migrating \(storage.databases.count) workspace databases...")
        for database in storage.databases {
            modelContext.insert(SDWorkspaceDatabase.from(database))
        }
        logger.info("🧱 Migrating \(storage.items.count) workspace items...")
        for item in storage.items {
            let text = searchableText(for: item, storage: storage)
            modelContext.insert(SDWorkspaceItem.from(item, searchableText: text))
        }
        try? modelContext.save()
        hasMigratedWorkspace = true
        logger.info("✅ Workspace migration complete")
    }

    // MARK: - Workspace Operations

    func fetchWorkspaceDatabases() -> [SDWorkspaceDatabase] {
        let descriptor = FetchDescriptor<SDWorkspaceDatabase>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchWorkspaceItems() -> [SDWorkspaceItem] {
        let descriptor = FetchDescriptor<SDWorkspaceItem>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func getWorkspaceDatabase(id: UUID) -> SDWorkspaceDatabase? {
        let predicate = #Predicate<SDWorkspaceDatabase> { $0.id == id }
        let descriptor = FetchDescriptor<SDWorkspaceDatabase>(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }

    func getWorkspaceItem(id: UUID) -> SDWorkspaceItem? {
        let predicate = #Predicate<SDWorkspaceItem> { $0.id == id }
        let descriptor = FetchDescriptor<SDWorkspaceItem>(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }

    func syncWorkspaceDatabase(_ database: Database) {
        if let existing = getWorkspaceDatabase(id: database.id) {
            existing.name = database.name
            existing.icon = database.icon
            existing.coverImageURL = database.coverImageURL
            existing.defaultView = database.defaultView.rawValue
            existing.createdAt = database.createdAt
            existing.updatedAt = database.updatedAt
            existing.isFavorite = database.isFavorite
            existing.isArchived = database.isArchived
        } else {
            modelContext.insert(SDWorkspaceDatabase.from(database))
        }
        try? modelContext.save()
    }

    func syncWorkspaceItem(_ item: WorkspaceItem) {
        let storage = WorkspaceStorageServiceOptimized.shared
        let text = searchableText(for: item, storage: storage)
        if let existing = getWorkspaceItem(id: item.id) {
            existing.title = item.title
            existing.icon = item.icon
            existing.itemType = item.itemType.rawValue
            existing.workspaceID = item.workspaceID
            existing.parentID = item.parentID
            existing.createdAt = item.createdAt
            existing.updatedAt = item.updatedAt
            existing.isFavorite = item.isFavorite
            existing.isArchived = item.isArchived
            existing.searchableText = text
        } else {
            modelContext.insert(SDWorkspaceItem.from(item, searchableText: text))
        }
        try? modelContext.save()
    }

    func deleteWorkspaceDatabase(id: UUID) {
        if let database = getWorkspaceDatabase(id: id) {
            modelContext.delete(database)
            try? modelContext.save()
        }
    }

    func deleteWorkspaceItem(id: UUID) {
        if let item = getWorkspaceItem(id: id) {
            modelContext.delete(item)
            try? modelContext.save()
        }
    }

    func searchWorkspaceItems(query: String) -> [SDWorkspaceItem] {
        let lowered = query.lowercased()
        let predicate = #Predicate<SDWorkspaceItem> { item in
            item.searchableText.localizedStandardContains(lowered) ||
            item.title.localizedStandardContains(lowered)
        }
        let descriptor = FetchDescriptor<SDWorkspaceItem>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    // MARK: - Session Operations (Fast Queries)
    
    /// Fetch sessions with pagination and optional transcript inclusion
    /// - Parameters:
    ///   - folderID: Optional folder filter
    ///   - labelID: Optional label filter
    ///   - fetchLimit: Maximum number of sessions to return
    ///   - fetchOffset: Number of sessions to skip
    ///   - includeTranscript: Whether to include transcript bodies (default: false for performance)
    /// - Returns: Array of SDSession objects
    func fetchSessions(
        folderID: UUID? = nil,
        labelID: UUID? = nil,
        fetchLimit: Int? = nil,
        fetchOffset: Int = 0,
        includeTranscript: Bool = false
    ) -> [SDSession] {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        var descriptor = FetchDescriptor<SDSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        
        // Apply predicates based on filters
        if let folderID = folderID {
            if folderID == Folder.inboxID {
                descriptor.predicate = #Predicate<SDSession> { $0.folderID == nil }
            } else {
                descriptor.predicate = #Predicate<SDSession> { $0.folderID == folderID }
            }
        } else if let labelID = labelID {
            // For label filtering, we need to fetch all and filter in memory
            // TODO: Optimize when SwiftData supports array contains predicates
            let all = fetchAllSessions()
            let filtered = all.filter { $0.labelIDs.contains(labelID) }
            let start = filtered.index(filtered.startIndex, offsetBy: min(fetchOffset, filtered.count))
            let end = filtered.index(filtered.startIndex, offsetBy: min(fetchOffset + (fetchLimit ?? filtered.count), filtered.count))
            return Array(filtered[start..<end])
        }
        
        descriptor.fetchOffset = fetchOffset
        if let limit = fetchLimit {
            descriptor.fetchLimit = limit
        }
        
        let result = (try? modelContext.fetch(descriptor)) ?? []
        
        let queryTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        if queryTime > 100 {
            logger.warning("⚠️ fetchSessions exceeded 100ms: \(String(format: "%.1f", queryTime))ms")
        }
        
        // Note: SwiftData uses faulting by default, so transcript bodies won't load
        // unless explicitly accessed. The includeTranscript parameter is for documentation
        // and future use when we implement manual fault control.
        
        return result
    }
    
    func fetchAllSessions() -> [SDSession] {
        let descriptor = FetchDescriptor<SDSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func fetchRecentSessions(limit: Int = 20) -> [SDSession] {
        var descriptor = FetchDescriptor<SDSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func fetchSessions(inFolder folderID: UUID) -> [SDSession] {
        return fetchSessions(folderID: folderID)
    }
    
    func fetchSessions(withLabel labelID: UUID) -> [SDSession] {
        return fetchSessions(labelID: labelID)
    }
    
    func fetchUnclassifiedSessions() -> [SDSession] {
        let predicate = #Predicate<SDSession> { $0.folderID == nil && !$0.isClassified }
        let descriptor = FetchDescriptor<SDSession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func searchSessions(query: String) -> [SDSession] {
        let lowercaseQuery = query.lowercased()
        let predicate = #Predicate<SDSession> { session in
            session.searchableText.localizedStandardContains(lowercaseQuery) ||
            session.speakerNames.localizedStandardContains(lowercaseQuery) ||
            (session.title ?? "").localizedStandardContains(lowercaseQuery)
        }
        let descriptor = FetchDescriptor<SDSession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func getSession(id: UUID) -> SDSession? {
        let predicate = #Predicate<SDSession> { $0.id == id }
        let descriptor = FetchDescriptor<SDSession>(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }
    
    func insertSession(_ session: RecordingSession) {
        let startTime = Date()
        let sdSession = SDSession.from(session)
        modelContext.insert(sdSession)
        try? modelContext.save()
        
        // Incremental index update (non-blocking, uses new async API)
        Task.detached(priority: .utility) {
            await TranscriptSearchIndex.shared.indexTranscript(
                for: session.id,
                segments: session.transcriptSegments
            )
            
            let duration = Date().timeIntervalSince(startTime)
            await MainActor.run {
                if duration > 0.05 {
                    self.logger.warning("⚠️ Session insert + indexing took \(String(format: "%.0f", duration * 1000))ms")
                } else {
                    self.logger.debug("📝 Inserted session \(session.id) in \(String(format: "%.2f", duration))s")
                }
            }
        }
    }
    
    func updateSession(_ session: RecordingSession) {
        if let existing = getSession(id: session.id) {
            existing.startDate = session.startDate
            existing.endDate = session.endDate
            existing.title = session.title
            existing.sessionType = session.sessionType.rawValue
            existing.audioFileName = session.audioFileName
            existing.micAudioFileName = session.micAudioFileName
            existing.systemAudioFileName = session.systemAudioFileName
            existing.audioSource = session.audioSource.rawValue
            existing.speakerCount = session.speakers.count
            existing.segmentCount = session.transcriptSegments.count
            existing.totalDuration = session.duration
            existing.hasTranscript = !session.transcriptSegments.isEmpty
            existing.hasSummary = session.summary != nil
            existing.folderID = session.folderID
            existing.labelIDs = session.labelIDs
            existing.isClassified = session.isClassified
            existing.aiSuggestedFolderID = session.aiSuggestedFolderID
            existing.aiClassificationConfidence = session.aiClassificationConfidence
            existing.searchableText = String(session.fullTranscript.prefix(1000))
            existing.speakerNames = session.speakers.compactMap { $0.name }.joined(separator: ", ")
            existing.updatedAt = Date()
            
            try? modelContext.save()
            
            // Incremental index update with debouncing (non-blocking, uses new async API)
            Task.detached(priority: .utility) {
                await TranscriptSearchIndex.shared.updateTranscript(
                    for: session.id,
                    segments: session.transcriptSegments
                )
                await MainActor.run {
                    self.logger.debug("📝 Updated session \(session.id) and queued debounced index refresh")
                }
            }
        } else {
            insertSession(session)
        }
    }
    
    func deleteSession(id: UUID) {
        let startTime = Date()
        if let session = getSession(id: id) {
            modelContext.delete(session)
            try? modelContext.save()
            
            // Remove from search index before deletion (non-blocking, uses new async API)
            Task.detached(priority: .utility) {
                await TranscriptSearchIndex.shared.removeTranscript(for: id)
                
                let duration = Date().timeIntervalSince(startTime)
                await MainActor.run {
                    self.logger.info("🗑️ Deleted session \(id) and removed from search index in \(String(format: "%.2f", duration))s")
                }
            }
        }
    }

    /// Remove duplicate sessions based on shared audio filenames.
    /// Returns the number of SwiftData sessions removed.
    func removeDuplicateSessionsByAudioFiles() -> Int {
        let sessions = fetchAllSessions()
        guard !sessions.isEmpty else { return 0 }

        var groups: [String: [SDSession]] = [:]
        for session in sessions {
            for key in audioFileKeys(for: session) {
                groups[key, default: []].append(session)
            }
        }

        var keepIDs = Set<UUID>()
        var deleteCandidates = Set<UUID>()

        for (_, group) in groups where group.count > 1 {
            let sorted = group.sorted { isBetterSession($0, $1) }
            if let keep = sorted.first {
                keepIDs.insert(keep.id)
            }
            for session in sorted.dropFirst() {
                deleteCandidates.insert(session.id)
            }
        }

        let deleteIDs = deleteCandidates.subtracting(keepIDs)
        guard !deleteIDs.isEmpty else { return 0 }

        // Batch remove from search index for efficiency (non-blocking)
        Task { @MainActor in
            let batchStartTime = Date()
            for id in deleteIDs {
                searchIndex.removeFromIndex(sessionID: id)
            }
            let batchDuration = Date().timeIntervalSince(batchStartTime)
            logger.info("🗑️ Batch removed \(deleteIDs.count) sessions from search index in \(String(format: "%.2f", batchDuration))s")
        }

        for id in deleteIDs {
            if let session = getSession(id: id) {
                modelContext.delete(session)
            }
        }
        try? modelContext.save()
        logger.info("🧹 Removed \(deleteIDs.count) duplicate session(s) from SwiftData")
        return deleteIDs.count
    }
    
    // MARK: - Folder Operations
    
    func fetchAllFolders() -> [SDFolder] {
        let descriptor = FetchDescriptor<SDFolder>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func getFolder(id: UUID) -> SDFolder? {
        let predicate = #Predicate<SDFolder> { $0.id == id }
        let descriptor = FetchDescriptor<SDFolder>(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }
    
    func insertFolder(_ folder: Folder) {
        let sdFolder = SDFolder.from(folder)
        modelContext.insert(sdFolder)
        try? modelContext.save()
        logger.info("📁 Inserted folder: \(folder.name)")
    }
    
    func updateFolder(_ folder: Folder) {
        if let existing = getFolder(id: folder.id) {
            existing.name = folder.name
            existing.parentID = folder.parentID
            existing.icon = folder.icon
            existing.color = folder.color
            existing.sortOrder = folder.sortOrder
            existing.classificationKeywords = folder.classificationKeywords.joined(separator: ",")
            existing.classificationDescription = folder.classificationDescription
            
            try? modelContext.save()
            logger.info("📁 Updated folder: \(folder.name)")
        } else {
            insertFolder(folder)
        }
    }
    
    func deleteFolder(id: UUID) {
        if let folder = getFolder(id: id) {
            modelContext.delete(folder)
            try? modelContext.save()
            logger.info("🗑️ Deleted folder: \(id)")
        }
    }
    
    // MARK: - Label Operations
    
    func fetchAllLabels() -> [SDLabel] {
        let descriptor = FetchDescriptor<SDLabel>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func getLabel(id: UUID) -> SDLabel? {
        let predicate = #Predicate<SDLabel> { $0.id == id }
        let descriptor = FetchDescriptor<SDLabel>(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }
    
    func insertLabel(_ label: SessionLabel) {
        let sdLabel = SDLabel.from(label)
        modelContext.insert(sdLabel)
        try? modelContext.save()
        logger.info("🏷️ Inserted label: \(label.name)")
    }
    
    func updateLabel(_ label: SessionLabel) {
        if let existing = getLabel(id: label.id) {
            existing.name = label.name
            existing.color = label.color
            existing.icon = label.icon
            existing.sortOrder = label.sortOrder
            
            try? modelContext.save()
            logger.info("🏷️ Updated label: \(label.name)")
        } else {
            insertLabel(label)
        }
    }
    
    func deleteLabel(id: UUID) {
        if let label = getLabel(id: id) {
            modelContext.delete(label)
            try? modelContext.save()
            logger.info("🗑️ Deleted label: \(id)")
        }
    }
    
    // MARK: - Speaker Operations
    
    func fetchAllSpeakers() -> [SDKnownSpeaker] {
        let descriptor = FetchDescriptor<SDKnownSpeaker>(
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func getSpeaker(id: UUID) -> SDKnownSpeaker? {
        let predicate = #Predicate<SDKnownSpeaker> { $0.id == id }
        let descriptor = FetchDescriptor<SDKnownSpeaker>(predicate: predicate)
        return try? modelContext.fetch(descriptor).first
    }
    
    func insertSpeaker(_ speaker: KnownSpeaker) {
        let sdSpeaker = SDKnownSpeaker.from(speaker)
        modelContext.insert(sdSpeaker)
        try? modelContext.save()
        logger.info("🎤 Inserted speaker: \(speaker.name)")
    }
    
    func updateSpeaker(_ speaker: KnownSpeaker) {
        if let existing = getSpeaker(id: speaker.id) {
            existing.name = speaker.name
            existing.color = speaker.color
            existing.notes = speaker.notes
            existing.voiceCharacteristics = speaker.voiceCharacteristics
            existing.lastUsedAt = speaker.lastUsedAt
            existing.usageCount = speaker.usageCount
            
            try? modelContext.save()
            logger.info("🎤 Updated speaker: \(speaker.name)")
        } else {
            insertSpeaker(speaker)
        }
    }
    
    func deleteSpeaker(id: UUID) {
        if let speaker = getSpeaker(id: id) {
            modelContext.delete(speaker)
            try? modelContext.save()
            logger.info("🗑️ Deleted speaker: \(id)")
        }
    }
    
    // MARK: - Statistics (Fast)
    
    func getSessionCount() -> Int {
        let descriptor = FetchDescriptor<SDSession>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
    
    func getSessionCount(inFolder folderID: UUID) -> Int {
        let predicate = #Predicate<SDSession> { $0.folderID == folderID }
        let descriptor = FetchDescriptor<SDSession>(predicate: predicate)
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
    
    func getTotalDuration() -> TimeInterval {
        let sessions = fetchAllSessions()
        return sessions.reduce(0) { $0 + $1.totalDuration }
    }
    
    // MARK: - Sync with StorageService
    
    /// Call this after StorageService saves to keep SwiftData in sync
    func syncSession(_ session: RecordingSession) {
        updateSession(session)
    }
    
    func syncFolder(_ folder: Folder) {
        updateFolder(folder)
    }
    
    func syncLabel(_ label: SessionLabel) {
        updateLabel(label)
    }
    
    func syncSpeaker(_ speaker: KnownSpeaker) {
        updateSpeaker(speaker)
    }
}

private extension SwiftDataService {
    func audioFileKeys(for session: SDSession) -> Set<String> {
        var keys = Set<String>()
        if let file = session.audioFileName { keys.insert(file) }
        if let file = session.micAudioFileName { keys.insert(file) }
        if let file = session.systemAudioFileName { keys.insert(file) }
        return keys
    }

    func isBetterSession(_ lhs: SDSession, _ rhs: SDSession) -> Bool {
        if lhs.hasTranscript != rhs.hasTranscript {
            return lhs.hasTranscript && !rhs.hasTranscript
        }
        if lhs.hasSummary != rhs.hasSummary {
            return lhs.hasSummary && !rhs.hasSummary
        }
        if lhs.segmentCount != rhs.segmentCount {
            return lhs.segmentCount > rhs.segmentCount
        }
        if lhs.totalDuration != rhs.totalDuration {
            return lhs.totalDuration > rhs.totalDuration
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}

// MARK: - Workspace Search Helpers

private extension SwiftDataService {
    func searchableText(for item: WorkspaceItem, storage: WorkspaceStorageServiceOptimized) -> String {
        var parts: [String] = [item.title]
        parts.append(contentsOf: propertySearchParts(for: item, storage: storage))
        parts.append(contentsOf: blockSearchParts(item.blocks))
        return normalizeSearchText(parts.joined(separator: " "))
    }

    func propertySearchParts(for item: WorkspaceItem, storage: WorkspaceStorageServiceOptimized) -> [String] {
        var parts: [String] = []
        let database = item.workspaceID.flatMap { storage.database(withID: $0) }
        let definitions = database?.properties ?? []

        for (key, value) in item.properties {
            if let definition = definitions.first(where: { $0.storageKey == key || PropertyDefinition.legacyKey(for: $0.name) == key }) {
                parts.append(definition.name)
                appendPropertyValue(value, to: &parts, storage: storage)
            } else {
                parts.append(key)
                appendPropertyValue(value, to: &parts, storage: storage)
            }
        }

        if let database {
            for definition in database.properties where definition.type == .rollup || definition.type == .formula {
                let value = PropertyValueResolver.value(for: item, definition: definition, database: database, storage: storage)
                guard !value.isEmpty else { continue }
                parts.append(definition.name)
                parts.append(value.displayValue)
            }
        }

        return parts
    }

    func appendPropertyValue(_ value: PropertyValue, to parts: inout [String], storage: WorkspaceStorageServiceOptimized) {
        switch value {
        case .relation(let id):
            if let related = storage.item(withID: id) {
                parts.append(related.title)
            } else {
                parts.append(value.displayValue)
            }
        case .relations(let ids):
            if ids.isEmpty {
                parts.append(value.displayValue)
            } else {
                for id in ids {
                    if let related = storage.item(withID: id) {
                        parts.append(related.title)
                    }
                }
            }
        default:
            parts.append(value.displayValue)
        }
    }

    func blockSearchParts(_ blocks: [Block]) -> [String] {
        var parts: [String] = []
        for block in blocks {
            if !block.content.isEmpty {
                parts.append(block.content)
            }
            if let richText = decodeRichText(block.richTextData) {
                parts.append(richText)
            }
            if let url = block.url {
                parts.append(url)
            }
            if !block.children.isEmpty {
                parts.append(contentsOf: blockSearchParts(block.children))
            }
        }
        return parts
    }

    func decodeRichText(_ data: Data?) -> String? {
#if canImport(AppKit)
        guard let data else { return nil }
        if let attributed = try? NSAttributedString(rtfd: data, documentAttributes: nil) {
            return attributed.string
        }
#endif
        return nil
    }

    func normalizeSearchText(_ text: String) -> String {
        let components = text.components(separatedBy: .whitespacesAndNewlines)
        return components.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
