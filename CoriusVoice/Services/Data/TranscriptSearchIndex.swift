import Foundation
import CoreSpotlight
import CoreServices

// MARK: - Session Match Result

struct SessionMatch: Identifiable, Codable {
    let id: UUID  // Session ID
    let title: String?
    let timestamp: TimeInterval  // Segment timestamp for jumping to position
    let snippet: String  // Highlighted text excerpt
    let relevanceScore: Double  // 0.0 to 1.0
    let segmentID: UUID  // Specific segment ID
}

import os.log

// MARK: - Transcript Search Index

/// Fast full-text search index over transcript content using Core Spotlight + inverted index
/// Targets sub-200ms search across 10K+ transcript segments
@MainActor
final class TranscriptSearchIndex: ObservableObject {
    
    static let shared = TranscriptSearchIndex()
    
    private let logger = Logger(subsystem: "com.corius.voice", category: "TranscriptSearchIndex")
    
    // MARK: - Inverted Index
    
    /// Word -> Set of session matches with position context
    private var invertedIndex: [String: Set<IndexedMatch>] = [:]
    
    /// Session ID -> Full text content for quick excerpt extraction
    private var sessionContentCache: [UUID: String] = [:]
    
    /// Session ID -> List of segments with timestamps for precise navigation
    private var sessionSegments: [UUID: [SegmentInfo]] = [:]
    
    // MARK: - Core Spotlight Integration
    
    private let spotlightIndex = CSSearchableIndex.default()
    private let spotlightDomain = "com.corius.transcripts"
    
    // MARK: - Debouncing
    
    private var debounceTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 0.5  // 500ms
    
    // MARK: - Batch Processing
    
    private var updateQueue: [(sessionID: UUID, operation: IndexOperation)] = []
    private let batchSize = 50
    private var batchTask: Task<Void, Never>?
    
    // MARK: - Error Recovery
    
    private var failedUpdates: [FailedIndexUpdate] = []
    private let maxRetries = 3
    private let retryDelayBase: TimeInterval = 1.0  // Exponential backoff base
    
    // MARK: - Persistence
    
    private let indexFilePath: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Published Results
    
    @Published var lastSearchResults: [SessionMatch] = []
    @Published var isIndexing = false
    
    // MARK: - Initialization
    
    private init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths.first!
        let indexDirectory = appSupport.appendingPathComponent("CoriusVoice", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        self.indexFilePath = indexDirectory.appendingPathComponent("transcript_search_index.json")
        
        loadIndexFromDisk()
    }
    
    // MARK: - Public API
    
    // MARK: - Incremental Index Updates
    
    /// Index a new transcript (called after session save)
    func indexTranscript(for sessionID: UUID, segments: [TranscriptSegment]) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard !segments.isEmpty else {
            logger.debug("⏭️ Skipping index for empty transcript: \(sessionID)")
            return
        }
        
