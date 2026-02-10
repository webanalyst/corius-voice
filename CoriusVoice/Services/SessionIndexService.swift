import Foundation
import SwiftData

// MARK: - Session Index Service

/// Servicio de indexación para sesiones, adaptado de IndexService
/// Proporciona O(1) lookups para búsquedas frecuentes de sesiones
@MainActor
class SessionIndexService: ObservableObject {
    
    // MARK: - Shared Instance
    
    static let shared = SessionIndexService()
    
    // MARK: - Full-Text Search Index
    
    private var textIndex: [String: Set<UUID>] = [:]
    private var wordIndex: [String: Set<UUID>] = [:]
    private var searchableTextById: [UUID: String] = [:]
    private var tokensById: [UUID: Set<String>] = [:]
    
    // MARK: - Date Indexes
    
    private var startDateIndex: [Date: Set<UUID>] = [:]
    private var endDateIndex: [Date: Set<UUID>] = [:]
    
    // MARK: - Hierarchical Index (Folder)
    
    private var folderIndex: [UUID: Set<UUID>] = [:]
    
    // MARK: - Label Index
    
    private var labelIndex: [UUID: Set<UUID>] = [:]
    
    // MARK: - Speaker Index
    
    private var speakerCountIndex: [Int: Set<UUID>] = [:]
    
    // MARK: - Type Index
    
    private var sessionTypeIndex: [String: Set<UUID>] = [:]
    
    // MARK: - Building Indexes
    
    /// Index a session for fast lookups
    func indexSession(_ session: SDSession) {
        // Text index (title)
        let lowercaseTitle = (session.title ?? "").lowercased()
        if !lowercaseTitle.isEmpty {
            textIndex[lowercaseTitle, default: []].insert(session.id)
        }
        
        // Use searchableText for content indexing
        let rawText = session.searchableText.isEmpty 
            ? (session.title ?? "") 
            : session.searchableText
        searchableTextById[session.id] = rawText
        
        let tokens = Set(tokenize(rawText.lowercased()))
        tokensById[session.id] = tokens
        for token in tokens {
            wordIndex[token, default: []].insert(session.id)
        }
        
        // Date indexes
        let startDateKey = Calendar.current.startOfDay(for: session.startDate)
        startDateIndex[startDateKey, default: []].insert(session.id)
        
        if let endDate = session.endDate {
            let endDateKey = Calendar.current.startOfDay(for: endDate)
            endDateIndex[endDateKey, default: []].insert(session.id)
        }
        
        // Folder index
        if let folderID = session.folderID {
            folderIndex[folderID, default: []].insert(session.id)
        } else {
            // Index sessions without folder (INBOX)
            folderIndex[Folder.inboxID, default: []].insert(session.id)
        }
        
        // Label index
        for labelID in session.labelIDs {
            labelIndex[labelID, default: []].insert(session.id)
        }
        
        // Speaker count index
        speakerCountIndex[session.speakerCount, default: []].insert(session.id)
        
        // Session type index
        sessionTypeIndex[session.sessionType, default: []].insert(session.id)
    }
    
    /// Remove session from all indexes
    func removeSessionFromIndex(_ session: SDSession) {
        let lowercaseTitle = (session.title ?? "").lowercased()
        textIndex[lowercaseTitle]?.remove(session.id)
        
        if let tokens = tokensById[session.id] {
            for token in tokens {
                wordIndex[token]?.remove(session.id)
            }
        }
        tokensById.removeValue(forKey: session.id)
        searchableTextById.removeValue(forKey: session.id)
        
        let startDateKey = Calendar.current.startOfDay(for: session.startDate)
        startDateIndex[startDateKey]?.remove(session.id)
        
        if let endDate = session.endDate {
            let endDateKey = Calendar.current.startOfDay(for: endDate)
            endDateIndex[endDateKey]?.remove(session.id)
        }
        
        if let folderID = session.folderID {
            folderIndex[folderID]?.remove(session.id)
        } else {
            folderIndex[Folder.inboxID]?.remove(session.id)
        }
        
        for labelID in session.labelIDs {
            labelIndex[labelID]?.remove(session.id)
        }
        
        speakerCountIndex[session.speakerCount]?.remove(session.id)
        sessionTypeIndex[session.sessionType]?.remove(session.id)
    }
    
    // MARK: - Searches
    
    /// Full-text search across session titles and searchable text
    func search(text: String) -> Set<UUID> {
        let lowercaseText = text.lowercased()
        
        // Exact title match first
        if let exactMatches = textIndex[lowercaseText], !exactMatches.isEmpty {
            return exactMatches
        }
        
        // Word-based search
        let tokens = tokenize(lowercaseText)
        guard !tokens.isEmpty else { return [] }
        
        var intersection: Set<UUID>? = nil
        var union: Set<UUID> = []
        
        for token in tokens {
            let matches = wordIndex[token] ?? []
            union.formUnion(matches)
            if intersection == nil {
                intersection = matches
            } else {
                intersection = intersection?.intersection(matches)
            }
        }
        
        // Prefer AND results (intersection), fall back to OR (union)
        if let intersection, !intersection.isEmpty {
            return intersection
        }
        return union
    }
    
