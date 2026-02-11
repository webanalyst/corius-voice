import Foundation
import SwiftData
import os.log

/// Lightweight metadata struct for list views - excludes transcript bodies
struct SessionMetadata: Identifiable, Equatable {
    let id: UUID
    let title: String?
    let startDate: Date
    let endDate: Date?
    let duration: TimeInterval
    let speakerIDs: [UUID]
    let labelIDs: [UUID]
    let folderID: UUID?
    let hasTranscript: Bool
    let segmentCount: Int
    let speakerCount: Int
    let speakerNames: String
    
    init(from session: SDSession) {
        self.id = session.id
        self.title = session.title
        self.startDate = session.startDate
        self.endDate = session.endDate
        self.duration = session.totalDuration
        self.speakerIDs = []
        self.labelIDs = session.labelIDs ?? []
        self.folderID = session.folderID
        self.hasTranscript = session.hasTranscript
        self.segmentCount = session.segmentCount
        self.speakerCount = session.speakerCount
        self.speakerNames = session.speakerNames
    }
    
    static func == (lhs: SessionMetadata, rhs: SessionMetadata) -> Bool {
        lhs.id == rhs.id
    }
}

/// Repository pattern wrapper over SwiftData providing paginated, faulted, and cached access
@MainActor
final class SessionRepository: ObservableObject {
    static let shared = SessionRepository()

    private let logger = Logger(subsystem: "com.corius.voice", category: "SessionRepository")
    private let swiftData = SwiftDataService.shared
    private let searchIndex = TranscriptSearchIndex.shared
    private let indexService = IndexService.shared
    private let queryCache = SessionQueryCache.shared

    // MARK: - Pagination State

    @Published private(set) var sessions: [SDSession] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMorePages = true
    @Published private(set) var totalCount = 0

    private var currentOffset = 0
    private let pageSize = 50
    private var currentFolderID: UUID?
    private var currentLabelID: UUID?
    private var currentSearchQuery = ""

    // MARK: - LRU Cache

    private var fullSessionCache: LRUCache<UUID, RecordingSession> = LRUCache(capacity: 20)
    private var metadataCache: LRUCache<String, [SessionMetadata]> = LRUCache(capacity: 10)

    // MARK: - Performance Metrics

    private var lastLoadTime: TimeInterval = 0

    // MARK: - Initialization

    private init() {
        reloadTotalCount()
    }

    // MARK: - Public API

    /// Load the first page of sessions based on current filter
    func loadFirstPage() async {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.debug("📄 Loading first page...")

        currentOffset = 0
        hasMorePages = true

        await loadPage()

        let loadTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        lastLoadTime = loadTime
        logger.info("✅ First page loaded in \(String(format: "%.1f", loadTime))ms (\(sessions.count) sessions)")

        if loadTime > 100 {
            logger.warning("⚠️ Page load exceeded 100ms target: \(String(format: "%.1f", loadTime))ms")
        }
    }

    /// Load the next page of sessions
    func loadNextPage() async {
        guard !isLoading && hasMorePages else { return }
        await loadPage()
    }

    /// Reset and load sessions with new filters
    func setFilter(folderID: UUID?, labelID: UUID?, searchQuery: String = "") async {
        currentFolderID = folderID
        currentLabelID = labelID
        currentSearchQuery = searchQuery

        await loadFirstPage()
    }

    /// Get full session with transcript (uses cache)
    func getFullSession(id: UUID) -> RecordingSession? {
        // Check cache first
        if let cached = fullSessionCache.get(id) {
            logger.debug("💎 Cache hit for session \(id)")
            return cached
        }

        // Load from storage
        logger.debug("📂 Loading full session \(id) from storage")
        let session = StorageService.shared.loadSession(id: id)

        // Update cache
        if let session = session {
            fullSessionCache.put(id, value: session)
        }

        return session
    }

    /// Prefetch sessions for smooth scrolling
    func prefetchSessions(ids: [UUID]) {
        let uncachedIDs = ids.filter { fullSessionCache.get($0) == nil }
        guard !uncachedIDs.isEmpty else { return }

        Task.detached(priority: .userInitiated) {
            for id in uncachedIDs.prefix(10) { // Limit prefetch
                if let session = await StorageService.shared.loadSession(id: id) {
                    await MainActor.run {
                        self.fullSessionCache.put(id, value: session)
                    }
                }
            }
        }
    }

