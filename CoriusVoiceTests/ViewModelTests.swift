import XCTest
@testable import CoriusVoice

// MARK: - Workspace View Model Tests

@MainActor
final class WorkspaceViewModelTests: XCTestCase {
    
    var sut: WorkspaceViewModel!
    var mockStorage: MockWorkspaceStorage!
    
    override func setUp() {
        super.setUp()
        mockStorage = MockWorkspaceStorage()
        sut = WorkspaceViewModel(storage: mockStorage)
    }
    
    override func tearDown() {
        sut = nil
        mockStorage = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitializesWithEmptyState() {
        XCTAssertEqual(sut.searchText, "")
        XCTAssertNil(sut.selectedItemID)
        XCTAssertNil(sut.selectedCategory)
        XCTAssertFalse(sut.showingNewItemSheet)
    }
    
    // MARK: - Create Item Tests
    
    func testCreateNewItem() {
        let type = WorkspaceItemType.page
        let initialCount = mockStorage.items.count
        
        sut.createNewItem(type: type)
        
        XCTAssertEqual(mockStorage.items.count, initialCount + 1)
        XCTAssertEqual(mockStorage.getCallCount(for: "addItem(_:)"), 1)
    }
    
    func testCreateNewItemWithParent() {
        let parentID = UUID()
        let type = WorkspaceItemType.page
        
        sut.createNewItem(type: type, in: parentID)
        
        let addedItem = mockStorage.item(withID: sut.selectedItemID ?? UUID())
        XCTAssertEqual(addedItem?.parentID, parentID)
    }
    
    // MARK: - Delete Item Tests
    
    func testDeleteItem() {
        let item = WorkspaceItem(title: "Test", itemType: .page)
        mockStorage.addItem(item)
        let initialCount = mockStorage.items.count
        
        sut.deleteItem(item.id)
        
        XCTAssertEqual(mockStorage.items.count, initialCount - 1)
        XCTAssertEqual(mockStorage.getCallCount(for: "deleteItem(_:)"), 1)
    }
    
    func testDeleteItemClearsSelection() {
        let item = WorkspaceItem(title: "Test", itemType: .page)
        mockStorage.addItem(item)
        sut.selectItem(item.id)
        
        sut.deleteItem(item.id)
        
        XCTAssertNil(sut.selectedItemID)
    }
    
    // MARK: - Favorite Tests
    
    func testToggleFavorite() {
        let item = WorkspaceItem(title: "Test", itemType: .page)
        mockStorage.addItem(item)
        
        XCTAssertFalse(mockStorage.item(withID: item.id)?.isFavorite ?? false)
        
        sut.toggleFavorite(itemID: item.id)
        
        XCTAssertTrue(mockStorage.item(withID: item.id)?.isFavorite ?? false)
        
        sut.toggleFavorite(itemID: item.id)
        
        XCTAssertFalse(mockStorage.item(withID: item.id)?.isFavorite ?? false)
    }
    
    // MARK: - Archive Tests
    
    func testArchiveItem() {
        let item = WorkspaceItem(title: "Test", itemType: .page)
        mockStorage.addItem(item)
        
        sut.archiveItem(item.id)
        
        XCTAssertTrue(mockStorage.item(withID: item.id)?.isArchived ?? false)
    }
    
    func testArchiveItemClearsSelection() {
        let item = WorkspaceItem(title: "Test", itemType: .page)
        mockStorage.addItem(item)
        sut.selectItem(item.id)
        
        sut.archiveItem(item.id)
        
        XCTAssertNil(sut.selectedItemID)
    }
    
    // MARK: - Selection Tests
    
    func testSelectItem() {
        let item = WorkspaceItem(title: "Test", itemType: .page)
        mockStorage.addItem(item)
        
        sut.selectItem(item.id)
        
        XCTAssertEqual(sut.selectedItemID, item.id)
    }
    
    // MARK: - Search Tests
    
    func testSearchFiltersItems() {
        let item1 = WorkspaceItem(title: "Apples", itemType: .page)
        let item2 = WorkspaceItem(title: "Bananas", itemType: .page)
        mockStorage.seedData(databases: [], items: [item1, item2])
        
        sut.searchText = "Apple"
        
        let filtered = sut.filteredItems
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.title, "Apples")
    }
    
    func testClearSearch() {
        sut.searchText = "something"
        sut.clearSearch()
        XCTAssertEqual(sut.searchText, "")
    }
    
    // MARK: - Category Tests
    
    func testSetCategory() {
        sut.setCategory(.page)
        XCTAssertEqual(sut.selectedCategory, .page)
        
        sut.setCategory(nil)
        XCTAssertNil(sut.selectedCategory)
    }
    
    // MARK: - Computed Properties Tests
    