    /// Sessions started on a specific date
    func sessionsStartedOn(_ date: Date) -> Set<UUID> {
        let dateKey = Calendar.current.startOfDay(for: date)
        return startDateIndex[dateKey] ?? []
    }
    
    /// Sessions in a specific folder
    func sessionsInFolder(_ folderID: UUID) -> Set<UUID> {
        return folderIndex[folderID] ?? []
    }
    
    /// Sessions with a specific label
    func sessionsWithLabel(_ labelID: UUID) -> Set<UUID> {
        return labelIndex[labelID] ?? []
    }
    
    /// Sessions with specific speaker count
    func sessionsWithSpeakerCount(_ count: Int) -> Set<UUID> {
        return speakerCountIndex[count] ?? []
    }
    
    /// Sessions of specific type
    func sessionsOfType(_ type: String) -> Set<UUID> {
        return sessionTypeIndex[type] ?? []
    }
    
    /// Get count of sessions in folder (cached, O(1))
    func sessionCount(for folderID: UUID) -> Int {
        return folderIndex[folderID]?.count ?? 0
    }
    
    /// Get count of sessions with label (cached, O(1))
    func sessionCountForLabel(_ labelID: UUID) -> Int {
        return labelIndex[labelID]?.count ?? 0
    }
    
    // MARK: - Batch Operations
    
    /// Index multiple sessions efficiently
    func indexSessions(_ sessions: [SDSession]) {
        for session in sessions {
            indexSession(session)
        }
    }
    
    /// Remove multiple sessions from index
    func removeSessions(_ sessions: [SDSession]) {
        for session in sessions {
            removeSessionFromIndex(session)
        }
    }
    
    // MARK: - Maintenance
    
    /// Clear all indexes
    func clear() {
        textIndex.removeAll()
        wordIndex.removeAll()
        startDateIndex.removeAll()
        endDateIndex.removeAll()
        folderIndex.removeAll()
        labelIndex.removeAll()
        speakerCountIndex.removeAll()
        sessionTypeIndex.removeAll()
        searchableTextById.removeAll()
        tokensById.removeAll()
    }
    
    /// Rebuild all indexes from scratch
    func rebuild(with sessions: [SDSession]) {
        clear()
        indexSessions(sessions)
    }
    
    // MARK: - Helpers
    
    func searchableText(for id: UUID) -> String? {
        searchableTextById[id]
    }
    
    private func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Session Cache Service

/// Caché específica para sesiones con 5-minute TTL
@MainActor
class SessionCacheService {
    
    static let shared = SessionCacheService()
    
    private let sessionCache = CacheService<UUID, SDSession>(ttl: 300) // 5 minutos
    private let metadataCache = CacheService<UUID, SessionMetadata>(ttl: 300)
    private let folderCountCache = CacheService<UUID, Int>(ttl: 60) // 1 minuto
    private let labelCountCache = CacheService<UUID, Int>(ttl: 60) // 1 minuto
    
    private init() {}
    
    // MARK: - Session Cache
    
    func getSession(_ id: UUID) -> SDSession? {
        return sessionCache.get(id)
    }
    
    func setSession(_ session: SDSession) {
        sessionCache.set(session.id, value: session)
    }
    
    func removeSession(_ id: UUID) {
        sessionCache.invalidate(id)
    }
    
    // MARK: - Metadata Cache
    
    func getMetadata(_ id: UUID) -> SessionMetadata? {
        return metadataCache.get(id)
    }
    
    func setMetadata(_ metadata: SessionMetadata) {
        metadataCache.set(metadata.id, value: metadata)
    }
    
    func removeMetadata(_ id: UUID) {
        metadataCache.invalidate(id)
    }
    
    // MARK: - Count Caches
    
    func getFolderCount(_ folderID: UUID) -> Int? {
        return folderCountCache.get(folderID)
    }
    
    func setFolderCount(_ folderID: UUID, count: Int) {
        folderCountCache.set(folderID, value: count)
    }
    
    func invalidateFolderCount(_ folderID: UUID) {
        folderCountCache.invalidate(folderID)
    }
    
    func getLabelCount(_ labelID: UUID) -> Int? {
        return labelCountCache.get(labelID)
    }
    
    func setLabelCount(_ labelID: UUID, count: Int) {
        labelCountCache.set(labelID, value: count)
    }
    
    func invalidateLabelCount(_ labelID: UUID) {
        labelCountCache.invalidate(labelID)
    }
    
    // MARK: - Batch Invalidation
    
    func invalidateAllFolderCounts() {
        folderCountCache.invalidateAll()
    }
    
    func invalidateAllLabelCounts() {
        labelCountCache.invalidateAll()
    }
    
