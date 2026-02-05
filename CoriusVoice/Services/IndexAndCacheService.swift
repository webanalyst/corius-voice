import Foundation

// MARK: - Index Service

/// Servicio de indexación avanzada para búsquedas rápidas
/// Proporciona O(1) lookups con múltiples índices
@MainActor
class IndexService: ObservableObject {
    
    // MARK: - Full-Text Search Index
    
    private var textIndex: [String: Set<UUID>] = [:]
    private var wordIndex: [String: Set<UUID>] = [:]
    private var searchableTextById: [UUID: String] = [:]
    private var tokensById: [UUID: Set<String>] = [:]
    
    // MARK: - Date Indexes
    
    private var createdDateIndex: [Date: Set<UUID>] = [:]
    private var modifiedDateIndex: [Date: Set<UUID>] = [:]
    
    // MARK: - Hierarchical Index
    
    private var pathIndex: [String: Set<UUID>] = [:]
    
    // MARK: - Building Indexes
    
    func indexItem(_ item: WorkspaceItem, searchableText: String? = nil) {
        // Text index (full title)
        let lowercaseTitle = item.title.lowercased()
        textIndex[lowercaseTitle, default: []].insert(item.id)

        let rawText = searchableText ?? item.title
        searchableTextById[item.id] = rawText

        let tokens = Set(tokenize(rawText.lowercased()))
        tokensById[item.id] = tokens
        for token in tokens {
            wordIndex[token, default: []].insert(item.id)
        }
        
        // Date indexes
        let createdDateKey = Calendar.current.startOfDay(for: item.createdAt)
        createdDateIndex[createdDateKey, default: []].insert(item.id)
        
        let modifiedDateKey = Calendar.current.startOfDay(for: item.updatedAt)
        modifiedDateIndex[modifiedDateKey, default: []].insert(item.id)
        
        // Path index (hierarchical)
        let path = buildPath(for: item)
        pathIndex[path, default: []].insert(item.id)
    }
    
    func removeItemFromIndex(_ item: WorkspaceItem) {
        let lowercaseTitle = item.title.lowercased()
        textIndex[lowercaseTitle]?.remove(item.id)

        if let tokens = tokensById[item.id] {
            for token in tokens {
                wordIndex[token]?.remove(item.id)
            }
        }
        tokensById.removeValue(forKey: item.id)
        searchableTextById.removeValue(forKey: item.id)
        
        let createdDateKey = Calendar.current.startOfDay(for: item.createdAt)
        createdDateIndex[createdDateKey]?.remove(item.id)
        
        let modifiedDateKey = Calendar.current.startOfDay(for: item.updatedAt)
        modifiedDateIndex[modifiedDateKey]?.remove(item.id)
        
        let path = buildPath(for: item)
        pathIndex[path]?.remove(item.id)
    }
    
    // MARK: - Searches
    
    func search(text: String) -> Set<UUID> {
        let lowercaseText = text.lowercased()

        // Búsqueda exacta primero
        if let exactMatches = textIndex[lowercaseText] {
            return exactMatches
        }

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

        if let intersection, !intersection.isEmpty {
            return intersection
        }
        return union
    }
    
    func itemsCreatedOn(_ date: Date) -> Set<UUID> {
        let dateKey = Calendar.current.startOfDay(for: date)
        return createdDateIndex[dateKey] ?? []
    }
    
    func itemsModifiedOn(_ date: Date) -> Set<UUID> {
        let dateKey = Calendar.current.startOfDay(for: date)
        return modifiedDateIndex[dateKey] ?? []
    }
    
    func itemsInPath(_ path: String) -> Set<UUID> {
        return pathIndex[path] ?? []
    }
    
    // MARK: - Helpers
    
    private func buildPath(for item: WorkspaceItem) -> String {
        if let parentID = item.parentID {
            return "\(parentID)/\(item.id)"
        }
        return item.id.uuidString
    }
    
    func clear() {
        textIndex.removeAll()
        wordIndex.removeAll()
        createdDateIndex.removeAll()
        modifiedDateIndex.removeAll()
        pathIndex.removeAll()
        searchableTextById.removeAll()
        tokensById.removeAll()
    }

    func searchableText(for id: UUID) -> String? {
        searchableTextById[id]
    }

    private func tokenize(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Cache Service

/// Servicio de caché para resultados costosos de computar
@MainActor
class CacheService<Key: Hashable, Value> {
    
    private var cache: [Key: (value: Value, timestamp: Date)] = [:]
    private let ttl: TimeInterval // Time to live en segundos
    
    init(ttl: TimeInterval = 300) { // 5 minutos por defecto
        self.ttl = ttl
    }
    
    func get(_ key: Key) -> Value? {
        guard let entry = cache[key] else { return nil }
        
        // Verificar si está expirado
        if Date().timeIntervalSince(entry.timestamp) > ttl {
            cache.removeValue(forKey: key)
            return nil
        }
        
        return entry.value
    }
    
    func set(_ key: Key, value: Value) {
        cache[key] = (value, Date())
    }
    
    func invalidate(_ key: Key) {
        cache.removeValue(forKey: key)
    }
    
    func invalidateAll() {
        cache.removeAll()
    }
    
    func prune() {
        let now = Date()
        cache = cache.filter { _, entry in
            now.timeIntervalSince(entry.timestamp) <= ttl
        }
    }
}

// MARK: - Query Cache

/// Caché específica para queries de búsqueda y filtrado
@MainActor
class QueryCache {
    
    private let searchCache = CacheService<String, [WorkspaceItem]>(ttl: 60) // 1 minuto
    private let filterCache = CacheService<String, [WorkspaceItem]>(ttl: 120) // 2 minutos
    
    func cachedSearch(text: String, in items: [WorkspaceItem]) -> [WorkspaceItem] {
        if let cached = searchCache.get(text) {
            return cached
        }
        
        let results = items.filter { item in
            item.title.localizedCaseInsensitiveContains(text)
        }
        
        searchCache.set(text, value: results)
        return results
    }
    
    func cachedFilter(key: String, in items: [WorkspaceItem], predicate: (WorkspaceItem) -> Bool) -> [WorkspaceItem] {
        if let cached = filterCache.get(key) {
            return cached
        }
        
        let results = items.filter(predicate)
        filterCache.set(key, value: results)
        return results
    }
    
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
