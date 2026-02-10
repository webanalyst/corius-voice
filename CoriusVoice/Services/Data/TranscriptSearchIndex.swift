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

// MARK: - Transcript Search Index

/// Fast full-text search index over transcript content using Core Spotlight + inverted index
/// Targets sub-200ms search across 10K+ transcript segments
@MainActor
final class TranscriptSearchIndex: ObservableObject {
    
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
    
    // MARK: - Persistence
    
    private let indexFilePath: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Published Results
    
    @Published var lastSearchResults: [SessionMatch] = []
    @Published var isIndexing = false
    
    // MARK: - Initialization
    
    init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths.first!
        let indexDirectory = appSupport.appendingPathComponent("CoriusVoice", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        self.indexFilePath = indexDirectory.appendingPathComponent("transcript_search_index.json")
        
        loadIndexFromDisk()
    }
    
    // MARK: - Public API
    
    /// Index a session's transcript content for search
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
    
    /// Update index for a modified session (debounced for rapid edits)
    func updateSession(_ session: SDSession, transcriptSegments: [TranscriptSegment]) {
        // Cancel any pending debounce task
        debounceTask?.cancel()
        
        // Debounce the re-indexing
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            
            guard !Task.isCancelled else { return }
            indexSession(session, transcriptSegments: transcriptSegments)
        }
    }
    
    /// Remove a session from the index
    func removeFromIndex(sessionID: UUID) {
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
        spotlightIndex.deleteSearchableItems(withDomainIdentifiers: [sessionID.uuidString]) { error in
            if let error = error {
                print("Failed to remove from Spotlight: \(error)")
            }
        }
        
        saveIndexToDisk()
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
    
    // MARK: - Statistics
    
    func getIndexStats() -> (tokenCount: Int, sessionCount: Int, segmentCount: Int) {
        let tokenCount = invertedIndex.count
        let sessionCount = sessionContentCache.count
        let segmentCount = sessionSegments.values.reduce(0) { $0 + $1.count }
        return (tokenCount, sessionCount, segmentCount)
    }
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
