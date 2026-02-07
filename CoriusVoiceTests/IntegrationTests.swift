import XCTest
@testable import CoriusVoice

// MARK: - Integration Tests

@MainActor
final class WorkspaceIntegrationTests: XCTestCase {
    
    var mockStorage: MockWorkspaceStorage!
    var workspaceVM: WorkspaceViewModel!
    var simplePageVM: SimplePageViewModel!
    var kanbanVM: KanbanBoardViewModel!
    
    override func setUp() {
        super.setUp()
        mockStorage = MockWorkspaceStorage()
        workspaceVM = WorkspaceViewModel(storage: mockStorage)
        
        // Create a test database for kanban tests
        let testDB = Database.taskBoard(name: "Test Kanban")
        mockStorage.addDatabase(testDB)
        kanbanVM = KanbanBoardViewModel(databaseID: testDB.id, storage: mockStorage)
    }
    
    override func tearDown() {
        mockStorage = nil
        workspaceVM = nil
        simplePageVM = nil
        kanbanVM = nil
        super.tearDown()
    }
    
    // MARK: - Create-Edit-Save Workflow
    
    func testCreateEditSaveWorkflow() {
        // 1. Create item
        workspaceVM.createNewItem(type: .page)
        let itemID = workspaceVM.selectedItemID ?? UUID()
        let createdItem = mockStorage.item(withID: itemID)
        
        XCTAssertNotNil(createdItem)
        
        // 2. Edit item
        simplePageVM = SimplePageViewModel(item: createdItem!, storage: mockStorage)
        simplePageVM.updateTitle("Updated Title")
        simplePageVM.addBlock(at: 0, type: .paragraph)
        simplePageVM.updateBlock(simplePageVM.item.blocks[0].id, content: "Block content")
        
        // 3. Verify changes propagate
        let expectation = self.expectation(description: "Save debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2)
        
        let savedItem = mockStorage.item(withID: itemID)
        XCTAssertEqual(savedItem?.title, "Updated Title")
        XCTAssertEqual(savedItem?.blocks.count, 1)
    }
    
    // MARK: - Kanban Drag & Drop Workflow
    
    func testKanbanDragDropWorkflow() {
        // 1. Setup kanban board
        kanbanVM.addColumn(named: "Todo")
        kanbanVM.addColumn(named: "In Progress")
        kanbanVM.addColumn(named: "Done")
        
        let todoColumnID = kanbanVM.columns[0].id
        let inProgressColumnID = kanbanVM.columns[1].id
        let doneColumnID = kanbanVM.columns[2].id
        
        // 2. Create cards
        kanbanVM.addCard(titled: "Task 1", to: todoColumnID)
        kanbanVM.addCard(titled: "Task 2", to: todoColumnID)
        
        XCTAssertEqual(kanbanVM.cardCount(in: todoColumnID), 2)
        
        // 3. Drag card from Todo to In Progress
        let cardID = kanbanVM.cards[0].id
        kanbanVM.performDrop(cardID, toColumn: inProgressColumnID)
        
        XCTAssertEqual(kanbanVM.cardCount(in: todoColumnID), 1)
        XCTAssertEqual(kanbanVM.cardCount(in: inProgressColumnID), 1)
        
        // 4. Drag card from In Progress to Done
        kanbanVM.performDrop(cardID, toColumn: doneColumnID)
        
        XCTAssertEqual(kanbanVM.cardCount(in: inProgressColumnID), 0)
        XCTAssertEqual(kanbanVM.cardCount(in: doneColumnID), 1)
    }
    
    // MARK: - Search & Filter Workflow
    
    func testSearchAndFilterWorkflow() {
        // 1. Create multiple items
        let item1 = WorkspaceItem(title: "Project Alpha", itemType: .page)
        let item2 = WorkspaceItem(title: "Project Beta", itemType: .database)
        let item3 = WorkspaceItem(title: "Document Gamma", itemType: .page)
        
        mockStorage.seedData(databases: [], items: [item1, item2, item3])
        workspaceVM.refreshIndexes()
        
        // 2. Test search
        workspaceVM.searchText = "Project"
        var filtered = workspaceVM.filteredItems
        let projectResults = Set(filtered.map(\.id))
        XCTAssertTrue(projectResults.contains(item1.id))
        XCTAssertTrue(projectResults.contains(item2.id))
        XCTAssertFalse(projectResults.contains(item3.id))
        
        // 3. Add category filter
        workspaceVM.setCategory(.page)
        filtered = workspaceVM.filteredItems
        
        // Should only have items that match "Project" AND are of type .page
        XCTAssertTrue(filtered.allSatisfy { $0.itemType == .page })
        XCTAssertTrue(filtered.allSatisfy { $0.title.localizedCaseInsensitiveContains("Project") })
        XCTAssertTrue(filtered.contains(where: { $0.id == item1.id }))
        XCTAssertFalse(filtered.contains(where: { $0.id == item2.id }))
        
        // 4. Clear filters
        workspaceVM.clearSearch()
        workspaceVM.setCategory(nil)
        
        filtered = workspaceVM.filteredItems
        XCTAssertEqual(filtered.count, 3)
    }
    
    // MARK: - Hierarchy Workflow
    
    func testHierarchyWorkflow() {
        // 1. Create parent item
        workspaceVM.createNewItem(type: .page)
        let parentID = workspaceVM.selectedItemID ?? UUID()
        
        // 2. Create child items
        workspaceVM.createNewItem(type: .page, in: parentID)
        let child1ID = workspaceVM.selectedItemID ?? UUID()
        
        workspaceVM.createNewItem(type: .page, in: parentID)
        let child2ID = workspaceVM.selectedItemID ?? UUID()
        
        // 3. Verify hierarchy
        let children = mockStorage.items(withParent: parentID)
        XCTAssertEqual(children.count, 2)
        
        // 4. Delete parent and verify children
        workspaceVM.deleteItem(parentID)
        
        // Children should still exist but be orphaned
        let orphanedChild = mockStorage.item(withID: child1ID)
        XCTAssertNotNil(orphanedChild)
    }
    
    // MARK: - Favorites Workflow
    
    func testFavoritesWorkflow() {
        // 1. Create items
        let item1 = WorkspaceItem(title: "Regular Item", itemType: .page)
        let item2 = WorkspaceItem(title: "Favorite Item", itemType: .page, isFavorite: true)
        
        mockStorage.seedData(databases: [], items: [item1, item2])
        
        // 2. Verify favorites
        let favorites = workspaceVM.favoriteItems
        XCTAssertEqual(favorites.count, 1)
        
        // 3. Toggle favorite
        workspaceVM.toggleFavorite(itemID: item1.id)
        
        // 4. Verify updated favorites
        let updatedFavorites = workspaceVM.favoriteItems
        XCTAssertEqual(updatedFavorites.count, 2)
    }
    
    // MARK: - Multi-Block Page Workflow
    
    func testMultiBlockPageWorkflow() {
        // 1. Create page
        workspaceVM.createNewItem(type: .page)
        let pageID = workspaceVM.selectedItemID ?? UUID()
        let page = mockStorage.item(withID: pageID)!
        
        simplePageVM = SimplePageViewModel(item: page, storage: mockStorage)
        
        // 2. Add multiple blocks of different types
        simplePageVM.addBlock(at: 0, type: .heading1)
        simplePageVM.updateBlock(simplePageVM.item.blocks[0].id, content: "Title")
        
        simplePageVM.addBlock(at: 1, type: .paragraph)
        simplePageVM.updateBlock(simplePageVM.item.blocks[1].id, content: "Some text")
        
        simplePageVM.addBlock(at: 2, type: .bulletList)
        simplePageVM.updateBlock(simplePageVM.item.blocks[2].id, content: "Item 1\nItem 2")
        
        simplePageVM.addBlock(at: 3, type: .code)
        simplePageVM.updateBlock(simplePageVM.item.blocks[3].id, content: "let x = 42")
        
        // 3. Verify block structure
        XCTAssertEqual(simplePageVM.blockCount, 4)
        XCTAssertEqual(simplePageVM.item.blocks[0].type, .heading1)
        XCTAssertEqual(simplePageVM.item.blocks[1].type, .paragraph)
        XCTAssertEqual(simplePageVM.item.blocks[2].type, .bulletList)
        XCTAssertEqual(simplePageVM.item.blocks[3].type, .code)
        
        // 4. Move blocks
        simplePageVM.moveBlock(from: 0, to: 1)
        XCTAssertEqual(simplePageVM.item.blocks[0].type, .paragraph)
        XCTAssertEqual(simplePageVM.item.blocks[1].type, .heading1)
        
        // 5. Delete middle block
        let middleBlockID = simplePageVM.item.blocks[1].id
        simplePageVM.deleteBlock(middleBlockID)
        XCTAssertEqual(simplePageVM.blockCount, 3)
    }
    
    // MARK: - Archive Workflow
    
    func testArchiveWorkflow() {
        // 1. Create items
        let item1 = WorkspaceItem(title: "Active Item", itemType: .page)
        let item2 = WorkspaceItem(title: "To Archive", itemType: .page)
        
        mockStorage.seedData(databases: [], items: [item1, item2])
        
        // 2. Archive item
        workspaceVM.archiveItem(item2.id)
        
        // 3. Verify archived items not in regular queries
        let activeItems = mockStorage.items.filter { !$0.isArchived }
        XCTAssertEqual(activeItems.count, 1)
        
        // 4. Verify favorite items exclude archived
        workspaceVM.toggleFavorite(itemID: item2.id) // Try to fav archived
        XCTAssertEqual(workspaceVM.favoriteItems.count, 0)
    }
    
    // MARK: - Concurrent Operations
    
    func testConcurrentOperations() async {
        let expectation = expectation(description: "Concurrent item creation")
        expectation.expectedFulfillmentCount = 100
        let queue = DispatchQueue.global(qos: .userInitiated)
        
        // Dispatch concurrent work and funnel storage mutations through MainActor.
        for i in 0..<100 {
            queue.async {
                Task { @MainActor in
                    let item = WorkspaceItem(title: "Item \(i)", itemType: .page)
                    self.mockStorage.addItem(item)
                    expectation.fulfill()
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertEqual(mockStorage.items.count, 100)
        XCTAssertEqual(workspaceVM.hasItems, true)
    }
}

// MARK: - Sprint 1 Regression Coverage

@MainActor
final class WorkspaceRegressionCoverageTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var storage: WorkspaceStorageServiceOptimized!
    private var sessionIntegration: SessionIntegrationService!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoriusVoice-RegressionTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        storage = WorkspaceStorageServiceOptimized(baseDirectoryURL: temporaryDirectory, enableSwiftDataSync: false)
        sessionIntegration = SessionIntegrationService(workspaceStorage: storage, legacyStorage: nil)
    }

    override func tearDown() {
        sessionIntegration = nil
        storage = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        super.tearDown()
    }

    func testSessionMeetingActionsEndToEndAndDeduplicates() {
        let session = RecordingSession(
            startDate: Date(timeIntervalSince1970: 1_738_000_000),
            endDate: Date(timeIntervalSince1970: 1_738_000_900),
            transcriptSegments: [
                TranscriptSegment(timestamp: 12, text: "Definimos próximos pasos", speakerID: 0),
                TranscriptSegment(timestamp: 40, text: "Ana enviará el resumen", speakerID: 1),
            ],
            speakers: [Speaker(id: 0, name: "Alex"), Speaker(id: 1, name: "Ana")],
            audioSource: .microphone,
            title: "Planning semanal",
            summary: SessionSummary(
                modelUsed: "test-model",
                sessionType: .meeting,
                markdownContent: """
                ## Summary
                Revisión de avances y pendientes.

                ## Decisions
                Continuar con el plan actual.

                ## Action Items
                - [ ] Enviar resumen urgente al equipo @Ana mañana
                - [ ] Actualizar tablero de prioridades @Alex próxima semana
                - [ ] Enviar resumen urgente al equipo @Ana mañana
                """
            )
        )

        let meetingNote = sessionIntegration.upsertMeetingNote(for: session)
        let createdActions = sessionIntegration.syncActions(from: session, meetingNote: meetingNote)
        sessionIntegration.reconcileMeetingGraph(sessionID: session.id)
        let secondSyncActions = sessionIntegration.syncActions(from: session, meetingNote: meetingNote)

        XCTAssertEqual(createdActions.count, 2, "Duplicate action items should be deduplicated")
        XCTAssertEqual(secondSyncActions.count, 0, "Second sync should not create duplicate actions")

        let meetingDatabase = storage.databases.first { $0.name == "Meeting Notes" }
        let actionsDatabase = storage.databases.first { $0.name == "Meeting Actions" }
        XCTAssertNotNil(meetingDatabase)
        XCTAssertNotNil(actionsDatabase)
        XCTAssertTrue(actionsDatabase?.views.contains(where: { $0.name == "Action Tracker" }) ?? false)
        XCTAssertTrue(actionsDatabase?.views.contains(where: { $0.name == "Open Actions" }) ?? false)

        let refreshedMeetingNote = storage.item(withID: meetingNote.id)
        let actionCountKey = propertyKey(in: meetingDatabase!, named: "Action Count")
        let actionsRelationKey = propertyKey(in: meetingDatabase!, named: "Actions")
        if case .number(let actionCount)? = refreshedMeetingNote?.properties[actionCountKey] {
            XCTAssertEqual(actionCount, 2)
        } else {
            XCTFail("Expected Action Count property")
        }

        let relationIDs: [UUID]
        if case .relations(let ids)? = refreshedMeetingNote?.properties[actionsRelationKey] {
            relationIDs = ids
        } else {
            XCTFail("Expected Actions relation property")
            return
        }
        XCTAssertEqual(Set(relationIDs).count, 2)

        let sessionItems = storage.items.filter { $0.itemType == .session && $0.sessionID == session.id }
        XCTAssertEqual(sessionItems.count, 1, "Session workspace item should be created once")

        let allActions = storage.items(inDatabase: actionsDatabase!.id).filter { $0.sessionID == session.id }
        XCTAssertEqual(allActions.count, 2)

        let ownerKey = propertyKey(in: actionsDatabase!, named: "Owner")
        let dueDateKey = propertyKey(in: actionsDatabase!, named: "Due Date")
        let priorityKey = propertyKey(in: actionsDatabase!, named: "Priority")
        let meetingKey = propertyKey(in: actionsDatabase!, named: "Meeting")
        let sessionKey = propertyKey(in: actionsDatabase!, named: "Session")

        let urgentAction = allActions.first(where: { $0.title.localizedCaseInsensitiveContains("urgente") })
        XCTAssertNotNil(urgentAction)

        switch urgentAction?.properties[ownerKey] {
        case .text(let ownerName):
            XCTAssertEqual(ownerName, "Ana")
        case .person:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected owner suggestion for urgent action")
        }

        if case .date(let dueDate)? = urgentAction?.properties[dueDateKey] {
            let expectedDue = Calendar.current.startOfDay(for: session.startDate.addingTimeInterval(86_400))
            XCTAssertEqual(Calendar.current.startOfDay(for: dueDate), expectedDue)
        } else {
            XCTFail("Expected suggested due date")
        }

        if case .select(let priority)? = urgentAction?.properties[priorityKey] {
            XCTAssertEqual(priority, "High")
        } else {
            XCTFail("Expected priority suggestion")
        }

        for action in allActions {
            if case .relation(let meetingID)? = action.properties[meetingKey] {
                XCTAssertEqual(meetingID, meetingNote.id)
            } else {
                XCTFail("Expected meeting relation on action")
            }
            if case .relation(let sessionItemID)? = action.properties[sessionKey] {
                XCTAssertEqual(sessionItemID, sessionItems.first?.id)
            } else {
                XCTFail("Expected session relation on action")
            }
        }

        let actionEmbed = refreshedMeetingNote?.blocks.first(where: {
            $0.type == .databaseEmbed && $0.metadata["databaseID"] == actionsDatabase?.id.uuidString
        })
        XCTAssertNotNil(actionEmbed)
        XCTAssertEqual(actionEmbed?.metadata["relationProperty"], "Session")
        XCTAssertEqual(
            actionEmbed?.metadata["relationPropertyID"],
            actionsDatabase?.properties.first(where: { $0.name == "Session" })?.id.uuidString
        )
        let trackerView = actionsDatabase?.views.first(where: { $0.name == "Action Tracker" })
        XCTAssertEqual(actionEmbed?.metadata["viewID"], trackerView?.id.uuidString)
        XCTAssertEqual(actionEmbed?.metadata["viewType"], trackerView?.type.rawValue)
    }

    func testLinkedDatabaseEmbedPersistsAfterReload() async {
        var sourceDatabase = Database.taskBoard(name: "Linked Source")
        let statusDefinition = sourceDatabase.properties.first(where: { $0.type == .status })
        XCTAssertNotNil(statusDefinition)
        let tableView = DatabaseView(
            name: "Todo Table",
            type: .table,
            filters: [
                ViewFilter(
                    propertyName: "Status",
                    propertyId: statusDefinition?.id,
                    operation: .equals,
                    value: .select("Todo")
                ),
            ],
            sorts: [ViewSort(propertyName: "Title", ascending: true)]
        )
        sourceDatabase.views = [tableView]
        storage.addDatabase(sourceDatabase)

        var linkedBlock = Block(type: .databaseEmbed, content: "Linked Source")
        linkedBlock.metadata["databaseID"] = sourceDatabase.id.uuidString
        linkedBlock.metadata["viewType"] = DatabaseViewType.table.rawValue
        linkedBlock.metadata["viewID"] = tableView.id.uuidString
        linkedBlock.metadata["source"] = "linked"

        var page = WorkspaceItem.page(title: "Linked Page")
        page.blocks = [linkedBlock]
        storage.addItem(page)

        await storage.forceSave()

        let reloaded = WorkspaceStorageServiceOptimized(baseDirectoryURL: temporaryDirectory, enableSwiftDataSync: false)
        let persistedPage = reloaded.item(withID: page.id)
        let persistedBlock = persistedPage?.blocks.first

        XCTAssertEqual(persistedBlock?.type, .databaseEmbed)
        XCTAssertEqual(persistedBlock?.metadata["databaseID"], sourceDatabase.id.uuidString)
        XCTAssertEqual(persistedBlock?.metadata["viewType"], DatabaseViewType.table.rawValue)
        XCTAssertEqual(persistedBlock?.metadata["viewID"], tableView.id.uuidString)
        let persistedDatabase = reloaded.database(withID: sourceDatabase.id)
        XCTAssertNotNil(persistedDatabase)
        XCTAssertTrue(persistedDatabase?.views.contains(where: { $0.id == tableView.id }) ?? false)
    }

    func testSavedViewFilterSortConfigurationPersists() async {
        var database = Database.taskBoard(name: "View Persistence Board")
        let statusProperty = database.properties.first(where: { $0.type == .status })
        let priorityProperty = database.properties.first(where: { $0.type == .priority })
        XCTAssertNotNil(statusProperty)
        XCTAssertNotNil(priorityProperty)

        let savedView = DatabaseView(
            name: "Only Todo",
            type: .table,
            filters: [
                ViewFilter(
                    propertyName: "Status",
                    propertyId: statusProperty?.id,
                    operation: .equals,
                    value: .select("Todo")
                ),
            ],
            sorts: [
                ViewSort(propertyName: "Priority", propertyId: priorityProperty?.id, ascending: false),
            ],
            visibleProperties: [statusProperty!.id, priorityProperty!.id],
            groupBy: "Status"
        )
        database.views = [savedView]
        storage.addDatabase(database)

        await storage.forceSave()

        let reloaded = WorkspaceStorageServiceOptimized(baseDirectoryURL: temporaryDirectory, enableSwiftDataSync: false)
        let persisted = reloaded.database(withID: database.id)
        let persistedView = persisted?.views.first
        XCTAssertEqual(persistedView?.name, "Only Todo")
        XCTAssertEqual(persistedView?.filters.count, 1)
        XCTAssertEqual(persistedView?.filters.first?.operation, .equals)
        XCTAssertEqual(persistedView?.sorts.count, 1)
        XCTAssertEqual(persistedView?.sorts.first?.ascending, false)
        XCTAssertEqual(persistedView?.groupBy, "Status")
        XCTAssertEqual(persistedView?.visibleProperties.count, 2)
    }

    func testRecoveryMarkerIsClearedOnNextLaunch() async {
        let database = Database.taskBoard(name: "Recovery Board")
        storage.addDatabase(database)
        _ = storage.createTask(title: "Task", databaseID: database.id)
        await storage.forceSave()

        let markerURL = temporaryDirectory.appendingPathComponent(".save_in_progress")
        try? Data("in_progress".utf8).write(to: markerURL, options: .atomic)
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))

        _ = WorkspaceStorageServiceOptimized(baseDirectoryURL: temporaryDirectory, enableSwiftDataSync: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
    }

    private func propertyKey(in database: Database, named name: String) -> String {
        if let definition = database.properties.first(where: { $0.name == name }) {
            return definition.storageKey
        }
        return PropertyDefinition.legacyKey(for: name)
    }
}

// MARK: - Baseline Metrics (Sprint 1)

@MainActor
final class WorkspaceBaselineMetricsTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var storage: WorkspaceStorageServiceOptimized!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoriusVoice-BaselineTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        storage = WorkspaceStorageServiceOptimized(baseDirectoryURL: temporaryDirectory, enableSwiftDataSync: false)
    }

    override func tearDown() {
        storage = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        super.tearDown()
    }

    func testBaselineSaveP95() async {
        let database = Database.taskBoard(name: "Baseline Save")
        storage.addDatabase(database)

        var task = storage.createTask(title: "Task 0", databaseID: database.id)
        for i in 1...40 {
            task.title = "Task \(i)"
            task.updatedAt = Date().addingTimeInterval(Double(i))
            storage.updateItem(task)
            await storage.flush(reason: .manual)
        }

        let metrics = storage.lastFlushMetrics()
        print("BASELINE save_p50_ms=\(formatted(metrics.p50DurationMs)) save_p95_ms=\(formatted(metrics.p95DurationMs))")
        XCTAssertTrue(metrics.success)
        XCTAssertGreaterThan(metrics.p95DurationMs, 0)
    }

    func testBaselineSearchP95() {
        let profiler = PerformanceProfiler.shared
        profiler.reset()

        for i in 0..<2500 {
            let item = WorkspaceItem(title: "Documento \(i) plan semanal", itemType: .page)
            storage.addItem(item)
        }

        let queries = ["Documento", "plan", "semanal", "Documento 2499", "inexistente"]
        for _ in 0..<80 {
            for query in queries {
                _ = try? profiler.measureSync(operation: "workspace_search_baseline") {
                    storage.items.filter { $0.title.localizedCaseInsensitiveContains(query) }
                }
            }
        }

        let p95 = profiler.percentileMs(operation: "workspace_search_baseline", percentile: 95)
        print("BASELINE search_p95_ms=\(formatted(p95))")
        XCTAssertGreaterThan(p95, 0)
    }

    func testBaselineVoiceCommandErrorRate() {
        let board = Database.taskBoard(name: "Voice Baseline")
        storage.addDatabase(board)
        _ = storage.createTask(title: "Preparar informe", databaseID: board.id)
        _ = storage.createTask(title: "Enviar resumen", databaseID: board.id)

        let sessionIntegration = SessionIntegrationService(workspaceStorage: storage, legacyStorage: nil)
        let voiceService = WorkspaceVoiceCommandsService(
            workspaceStorage: storage,
            sessionIntegration: sessionIntegration
        )

        let flows: [([String], Bool)] = [
            (["mover tarea enviar a done"], true),
            (["completar tarea preparar informe"], true),
            (["eliminar tarea enviar resumen", "sí"], true),
            (["mover tarea inexistente a done"], false),
            (["eliminar tarea no existe"], false),
        ]

        var failures = 0
        for (commands, expectedSuccess) in flows {
            for command in commands {
                XCTAssertTrue(voiceService.processVoiceInput(command))
            }
            let success = voiceService.lastCommandResult?.success ?? false
            XCTAssertEqual(success, expectedSuccess)
            if !success {
                failures += 1
            }
        }

        let errorRate = (Double(failures) / Double(flows.count)) * 100
        print("BASELINE voice_error_rate_pct=\(formatted(errorRate)) voice_total=\(flows.count)")
        XCTAssertGreaterThanOrEqual(errorRate, 0)
        XCTAssertLessThanOrEqual(errorRate, 100)
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

@MainActor
final class DatabaseViewQueryEngineTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var storage: WorkspaceStorageServiceOptimized!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoriusVoice-QueryEngineTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        storage = WorkspaceStorageServiceOptimized(baseDirectoryURL: temporaryDirectory, enableSwiftDataSync: false)
    }

    override func tearDown() {
        storage = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        super.tearDown()
    }

    func testApplyFiltersAndSortsWithPropertyIDs() {
        let database = Database.taskBoard(name: "Query Engine Board")
        storage.addDatabase(database)

        let statusDefinition = database.properties.first(where: { $0.type == .status })!
        let dueDateDefinition = database.properties.first(where: { $0.type == .date })!

        var taskA = storage.createTask(title: "Task A", databaseID: database.id, status: "Todo")
        taskA.properties[dueDateDefinition.storageKey] = .date(Date(timeIntervalSince1970: 1_738_000_300))
        storage.updateItem(taskA)

        var taskB = storage.createTask(title: "Task B", databaseID: database.id, status: "Todo")
        taskB.properties[dueDateDefinition.storageKey] = .date(Date(timeIntervalSince1970: 1_738_000_100))
        storage.updateItem(taskB)

        var taskC = storage.createTask(title: "Task C", databaseID: database.id, status: "Done")
        taskC.properties[dueDateDefinition.storageKey] = .date(Date(timeIntervalSince1970: 1_738_000_200))
        storage.updateItem(taskC)

        let filters = [
            ViewFilter(
                propertyName: "Status",
                propertyId: statusDefinition.id,
                operation: .equals,
                value: .select("Todo")
            ),
        ]
        let sorts = [
            ViewSort(
                propertyName: "Due Date",
                propertyId: dueDateDefinition.id,
                ascending: true
            ),
        ]

        let queried = DatabaseViewQueryEngine.apply(
            filters: filters,
            sorts: sorts,
            to: storage.items(inDatabase: database.id),
            database: database,
            storage: storage
        )

        XCTAssertEqual(queried.map(\.title), ["Task B", "Task A"])
    }

    func testApplySortByTitleWithoutPropertyID() {
        let database = Database.taskBoard(name: "Query Engine Titles")
        storage.addDatabase(database)

        _ = storage.createTask(title: "gamma", databaseID: database.id, status: "Todo")
        _ = storage.createTask(title: "alpha", databaseID: database.id, status: "Todo")
        _ = storage.createTask(title: "beta", databaseID: database.id, status: "Todo")

        let queried = DatabaseViewQueryEngine.apply(
            filters: [],
            sorts: [ViewSort(propertyName: "Title", propertyId: nil, ascending: true)],
            to: storage.items(inDatabase: database.id),
            database: database,
            storage: storage
        )

        XCTAssertEqual(queried.map(\.title), ["alpha", "beta", "gamma"])
    }

    func testApplyFilterUsesPropertyIDWhenPropertyNameIsStale() {
        let database = Database.taskBoard(name: "Query Engine Filter ID Priority")
        storage.addDatabase(database)

        let statusDefinition = database.properties.first(where: { $0.type == .status })!
        _ = storage.createTask(title: "Task Todo", databaseID: database.id, status: "Todo")
        _ = storage.createTask(title: "Task Done", databaseID: database.id, status: "Done")

        let queried = DatabaseViewQueryEngine.apply(
            filters: [
                ViewFilter(
                    propertyName: "Estado Antiguo",
                    propertyId: statusDefinition.id,
                    operation: .equals,
                    value: .select("Todo")
                ),
            ],
            sorts: [],
            to: storage.items(inDatabase: database.id),
            database: database,
            storage: storage
        )

        XCTAssertEqual(queried.map(\.title), ["Task Todo"])
    }

    func testApplySortUsesPropertyIDWhenPropertyNameIsStale() {
        let database = Database.taskBoard(name: "Query Engine Sort ID Priority")
        storage.addDatabase(database)

        let dueDateDefinition = database.properties.first(where: { $0.type == .date })!

        var taskA = storage.createTask(title: "Task A", databaseID: database.id, status: "Todo")
        taskA.properties[dueDateDefinition.storageKey] = .date(Date(timeIntervalSince1970: 1_738_010_300))
        storage.updateItem(taskA)

        var taskB = storage.createTask(title: "Task B", databaseID: database.id, status: "Todo")
        taskB.properties[dueDateDefinition.storageKey] = .date(Date(timeIntervalSince1970: 1_738_010_100))
        storage.updateItem(taskB)

        let queried = DatabaseViewQueryEngine.apply(
            filters: [],
            sorts: [ViewSort(propertyName: "Fecha antigua", propertyId: dueDateDefinition.id, ascending: true)],
            to: storage.items(inDatabase: database.id),
            database: database,
            storage: storage
        )

        XCTAssertEqual(queried.map(\.title), ["Task B", "Task A"])
    }
}