    func invalidateAll() {
        sessionCache.invalidateAll()
        metadataCache.invalidateAll()
        folderCountCache.invalidateAll()
        labelCountCache.invalidateAll()
    }
    
    // MARK: - Pruning
    
    func prune() {
        sessionCache.prune()
        metadataCache.prune()
        folderCountCache.prune()
        labelCountCache.prune()
    }
}

// MARK: - Session Query Cache

/// Caché para resultados de queries de búsqueda y filtrado de sesiones
@MainActor
class SessionQueryCache {
    
    static let shared = SessionQueryCache()
    
    private let searchCache = CacheService<String, [SDSession]>(ttl: 60) // 1 minuto
    private let filterCache = CacheService<String, [SDSession]>(ttl: 120) // 2 minutos
    
    private init() {}
    
    // MARK: - Search Cache
    
    func cachedSearch(text: String) -> [SDSession]? {
        return searchCache.get(text)
    }
    
    func setSearchResults(_ results: [SDSession], for text: String) {
        searchCache.set(text, value: results)
    }
    
    // MARK: - Filter Cache
    
    func cachedFilter(key: String) -> [SDSession]? {
        return filterCache.get(key)
    }
    
    func setFilterResults(_ results: [SDSession], for key: String) {
        filterCache.set(key, value: results)
    }
    
    // Generate cache key for folder filter
    func folderFilterKey(folderID: UUID, includeDescendants: Bool = false) -> String {
        return "folder:\(folderID):descendants:\(includeDescendants)"
    }
    
    // Generate cache key for label filter
    func labelFilterKey(labelID: UUID) -> String {
        return "label:\(labelID)"
    }
    
    // Generate cache key for date range filter
    func dateRangeFilterKey(startDate: Date, endDate: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return "date:\(formatter.string(from: startDate))-\(formatter.string(from: endDate))"
    }
    
    // MARK: - Invalidation
    
    func invalidateSearch() {
        searchCache.invalidateAll()
    }
    
    func invalidateFilter() {
        filterCache.invalidateAll()
    }
    
    func invalidateAll() {
        searchCache.invalidateAll()
        filterCache.invalidateAll()
    }
}

// MARK: - Metrics Logging

/// Servicio para monitorear métricas de cache hit rate
@MainActor
class CacheMetrics {
    
    static let shared = CacheMetrics()
    
    private var sessionHits: Int = 0
    private var sessionMisses: Int = 0
    private var folderCountHits: Int = 0
    private var folderCountMisses: Int = 0
    private var searchHits: Int = 0
    private var searchMisses: Int = 0
    
    private init() {}
    
    // MARK: - Session Metrics
    
    func recordSessionHit() {
        sessionHits += 1
    }
    
    func recordSessionMiss() {
        sessionMisses += 1
    }
    
    var sessionHitRate: Double {
        let total = sessionHits + sessionMisses
        return total > 0 ? Double(sessionHits) / Double(total) : 0
    }
    
    // MARK: - Folder Count Metrics
    
    func recordFolderCountHit() {
        folderCountHits += 1
    }
    
    func recordFolderCountMiss() {
        folderCountMisses += 1
    }
    
    var folderCountHitRate: Double {
        let total = folderCountHits + folderCountMisses
        return total > 0 ? Double(folderCountHits) / Double(total) : 0
    }
    
    // MARK: - Search Metrics
    
    func recordSearchHit() {
        searchHits += 1
    }
    
    func recordSearchMiss() {
        searchMisses += 1
    }
    
    var searchHitRate: Double {
        let total = searchHits + searchMisses
        return total > 0 ? Double(searchHits) / Double(total) : 0
    }
    
    // MARK: - Logging
    
    func logMetrics() {
        print("📊 [CacheMetrics] Session Hit Rate: \(String(format: "%.2f%%", sessionHitRate * 100)) (\(sessionHits)/\(sessionHits + sessionMisses))")
        print("📊 [CacheMetrics] Folder Count Hit Rate: \(String(format: "%.2f%%", folderCountHitRate * 100)) (\(folderCountHits)/\(folderCountHits + folderCountMisses))")
        print("📊 [CacheMetrics] Search Hit Rate: \(String(format: "%.2f%%", searchHitRate * 100)) (\(searchHits)/\(searchHits + searchMisses))")
    }
    
    func reset() {
        sessionHits = 0
        sessionMisses = 0
        folderCountHits = 0
        folderCountMisses = 0
        searchHits = 0
        searchMisses = 0
    }
}

// MARK: - Session Metadata Helper

struct SessionMetadata: Codable {
    let id: UUID
    let startDate: Date
    let endDate: Date?
    let title: String?
    let sessionType: String
    let audioSource: String
    let audioFileName: String?
    let micAudioFileName: String?
    let systemAudioFileName: String?
    let folderID: UUID?
    let labelIDs: [UUID]
    let isClassified: Bool
    let aiSuggestedFolderID: UUID?
    let aiClassificationConfidence: Double?
}