    /// Search sessions using TranscriptSearchIndex for full-text search
    func searchSessions(query: String) async -> [SDSession] {
        guard !query.isEmpty else { return [] }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Use the search index for fast full-text search
        let matches = await searchIndex.search(query: query)

        // Convert matches to SDSession objects
        let matchedIDs = Set(matches.map { $0.sessionID })
        let results = sessions.filter { matchedIDs.contains($0.id) }

        let searchTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        logger.info("🔍 Search '\(query)' found \(results.count) results in \(String(format: "%.1f", searchTime))ms")

        if searchTime > 200 {
            logger.warning("⚠️ Search exceeded 200ms target: \(String(format: "%.1f", searchTime))ms")
        }

        return results
    }

    /// Reload total count (efficient count query)
    func reloadTotalCount() {
        totalCount = swiftData.countSessions()
        logger.debug("📊 Total sessions: \(totalCount)")
    }

    // MARK: - Private Methods

    private func loadPage() async {
        isLoading = true

        let page: [SDSession]
        if !currentSearchQuery.isEmpty {
            // Use search index for query
            let allResults = await searchIndex.search(query: currentSearchQuery)
            let paginatedResults = Array(allResults.prefix(currentOffset + pageSize))
            page = paginatedResults.compactMap { match in
                swiftData.getSession(id: match.sessionID)
            }
        } else if let labelID = currentLabelID {
            // Fetch by label
            page = fetchSessionsByLabel(labelID, offset: currentOffset, limit: pageSize)
        } else if let folderID = currentFolderID {
            // Fetch by folder
            page = fetchSessionsByFolder(folderID, offset: currentOffset, limit: pageSize)
        } else {
            // Fetch all sessions
            page = fetchAllSessions(offset: currentOffset, limit: pageSize)
        }

        if currentOffset == 0 {
            sessions = page
        } else {
            sessions.append(contentsOf: page)
        }

        currentOffset += page.count
        hasMorePages = page.count == pageSize && sessions.count < totalCount

        isLoading = false
    }

    private func fetchAllSessions(offset: Int, limit: Int) -> [SDSession] {
        var descriptor = FetchDescriptor<SDSession>(
            sortBy: [SortDescriptor(\SDSession.startDate, order: .reverse)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return (try? swiftData.modelContext.fetch(descriptor)) ?? []
    }

    private func fetchSessionsByFolder(_ folderID: UUID, offset: Int, limit: Int) -> [SDSession] {
        if folderID == Folder.inboxID {
            var descriptor = FetchDescriptor<SDSession>(
                predicate: #Predicate<SDSession> { $0.folderID == nil },
                sortBy: [SortDescriptor(\SDSession.startDate, order: .reverse)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = limit
            return (try? swiftData.modelContext.fetch(descriptor)) ?? []
        }

        let predicate = #Predicate<SDSession> { $0.folderID == folderID }
        var descriptor = FetchDescriptor<SDSession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\SDSession.startDate, order: .reverse)]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return (try? swiftData.modelContext.fetch(descriptor)) ?? []
    }

    private func fetchSessionsByLabel(_ labelID: UUID, offset: Int, limit: Int) -> [SDSession] {
        // Fetch all and filter in memory (labelIDs is encoded data)
        // TODO: Optimize with proper predicate when SwiftData supports array contains
        let all = swiftData.fetchSessions(withLabel: labelID)
        let start = all.index(all.startIndex, offsetBy: min(offset, all.count))
        let end = all.index(all.startIndex, offsetBy: min(offset + limit, all.count))
        return Array(all[start..<end]))
    }

    // MARK: - Cache Management

    func clearCache() {
        fullSessionCache.removeAll()
        logger.debug("🧹 Cleared session cache")
    }

    func updateCache(_ session: RecordingSession) {
        fullSessionCache.put(session.id, value: session)
    }
}

// MARK: - LRU Cache

private class LRUCache<Key: Hashable, Value> {
    private var cache: [Key: Value] = [:]
    private var accessOrder: [Key] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
    }

    func get(_ key: Key) -> Value? {
        guard let value = cache[key] else { return nil }
        // Move to end (most recently used)
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        return value
    }

    func put(_ key: Key, value: Value) {
        if cache[key] != nil {
            accessOrder.removeAll { $0 == key }
        } else if cache.count >= capacity {
            // Remove least recently used
            if let lruKey = accessOrder.first {
                cache.removeValue(forKey: lruKey)
                accessOrder.removeFirst()
            }
        }
        cache[key] = value
        accessOrder.append(key)
    }

    func removeAll() {
        cache.removeAll()
        accessOrder.removeAll()
    }
}