    func testFavoriteItems() {
        let item1 = WorkspaceItem(title: "Fav", itemType: .page, isFavorite: true)
        let item2 = WorkspaceItem(title: "Regular", itemType: .page, isFavorite: false)
        mockStorage.seedData(databases: [], items: [item1, item2])
        
        XCTAssertEqual(sut.favoriteItems.count, 1)
        XCTAssertEqual(sut.favoriteItems.first?.title, "Fav")
    }
    
    func testRecentItems() {
        let item1 = WorkspaceItem(title: "Old", itemType: .page)
        let item2 = WorkspaceItem(title: "New", itemType: .page)
        mockStorage.seedData(databases: [], items: [item1, item2])
        
        XCTAssertEqual(sut.recentItems.count, 2)
    }
    
    func testHasItems() {
        XCTAssertFalse(sut.hasItems)
        
        let item = WorkspaceItem(title: "Test", itemType: .page)
        mockStorage.addItem(item)
        
        XCTAssertTrue(sut.hasItems)
    }
}

// MARK: - Simple Page View Model Tests

@MainActor
final class SimplePageViewModelTests: XCTestCase {
    
    var sut: SimplePageViewModel!
    var mockStorage: MockWorkspaceStorage!
    var testItem: WorkspaceItem!
    
    override func setUp() {
        super.setUp()
        mockStorage = MockWorkspaceStorage()
        testItem = WorkspaceItem(title: "Test Page", itemType: .page)
        sut = SimplePageViewModel(item: testItem, storage: mockStorage)
    }
    
    override func tearDown() {
        sut = nil
        mockStorage = nil
        testItem = nil
        super.tearDown()
    }
    
    // MARK: - Block Management Tests
    
    func testAddBlock() {
        let initialCount = sut.blockCount
        sut.addBlock(at: 0, type: .paragraph)
        
        XCTAssertEqual(sut.blockCount, initialCount + 1)
    }
    
    func testDeleteBlock() {
        sut.addBlock(at: 0, type: .paragraph)
        let blockID = sut.item.blocks[0].id
        let initialCount = sut.blockCount
        
        sut.deleteBlock(blockID)
        
        XCTAssertEqual(sut.blockCount, initialCount - 1)
    }
    
    func testDeleteBlockClearsFocus() {
        sut.addBlock(at: 0, type: .paragraph)
        let blockID = sut.item.blocks[0].id
        sut.focusBlock(blockID)
        
        sut.deleteBlock(blockID)
        
        XCTAssertNil(sut.focusedBlockID)
    }
    
    func testUpdateBlock() {
        sut.addBlock(at: 0, type: .paragraph)
        let blockID = sut.item.blocks[0].id
        
        sut.updateBlock(blockID, content: "New content")
        
        let block = sut.block(withID: blockID)
        XCTAssertEqual(block?.content, "New content")
    }
    
    func testMoveBlock() {
        sut.addBlock(at: 0, type: .paragraph)
        sut.addBlock(at: 1, type: .heading1)
        
        let firstBlockID = sut.item.blocks[0].id
        
        sut.moveBlock(from: 0, to: 1)
        
        XCTAssertNotEqual(sut.item.blocks[0].id, firstBlockID)
    }
    
    func testDuplicateBlock() {
        sut.addBlock(at: 0, type: .paragraph)
        sut.updateBlock(sut.item.blocks[0].id, content: "Test content")
        let initialCount = sut.blockCount
        
        let blockID = sut.item.blocks[0].id
        sut.duplicateBlock(blockID)
        
        XCTAssertEqual(sut.blockCount, initialCount + 1)
        XCTAssertEqual(sut.item.blocks[1].content, "Test content")
    }
    
    func testChangeBlockType() {
        sut.addBlock(at: 0, type: .paragraph)
        let blockID = sut.item.blocks[0].id
        
        sut.changeBlockType(blockID, to: .heading1)
        
        let block = sut.block(withID: blockID)
        XCTAssertEqual(block?.type, .heading1)
    }
    
    // MARK: - Title & Metadata Tests
    
    func testUpdateTitle() {
        sut.updateTitle("New Title")
        XCTAssertEqual(sut.item.title, "New Title")
    }
    
    // MARK: - Focus Tests
    
    func testFocusBlock() {
        sut.addBlock(at: 0, type: .paragraph)
        let blockID = sut.item.blocks[0].id
        
        sut.focusBlock(blockID)
        
        XCTAssertEqual(sut.focusedBlockID, blockID)
    }
    
    // MARK: - Saving Tests
    
