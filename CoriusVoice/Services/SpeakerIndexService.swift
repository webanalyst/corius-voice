import Foundation
import SwiftData

// MARK: - Speaker Index Service

/// Servicio de indexación para speakers, adaptado de IndexService
/// Proporciona O(1) lookups para búsquedas frecuentes de speakers
@MainActor
class SpeakerIndexService: ObservableObject {
    
    // MARK: - Shared Instance
    
    static let shared = SpeakerIndexService()
    
    // MARK: - Full-Text Search Index
    
    private var textIndex: [String: Set<UUID>] = [:]
    private var wordIndex: [String: Set<UUID>] = [:]
    private var searchableTextById: [UUID: String] = [:]
    private var tokensById: [UUID: Set<String>] = [:]
    
    // MARK: - Profile Type Index
    
    private var profileTypeIndex: [String: Set<UUID>] = [:]
    
    // MARK: - Embedding Available Index
    
    private var hasEmbeddingIndex: [Bool: Set<UUID>] = [:]
    
    // MARK: - Building Indexes
    
    /// Index a speaker for fast lookups
    func indexSpeaker(_ speaker: SDKnownSpeaker) {
        // Text index (name)
        let lowercaseName = (speaker.name ?? "").lowercased()
        if !lowercaseName.isEmpty {
            textIndex[lowercaseName, default: []].insert(speaker.id)
        }
        
        // Use searchableText for content indexing
        let rawText = speaker.searchableText.isEmpty 
            ? (speaker.name ?? "") 
            : speaker.searchableText
        searchableTextById[speaker.id] = rawText
        
        let tokens = Set(tokenize(rawText.lowercased()))
        tokensById[speaker.id] = tokens
        for token in tokens {
            wordIndex[token, default: []].insert(speaker.id)
        }
        
        // Profile type index
        profileTypeIndex[speaker.profileType, default: []].insert(speaker.id)
        
        // Has embedding index
        hasEmbeddingIndex[speaker.hasEmbedding, default: []].insert(speaker.id)
    }
    
    /// Remove speaker from all indexes
    func removeSpeakerFromIndex(_ speaker: SDKnownSpeaker) {
        let lowercaseName = (speaker.name ?? "").lowercased()
        textIndex[lowercaseName]?.remove(speaker.id)
        
        if let tokens = tokensById[speaker.id] {
            for token in tokens {
                wordIndex[token]?.remove(speaker.id)
            }
        }
        tokensById.removeValue(forKey: speaker.id)
        searchableTextById.removeValue(forKey: speaker.id)
        
        profileTypeIndex[speaker.profileType]?.remove(speaker.id)
        hasEmbeddingIndex[speaker.hasEmbedding]?.remove(speaker.id)
    }
    
    // MARK: - Searches
    
    /// Full-text search across speaker names and searchable text
    func search(text: String) -> Set<UUID> {
        let lowercaseText = text.lowercased()
        
        // Exact name match first
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
    
    /// Speakers of specific profile type
    func speakersOfType(_ type: String) -> Set<UUID> {
        return profileTypeIndex[type] ?? []
    }
    
    /// Speakers with embeddings
    func speakersWithEmbeddings() -> Set<UUID> {
        return hasEmbeddingIndex[true] ?? []
    }
    
    /// Speakers without embeddings
    func speakersWithoutEmbeddings() -> Set<UUID> {
        return hasEmbeddingIndex[false] ?? []
    }
    
    /// Get count of speakers by profile type (cached, O(1))
    func speakerCount(for profileType: String) -> Int {
        return profileTypeIndex[profileType]?.count ?? 0
    }
    
    // MARK: - Batch Operations
    
    /// Index multiple speakers efficiently
    func indexSpeakers(_ speakers: [SDKnownSpeaker]) {
        for speaker in speakers {
            indexSpeaker(speaker)
        }
    }
    
    /// Remove multiple speakers from index
    func removeSpeakers(_ speakers: [SDKnownSpeaker]) {
        for speaker in speakers {
            removeSpeakerFromIndex(speaker)
        }
    }
    
    // MARK: - Maintenance
    
    /// Clear all indexes
    func clear() {
        textIndex.removeAll()
        wordIndex.removeAll()
        profileTypeIndex.removeAll()
        hasEmbeddingIndex.removeAll()
        searchableTextById.removeAll()
        tokensById.removeAll()
    }
    
    /// Rebuild all indexes from scratch
    func rebuild(with speakers: [SDKnownSpeaker]) {
        clear()
        indexSpeakers(speakers)
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

// MARK: - Speaker Cache Service

/// Caché específica para speakers con 5-minute TTL
@MainActor
class SpeakerCacheService {
    
    static let shared = SpeakerCacheService()
    
    private let speakerCache = CacheService<UUID, SDKnownSpeaker>(ttl: 300) // 5 minutos
    private let profileCountCache = CacheService<String, Int>(ttl: 60) // 1 minuto
    
    private init() {}
    
    // MARK: - Speaker Cache
    
    func getSpeaker(_ id: UUID) -> SDKnownSpeaker? {
        return speakerCache.get(id)
    }
    
    func setSpeaker(_ speaker: SDKnownSpeaker) {
        speakerCache.set(speaker.id, value: speaker)
    }
    
    func removeSpeaker(_ id: UUID) {
        speakerCache.invalidate(id)
    }
    
    // MARK: - Count Cache
    
    func getProfileCount(_ profileType: String) -> Int? {
        return profileCountCache.get(profileType)
    }
    
    func setProfileCount(_ profileType: String, count: Int) {
        profileCountCache.set(profileType, value: count)
    }
    
    func invalidateProfileCount(_ profileType: String) {
        profileCountCache.invalidate(profileType)
    }
    
    // MARK: - Batch Invalidation
    
    func invalidateAllProfileCounts() {
        profileCountCache.invalidateAll()
    }
    
    func invalidateAll() {
        speakerCache.invalidateAll()
        profileCountCache.invalidateAll()
    }
    
    // MARK: - Pruning
    
    func prune() {
        speakerCache.prune()
        profileCountCache.prune()
    }
}

// MARK: - Extension for SDKnownSpeaker

extension SDKnownSpeaker {
    
    /// Searchable text combining name and notes
    var searchableText: String {
        var text = name ?? ""
        if let notes = notes, !notes.isEmpty {
            text += " " + notes
        }
        return text
    }
    
    /// Check if speaker has embedding vector
    var hasEmbedding: Bool {
        embeddingVector != nil && !embeddingVector!.isEmpty
    }
}
