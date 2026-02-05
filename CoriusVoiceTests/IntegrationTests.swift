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
        
        // 2. Test search
        workspaceVM.searchText = "Project"
        var filtered = workspaceVM.filteredItems
        XCTAssertEqual(filtered.count, 2)
        
        // 3. Add category filter
        workspaceVM.setCategory(.page)
        filtered = workspaceVM.filteredItems
        
        // Should only have items that match "Project" AND are of type .page
        XCTAssertLessThanOrEqual(filtered.count, 1)
        
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
        let childIDs = Set([child1ID, child2ID])
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
        XCTAssertNotEqual(simplePageVM.item.blocks[1].type, .heading1)
        
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
    
    func testConcurrentOperations() {
        let dispatchGroup = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        
        // Create 100 items concurrently
        for i in 0..<100 {
            dispatchGroup.enter()
            queue.async {
                DispatchQueue.main.async {
                    let item = WorkspaceItem(title: "Item \(i)", itemType: .page)
                    self.mockStorage.addItem(item)
                    dispatchGroup.leave()
                }
            }
        }
        
        dispatchGroup.wait()
        
        XCTAssertEqual(mockStorage.items.count, 100)
        XCTAssertEqual(workspaceVM.hasItems, true)
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