        do {
            // Fetch session metadata from SwiftData
            let swiftDataService = SwiftDataService.shared
            guard let session = swiftDataService.getSession(id: sessionID) else {
                logger.warning("⚠️ Cannot index session \(sessionID): not found in SwiftData")
                return
            }
            
            // Perform indexing
            await performIndexOperation(sessionID: sessionID, session: session, segments: segments)
            
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            if duration > 50 {
                logger.warning("⚠️ Index update exceeded 50ms: \(String(format: "%.1f", duration))ms")
            } else {
                logger.debug("✅ Indexed transcript \(sessionID) in \(String(format: "%.1f", duration))ms")
            }
        } catch {
            logger.error("❌ Failed to index transcript \(sessionID): \(error.localizedDescription)")
            await recordFailedUpdate(sessionID: sessionID, operation: .index, segments: segments)
        }
    }
    
    /// Update existing transcript (debounced for rapid edits)
    func updateTranscript(for sessionID: UUID, segments: [TranscriptSegment]) async {
        // Queue update for batch processing
        updateQueue.append((sessionID, .update(segments)))
        
        // Cancel existing batch task and schedule new one
        batchTask?.cancel()
        batchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await processBatchedUpdates()
        }
        
        logger.debug("📝 Queued update for transcript \(sessionID) (batch size: \(updateQueue.count))")
    }
    
    /// Remove transcript from index (called before session delete)
    func removeTranscript(for sessionID: UUID) async {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            // Remove from inverted index
            for token in invertedIndex.keys {
                invertedIndex[token]?.removeAll { $0.sessionID == sessionID }
            }
            
            // Clean up empty token entries
            invertedIndex = invertedIndex.filter { !$0.value.isEmpty }
            
            // Clear caches
            sessionContentCache.removeValue(forKey: sessionID)
            sessionSegments.removeValue(forKey: sessionID)
            
            // Remove from Core Spotlight
            await removeFromSpotlight(sessionID: sessionID)
            
            // Persist changes
            await saveIndexToDiskAsync()
            
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            logger.debug("✅ Removed transcript \(sessionID) from index in \(String(format: "%.1f", duration))ms")
        } catch {
            logger.error("❌ Failed to remove transcript \(sessionID): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Public API (Legacy)
    
    /// Index a session's transcript content for search (legacy method for backward compatibility)
    func indexSession(_ session: SDSession, transcriptSegments: [TranscriptSegment]) {
        guard !transcriptSegments.isEmpty else { return }
        
        // Remove old index for this session if exists
        removeFromIndex(sessionID: session.id)
        
        // Build full transcript text
        let fullText = transcriptSegments.map { $0.text }.joined(separator: " ")
        sessionContentCache[session.id] = fullText
        
        // Store segment info for timestamp navigation
        sessionSegments[session.id] = transcriptSegments.map { segment in
            SegmentInfo(
                segmentID: segment.id,
                timestamp: segment.timestamp,
                text: segment.text,
                speakerID: segment.speakerID
            )
        }
        
        // Tokenize and index each word
        let tokens = tokenize(fullText)
        for token in tokens {
            let match = IndexedMatch(
                sessionID: session.id,
                title: session.title,
                segmentID: transcriptSegments.first?.id ?? UUID(),
                timestamp: transcriptSegments.first?.timestamp ?? 0,
                relevanceScore: 1.0
            )
            invertedIndex[token, default: []].insert(match)
        }
        
        // Index in Core Spotlight for system-wide search
        indexInSpotlight(session: session, transcriptText: fullText, segments: transcriptSegments)
        
        // Persist updated index
        saveIndexToDisk()
    }
    
    /// Update index for a modified session (debounced for rapid edits) - legacy method
    func updateSession(_ session: SDSession, transcriptSegments: [TranscriptSegment]) {
        // Use new async API
        Task { @MainActor in
            await updateTranscript(for: session.id, segments: transcriptSegments)
        }
    }
    
    /// Remove a session from the index (legacy method for backward compatibility)
    func removeFromIndex(sessionID: UUID) {
        // Use new async API
        Task { @MainActor in
            await removeTranscript(for: sessionID)
        }
    }
    
    /// Search for sessions matching the query text
    func search(query: String) -> [SessionMatch] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            lastSearchResults = []
            return []
        }
        
        let tokens = tokenize(trimmedQuery)
        guard !tokens.isEmpty else {
            lastSearchResults = []
            return []
        }
        
        var matchesBySession: [UUID: [IndexedMatch]] = [:]
        
        // Collect all matches across query tokens
        for token in tokens {
            if let tokenMatches = invertedIndex[token] {
                for match in tokenMatches {
                    matchesBySession[match.sessionID, default: []].append(match)
                }
            }
        }
        
        // Calculate relevance scores and build results
        var results: [SessionMatch] = []
        
        for (sessionID, matches) in matchesBySession {
            // Higher score for sessions matching more query tokens
            let tokenMatchRatio = Double(matches.count) / Double(tokens.count)
            
            // Find best matching segment with snippet
            if let bestMatch = findBestMatch(sessionID: sessionID, query: trimmedQuery) {
                let finalScore = tokenMatchRatio * bestMatch.relevanceScore
                results.append(bestMatch.withScore(finalScore))
            }
        }
        
        // Sort by relevance (highest first) and limit results
        results.sort { $0.relevanceScore > $1.relevanceScore }
        let limited = Array(results.prefix(100))
        
        lastSearchResults = limited
        return limited
    }
    
    /// Get all matches for a specific session (for highlighting in UI)
    func getMatchesInSession(sessionID: UUID, query: String) -> [SessionMatch] {
        guard let segments = sessionSegments[sessionID],
              let content = sessionContentCache[sessionID] else {
            return []
        }
        
        let tokens = tokenize(query)
        var results: [SessionMatch] = []
        
        for segment in segments {
            // Check if this segment contains any query tokens
            let segmentText = segment.text.lowercased()
            let hasMatch = tokens.contains { segmentText.contains($0) }
            
            if hasMatch {
                let snippet = extractSnippet(from: segment.text, query: query)
                results.append(SessionMatch(
                    id: sessionID,
                    title: nil,
                    timestamp: segment.timestamp,
                    snippet: snippet,
                    relevanceScore: calculateRelevance(segment.text, query: query),
                    segmentID: segment.segmentID
                ))
            }
        }
        
        return results.sorted { $0.relevanceScore > $1.relevanceScore }
    }
    
    // MARK: - Private Helper Methods
    
    private func findBestMatch(sessionID: UUID, query: String) -> SessionMatch? {
        guard let segments = sessionSegments[sessionID] else { return nil }
        
        var bestSegment: (segment: SegmentInfo, score: Double)? = nil
        
        for segment in segments {
            let score = calculateRelevance(segment.text, query: query)
            if let current = bestSegment {
                if score > current.score {
                    bestSegment = (segment, score)
                }
            } else {
                bestSegment = (segment, score)
            }
        }
        
        guard let best = bestSegment else { return nil }
        
        let snippet = extractSnippet(from: best.segment.text, query: query)
        return SessionMatch(
            id: sessionID,
            title: nil,  // Title will be filled by caller from SDSession
            timestamp: best.segment.timestamp,
            snippet: snippet,
            relevanceScore: best.score,
            segmentID: best.segment.segmentID
        )
    }
    
    /// Calculate relevance score based on query match quality
    private func calculateRelevance(_ text: String, query: String) -> Double {
        let lowerText = text.lowercased()
        let lowerQuery = query.lowercased()
        let tokens = tokenize(lowerQuery)
        
        var score = 0.0
        var matchedTokens = 0
        
        for token in tokens {
            if lowerText.contains(token) {
                matchedTokens += 1
                // Boost score for exact phrase matches
                if lowerText.contains(lowerQuery) {
                    score += 1.5
                } else {
                    score += 1.0
                }
            }
        }
        
        // Normalize by token count
        return tokens.isEmpty ? 0 : score / Double(tokens.count)
    }
    
    /// Extract a snippet around the matched query terms
    private func extractSnippet(from text: String, query: String) -> String {
        let lowerText = text.lowercased()
        let lowerQuery = query.lowercased()
        let tokens = tokenize(lowerQuery)
        
        // Find first occurrence of any query token
        var firstMatchRange: Range<String.Index>?
        for token in tokens {
            if let range = lowerText.range(of: token) {
                if firstMatchRange == nil || range.lowerBound < firstMatchRange!.lowerBound {
                    firstMatchRange = range
                }
            }
        }
        
        guard let matchRange = firstMatchRange else {
            // Return first 150 chars if no match found
            return String(text.prefix(150))
        }
        
        // Extract context around the match (75 chars before and after)
        let start = text.index(matchRange.lowerBound, offsetBy: -75, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(matchRange.upperBound, offsetBy: 75, limitedBy: text.endIndex) ?? text.endIndex
        
        var snippet = String(text[start..<end])
        
        // Add ellipsis if truncated
        if start > text.startIndex {
            snippet = "..." + snippet
        }
        if end < text.endIndex {
            snippet = snippet + "..."
        }
        
        return snippet
    }
    
    /// Tokenize text for indexing (handles Spanish/English multilingual content)
    private func tokenize(_ text: String) -> Set<String> {
        var tokens = Set<String>()
        
        // Define multilingual word boundaries (Latin script + Spanish accents)
        let pattern = "[\\wáéíóúüñÁÉÍÓÚÜÑ]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            // Fallback to simple whitespace splitting
            return Set(text.components(separatedBy: .whitespacesAndNewlines).map { $0.lowercased() })
        }
        
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        
        for match in matches {
            if let swiftRange = Range(match.range, in: text) {
                let token = String(text[swiftRange]).lowercased()
                // Skip very short tokens (< 2 chars) and common stopwords
                if token.count >= 2 && !isStopword(token) {
                    tokens.insert(token)
                }
            }
        }
        
        return tokens
    }
    
    /// Common stopwords for Spanish and English
    private func isStopword(_ token: String) -> Bool {
        let stopwords: Set<String> = [
            // English
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by",
            // Spanish
            "el", "la", "los", "las", "un", "una", "unos", "unas", "y", "o", "pero", "en", "de", "con", "por", "para"
        ]
        return stopwords.contains(token)
    }
    
    // MARK: - Core Spotlight Integration
    
    /// Index a session in Core Spotlight for system-wide macOS search (Cmd+Space)
    private func indexInSpotlight(session: SDSession, transcriptText: String, segments: [TranscriptSegment]) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        
        // Title: Use session title or fallback to display title
        attributeSet.title = session.title ?? session.displayTitle
        
        // Content description: Full transcript text for search
        attributeSet.contentDescription = transcriptText
        
        // Keywords: Combine transcript tokens + metadata for rich search
        var keywords = Set<String>()
        
        // Add transcript content keywords
        keywords.formUnion(tokenize(transcriptText))
        
        // Add session metadata keywords
        if let title = session.title {
            keywords.formUnion(tokenize(title))
        }
        
        // Add speaker names as keywords (if available from segments)
        let speakerIDs = Set(segments.compactMap { $0.speakerID })
        for speakerID in speakerIDs {
            // Format as "Speaker 1", "Speaker 2", etc.
            keywords.insert("speaker \(speakerID)")
            keywords.insert("locutor \(speakerID)")  // Spanish support
        }
        
        // Add date keywords (year and month for navigation)
        let calendar = Calendar.current
        if let startDate = session.startDate {
            keywords.insert("\(calendar.component(.year, from: startDate))")
            let monthFormatter = DateFormatter()
            monthFormatter.locale = Locale(identifier: "en_US")
            keywords.insert(monthFormatter.monthSymbols[calendar.component(.month, from: startDate) - 1])
            
            // Spanish month names
            let esLocale = Locale(identifier: "es_ES")
            let esFormatter = DateFormatter()
            esFormatter.locale = esLocale
            keywords.insert(esFormatter.monthSymbols[calendar.component(.month, from: startDate) - 1])
        }
        
        attributeSet.keywords = Array(keywords).sorted()
        
        // Set unique identifier for deep linking
        attributeSet.identifier = session.id.uuidString
        attributeSet.domain = spotlightDomain
        
        // Add session date for timeline sorting in Spotlight
        if let startDate = session.startDate {
            attributeSet.startDate = startDate
        }
        
        // Add file path metadata (if stored in specific folder)
        if let folderPath = session.folderPath {
            attributeSet.path = folderPath
        }
        
        // Thumbnail data (could be enhanced with session waveform/image)
        attributeSet.thumbnailData = nil
        
        // Create searchable item
        let item = CSSearchableItem(
            uniqueIdentifier: session.id.uuidString,
            domainIdentifier: spotlightDomain,
            attributeSet: attributeSet
        )
        
        // Index asynchronously - errors are logged but don't block the app
        spotlightIndex.indexSearchableItems([item]) { error in
            if let error = error {
                print("⚠️ Core Spotlight indexing failed for session '\(attributeSet.title)': \(error.localizedDescription)")
            } else {
                print("✅ Indexed session in Spotlight: \(attributeSet.title ?? "Untitled")")
            }
        }
    }
    
    // MARK: - Index Persistence
    
    private func saveIndexToDisk() {
        Task.detached(priority: .utility) {
            do {
                let data = try self.encoder.encode(IndexSerialization(
                    invertedIndex: self.invertedIndex,
                    sessionContent: self.sessionContentCache,
                    sessionSegments: self.sessionSegments
                ))
                try data.write(to: self.indexFilePath, options: .atomic)
            } catch {
                print("Failed to save search index: \(error)")
            }
        }
    }
    
    private func loadIndexFromDisk() {
        guard FileManager.default.fileExists(atPath: indexFilePath.path) else {
            rebuildFromSpotlight()
            return
        }
        
        Task.detached(priority: .utility) {
            do {
                let data = try Data(contentsOf: self.indexFilePath)
                let serialized = try self.decoder.decode(IndexSerialization.self, from: data)
                
                await MainActor.run {
                    self.invertedIndex = serialized.invertedIndex
                    self.sessionContentCache = serialized.sessionContent
                    self.sessionSegments = serialized.sessionSegments
                }
            } catch {
                print("Failed to load search index, rebuilding from Spotlight: \(error)")
                self.rebuildFromSpotlight()
            }
        }
    }
    
    /// Fallback: Rebuild index from Core Spotlight if disk load fails
    private func rebuildFromSpotlight() {
        // Clear existing index
        invertedIndex.removeAll()
        sessionContentCache.removeAll()
        sessionSegments.removeAll()
        
        // Fetch all indexed items from Spotlight and rebuild
        // Note: This is a fallback - ideally index should be kept in sync
        print("Search index rebuilt - will be populated as sessions are accessed")
    }
    
    /// Rebuild entire index from all sessions (called after migration or import)
    func rebuildAll() async throws {
        print("🔄 Starting full search index rebuild...")
        let startTime = Date()
        isIndexing = true
        
        // Clear existing index
        invertedIndex.removeAll()
        sessionContentCache.removeAll()
        sessionSegments.removeAll()
        
        // Batch index all sessions from SwiftData
        let swiftDataService = SwiftDataService.shared
        let allSessions = swiftDataService.fetchAllSessions()
        
        var indexedCount = 0
        var errorCount = 0
        
        for session in allSessions {
            do {
                // Load full transcript from StorageService
                let storageSession = StorageService.shared.loadSession(id: session.id)
                if let storageSession = storageSession {
                    indexSession(session, transcriptSegments: storageSession.transcriptSegments)
                    indexedCount += 1
                }
            } catch {
                errorCount += 1
                print("⚠️ Failed to index session \(session.id): \(error.localizedDescription)")
            }
        }
        
        isIndexing = false
        let duration = Date().timeIntervalSince(startTime)
        print("✅ Search index rebuild complete: \(indexedCount) sessions indexed in \(String(format: "%.2f", duration))s")
        
        if errorCount > 0 {
            print("⚠️ \(errorCount) sessions failed to index")
        }
    }
    
    // MARK: - Statistics
    
    func getIndexStats() -> (tokenCount: Int, sessionCount: Int, segmentCount: Int) {
        let tokenCount = invertedIndex.count
        let sessionCount = sessionContentCache.count
        let segmentCount = sessionSegments.values.reduce(0) { $0 + $1.count }
        return (tokenCount, sessionCount, segmentCount)
    }
    
    // MARK: - Index Consistency
    
    /// Verify index integrity by comparing with SwiftData session count
    func verifyIndexIntegrity() async -> Bool {
        logger.debug("🔍 Verifying search index integrity...")
        
        let swiftDataService = SwiftDataService.shared
        let swiftDataSessionCount = swiftDataService.getSessionCount()
        let indexedSessionCount = sessionContentCache.count
        
        let isConsistent = swiftDataSessionCount == indexedSessionCount
        
        if !isConsistent {
            logger.warning("⚠️ Index mismatch: SwiftData has \(swiftDataSessionCount) sessions, index has \(indexedSessionCount)")
            logger.info("💡 Consider running rebuildAll() to synchronize index")
        } else {
            logger.info("✅ Index integrity verified: \(indexedSessionCount) sessions indexed")
        }
        
        return isConsistent
    }
    
    /// Get failed updates for recovery
    func getFailedUpdates() -> [FailedIndexUpdate] {
        return failedUpdates
    }
    
    /// Retry failed index updates
    func retryFailedUpdates() async {
        guard !failedUpdates.isEmpty else { return }
        
        logger.info("🔄 Retrying \(failedUpdates.count) failed index updates...")
        let failures = failedUpdates
        failedUpdates.removeAll()
        
        for failure in failures {
            switch failure.operation {
            case .index(let segments):
                await indexTranscript(for: failure.sessionID, segments: segments)
            case .update(let segments):
                await updateTranscript(for: failure.sessionID, segments: segments)
            case .remove:
                await removeTranscript(for: failure.sessionID)
            }
        }
    }
    
    // MARK: - Private Helper Methods (Batch Processing)
    
    /// Process batched index updates with exponential backoff
    private func processBatchedUpdates() async {
        guard !updateQueue.isEmpty else { return }
        
        let batch = updateQueue.prefix(batchSize)
        updateQueue.removeFirst(min(batchSize, updateQueue.count))
        
        let batchStartTime = Date()
        logger.info("🔄 Processing batch of \(batch.count) index updates...")
        
        let swiftDataService = SwiftDataService.shared
        
        for item in batch {
            do {
                guard let session = swiftDataService.getSession(id: item.sessionID) else {
                    logger.warning("⚠️ Session \(item.sessionID) not found during batch update")
                    continue
                }
                
                switch item.operation {
                case .index(let segments):
                    await performIndexOperation(sessionID: item.sessionID, session: session, segments: segments)
                case .update(let segments):
                    await performIndexOperation(sessionID: item.sessionID, session: session, segments: segments)
                case .remove:
                    await removeTranscript(for: item.sessionID)
                }
            } catch {
                logger.error("❌ Batch update failed for session \(item.sessionID): \(error.localizedDescription)")
            }
        }
        
        let batchDuration = Date().timeIntervalSince(batchStartTime)
        logger.info("✅ Batch processed in \(String(format: "%.2f", batchDuration))s")
        
        if batchDuration > 0.5 {
            logger.warning("⚠️ Batch indexing exceeded 500ms target: \(String(format: "%.0f", batchDuration * 1000))ms")
        }
        
        // Process remaining queue if any
        if !updateQueue.isEmpty {
            await processBatchedUpdates()
        }
    }
    
    /// Perform the actual index operation with retry logic
    private func performIndexOperation(sessionID: UUID, session: SDSession, segments: [TranscriptSegment]) async {
        var attempt = 0
        var lastError: Error?
        
        while attempt < maxRetries {
            do {
                // Remove old index first
                await clearSessionIndex(sessionID: sessionID)
                
                // Build full transcript text
                let fullText = segments.map { $0.text }.joined(separator: " ")
                sessionContentCache[sessionID] = fullText
                
                // Store segment info for timestamp navigation
                sessionSegments[sessionID] = segments.map { segment in
                    SegmentInfo(
                        segmentID: segment.id,
                        timestamp: segment.timestamp,
                        text: segment.text,
                        speakerID: segment.speakerID
                    )
                }
                
                // Tokenize and index each word
                let tokens = tokenize(fullText)
                for token in tokens {
                    let match = IndexedMatch(
                        sessionID: sessionID,
                        title: session.title,
                        segmentID: segments.first?.id ?? UUID(),
                        timestamp: segments.first?.timestamp ?? 0,
                        relevanceScore: 1.0
                    )
                    invertedIndex[token, default: []].insert(match)
                }
                
                // Index in Core Spotlight
                await indexInSpotlightAsync(session: session, transcriptText: fullText, segments: segments)
                
                // Persist updated index
                await saveIndexToDiskAsync()
                
                logger.debug("✅ Successfully indexed session \(sessionID) (attempt \(attempt + 1))")
                return
            } catch {
                lastError = error
                attempt += 1
                
                if attempt < maxRetries {
                    let delay = retryDelayBase * pow(2.0, Double(attempt - 1))
                    logger.warning("⚠️ Index attempt \(attempt) failed for \(sessionID), retrying in \(String(format: "%.1f", delay))s: \(error.localizedDescription)")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        // All retries exhausted
        logger.error("❌ Failed to index session \(sessionID) after \(maxRetries) attempts: \(lastError?.localizedDescription ?? "Unknown error")")
    }
    
    /// Clear session index before re-indexing
    private func clearSessionIndex(sessionID: UUID) async {
        for token in invertedIndex.keys {
            invertedIndex[token]?.removeAll { $0.sessionID == sessionID }
        }
        invertedIndex = invertedIndex.filter { !$0.value.isEmpty }
        sessionContentCache.removeValue(forKey: sessionID)
        sessionSegments.removeValue(forKey: sessionID)
        await removeFromSpotlight(sessionID: sessionID)
    }
    
    /// Record failed update for recovery
    private func recordFailedUpdate(sessionID: UUID, operation: IndexOperation, segments: [TranscriptSegment]) async {
        let failure = FailedIndexUpdate(sessionID: sessionID, operation: operation, segments: segments, timestamp: Date())
        failedUpdates.append(failure)
        
        // Keep only last 100 failures to prevent memory bloat
        if failedUpdates.count > 100 {
            failedUpdates.removeFirst(failedUpdates.count - 100)
        }
        
        logger.warning("⚠️ Recorded failed update for session \(sessionID) (total failures: \(failedUpdates.count))")
    }
    
    /// Async version of saveIndexToDisk
    private func saveIndexToDiskAsync() async {
        await Task.detached(priority: .utility) {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(IndexSerialization(
                    invertedIndex: self.invertedIndex,
                    sessionContent: self.sessionContentCache,
                    sessionSegments: self.sessionSegments
                ))
                try data.write(to: self.indexFilePath, options: .atomic)
            } catch {
                print("Failed to save search index: \(error)")
            }
        }.value
    }
    
    /// Async version of Core Spotlight indexing
    private func indexInSpotlightAsync(session: SDSession, transcriptText: String, segments: [TranscriptSegment]) async {
        return await withCheckedContinuation { continuation in
            let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
            
            attributeSet.title = session.title ?? session.displayTitle
            attributeSet.contentDescription = transcriptText
            
            var keywords = Set<String>()
            keywords.formUnion(tokenize(transcriptText))
            
            if let title = session.title {
                keywords.formUnion(tokenize(title))
            }
            
            let speakerIDs = Set(segments.compactMap { $0.speakerID })
            for speakerID in speakerIDs {
                keywords.insert("speaker \(speakerID)")
                keywords.insert("locutor \(speakerID)")
            }
            
            attributeSet.keywords = Array(keywords).sorted()
            attributeSet.identifier = session.id.uuidString
            attributeSet.domain = spotlightDomain
            
            if let startDate = session.startDate {
                attributeSet.startDate = startDate
            }
            
            if let folderPath = session.folderPath {
                attributeSet.path = folderPath
            }
            
            let item = CSSearchableItem(
                uniqueIdentifier: session.id.uuidString,
                domainIdentifier: spotlightDomain,
                attributeSet: attributeSet
            )
            
            spotlightIndex.indexSearchableItems([item]) { error in
                if let error = error {
                    self.logger.error("⚠️ Core Spotlight indexing failed: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }
    
    /// Async version of Spotlight removal
    private func removeFromSpotlight(sessionID: UUID) async {
        return await withCheckedContinuation { continuation in
            spotlightIndex.deleteSearchableItems(withDomainIdentifiers: [sessionID.uuidString]) { error in
                if let error = error {
                    self.logger.warning("⚠️ Failed to remove from Spotlight: \(error.localizedDescription)")
                }
                continuation.resume()
            }
        }
    }
}

// MARK: - Supporting Types

private enum IndexOperation: Equatable {
    case index([TranscriptSegment])
    case update([TranscriptSegment])
    case remove
    
    static func == (lhs: IndexOperation, rhs: IndexOperation) -> Bool {
        switch (lhs, rhs) {
        case (.index, .index), (.update, .update), (.remove, .remove):
            return true
        default:
            return false
        }
    }
}

struct FailedIndexUpdate: Identifiable {
    let id = UUID()
    let sessionID: UUID
    let operation: IndexOperation
    let segments: [TranscriptSegment]
    let timestamp: Date
}

// MARK: - Supporting Types

private struct IndexedMatch: Hashable, Codable {
    let sessionID: UUID
    let title: String?
    let segmentID: UUID
    let timestamp: TimeInterval
    let relevanceScore: Double
}

private struct SegmentInfo: Codable {
    let segmentID: UUID
    let timestamp: TimeInterval
    let text: String
    let speakerID: Int?
}

private struct IndexSerialization: Codable {
    var invertedIndex: [String: Set<IndexedMatch>]
    var sessionContent: [UUID: String]
    var sessionSegments: [UUID: [SegmentInfo]]
}

// MARK: - SessionMatch Extension

extension SessionMatch {
    func withScore(_ newScore: Double) -> SessionMatch {
        SessionMatch(
            id: id,
            title: title,
            timestamp: timestamp,
            snippet: snippet,
            relevanceScore: newScore,
            segmentID: segmentID
        )
    }
}