// MARK: - Performance Integration Tests

@MainActor
final class PerformanceIntegrationTests: XCTestCase {
    
    var mockStorage: MockWorkspaceStorage!
    
    override func setUp() {
        super.setUp()
        mockStorage = MockWorkspaceStorage()
    }
    
    override func tearDown() {
        mockStorage = nil
        super.tearDown()
    }
    
    func testCreateManyItemsPerformance() {
        measure {
            for i in 0..<1000 {
                let item = WorkspaceItem(title: "Item \(i)", itemType: .page)
                mockStorage.addItem(item)
            }
        }
    }
    
    func testSearchPerformanceWith1000Items() {
        // Setup
        for i in 0..<1000 {
            let item = WorkspaceItem(title: "Item \(i)", itemType: .page)
            mockStorage.addItem(item)
        }
        
        let viewModel = WorkspaceViewModel(storage: mockStorage)
        
        // Measure search
        measure {
            viewModel.searchText = "Item"
            _ = viewModel.filteredItems
        }
    }
    
    func testFilteringPerformanceWith1000Items() {
        // Setup - create 500 pages and 500 databases
        for i in 0..<500 {
            let page = WorkspaceItem(title: "Page \(i)", itemType: .page)
            mockStorage.addItem(page)
            
            let db = WorkspaceItem(title: "DB \(i)", itemType: .database)
            mockStorage.addItem(db)
        }
        
        let viewModel = WorkspaceViewModel(storage: mockStorage)
        
        // Measure filtering
        measure {
            viewModel.setCategory(.page)
            _ = viewModel.filteredItems
        }
    }
}

