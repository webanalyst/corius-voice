import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Workspace View Model

/// ViewModel para gestionar la lógica de WorkspaceView
/// Separa presentación de lógica de negocio
@MainActor
class WorkspaceViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    let storage: WorkspaceStorageProtocol
    private let indexService = IndexService()
    private let queryCache = QueryCache()
    
    // MARK: - Published State
    
    @Published var selectedItemID: UUID?
    @Published var searchText = ""
    @Published var selectedCategory: WorkspaceItemType?
    @Published var showingNewItemSheet = false
    @Published var showingSettingsSheet = false
    @Published var selectedView: WorkspaceViewType = .pages
    
    // MARK: - Computed Properties
    
    var filteredItems: [WorkspaceItem] {
        var results = selectedCategory == nil
            ? storage.items
            : storage.items(ofType: selectedCategory!)
        
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return results }
        
        let indexedIDs = indexService.search(text: trimmedQuery)
        if !indexedIDs.isEmpty {
            let indexedResults = results.filter { indexedIDs.contains($0.id) }
            if !indexedResults.isEmpty {
                return indexedResults
            }
        }

        return queryCache.cachedSearch(text: trimmedQuery, in: results)
    }

    var searchResults: [WorkspaceItem] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let indexedIDs = indexService.search(text: trimmedQuery)
        var results = storage.items.filter { indexedIDs.contains($0.id) && !$0.isArchived }
        let lowered = trimmedQuery.lowercased()

        if results.isEmpty {
            results = storage.items.filter { item in
                !item.isArchived && indexService.searchableText(for: item.id)?.lowercased().contains(lowered) == true
            }
        } else {
            results = results.filter { item in
                indexService.searchableText(for: item.id)?.lowercased().contains(lowered) ?? true
            }
        }

        return results.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    var favoriteItems: [WorkspaceItem] {
        storage.favoriteItems
    }
    
    var recentItems: [WorkspaceItem] {
        storage.recentItems(limit: 20)
    }
    
    var hasItems: Bool {
        !storage.items.isEmpty
    }
    
    // MARK: - Initialization
    
    init(storage: WorkspaceStorageProtocol = WorkspaceStorageServiceOptimized.shared) {
        self.storage = storage
        refreshIndexes()
    }
    
    // MARK: - Actions
    
    func createNewItem(type: WorkspaceItemType, in parentID: UUID? = nil) {
        let newItem = WorkspaceItem(
            title: "Nuevo \(type.displayName)",
            parentID: parentID,
            itemType: type
        )
        storage.addItem(newItem)
        selectedItemID = newItem.id
    }
    
    func deleteItem(_ id: UUID) {
        if selectedItemID == id {
            selectedItemID = nil
        }
        storage.deleteItem(id)
    }
    
    func toggleFavorite(itemID: UUID) {
        guard var item = storage.item(withID: itemID) else { return }
        item.isFavorite.toggle()
        storage.updateItem(item)
    }
    
    func archiveItem(_ id: UUID) {
        guard var item = storage.item(withID: id) else { return }
        item.isArchived = true
        if selectedItemID == id {
            selectedItemID = nil
        }
        storage.updateItem(item)
    }
    
    func selectItem(_ id: UUID) {
        selectedItemID = id
    }
    
    func clearSearch() {
        searchText = ""
    }
    
    func setCategory(_ type: WorkspaceItemType?) {
        selectedCategory = type
    }

    // MARK: - Indexing

    func refreshIndexes() {
        indexService.clear()
        queryCache.invalidateAll()
        storage.items.filter { !$0.isArchived }.forEach { item in
            indexService.indexItem(item, searchableText: buildSearchableText(for: item))
        }
    }

    // MARK: - Search Helpers

    func snippet(for item: WorkspaceItem, query: String) -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return "" }
        let text = indexService.searchableText(for: item.id) ?? buildSearchableText(for: item)
        return snippet(in: text, query: trimmedQuery)
    }

    private func buildSearchableText(for item: WorkspaceItem) -> String {
        var parts: [String] = [item.title]
        parts.append(contentsOf: propertySearchParts(for: item))
        parts.append(contentsOf: blockSearchParts(item.blocks))
        return normalizeSearchText(parts.joined(separator: " "))
    }

    private func propertySearchParts(for item: WorkspaceItem) -> [String] {
        var parts: [String] = []
        let database = item.workspaceID.flatMap { storage.database(withID: $0) }
        let definitions = database?.properties ?? []

        for (key, value) in item.properties {
            if let definition = definitions.first(where: { $0.storageKey == key || PropertyDefinition.legacyKey(for: $0.name) == key }) {
                parts.append(definition.name)
                appendPropertyValue(value, to: &parts)
            } else {
                parts.append(key)
                appendPropertyValue(value, to: &parts)
            }
        }

        if let database,
           let optimized = storage as? WorkspaceStorageServiceOptimized {
            for definition in database.properties where definition.type == .rollup || definition.type == .formula {
                let value = PropertyValueResolver.value(for: item, definition: definition, database: database, storage: optimized)
                guard !value.isEmpty else { continue }
                parts.append(definition.name)
                parts.append(value.displayValue)
            }
        }

        return parts
    }

    private func appendPropertyValue(_ value: PropertyValue, to parts: inout [String]) {
        switch value {
        case .relation(let id):
            if let related = storage.item(withID: id) {
                parts.append(related.title)
            }
        case .relations(let ids):
            for id in ids {
                if let related = storage.item(withID: id) {
                    parts.append(related.title)
                }
            }
        default:
            parts.append(value.displayValue)
        }
    }

    private func blockSearchParts(_ blocks: [Block]) -> [String] {
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

    private func decodeRichText(_ data: Data?) -> String? {
#if canImport(AppKit)
        guard let data else { return nil }
        if let attributed = try? NSAttributedString(rtfd: data, documentAttributes: nil) {
            return attributed.string
        }
#endif
        return nil
    }

    private func normalizeSearchText(_ text: String) -> String {
        let components = text.components(separatedBy: .whitespacesAndNewlines)
        return components.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func snippet(in text: String, query: String, radius: Int = 60) -> String {
        let token = query.split(separator: " ").map(String.init).first ?? query
        guard let range = text.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return text.truncated(to: 120)
        }

        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        let snippet = text[start..<end]
        return snippet.trimmingCharacters(in: .whitespacesAndNewlines).truncated(to: 160)
    }
}

// MARK: - View Type

enum WorkspaceViewType: String, CaseIterable {
    case pages
    case databases
    case favorites
    case recent
    
    var displayName: String {
        switch self {
        case .pages: return "Páginas"
        case .databases: return "Bases de Datos"
        case .favorites: return "Favoritos"
        case .recent: return "Recientes"
        }
    }
}

// MARK: - Helper Extension

extension WorkspaceItemType {
    var displayName: String {
        switch self {
        case .page: return "Página"
        case .database: return "Base de Datos"
        case .session: return "Sesión"
        case .task: return "Tarea"
        }
    }
}
