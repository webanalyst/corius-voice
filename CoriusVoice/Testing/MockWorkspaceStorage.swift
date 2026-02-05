import Foundation
@testable import CoriusVoice

// MARK: - Mock Storage Service

/// Mock implementation de WorkspaceStorageProtocol para testing
@MainActor
class MockWorkspaceStorage: ObservableObject, WorkspaceStorageProtocol {
    
    // MARK: - Published Properties
    
    @Published private(set) var lastUpdate = Date()
    
    // MARK: - Internal State
    
    private var databasesById: [UUID: Database] = [:]
    private var itemsById: [UUID: WorkspaceItem] = [:]
    private var itemsByType: [WorkspaceItemType: Set<UUID>] = [:]
    private var itemsByDatabase: [UUID: Set<UUID>] = [:]
    
    // MARK: - Testing Helpers
    
    var callCount: [String: Int] = [:]
    var recordedCalls: [String: [Any]] = [:]
    
    // MARK: - Computed Properties
    
    var databases: [Database] {
        Array(databasesById.values).sorted { $0.createdAt > $1.createdAt }
    }
    
    var items: [WorkspaceItem] {
        Array(itemsById.values).sorted { $0.createdAt > $1.createdAt }
    }
    
    var favoriteItems: [WorkspaceItem] {
        items.filter { $0.isFavorite && !$0.isArchived }
    }
    
    // MARK: - Initialization
    
    init() {}
    
    func seedData(databases: [Database], items: [WorkspaceItem]) {
        databasesById = databases.reduce(into: [:]) { $0[$1.id] = $1 }
        itemsById = items.reduce(into: [:]) { $0[$1.id] = $1 }
        
        // Rebuild indexes
        for item in items {
            itemsByType[item.itemType, default: []].insert(item.id)
            if let dbID = item.workspaceID {
                itemsByDatabase[dbID, default: []].insert(item.id)
            }
        }
    }
    
    // MARK: - Queries
    
    func database(withID id: UUID) -> Database? {
        recordCall("database(withID:)", args: id)
        return databasesById[id]
    }
    
    func item(withID id: UUID) -> WorkspaceItem? {
        recordCall("item(withID:)", args: id)
        return itemsById[id]
    }
    
    func items(ofType type: WorkspaceItemType) -> [WorkspaceItem] {
        recordCall("items(ofType:)", args: type)
        guard let ids = itemsByType[type] else { return [] }
        return ids.compactMap { itemsById[$0] }.filter { !$0.isArchived }
    }
    
    func items(inDatabase databaseID: UUID) -> [WorkspaceItem] {
        recordCall("items(inDatabase:)", args: databaseID)
        guard let ids = itemsByDatabase[databaseID] else { return [] }
        return ids.compactMap { itemsById[$0] }.filter { !$0.isArchived }
    }
    
    func items(withParent parentID: UUID?) -> [WorkspaceItem] {
        recordCall("items(withParent:)", args: parentID)
        return items.filter { $0.parentID == parentID && !$0.isArchived }
    }
    
    func recentItems(limit: Int = 20) -> [WorkspaceItem] {
        recordCall("recentItems(limit:)", args: limit)
        return items
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }
    
    // MARK: - Mutations
    
    func addDatabase(_ database: Database) {
        recordCall("addDatabase(_:)", args: database)
        databasesById[database.id] = database
        notifyChange()
    }
    
    func updateDatabase(_ database: Database) {
        recordCall("updateDatabase(_:)", args: database)
        databasesById[database.id] = database
        notifyChange()
    }
    
    func deleteDatabase(_ id: UUID) {
        recordCall("deleteDatabase(_:)", args: id)
        databasesById.removeValue(forKey: id)
        notifyChange()
    }
    
    func addItem(_ item: WorkspaceItem) {
        recordCall("addItem(_:)", args: item)
        itemsById[item.id] = item
        itemsByType[item.itemType, default: []].insert(item.id)
        if let dbID = item.workspaceID {
            itemsByDatabase[dbID, default: []].insert(item.id)
        }
        notifyChange()
    }
    
    func updateItem(_ item: WorkspaceItem) {
        recordCall("updateItem(_:)", args: item)
        itemsById[item.id] = item
        notifyChange()
    }
    
    func deleteItem(_ id: UUID) {
        recordCall("deleteItem(_:)", args: id)
        itemsById.removeValue(forKey: id)
        notifyChange()
    }
    
    func forceSave() async {
        recordCall("forceSave()", args: nil)
        // No-op para testing
    }
    
    // MARK: - Helpers
    
    private func notifyChange() {
        lastUpdate = Date()
    }
    
    private func recordCall(_ method: String, args: Any?) {
        callCount[method, default: 0] += 1
        if recordedCalls[method] == nil {
            recordedCalls[method] = []
        }
        if let args = args {
            recordedCalls[method]?.append(args)
        }
    }
    
    // MARK: - Testing Methods
    
    func getCallCount(for method: String) -> Int {
        callCount[method] ?? 0
    }
    
    func getCalls(for method: String) -> [Any] {
        recordedCalls[method] ?? []
    }
    
    func resetCallTracking() {
        callCount.removeAll()
        recordedCalls.removeAll()
    }
}