// MARK: - Storage Hardening Tests

@MainActor
final class WorkspaceStorageHardeningTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoriusVoice-StorageTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        super.tearDown()
    }

    func testBurstUpdatesPersistLatestState() async {
        let storage = WorkspaceStorageServiceOptimized(baseDirectoryURL: temporaryDirectory, enableSwiftDataSync: false)
        let database = Database.taskBoard(name: "Stress DB")
        storage.addDatabase(database)

        var item = WorkspaceItem.task(title: "Task 0", workspaceID: database.id, status: "Todo")
        storage.addItem(item)

        for i in 1...120 {
            item.title = "Task \(i)"
            item.updatedAt = Date().addingTimeInterval(Double(i))
            storage.updateItem(item)
        }

        await storage.forceSave()
        let metrics = storage.lastFlushMetrics()
        XCTAssertTrue(metrics.success)
        XCTAssertGreaterThan(metrics.durationMs, 0)
        XCTAssertGreaterThanOrEqual(metrics.p95DurationMs, 0)

        let reloaded = WorkspaceStorageServiceOptimized(baseDirectoryURL: temporaryDirectory, enableSwiftDataSync: false)
        let persisted = reloaded.item(withID: item.id)
        XCTAssertEqual(persisted?.title, "Task 120")
    }

    func testFlushIfPendingIsSafeWithoutWrites() async {
        let storage = WorkspaceStorageServiceOptimized(baseDirectoryURL: temporaryDirectory, enableSwiftDataSync: false)
        await storage.flushIfPending()
        let metrics = storage.lastFlushMetrics()
        XCTAssertTrue(metrics.success)
    }
}

