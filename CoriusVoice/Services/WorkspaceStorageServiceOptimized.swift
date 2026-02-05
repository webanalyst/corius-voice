import Foundation

// MARK: - Optimized Workspace Storage Service

/// Servicio optimizado de almacenamiento con indexación O(1) y guardado asíncrono
class WorkspaceStorageServiceOptimized: ObservableObject {
    static let shared = WorkspaceStorageServiceOptimized()
    
    // MARK: - Published Properties (Solo notificaciones específicas)
    
    @Published private(set) var lastUpdate = Date()
    
    // MARK: - Private Indexed Storage
    
    private var databasesById: [UUID: Database] = [:]
    private var itemsById: [UUID: WorkspaceItem] = [:]
    private var itemsByType: [WorkspaceItemType: Set<UUID>] = [:]
    private var itemsByParent: [UUID?: Set<UUID>] = [:]
    private var itemsByDatabase: [UUID: Set<UUID>] = [:]
    private var versionsById: [UUID: PageVersion] = [:]
    
    // MARK: - Public Computed Properties
    
    var databases: [Database] {
        Array(databasesById.values).sorted { $0.createdAt > $1.createdAt }
    }
    
    var items: [WorkspaceItem] {
        Array(itemsById.values).sorted { $0.createdAt > $1.createdAt }
    }
    
    var favoriteItems: [WorkspaceItem] {
        items.filter { $0.isFavorite && !$0.isArchived }
    }
    
    // MARK: - Debounced Save
    
    private var saveTask: Task<Void, Never>?
    private let saveQueue = DispatchQueue(label: "workspace.storage.save", qos: .utility)
    
    // MARK: - File URLs
    
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var workspaceDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("CoriusVoice", isDirectory: true)
        let workspaceDir = appDir.appendingPathComponent("Workspace", isDirectory: true)
        
        if !fileManager.fileExists(atPath: workspaceDir.path) {
            try? fileManager.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        }
        