    func testSaveRecordsUpdate() {
        mockStorage.resetCallTracking()
        sut.addBlock(at: 0, type: .paragraph)
        
        // Wait for debounce
        let expectation = self.expectation(description: "Save debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 2)
        
        // La actualización se registra en el mock
        XCTAssertGreaterThan(mockStorage.getCallCount(for: "updateItem(_:)"), 0)
    }
    
    // MARK: - State Query Tests
    
    func testBlockCount() {
        XCTAssertEqual(sut.blockCount, 0)
        
        sut.addBlock(at: 0, type: .paragraph)
        XCTAssertEqual(sut.blockCount, 1)
    }
    
    func testBlockWithID() {
        sut.addBlock(at: 0, type: .paragraph)
        let blockID = sut.item.blocks[0].id
        
        let block = sut.block(withID: blockID)
        XCTAssertNotNil(block)
        XCTAssertEqual(block?.id, blockID)
    }
}

// MARK: - Kanban Board View Model Tests

@MainActor
final class KanbanBoardViewModelTests: XCTestCase {
    
    var sut: KanbanBoardViewModel!
    var mockStorage: MockWorkspaceStorage!
    var testDatabase: Database!
    
    override func setUp() {
        super.setUp()
        mockStorage = MockWorkspaceStorage()
        testDatabase = Database.taskBoard(name: "Tasks")
        mockStorage.addDatabase(testDatabase)
        sut = KanbanBoardViewModel(databaseID: testDatabase.id, storage: mockStorage)
    }
    
    override func tearDown() {
        sut = nil
        mockStorage = nil
        testDatabase = nil
        super.tearDown()
    }
    
    // MARK: - Column Tests
    
    func testAddColumn() {
        let initialCount = sut.columns.count
        sut.addColumn(named: "New Column")
        
        XCTAssertEqual(sut.columns.count, initialCount + 1)
    }
    
    func testUpdateColumn() {
        sut.addColumn(named: "Original")
        let columnID = sut.columns[0].id
        
        sut.updateColumn(id: columnID, name: "Updated")
        
        XCTAssertEqual(sut.columns[0].name, "Updated")
    }
    
    func testDeleteColumn() {
        sut.addColumn(named: "To Delete")
        let initialCount = sut.columns.count
        let columnID = sut.columns[0].id
        
        sut.deleteColumn(columnID)
        
        XCTAssertEqual(sut.columns.count, initialCount - 1)
    }
    
    // MARK: - Card Tests
    
    func testAddCard() {
        sut.addColumn(named: "Todo")
        let columnID = sut.columns[0].id
        let initialCount = sut.cards.count
        
        sut.addCard(titled: "New Task", to: columnID)
        
        XCTAssertEqual(sut.cards.count, initialCount + 1)
    }
    
    func testMoveCard() {
        sut.addColumn(named: "Todo")
        sut.addColumn(named: "Done")
        
        let todoColumnID = sut.columns[0].id
        let doneColumnID = sut.columns[1].id
        
        sut.addCard(titled: "Task", to: todoColumnID)
        let cardID = sut.cards[0].id
        
        sut.moveCard(id: cardID, to: doneColumnID)
        
        let movedCard = mockStorage.item(withID: cardID)
        XCTAssertEqual(movedCard?.statusValue, "Done")
    }
    
    func testDeleteCard() {
        sut.addColumn(named: "Todo")
        let columnID = sut.columns[0].id
        sut.addCard(titled: "Task", to: columnID)
        let cardID = sut.cards[0].id
        let initialCount = sut.cards.count
        
        sut.deleteCard(cardID)
        
        XCTAssertEqual(sut.cards.count, initialCount - 1)
    }
    
    func testDeleteCardClearsSelection() {
        sut.addColumn(named: "Todo")
        let columnID = sut.columns[0].id
        sut.addCard(titled: "Task", to: columnID)
        let cardID = sut.cards[0].id
        
        sut.selectCard(cardID)
        sut.deleteCard(cardID)
        
        XCTAssertNil(sut.selectedCardID)
    }
    
    // MARK: - Expansion Tests
    
    func testToggleColumnExpansion() {
        sut.addColumn(named: "Todo")
        let columnID = sut.columns[0].id
        
        XCTAssertFalse(sut.isColumnExpanded(columnID))
        
        sut.toggleColumnExpansion(columnID)
        XCTAssertTrue(sut.isColumnExpanded(columnID))
        
        sut.toggleColumnExpansion(columnID)
        XCTAssertFalse(sut.isColumnExpanded(columnID))
    }
    
    // MARK: - Statistics Tests
    
    func testCompletionPercentage() {
        sut.addColumn(named: "Todo")
        let columnID = sut.columns[0].id
        
        sut.addCard(titled: "Task 1", to: columnID)
        sut.addCard(titled: "Task 2", to: columnID)
        
        XCTAssertEqual(sut.completionPercentage, 0)
    }
    
    func testCardCount() {
        sut.addColumn(named: "Todo")
        let columnID = sut.columns[0].id
        
        sut.addCard(titled: "Task 1", to: columnID)
        sut.addCard(titled: "Task 2", to: columnID)
        
        XCTAssertEqual(sut.cardCount(in: columnID), 2)
    }
}