// MARK: - Voice Command Tests

@MainActor
final class WorkspaceVoiceCommandsServiceTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var storage: WorkspaceStorageServiceOptimized!
    private var voiceService: WorkspaceVoiceCommandsService!

    private func makeVoiceTestBoard(name: String = "Voice Commands Board") -> Database {
        let database = Database.taskBoard(name: name)
        storage.addDatabase(database)
        return database
    }

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoriusVoice-VoiceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        storage = WorkspaceStorageServiceOptimized(baseDirectoryURL: temporaryDirectory, enableSwiftDataSync: false)
        voiceService = WorkspaceVoiceCommandsService(workspaceStorage: storage)
    }

    override func tearDown() {
        voiceService = nil
        storage = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        super.tearDown()
    }

    func testMoveTaskAmbiguityRequiresConfirmationAndMovesAfterYes() {
        let database = makeVoiceTestBoard()
        let targetColumn = database.kanbanColumns.last!

        let taskA = storage.createTask(title: "Preparar informe", databaseID: database.id)
        let taskB = storage.createTask(title: "Preparar roadmap", databaseID: database.id)
        XCTAssertNotNil(storage.item(withID: taskA.id))
        XCTAssertNotNil(storage.item(withID: taskB.id))

        let command = "mover tarea preparar a \(targetColumn.name.lowercased())"
        let recognized = voiceService.processVoiceInput(command)
        XCTAssertTrue(recognized)

        let firstResult = voiceService.lastCommandResult
        XCTAssertEqual(firstResult?.command, .moveTask)
        XCTAssertFalse(firstResult?.success ?? true)
        XCTAssertTrue(firstResult?.outcome?.requiresConfirmation ?? false)
        XCTAssertTrue(firstResult?.outcome?.ambiguity ?? false)

        let confirmationRecognized = voiceService.processVoiceInput("sí")
        XCTAssertTrue(confirmationRecognized)

        let finalResult = voiceService.lastCommandResult
        XCTAssertEqual(finalResult?.command, .moveTask)
        XCTAssertTrue(finalResult?.success ?? false)

        let movedTasks = storage.items(inDatabase: database.id).filter { item in
            storage.statusValue(for: item) == targetColumn.name
        }
        XCTAssertEqual(movedTasks.count, 1)
    }

    func testDeleteTaskRequiresConfirmationAndRespectsNoThenYes() {
        let database = makeVoiceTestBoard(name: "Voice Delete Board")

        let task = storage.createTask(title: "Eliminar demo", databaseID: database.id)
        XCTAssertNotNil(storage.item(withID: task.id))

        let firstRecognized = voiceService.processVoiceInput("eliminar tarea eliminar demo")
        XCTAssertTrue(firstRecognized)
        XCTAssertNotNil(storage.item(withID: task.id), "Task should not be deleted before confirmation")
        XCTAssertTrue(voiceService.lastCommandResult?.outcome?.requiresConfirmation ?? false)

        let rejectRecognized = voiceService.processVoiceInput("no")
        XCTAssertTrue(rejectRecognized)
        XCTAssertNotNil(storage.item(withID: task.id), "Task should remain after rejection")
        XCTAssertEqual(voiceService.lastCommandResult?.message, "Acción cancelada")

        _ = voiceService.processVoiceInput("eliminar tarea eliminar demo")
        XCTAssertNotNil(storage.item(withID: task.id), "Task should still exist until accepted")

        let acceptRecognized = voiceService.processVoiceInput("sí")
        XCTAssertTrue(acceptRecognized)
        XCTAssertNil(storage.item(withID: task.id), "Task should be deleted after confirmation")
        XCTAssertEqual(voiceService.lastCommandResult?.command, .deleteTask)
        XCTAssertTrue(voiceService.lastCommandResult?.success ?? false)
    }

    func testCompleteTaskAmbiguityRequiresConfirmationAndCompletesAfterYes() {
        let database = makeVoiceTestBoard(name: "Voice Complete Board")
        let doneColumn = database.kanbanColumns.first(where: {
            $0.name.lowercased().contains("done")
                || $0.name.lowercased().contains("complet")
                || $0.name.lowercased().contains("hecho")
        })
        XCTAssertNotNil(doneColumn)

        var taskA = storage.createTask(title: "Preparar informe", databaseID: database.id)
        taskA.updatedAt = Date(timeIntervalSince1970: 1_738_000_000)
        storage.updateItem(taskA)

        var taskB = storage.createTask(title: "Preparar resumen", databaseID: database.id)
        taskB.updatedAt = Date(timeIntervalSince1970: 1_738_000_100)
        storage.updateItem(taskB)

        XCTAssertTrue(voiceService.processVoiceInput("completar tarea preparar"))
        XCTAssertFalse(voiceService.lastCommandResult?.success ?? true)
        XCTAssertTrue(voiceService.lastCommandResult?.outcome?.requiresConfirmation ?? false)
        XCTAssertTrue(voiceService.lastCommandResult?.outcome?.ambiguity ?? false)

        XCTAssertTrue(voiceService.processVoiceInput("sí"))
        XCTAssertTrue(voiceService.lastCommandResult?.success ?? false)
        XCTAssertEqual(voiceService.lastCommandResult?.command, .completeTask)

        let doneTasks = storage.items(inDatabase: database.id).filter { item in
            storage.statusValue(for: item) == doneColumn?.name
        }
        XCTAssertEqual(doneTasks.count, 1)
    }

    func testOpenPageWithoutContextFailsSafely() {
        _ = storage.createItem(WorkspaceItem.page(title: "Roadmap 2026"))

        XCTAssertTrue(voiceService.processVoiceInput("abrir página"))
        XCTAssertEqual(voiceService.lastCommandResult?.command, .openPage)
        XCTAssertFalse(voiceService.lastCommandResult?.success ?? true)
        XCTAssertEqual(voiceService.lastCommandResult?.message, "Especifica qué página abrir")
    }

    func testOpenPageAmbiguityRequiresConfirmationAndOpensAfterYes() {
        var pageA = WorkspaceItem.page(title: "Roadmap Alpha")
        pageA.updatedAt = Date(timeIntervalSince1970: 1_738_000_000)
        _ = storage.createItem(pageA)

        var pageB = WorkspaceItem.page(title: "Roadmap Beta")
        pageB.updatedAt = Date(timeIntervalSince1970: 1_738_000_100)
        _ = storage.createItem(pageB)

        let openedExpectation = expectation(description: "Open page notification")
        var openedPageID: UUID?
        let token = NotificationCenter.default.addObserver(
            forName: .openWorkspacePage,
            object: nil,
            queue: .main
        ) { notification in
            openedPageID = notification.userInfo?["pageID"] as? UUID
            openedExpectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        XCTAssertTrue(voiceService.processVoiceInput("abrir página roadmap"))
        XCTAssertFalse(voiceService.lastCommandResult?.success ?? true)
        XCTAssertTrue(voiceService.lastCommandResult?.outcome?.requiresConfirmation ?? false)
        XCTAssertTrue(voiceService.lastCommandResult?.outcome?.ambiguity ?? false)

        XCTAssertTrue(voiceService.processVoiceInput("sí"))
        wait(for: [openedExpectation], timeout: 1.0)

        XCTAssertTrue(voiceService.lastCommandResult?.success ?? false)
        XCTAssertEqual(voiceService.lastCommandResult?.command, .openPage)
        XCTAssertEqual(openedPageID, pageB.id)
    }

    func testVoiceMetricsUseCanonicalIntentNames() {
        let database = makeVoiceTestBoard(name: "Voice Metric Board")
        _ = storage.createTask(title: "Eliminar demo", databaseID: database.id)

        XCTAssertTrue(voiceService.processVoiceInput("eliminar tarea eliminar demo"))

        guard let lastMetric = storage.recentMetricEvents(limit: 1).first else {
            return XCTFail("Expected at least one metric event")
        }

        guard case let .voiceCommand(intent, success, reason, _) = lastMetric else {
            return XCTFail("Expected voice command metric")
        }

        XCTAssertEqual(intent, "deleteTask")
        XCTAssertFalse(success)
        XCTAssertEqual(reason, "Destructive command requires confirmation")
    }
}

