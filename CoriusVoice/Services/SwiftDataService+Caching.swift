import Foundation
import SwiftData

// MARK: - SwiftData Service Caching Extension
// Extends SwiftDataService with IndexAndCacheService patterns for optimal performance

extension SwiftDataService {
    
    // MARK: - Cached Session Queries
    
    /// Fetch sessions with caching support
    func fetchSessions(inFolder folderID: UUID, useCache: Bool = true) -> [SDSession] {
        // Try query cache first
        if useCache {
            let cacheKey = queryCache.folderFilterKey(folderID: folderID)
            if let cached = queryCache.cachedFilter(key: cacheKey) {
                return cached
            }
            
            // Use session index for fast lookup
            let indexedIDs = sessionIndex.sessionsInFolder(folderID)
            
            if !indexedIDs.isEmpty {
                let predicate = #Predicate<SDSession> { indexedIDs.contains($0.id) }
                let descriptor = FetchDescriptor<SDSession>(
                    predicate: predicate,
                    sortBy: [SortDescriptor(\.startDate, order: .reverse)]
                )
                let results = (try? modelContext.fetch(descriptor)) ?? []
                queryCache.setFilterResults(results, for: cacheKey)
                return results
            }
        }
        
        // Fallback to direct query
        let predicate = #Predicate<SDSession> { $0.folderID == folderID }
        let descriptor = FetchDescriptor<SDSession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let results = (try? modelContext.fetch(descriptor)) ?? []
        if useCache {
            let cacheKey = queryCache.folderFilterKey(folderID: folderID)
            queryCache.setFilterResults(results, for: cacheKey)
        }
        return results
    }
    
    /// Fetch sessions by label with caching support
    func fetchSessions(withLabel labelID: UUID, useCache: Bool = true) -> [SDSession] {
        // Try query cache first
        if useCache {
            let cacheKey = queryCache.labelFilterKey(labelID: labelID)
            if let cached = queryCache.cachedFilter(key: cacheKey) {
                return cached
            }
            
            // Use session index for fast lookup
            let indexedIDs = sessionIndex.sessionsWithLabel(labelID)
            
            if !indexedIDs.isEmpty {
                let predicate = #Predicate<SDSession> { indexedIDs.contains($0.id) }
                let descriptor = FetchDescriptor<SDSession>(
                    predicate: predicate,
                    sortBy: [SortDescriptor(\.startDate, order: .reverse)]
                )
                let results = (try? modelContext.fetch(descriptor)) ?? []
                queryCache.setFilterResults(results, for: cacheKey)
                return results
            }
        }
        
        // Fallback to filter
        let allSessions = fetchAllSessions()
        let results = allSessions.filter { $0.labelIDs.contains(labelID) }
        if useCache {
            let cacheKey = queryCache.labelFilterKey(labelID: labelID)
            queryCache.setFilterResults(results, for: cacheKey)
        }
        return results
    }
    
    /// Search sessions with caching and index support
    func searchSessions(query: String, useCache: Bool = true) -> [SDSession] {
        // Try query cache first
        if useCache {
            if let cached = queryCache.cachedSearch(text: query) {
                metrics.recordSearchHit()
                return cached
            }
            metrics.recordSearchMiss()
            
            // Use session index for fast lookup if available
            let indexedIDs = sessionIndex.search(text: query)
            
            // If index has results, fetch only those sessions
            if !indexedIDs.isEmpty {
                let predicate = #Predicate<SDSession> { indexedIDs.contains($0.id) }
                let descriptor = FetchDescriptor<SDSession>(
                    predicate: predicate,
                    sortBy: [SortDescriptor(\.startDate, order: .reverse)]
                )
                let results = (try? modelContext.fetch(descriptor)) ?? []
                queryCache.setSearchResults(results, for: query)
                return results
            }
        }
        
        // Fallback to SwiftData query
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
        let results = (try? modelContext.fetch(descriptor)) ?? []
        if useCache {
            queryCache.setSearchResults(results, for: query)
        }
        return results
    }
    
    /// Get session with caching support
    func getSession(id: UUID, useCache: Bool = true) -> SDSession? {
        // Try cache first (O(1) lookup)
        if useCache {
            if let cached = sessionCache.getSession(id) {
                metrics.recordSessionHit()
                return cached
            }
            metrics.recordSessionMiss()
        }
        
        // Fetch from SwiftData
        let predicate = #Predicate<SDSession> { $0.id == id }
        let descriptor = FetchDescriptor<SDSession>(predicate: predicate)
        guard let session = (try? modelContext.fetch(descriptor).first) else { return nil }
        
        // Cache the result
        if useCache {
            sessionCache.setSession(session)
        }
        return session
    }
    
    /// Get session count in folder with caching
    func getSessionCount(inFolder folderID: UUID, useCache: Bool = true) -> Int {
        if useCache {
            if let cached = sessionCache.getFolderCount(folderID) {
                return cached
            }
        }
        
        let predicate = #Predicate<SDSession> { $0.folderID == folderID }
        let descriptor = FetchDescriptor<SDSession>(predicate: predicate)
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        
        if useCache {
            sessionCache.setFolderCount(folderID, count: count)
        }
        return count
    }
    
    /// Get session count by label with caching
    func getSessionCount(withLabel labelID: UUID, useCache: Bool = true) -> Int {
        if useCache {
            if let cached = sessionCache.getLabelCount(labelID) {
                return cached
            }
        }
        
        // Use session index for O(1) lookup
        let count = sessionIndex.sessionCountForLabel(labelID)
        
        if useCache && count > 0 {
            sessionCache.setLabelCount(labelID, count: count)
        }
        return count
    }
    
    // MARK: - Cache Invalidation Helpers
    
    /// Invalidate all caches when sessions are modified
    func invalidateSessionCaches(for sessionID: UUID) {
        sessionCache.removeSession(sessionID)
        queryCache.invalidateAll()
        sessionCache.invalidateAllFolderCounts()
        sessionCache.invalidateAllLabelCounts()
    }
    
    /// Invalidate folder-related caches
    func invalidateFolderCaches(for folderID: UUID) {
        sessionCache.invalidateFolderCount(folderID)
        queryCache.invalidateFilter()
    }
    
    /// Invalidate label-related caches
    func invalidateLabelCaches(for labelID: UUID) {
        sessionCache.invalidateLabelCount(labelID)
        queryCache.invalidateFilter()
    }
    
    /// Rebuild session index from all sessions
    func rebuildSessionIndex() {
        let sessions = fetchAllSessions()
        sessionIndex.rebuild(with: sessions)
        logger.info("🔄 Rebuilt session index with \(sessions.count) sessions")
    }
    
    /// Log cache metrics for monitoring
    func logCacheMetrics() {
        metrics.logMetrics()
    }
}