        return workspaceDir
    }
    
    private var databasesURL: URL { workspaceDirectory.appendingPathComponent("databases.json") }
    private var itemsURL: URL { workspaceDirectory.appendingPathComponent("items.json") }
    private var versionsURL: URL { workspaceDirectory.appendingPathComponent("versions.json") }
    
    // MARK: - Initialization
    
    init() {
        encoder.outputFormatting = .prettyPrinted
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        
        loadAll()
    }
    
    // MARK: - O(1) Lookups
    
    func database(withID id: UUID) -> Database? {
        databasesById[id]
    }
    
    func item(withID id: UUID) -> WorkspaceItem? {
        itemsById[id]
    }
    
    func items(ofType type: WorkspaceItemType) -> [WorkspaceItem] {
        guard let ids = itemsByType[type] else { return [] }
        return ids.compactMap { itemsById[$0] }.filter { !$0.isArchived }
    }
    
    func items(inDatabase databaseID: UUID) -> [WorkspaceItem] {
        guard let ids = itemsByDatabase[databaseID] else { return [] }
        return ids.compactMap { itemsById[$0] }.filter { !$0.isArchived }
    }
    
    func items(withParent parentID: UUID?) -> [WorkspaceItem] {
        guard let ids = itemsByParent[parentID] else { return [] }
        return ids.compactMap { itemsById[$0] }.filter { !$0.isArchived }
    }
    
    func recentItems(limit: Int = 20) -> [WorkspaceItem] {
        items
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }
    
    var versions: [PageVersion] {
        Array(versionsById.values).sorted { $0.createdAt > $1.createdAt }
    }
    
    func versions(for pageID: UUID) -> [PageVersion] {
        versions.filter { $0.pageID == pageID }
    }
    
    func createVersion(for page: WorkspaceItem, note: String? = nil) {
        let version = PageVersion(page: page, note: note)
        versionsById[version.id] = version
        notifyChange()
        saveDebounced()
    }
    
    func restoreVersion(_ version: PageVersion) {
        guard var page = item(withID: version.pageID) else { return }
        page.title = version.title
        page.icon = version.icon
        page.coverImageURL = version.coverImageURL
        page.blocks = version.blocks
        page.properties = version.properties
        page.updatedAt = Date()
        updateItem(page)
    }

    // MARK: - Mutations

    private func syncSwiftDataDatabase(_ database: Database) {
        Task { @MainActor in
            SwiftDataService.shared.syncWorkspaceDatabase(database)
        }
    }

    private func syncSwiftDataItem(_ item: WorkspaceItem) {
        Task { @MainActor in
            SwiftDataService.shared.syncWorkspaceItem(item)
        }
    }

    private func deleteSwiftDataDatabase(id: UUID) {
        Task { @MainActor in
            SwiftDataService.shared.deleteWorkspaceDatabase(id: id)
        }
    }

    private func deleteSwiftDataItem(id: UUID) {
        Task { @MainActor in
            SwiftDataService.shared.deleteWorkspaceItem(id: id)
        }
    }
    
    func addDatabase(_ database: Database) {
        databasesById[database.id] = database
        notifyChange()
        saveDebounced()
        syncSwiftDataDatabase(database)
    }
    
    // MARK: - Compatibility Helpers
    
    func createTask(title: String, databaseID: UUID, status: String = "Todo") -> WorkspaceItem {
        var item = WorkspaceItem.task(title: title, workspaceID: databaseID, status: status)
        if let database = databasesById[databaseID],
           let statusProperty = database.properties.first(where: { $0.type == .status }) {
            item.properties[statusProperty.storageKey] = .select(status)
            item.properties.removeValue(forKey: PropertyDefinition.legacyKey(for: statusProperty.name))
        }
        addItem(item)
        return item
    }
    
    func moveItem(_ itemID: UUID, toStatus status: String) {
        guard var item = itemsById[itemID] else { return }
        if let workspaceID = item.workspaceID,
           let database = databasesById[workspaceID],
           let statusProperty = database.properties.first(where: { $0.type == .status }) {
            item.properties[statusProperty.storageKey] = .select(status)
            item.properties.removeValue(forKey: PropertyDefinition.legacyKey(for: statusProperty.name))
            item.updatedAt = Date()
        } else {
            item.setStatus(status)
        }
        updateItem(item)
    }
    
    func moveItem(_ itemID: UUID, toDatabase databaseID: UUID) {
        guard var item = itemsById[itemID] else { return }
        item.workspaceID = databaseID
        updateItem(item)
    }
    
    func addColumn(to databaseID: UUID, name: String, color: String = "#6B7280") {
        guard var db = databasesById[databaseID] else { return }
        let column = KanbanColumn(name: name, color: color, sortOrder: db.kanbanColumns.count)
        db.kanbanColumns.append(column)
        updateDatabase(db)
    }
    
    func items(inDatabase databaseID: UUID, withStatus status: String) -> [WorkspaceItem] {
        guard let database = databasesById[databaseID],
              let statusProperty = database.properties.first(where: { $0.type == .status }) else {
            return items(inDatabase: databaseID).filter { $0.statusValue == status }
        }
        let legacyKey = PropertyDefinition.legacyKey(for: statusProperty.name)
        return items(inDatabase: databaseID).filter { item in
            if case .select(let value) = (item.properties[statusProperty.storageKey] ?? item.properties[legacyKey]) {
                return value == status
            }
            return false
        }
    }

    func statusValue(for item: WorkspaceItem) -> String? {
        if let workspaceID = item.workspaceID,
           let database = databasesById[workspaceID],
           let statusProperty = database.properties.first(where: { $0.type == .status }) {
            let legacyKey = PropertyDefinition.legacyKey(for: statusProperty.name)
            if case .select(let value) = (item.properties[statusProperty.storageKey] ?? item.properties[legacyKey]) {
                return value
            }
        }
        return item.statusValue
    }
    
    func syncSyncedBlocks() {
        var sourceByGroup: [String: Block] = [:]
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
            updateItem(item)
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
    
    func updateDatabase(_ database: Database) {
        databasesById[database.id] = database
        notifyChange()
        saveDebounced()
        syncSwiftDataDatabase(database)
    }
    
    func deleteDatabase(_ id: UUID) {
        databasesById.removeValue(forKey: id)
        // Archivar items del database
        if let ids = itemsByDatabase[id] {
            ids.forEach { itemID in
                if var item = itemsById[itemID] {
                    item.isArchived = true
                    updateItem(item)
                }
            }
        }
        notifyChange()
        saveDebounced()
        deleteSwiftDataDatabase(id: id)
    }
    
    func addItem(_ item: WorkspaceItem) {
        itemsById[item.id] = item
        indexItem(item)
        notifyChange()
        saveDebounced()
        syncSwiftDataItem(item)
    }
    
    func updateItem(_ item: WorkspaceItem) {
        // Remover de índices antiguos
        if let old = itemsById[item.id] {
            removeFromIndexes(old)
        }
        
        // Actualizar
        itemsById[item.id] = item
        indexItem(item)
        notifyChange()
        saveDebounced()
        syncSwiftDataItem(item)
    }
    
    func deleteItem(_ id: UUID) {
        if let item = itemsById[id] {
            removeFromIndexes(item)
        }
        itemsById.removeValue(forKey: id)
        notifyChange()
        saveDebounced()
        deleteSwiftDataItem(id: id)
    }
    
    // MARK: - Indexing
    
    private func indexItem(_ item: WorkspaceItem) {
        // Por tipo
        itemsByType[item.itemType, default: []].insert(item.id)
        
        // Por parent
        itemsByParent[item.parentID, default: []].insert(item.id)
        
        // Por database
        if let dbID = item.workspaceID {
            itemsByDatabase[dbID, default: []].insert(item.id)
        }
    }
    
    private func removeFromIndexes(_ item: WorkspaceItem) {
        itemsByType[item.itemType]?.remove(item.id)
        itemsByParent[item.parentID]?.remove(item.id)
        if let dbID = item.workspaceID {
            itemsByDatabase[dbID]?.remove(item.id)
        }
    }
    
    // MARK: - Debounced Save
    
    private func notifyChange() {
        lastUpdate = Date()
    }
    
    private func saveDebounced() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            if !Task.isCancelled {
                await saveToDisk()
            }
        }
    }
    
    func forceSave() async {
        saveTask?.cancel()
        await saveToDisk()
    }
    
    private func saveToDisk() async {
        let databases = Array(databasesById.values)
        let items = Array(itemsById.values)
        let versions = Array(versionsById.values)
        let databaseCount = databases.count
        let itemCount = items.count
        let saveQueue = self.saveQueue
        let databasesURL = self.databasesURL
        let itemsURL = self.itemsURL
        let versionsURL = self.versionsURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        do {
            let dbData = try encoder.encode(databases)
            let itemsData = try encoder.encode(items)
            let versionsData = try encoder.encode(versions)

            // Guardar en background queue
            saveQueue.async {
                do {
                    try dbData.write(to: databasesURL, options: .atomic)
                    try itemsData.write(to: itemsURL, options: .atomic)
                    try versionsData.write(to: versionsURL, options: .atomic)

                    DispatchQueue.main.async {
                        print("💾 Guardado exitoso: \(databaseCount) databases, \(itemCount) items")
                    }
                } catch {
                    DispatchQueue.main.async {
                        print("❌ Error guardando: \(error)")
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                print("❌ Error guardando: \(error)")
            }
        }
    }
    
    // MARK: - Load
    
    private func loadAll() {
        loadDatabases()
        loadItems()
        migratePropertyKeysIfNeeded()
        loadVersions()
    }
    
    private func loadDatabases() {
        guard fileManager.fileExists(atPath: databasesURL.path),
              let data = try? Data(contentsOf: databasesURL),
              let databases = try? decoder.decode([Database].self, from: data) else {
            createDefaults()
            return
        }
        
        databases.forEach { databasesById[$0.id] = $0 }
        print("📂 Cargadas \(databases.count) databases")
    }
    
    private func loadItems() {
        guard fileManager.fileExists(atPath: itemsURL.path),
              let data = try? Data(contentsOf: itemsURL),
              let items = try? decoder.decode([WorkspaceItem].self, from: data) else {
            return
        }
        
        items.forEach { item in
            itemsById[item.id] = item
            indexItem(item)
        }
        print("📄 Cargados \(items.count) items")
    }

    private func migratePropertyKeysIfNeeded() {
        var didChange = false
        for (id, item) in itemsById {
            guard let dbID = item.workspaceID,
                  let database = databasesById[dbID] else { continue }
            var updated = item
            var properties = updated.properties
            var changed = false

            for definition in database.properties {
                let newKey = definition.storageKey
                if properties[newKey] != nil { continue }
                let legacyKey = PropertyDefinition.legacyKey(for: definition.name)
                if let value = properties.removeValue(forKey: legacyKey) {
                    properties[newKey] = value
                    changed = true
                }
            }

            if changed {
                updated.properties = properties
                itemsById[id] = updated
                didChange = true
            }
        }

        if didChange {
            notifyChange()
            saveDebounced()
        }
    }
    
    private func loadVersions() {
          guard fileManager.fileExists(atPath: versionsURL.path),
              let data = try? Data(contentsOf: versionsURL),
              let versions = try? decoder.decode([PageVersion].self, from: data) else {
            return
        }
        
        versions.forEach { versionsById[$0.id] = $0 }
    }
    
    private func createDefaults() {
        let tasksDB = Database.taskBoard(name: "Tasks")
        addDatabase(tasksDB)

        var meetingsDB = Database.meetingNotes(name: "Meeting Notes")
        var actionsDB = Database.meetingActions(name: "Meeting Actions")
        configureMeetingRelations(meetingsDB: &meetingsDB, actionsDB: &actionsDB)
        addDatabase(meetingsDB)
        addDatabase(actionsDB)
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
    
    // MARK: - Compatibility Aliases
    
    func saveDatabase(_ database: Database) {
        updateDatabase(database)
    }
    
    func saveItem(_ item: WorkspaceItem) {
        updateItem(item)
    }
    
    func createItem(_ item: WorkspaceItem) -> WorkspaceItem {
        addItem(item)
        return item
    }
}

// MARK: - Migration Helper

extension WorkspaceStorageServiceOptimized {
    /// Migra datos del servicio antiguo al optimizado
    @MainActor
    func migrateFromOld(_ oldService: WorkspaceStorageService) {
        print("🔄 Migrando datos al servicio optimizado...")
        
        // Migrar databases
        oldService.databases.forEach { addDatabase($0) }
        
        // Migrar items
        oldService.items.forEach { addItem($0) }
        
        Task {
            await forceSave()
            print("✅ Migración completa")
        }
    }
}

// MARK: - Attachment Service

final class AttachmentService {
    static let shared = AttachmentService()

    private let fileManager = FileManager.default
    private let attachmentsDirectory: URL
    private let attachmentPrefix = "attachment://"

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("CoriusVoice", isDirectory: true)
        let attachmentsDir = appDir.appendingPathComponent("Attachments", isDirectory: true)

        if !fileManager.fileExists(atPath: attachmentsDir.path) {
            try? fileManager.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        }

        self.attachmentsDirectory = attachmentsDir
    }

    func importFile(from url: URL) throws -> String {
        let baseName = url.deletingPathExtension().lastPathComponent.fileSafeName
        let ext = url.pathExtension
        let unique = UUID().uuidString.prefix(8)
        let filename = ext.isEmpty
            ? "\(baseName)-\(unique)"
            : "\(baseName)-\(unique).\(ext)"
        let destination = attachmentsDirectory.appendingPathComponent(filename)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: url, to: destination)
        return "\(attachmentPrefix)\(filename)"
    }

    func resolveURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix(attachmentPrefix) {
            let name = raw.replacingOccurrences(of: attachmentPrefix, with: "")
            return attachmentsDirectory.appendingPathComponent(name)
        }
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: raw)
    }

    func displayName(for raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        if raw.hasPrefix(attachmentPrefix) {
            return URL(fileURLWithPath: raw.replacingOccurrences(of: attachmentPrefix, with: "")).lastPathComponent
        }
        if let url = URL(string: raw), url.scheme != nil {
            return url.lastPathComponent
        }
        return URL(fileURLWithPath: raw).lastPathComponent
    }
}