@MainActor
final class WorkspaceAgentActionServiceTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var storage: WorkspaceStorageServiceOptimized!
    private var agent: WorkspaceAgentActionService!

    override func setUp() {
        super.setUp()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoriusVoice-AgentTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        storage = WorkspaceStorageServiceOptimized(baseDirectoryURL: temporaryDirectory, enableSwiftDataSync: false)
        agent = WorkspaceAgentActionService(workspaceStorage: storage)
    }

    override func tearDown() {
        agent = nil
        storage = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        super.tearDown()
    }

    func testCreateTaskAndRollback() {
        let database = Database.taskBoard(name: "Agent Board")
        storage.addDatabase(database)

        let createResult = agent.execute(
            request: .init(
                action: .createTask,
                title: "Agent Created Task",
                databaseID: database.id,
                taskID: nil,
                taskQuery: nil,
                targetStatus: nil,
                itemID: nil,
                itemQuery: nil
            )
        )
        XCTAssertTrue(createResult.success)
        XCTAssertFalse(createResult.requiresConfirmation)

        let createdTask = storage.items(inDatabase: database.id).first(where: { $0.title == "Agent Created Task" })
        XCTAssertNotNil(createdTask)

        let rollbackResult = agent.rollbackLastAction()
        XCTAssertTrue(rollbackResult.success)
        XCTAssertNil(storage.items(inDatabase: database.id).first(where: { $0.title == "Agent Created Task" }))
    }

    func testDeleteItemRequiresConfirmationAndRollbackRestoresItem() throws {
        let database = Database.taskBoard(name: "Agent Delete Board")
        storage.addDatabase(database)
        let task = storage.createTask(title: "Delete Me", databaseID: database.id)

        let pending = agent.execute(
            request: .init(
                action: .deleteItem,
                title: nil,
                databaseID: nil,
                taskID: nil,
                taskQuery: nil,
                targetStatus: nil,
                itemID: task.id,
                itemQuery: nil
            )
        )
        XCTAssertFalse(pending.success)
        XCTAssertTrue(pending.requiresConfirmation)
        XCTAssertNotNil(storage.item(withID: task.id))

        let token = try XCTUnwrap(pending.confirmationToken)
        let confirmed = agent.confirm(token: token, accept: true)
        XCTAssertTrue(confirmed.success)
        XCTAssertNil(storage.item(withID: task.id))

        let rollback = agent.rollbackLastAction()
        XCTAssertTrue(rollback.success)
        XCTAssertNotNil(storage.item(withID: task.id))
    }

    func testMoveTaskAmbiguityRequiresConfirmationThenMovesAndRollsBack() throws {
        let database = Database.taskBoard(name: "Agent Move Board")
        storage.addDatabase(database)
        _ = storage.createTask(title: "Preparar informe", databaseID: database.id, status: "Todo")
        _ = storage.createTask(title: "Preparar roadmap", databaseID: database.id, status: "Todo")

        let pending = agent.execute(
            request: .init(
                action: .moveTask,
                title: nil,
                databaseID: nil,
                taskID: nil,
                taskQuery: "Preparar",
                targetStatus: "done",
                itemID: nil,
                itemQuery: nil
            )
        )
        XCTAssertFalse(pending.success)
        XCTAssertTrue(pending.requiresConfirmation)

        let token = try XCTUnwrap(pending.confirmationToken)
        let confirmed = agent.confirm(token: token, accept: true)
        XCTAssertTrue(confirmed.success)

        let doneCountAfterMove = storage.items(inDatabase: database.id).filter { item in
            storage.statusValue(for: item) == "Done"
        }.count
        XCTAssertEqual(doneCountAfterMove, 1)

        let rollback = agent.rollbackLastAction()
        XCTAssertTrue(rollback.success)

        let doneCountAfterRollback = storage.items(inDatabase: database.id).filter { item in
            storage.statusValue(for: item) == "Done"
        }.count
        XCTAssertEqual(doneCountAfterRollback, 0)
    }

    func testRejectingConfirmationCancelsPendingActionAndKeepsItem() throws {
        let database = Database.taskBoard(name: "Agent Reject Board")
        storage.addDatabase(database)
        let task = storage.createTask(title: "Keep Me", databaseID: database.id)

        let pending = agent.execute(
            request: .init(
                action: .deleteItem,
                title: nil,
                databaseID: nil,
                taskID: nil,
                taskQuery: nil,
                targetStatus: nil,
                itemID: task.id,
                itemQuery: nil
            )
        )
        let token = try XCTUnwrap(pending.confirmationToken)
        let canceled = agent.confirm(token: token, accept: false)

        XCTAssertFalse(canceled.success)
        XCTAssertNotNil(storage.item(withID: task.id))
        XCTAssertTrue(agent.recentAudit(limit: 2).contains(where: { $0.status == .canceled }))
    }
}
