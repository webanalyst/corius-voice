import Foundation

// MARK: - Workspace Storage Service

/// Manages persistence of workspace data (databases, items, pages)
@MainActor
class WorkspaceStorageService: ObservableObject {
    static let shared = WorkspaceStorageService()
    
    // MARK: - Published Properties
    
    @Published var databases: [Database] = []
    @Published var items: [WorkspaceItem] = []
    @Published var workspaces: [Workspace] = []
    @Published var versions: [PageVersion] = []
    
    // MARK: - Private Properties
    
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    private var workspaceDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("CoriusVoice", isDirectory: true)
        let workspaceDir = appDir.appendingPathComponent("Workspace", isDirectory: true)
        
        if !fileManager.fileExists(atPath: workspaceDir.path) {
            try? fileManager.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        }
        
        return workspaceDir
    }
    
    private var databasesURL: URL {
        workspaceDirectory.appendingPathComponent("databases.json")
    }
    
    private var itemsURL: URL {
        workspaceDirectory.appendingPathComponent("items.json")
    }

    private var versionsURL: URL {
        workspaceDirectory.appendingPathComponent("versions.json")
    }
    
    private var workspacesURL: URL {
        workspaceDirectory.appendingPathComponent("workspaces.json")
    }
    
    // MARK: - Initialization
    
    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        loadAll()
        createDefaultsIfNeeded()
    }
    
    // MARK: - Load All
    
    func loadAll() {
        workspaces = loadWorkspaces()
        databases = loadDatabases()
        items = loadItems()
        versions = loadVersions()
        
        print("[WorkspaceStorage] 📂 Loaded \(workspaces.count) workspaces, \(databases.count) databases, \(items.count) items")
    }
    
    // MARK: - Create Defaults
    
    private func createDefaultsIfNeeded() {
        // Create default workspace if none exist
        if workspaces.isEmpty {
            let personal = Workspace.personal
            workspaces.append(personal)
            saveWorkspaces()
            
            // Create default task board
            let taskBoard = Database.taskBoard(name: "Tasks", parentID: nil)
            databases.append(taskBoard)
            saveDatabases()

            // Create meeting databases
            var meetingsDB = Database.meetingNotes(name: "Meeting Notes", parentID: nil)
            var actionsDB = Database.meetingActions(name: "Meeting Actions", parentID: nil)
            configureMeetingRelations(meetingsDB: &meetingsDB, actionsDB: &actionsDB)
            databases.append(meetingsDB)
            databases.append(actionsDB)
            saveDatabases()
            
            print("[WorkspaceStorage] ✨ Created default workspace, task board, and meeting databases")
        }
    }

    private func configureMeetingRelations(meetingsDB: inout Database, actionsDB: inout Database) {
        let actionsRelationId = actionsDB.properties.first(where: { $0.name == "Meeting" })?.id
        let meetingsRelationId = meetingsDB.properties.first(where: { $0.name == "Actions" })?.id

        if let actionsRelationId {
            if let index = actionsDB.properties.firstIndex(where: { $0.id == actionsRelationId }) {
                actionsDB.properties[index].relationConfig = RelationConfig(
                    targetDatabaseId: meetingsDB.id,
                    isTwoWay: true,
                    reversePropertyId: meetingsRelationId,
                    reverseName: "Actions"
                )
            }
        }

        if let meetingsRelationId {
            if let index = meetingsDB.properties.firstIndex(where: { $0.id == meetingsRelationId }) {
                meetingsDB.properties[index].relationConfig = RelationConfig(
                    targetDatabaseId: actionsDB.id,
                    isTwoWay: true,
                    reversePropertyId: actionsRelationId,
                    reverseName: "Meeting"
                )
            }
        }
    }
    
    // MARK: - Workspaces
    
    func loadWorkspaces() -> [Workspace] {
        guard fileManager.fileExists(atPath: workspacesURL.path),
              let data = try? Data(contentsOf: workspacesURL),
              let loaded = try? decoder.decode([Workspace].self, from: data) else {
            return []
        }
        return loaded
    }
    
    func saveWorkspaces() {
        if let data = try? encoder.encode(workspaces) {
            try? data.write(to: workspacesURL)
        }
    }
    
    // MARK: - Databases
    
    func loadDatabases() -> [Database] {
        guard fileManager.fileExists(atPath: databasesURL.path),
              let data = try? Data(contentsOf: databasesURL),
              let loaded = try? decoder.decode([Database].self, from: data) else {
            return []
        }
        return loaded
    }
    
    func saveDatabases() {
        if let data = try? encoder.encode(databases) {
            try? data.write(to: databasesURL)
        }
    }
    
    func saveDatabase(_ database: Database) {
        if let index = databases.firstIndex(where: { $0.id == database.id }) {
            databases[index] = database
        } else {
            databases.append(database)
        }
        saveDatabases()
    }
    
    func deleteDatabase(_ id: UUID) {
        databases.removeAll { $0.id == id }
        // Also delete all items in this database
        items.removeAll { $0.workspaceID == id }
        saveDatabases()
        saveItems()
    }
    
    func database(withID id: UUID) -> Database? {
        databases.first { $0.id == id }
    }
    
    // MARK: - Items
    
    func loadItems() -> [WorkspaceItem] {
        guard fileManager.fileExists(atPath: itemsURL.path),
              let data = try? Data(contentsOf: itemsURL),
              let loaded = try? decoder.decode([WorkspaceItem].self, from: data) else {
            return []
        }
        return loaded
    }

    func loadVersions() -> [PageVersion] {
        guard fileManager.fileExists(atPath: versionsURL.path),
              let data = try? Data(contentsOf: versionsURL),
              let loaded = try? decoder.decode([PageVersion].self, from: data) else {
            return []
        }
        return loaded
    }
    
    func saveItems() {
        if let data = try? encoder.encode(items) {
            try? data.write(to: itemsURL)
        }
    }

    func saveVersions() {
        if let data = try? encoder.encode(versions) {
            try? data.write(to: versionsURL)
        }
    }
    
    func saveItem(_ item: WorkspaceItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        saveItems()
    }
    
    func deleteItem(_ id: UUID) {
        items.removeAll { $0.id == id }
        saveItems()
    }
    
    func item(withID id: UUID) -> WorkspaceItem? {
        items.first { $0.id == id }
    }
    
    // MARK: - Query Items
    
    /// Get all items in a database
    func items(inDatabase databaseID: UUID) -> [WorkspaceItem] {
        items.filter { $0.workspaceID == databaseID && !$0.isArchived }
    }
    
    /// Get items by status (for Kanban)
    func items(inDatabase databaseID: UUID, withStatus status: String) -> [WorkspaceItem] {
        items(inDatabase: databaseID).filter { $0.statusValue == status }
    }
    
    /// Get child items of a page
    func children(of parentID: UUID) -> [WorkspaceItem] {
        items.filter { $0.parentID == parentID && !$0.isArchived }
    }
    
    /// Get favorite items
    var favoriteItems: [WorkspaceItem] {
        items.filter { $0.isFavorite && !$0.isArchived }
    }
    
    /// Get recently updated items
    func recentItems(limit: Int = 10) -> [WorkspaceItem] {
        items
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }
    
    // MARK: - Move Item (for Drag & Drop)
    
    func moveItem(_ itemID: UUID, toStatus status: String) {
        guard var item = item(withID: itemID) else { return }
        item.setStatus(status)
        saveItem(item)
    }
    
    func moveItem(_ itemID: UUID, toDatabase databaseID: UUID) {
        guard var item = item(withID: itemID) else { return }
        item.workspaceID = databaseID
        item.updatedAt = Date()
        saveItem(item)
    }
    
    // MARK: - Quick Actions
    
    /// Create a new task in a database
    @discardableResult
    func createTask(title: String, databaseID: UUID, status: String = "Todo") -> WorkspaceItem {
        var task = WorkspaceItem.task(title: title, workspaceID: databaseID)
        
        // Find the database and set the initial status
        if let database = database(withID: databaseID),
           let column = database.kanbanColumns.first {
            task.properties["status"] = .select(column.name)
        }
        
        saveItem(task)
        return task
    }
    
    /// Create a new page
    @discardableResult
    func createPage(title: String, parentID: UUID? = nil) -> WorkspaceItem {
        let page = WorkspaceItem.page(title: title, icon: "📄", parentID: parentID)
        saveItem(page)
        return page
    }
    
    /// Create any item
    @discardableResult
    func createItem(_ item: WorkspaceItem) -> WorkspaceItem {
        saveItem(item)
        return item
    }
    
    /// Add item (alias for createItem)
    func addItem(_ item: WorkspaceItem) {
        _ = createItem(item)
    }
    
    /// Update an existing item
    func updateItem(_ item: WorkspaceItem) {
        var updatedItem = item
        updatedItem.updatedAt = Date()
        saveItem(updatedItem)

        if updatedItem.itemType == .page {
            createVersion(for: updatedItem, note: "Auto-save")
        }
    }

    // MARK: - Versions

    func createVersion(for page: WorkspaceItem, note: String? = nil) {
        if note == "Auto-save", shouldSkipAutoSave(for: page) {
            return
        }
        let version = PageVersion(page: page, note: note)
        versions.insert(version, at: 0)
        let pageVersions = versions.filter { $0.pageID == page.id }
        if pageVersions.count > 50 {
            let toRemove = pageVersions.dropFirst(50)
            versions.removeAll { version in
                toRemove.contains(where: { $0.id == version.id })
            }
        }
        saveVersions()
    }

    private func shouldSkipAutoSave(for page: WorkspaceItem) -> Bool {
        if let last = versions.first(where: { $0.pageID == page.id }) {
            let interval = Date().timeIntervalSince(last.createdAt)
            return interval < 120
        }
        return false
    }

    func versions(for pageID: UUID) -> [PageVersion] {
        versions.filter { $0.pageID == pageID }.sorted { $0.createdAt > $1.createdAt }
    }

    func restoreVersion(_ version: PageVersion) {
        guard var page = item(withID: version.pageID) else { return }
        page.title = version.title
        page.icon = version.icon
        page.coverImageURL = version.coverImageURL
        page.blocks = version.blocks
        page.properties = version.properties
        page.updatedAt = Date()
        saveItem(page)
    }

    // MARK: - Synced Blocks

    func syncSyncedBlocks() {
        var sourceByGroup: [String: Block] = [:]

        // Collect sources
        for item in items {
            collectSyncedSources(from: item.blocks, into: &sourceByGroup)
        }

        guard !sourceByGroup.isEmpty else { return }

        var updatedItems: [WorkspaceItem] = []

        for var item in items {
            var blocksChanged = false
            updateSyncedBlocks(in: &item.blocks, sources: sourceByGroup, changed: &blocksChanged)
            if blocksChanged {
                item.updatedAt = Date()
                updatedItems.append(item)
            }
        }

        for item in updatedItems {
            saveItem(item)
        }
    }

    private func collectSyncedSources(from blocks: [Block], into sources: inout [String: Block]) {
        for block in blocks {
            if block.type == .syncedBlock, block.isSyncedSource, let groupID = block.syncedGroupID {
                if sources[groupID] == nil {
                    sources[groupID] = block
                }
            }
            if !block.children.isEmpty {
                collectSyncedSources(from: block.children, into: &sources)
            }
        }
    }

    private func updateSyncedBlocks(in blocks: inout [Block], sources: [String: Block], changed: inout Bool) {
        for index in blocks.indices {
            if blocks[index].type == .syncedBlock,
               let groupID = blocks[index].syncedGroupID,
               let source = sources[groupID],
               !blocks[index].isSyncedSource {
                blocks[index].applySyncedContent(from: source)
                changed = true
            }
            if !blocks[index].children.isEmpty {
                updateSyncedBlocks(in: &blocks[index].children, sources: sources, changed: &changed)
            }
        }
    }
    
    /// Add a column to a Kanban board
    func addColumn(to databaseID: UUID, name: String, color: String = "#6B7280") {
        guard var database = database(withID: databaseID) else { return }
        let maxOrder = database.kanbanColumns.map { $0.sortOrder }.max() ?? -1
        let column = KanbanColumn(name: name, color: color, sortOrder: maxOrder + 1)
        database.kanbanColumns.append(column)
        database.updatedAt = Date()
        saveDatabase(database)
    }
    
    /// Remove a column from Kanban (moves items to first column)
    func removeColumn(_ columnID: UUID, from databaseID: UUID) {
        guard var database = database(withID: databaseID) else { return }
        
        // Find the column name
        guard let column = database.kanbanColumns.first(where: { $0.id == columnID }) else { return }
        let columnName = column.name
        
        // Find first column to move items to
        let firstColumn = database.sortedColumns.first { $0.id != columnID }
        let targetStatus = firstColumn?.name ?? "Todo"
        
        // Move all items from this column
        for item in items(inDatabase: databaseID, withStatus: columnName) {
            moveItem(item.id, toStatus: targetStatus)
        }
        
        // Remove the column
        database.kanbanColumns.removeAll { $0.id == columnID }
        database.updatedAt = Date()
        saveDatabase(database)
    }
    
    // MARK: - Search
    
    func search(query: String) -> [WorkspaceItem] {
        let lowercased = query.lowercased()
        return items.filter { item in
            item.title.lowercased().contains(lowercased) ||
            item.blocks.fullText.lowercased().contains(lowercased)
        }
    }
}
