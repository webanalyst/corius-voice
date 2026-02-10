import Foundation
import Combine
import SwiftData

// MARK: - Folder Tree View Model

@MainActor
class FolderTreeViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var folders: [Folder] = []
    @Published var labels: [SessionLabel] = []
    @Published var sessions: [RecordingSession] = []
    @Published var sessionMetadata: [SDSession] = []  // Fast metadata from SwiftData
    @Published var isLoading: Bool = false
    @Published var hasLoadedOnce: Bool = false
    @Published var hasDiskSessions: Bool = true

    @Published var selectedFolderID: UUID? = nil
    @Published var selectedLabelID: UUID? = nil

    @Published var expandedFolderIDs: Set<UUID> = []

    @Published var isEditingFolder: Bool = false
    @Published var editingFolder: Folder? = nil

    @Published var isEditingLabel: Bool = false
    @Published var editingLabel: SessionLabel? = nil

    // MARK: - Private Properties

    private let storage = StorageService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Cache services
    private let sessionCache = SessionCacheService.shared
    private let sessionIndex = SessionIndexService.shared
    private let queryCache = SessionQueryCache.shared
    private let metrics = CacheMetrics.shared

    // MARK: - Initialization

    init() {
        // Set default selection immediately
        _selectedFolderID = Published(initialValue: Folder.inboxID)
        // Load data from cache (fast)
        loadDataFromCache()
    }
    
    // MARK: - Data Loading
    
    /// Fast load from cache - called in init
    private func loadDataFromCache() {
        // Load folders and labels from JSON (small files, fast)
        folders = storage.loadFolders()
        labels = storage.loadLabels()
        
        // Try to load session metadata from SwiftData (fast)
        sessionMetadata = SwiftDataService.shared.fetchAllSessions()
        
        // If SwiftData has data, use it for counts - DON'T load full sessions yet
        if !sessionMetadata.isEmpty {
            // SwiftData is ready - we have fast metadata for counts and list display
            print("[FolderTreeViewModel] ⚡ Loaded \(sessionMetadata.count) sessions from SwiftData (fast)")
            // Don't load full sessions until needed
            refreshDiskSessionStatus()
        } else {
            // No SwiftData - fall back to JSON sessions
            sessions = storage.loadSessions()
            hasDiskSessions = !sessions.isEmpty
            print("[FolderTreeViewModel] 📂 Loaded \(sessions.count) sessions from JSON")
        }
        
        hasLoadedOnce = true
        
        // Auto-expand root folders
        if expandedFolderIDs.isEmpty {
            expandedFolderIDs = Set(folders.filter { $0.parentID == nil }.map { $0.id })
        }
    }

    func loadData() {
        guard !isLoading else { return }
        isLoading = true
        
        folders = storage.loadFolders()
        labels = storage.loadLabels()
        
        // Try SwiftData first for metadata
        sessionMetadata = SwiftDataService.shared.fetchAllSessions()
        if sessionMetadata.isEmpty {
            // Fall back to JSON
            sessions = storage.loadSessions()
            hasDiskSessions = !sessions.isEmpty
        } else {
            refreshDiskSessionStatus()
        }
        
        hasLoadedOnce = true
        isLoading = false

        let count = !sessionMetadata.isEmpty ? sessionMetadata.count : sessions.count
        print("[FolderTreeViewModel] 📂 Loaded \(folders.count) folders, \(labels.count) labels, \(count) sessions")

        // Auto-expand root folders by default (only if not already set)
        if expandedFolderIDs.isEmpty {
            expandedFolderIDs = Set(folders.filter { $0.parentID == nil }.map { $0.id })
        }
    }

    func reloadSessions() {
        sessionMetadata = SwiftDataService.shared.fetchAllSessions()
        if sessionMetadata.isEmpty {
            sessions = storage.loadSessions()
            hasDiskSessions = !sessions.isEmpty
        } else {
            refreshDiskSessionStatus()
        }
    }

    // MARK: - Computed Properties
    
    /// Check if we're using SwiftData metadata
    private var useSwiftData: Bool {
        !sessionMetadata.isEmpty
    }

    /// Sessions filtered by current selection
    var filteredSessions: [RecordingSession] {
        // Keep computed properties side-effect free to avoid view update cycles.
        return filterSessions(sessions)
    }
    
    /// Helper to filter sessions by current selection
    private func filterSessions(_ sessionsToFilter: [RecordingSession]) -> [RecordingSession] {
        if let labelID = selectedLabelID {
            return sessionsToFilter.filter { $0.labelIDs.contains(labelID) }
                .sorted { $0.startDate > $1.startDate }
        }

        if let folderID = selectedFolderID {
            if folderID == Folder.inboxID {
                // INBOX shows sessions with nil folderID
                return sessionsToFilter.filter { $0.folderID == nil }
                    .sorted { $0.startDate > $1.startDate }
            }
            // Include sessions from this folder and optionally descendants
            let folderIDs = Set([folderID] + folders.descendants(of: folderID).map { $0.id })
            return sessionsToFilter.filter { session in
                if let sessionFolderID = session.folderID {
                    return folderIDs.contains(sessionFolderID)
                }
                return false
            }.sorted { $0.startDate > $1.startDate }
        }

        // Default: show all sessions
        return sessionsToFilter.sorted { $0.startDate > $1.startDate }
    }

    /// Count of sessions in a specific folder (including subfolders)
    func sessionCount(for folderID: UUID) -> Int {
        // Try cache first (O(1) lookup)
        if useSwiftData {
            if let cachedCount = sessionCache.getFolderCount(folderID) {
                metrics.recordFolderCountHit()
                return cachedCount
            }
            metrics.recordFolderCountMiss()
        }
        
        // Use SwiftData metadata if available (fast)
        if useSwiftData {
            let count: Int
            if folderID == Folder.inboxID {
                count = sessionMetadata.filter { $0.folderID == nil }.count
            } else {
                let folderIDs = Set([folderID] + folders.descendants(of: folderID).map { $0.id })
                count = sessionMetadata.filter { meta in
                    if let metaFolderID = meta.folderID {
                        return folderIDs.contains(metaFolderID)
                    }
                    return false
                }.count
            }
            // Cache the result
            sessionCache.setFolderCount(folderID, count: count)
            return count
        }
        
        // Fall back to JSON sessions
        if folderID == Folder.inboxID {
            return sessions.filter { $0.folderID == nil }.count
        }

        let folderIDs = Set([folderID] + folders.descendants(of: folderID).map { $0.id })
        return sessions.filter { session in
            if let sessionFolderID = session.folderID {
                return folderIDs.contains(sessionFolderID)
            }
            return false
        }.count
    }

    /// Count of sessions with a specific label
    func sessionCountByLabel(_ labelID: UUID) -> Int {
        // Use SwiftData metadata if available
        if useSwiftData {
            return sessionMetadata.filter { $0.labelIDs.contains(labelID) }.count
        }
        return sessions.filter { $0.labelIDs.contains(labelID) }.count
    }
    
    // MARK: - SwiftData Fast Metadata Access
    
    /// Get filtered session metadata (fast, from SwiftData)
    var filteredSessionMetadata: [SDSession] {
        guard useSwiftData else { return [] }
        
        if let labelID = selectedLabelID {
            return sessionMetadata.filter { $0.labelIDs.contains(labelID) }
                .sorted { $0.startDate > $1.startDate }
        }
        
        if let folderID = selectedFolderID {
            if folderID == Folder.inboxID {
                return sessionMetadata.filter { $0.folderID == nil }
                    .sorted { $0.startDate > $1.startDate }
            }
            let folderIDs = Set([folderID] + folders.descendants(of: folderID).map { $0.id })
            return sessionMetadata.filter { meta in
                if let metaFolderID = meta.folderID {
                    return folderIDs.contains(metaFolderID)
                }
                return false
            }.sorted { $0.startDate > $1.startDate }
        }
        
        return sessionMetadata.sorted { $0.startDate > $1.startDate }
    }
    
    /// Load full session from JSON when needed (for detail view)
    func loadFullSession(id: UUID) -> RecordingSession? {
        // First check if we already have it in memory
        if let session = sessions.first(where: { $0.id == id }) {
            return session
        }

        // Otherwise load from storage cache without mutating @Published properties.
        // This function is called from selection bindings and must remain side-effect free.
        let allSessions = storage.loadSessions()
        if let fullSession = allSessions.first(where: { $0.id == id }) {
            return fullSession
        }

        // Fallback: build a lightweight session from SwiftData metadata
        if let metadata = sessionMetadata.first(where: { $0.id == id }) {
            return sessionFromMetadata(metadata)
        }

        return nil
    }

    /// Read-only access to cached sessions (no side effects)
    func cachedSession(id: UUID) -> RecordingSession? {
        sessions.first { $0.id == id }
    }

    var showDiskWarning: Bool {
        !sessionMetadata.isEmpty && !hasDiskSessions
    }

    private func refreshDiskSessionStatus() {
        let diskSessions = storage.loadSessionsFromDisk()
        hasDiskSessions = !diskSessions.isEmpty
    }

    private func sessionFromMetadata(_ metadata: SDSession) -> RecordingSession {
        let audioSource = AudioSource(rawValue: metadata.audioSource) ?? .microphone
        let sessionType = SessionType(rawValue: metadata.sessionType) ?? .meeting

        return RecordingSession(
            id: metadata.id,
            startDate: metadata.startDate,
            endDate: metadata.endDate,
            transcriptSegments: [],
            speakers: [],
            audioSource: audioSource,
            title: metadata.title,
            audioFileName: metadata.audioFileName,
            micAudioFileName: metadata.micAudioFileName,
            systemAudioFileName: metadata.systemAudioFileName,
            sessionType: sessionType,
            summary: nil,
            folderID: metadata.folderID,
            labelIDs: metadata.labelIDs,
            aiSuggestedFolderID: metadata.aiSuggestedFolderID,
            aiClassificationConfidence: metadata.aiClassificationConfidence,
            isClassified: metadata.isClassified
        )
    }
    
    /// Update a session in the local cache (called when session is edited)
    func updateSessionInCache(_ session: RecordingSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }
    
    /// Load sessions matching current filter (called when user views list)
    func loadFilteredSessions() {
        ensureFullSessionsLoaded()
    }

    private func ensureFullSessionsLoaded() {
        guard sessions.isEmpty else { return }
        sessions = storage.loadSessions()
    }

    /// Root folders (no parent)
    var rootFolders: [Folder] {
        folders.rootFolders
    }

    /// Children of a folder
    func children(of folderID: UUID?) -> [Folder] {
        folders.children(of: folderID)
    }

    /// Check if folder has children
    func hasChildren(_ folderID: UUID) -> Bool {
        !folders.children(of: folderID).isEmpty
    }

    /// Get folder by ID
    func folder(withID id: UUID) -> Folder? {
        folders.first { $0.id == id }
    }

    /// Get label by ID
    func label(withID id: UUID) -> SessionLabel? {
        labels.first { $0.id == id }
    }

    // MARK: - Folder CRUD

    func createFolder(name: String, parentID: UUID? = nil, icon: String = "folder.fill", color: String? = nil) {
        let newFolder = Folder(
            name: name,
            parentID: parentID,
            icon: icon,
            color: color,
            sortOrder: folders.filter { $0.parentID == parentID }.count + 1
        )
        storage.createFolder(newFolder)
        folders = storage.loadFolders()

        // Auto-expand parent if creating child
        if let parentID = parentID {
            expandedFolderIDs.insert(parentID)
        }
    }

    func updateFolder(_ folder: Folder) {
        storage.updateFolder(folder)
        folders = storage.loadFolders()
    }

    func deleteFolder(_ folderID: UUID) {
        storage.deleteFolder(folderID)
        folders = storage.loadFolders()
        sessions = storage.loadSessions()

        // Deselect if deleted
        if selectedFolderID == folderID {
            selectedFolderID = Folder.inboxID
        }
    }

    func renameFolder(_ folderID: UUID, to newName: String) {
        guard var folder = folders.first(where: { $0.id == folderID }),
              !folder.isSystem else { return }

        folder.name = newName
        updateFolder(folder)
    }

    func moveFolder(_ folderID: UUID, to newParentID: UUID?) {
        guard var folder = folders.first(where: { $0.id == folderID }),
              !folder.isSystem,
              !folders.wouldCreateCycle(moving: folderID, to: newParentID) else { return }

        folder.parentID = newParentID
        updateFolder(folder)
    }

    // MARK: - Label CRUD

    func createLabel(name: String, color: String, icon: String? = nil) {
        let newLabel = SessionLabel(
            name: name,
            color: color,
            icon: icon,
            sortOrder: labels.count + 1
        )
        storage.createLabel(newLabel)
        labels = storage.loadLabels()
    }

    func updateLabel(_ label: SessionLabel) {
        storage.updateLabel(label)
        labels = storage.loadLabels()
    }

    func deleteLabel(_ labelID: UUID) {
        storage.deleteLabel(labelID)
        labels = storage.loadLabels()
        sessions = storage.loadSessions()

        // Deselect if deleted
        if selectedLabelID == labelID {
            selectedLabelID = nil
        }
    }

    // MARK: - Session Organization

    func moveSession(_ sessionID: UUID, to folderID: UUID?) {
        storage.moveSession(sessionID, to: folderID)
        sessions = storage.loadSessions()
    }

    func addLabel(_ labelID: UUID, to sessionID: UUID) {
        storage.addLabel(labelID, to: sessionID)
        sessions = storage.loadSessions()
    }

    func removeLabel(_ labelID: UUID, from sessionID: UUID) {
        storage.removeLabel(labelID, from: sessionID)
        sessions = storage.loadSessions()
    }

    func toggleLabel(_ labelID: UUID, for sessionID: UUID) {
        ensureFullSessionsLoaded()
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }

        if session.labelIDs.contains(labelID) {
            removeLabel(labelID, from: sessionID)
        } else {
            addLabel(labelID, to: sessionID)
        }
    }

    // MARK: - Selection

    func selectFolder(_ folderID: UUID?) {
        selectedFolderID = folderID
        selectedLabelID = nil
    }

    func selectLabel(_ labelID: UUID?) {
        selectedLabelID = labelID
        selectedFolderID = nil
    }

    func selectInbox() {
        selectFolder(Folder.inboxID)
    }

    // MARK: - Expansion

    func toggleExpanded(_ folderID: UUID) {
        if expandedFolderIDs.contains(folderID) {
            expandedFolderIDs.remove(folderID)
        } else {
            expandedFolderIDs.insert(folderID)
        }
    }

    func isExpanded(_ folderID: UUID) -> Bool {
        expandedFolderIDs.contains(folderID)
    }

    func expandAll() {
        expandedFolderIDs = Set(folders.map { $0.id })
    }

    func collapseAll() {
        expandedFolderIDs.removeAll()
    }

    // MARK: - Edit Mode

    func startEditingFolder(_ folder: Folder) {
        editingFolder = folder
        isEditingFolder = true
    }

    func startCreatingFolder(parentID: UUID? = nil) {
        let newFolder = Folder(
            name: "New Folder",
            parentID: parentID
        )
        editingFolder = newFolder
        isEditingFolder = true
    }

    func cancelEditingFolder() {
        editingFolder = nil
        isEditingFolder = false
    }

    func startEditingLabel(_ label: SessionLabel) {
        editingLabel = label
        isEditingLabel = true
    }

    func startCreatingLabel() {
        let newLabel = SessionLabel(
            name: "New Label",
            color: SessionLabel.presetColors.first ?? "#3B82F6"
        )
        editingLabel = newLabel
        isEditingLabel = true
    }

    func cancelEditingLabel() {
        editingLabel = nil
        isEditingLabel = false
    }

    // MARK: - AI Classification

    /// Get sessions that have AI suggestions but haven't been classified
    var sessionsWithSuggestions: [RecordingSession] {
        sessions.filter { $0.aiSuggestedFolderID != nil && !$0.isClassified }
    }

    /// Accept AI suggestion for a session
    func acceptSuggestion(for sessionID: UUID) {
        guard var session = sessions.first(where: { $0.id == sessionID }),
              let suggestedFolderID = session.aiSuggestedFolderID else { return }

        session.folderID = suggestedFolderID
        session.isClassified = true
        session.aiSuggestedFolderID = nil
        session.aiClassificationConfidence = nil

        var allSessions = storage.loadSessions()
        if let index = allSessions.firstIndex(where: { $0.id == sessionID }) {
            allSessions[index] = session
            storage.saveSessions(allSessions)
        }

        sessions = storage.loadSessions()
    }

    /// Reject AI suggestion and keep in INBOX
    func rejectSuggestion(for sessionID: UUID) {
        guard var session = sessions.first(where: { $0.id == sessionID }) else { return }

        session.isClassified = true  // Mark as classified (user chose to keep in INBOX)
        session.aiSuggestedFolderID = nil
        session.aiClassificationConfidence = nil

        var allSessions = storage.loadSessions()
        if let index = allSessions.firstIndex(where: { $0.id == sessionID }) {
            allSessions[index] = session
            storage.saveSessions(allSessions)
        }

        sessions = storage.loadSessions()
    }

    // MARK: - Orphaned Audio Import

    /// Import orphaned audio files that exist in Sessions folder but have no JSON metadata
    /// Returns the number of sessions imported
    @discardableResult
    func importOrphanedAudioFiles() -> Int {
        let metadataSnapshots = sessionMetadata.map { meta in
            SessionMetadataSnapshot(
                id: meta.id,
                startDate: meta.startDate,
                endDate: meta.endDate,
                title: meta.title,
                sessionType: meta.sessionType,
                audioSource: meta.audioSource,
                audioFileName: meta.audioFileName,
                micAudioFileName: meta.micAudioFileName,
                systemAudioFileName: meta.systemAudioFileName,
                folderID: meta.folderID,
                labelIDs: meta.labelIDs,
                isClassified: meta.isClassified,
                aiSuggestedFolderID: meta.aiSuggestedFolderID,
                aiClassificationConfidence: meta.aiClassificationConfidence
            )
        }
        let count = storage.importOrphanedAudioFiles(using: metadataSnapshots)
        if count > 0 {
            sessions = storage.loadSessions()
        }
        return count
    }

    /// Check if there are orphaned audio files to import
    var hasOrphanedAudioFiles: Bool {
        !storage.findOrphanedAudioFiles().isEmpty
    }

    /// Get count of orphaned audio files
    var orphanedAudioCount: Int {
        storage.findOrphanedAudioFiles().count
    }
}
