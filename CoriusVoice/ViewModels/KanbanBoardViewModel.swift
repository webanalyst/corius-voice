import Foundation
import SwiftUI

// MARK: - Kanban Board View Model

/// ViewModel para gestionar la lógica de tableros Kanban
@MainActor
class KanbanBoardViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    let storage: any WorkspaceStorageProtocol
    let databaseID: UUID
    
    // MARK: - Published State
    
    @Published var database: Database?
    @Published var selectedCardID: UUID?
    @Published var showingNewCardSheet = false
    @Published var draggedCardID: UUID?
    @Published var draggedFromColumn: UUID?
    @Published var expandedColumns: Set<UUID> = []
    
    // MARK: - Initialization
    
    init(databaseID: UUID, storage: any WorkspaceStorageProtocol = WorkspaceStorageServiceOptimized.shared) {
        self.databaseID = databaseID
        self.storage = storage
        self.database = storage.database(withID: databaseID)
    }
    
    // MARK: - Columns & Cards
    
    var columns: [KanbanColumn] {
        database?.sortedColumns ?? []
    }
    
    var cards: [WorkspaceItem] {
        storage.items(inDatabase: databaseID)
    }
    
    func cardsInColumn(_ columnID: UUID) -> [WorkspaceItem] {
        guard let column = columns.first(where: { $0.id == columnID }) else { return [] }
        return cards.filter { $0.statusValue == column.name }
    }
    
    // MARK: - Column Operations
    
    func addColumn(named name: String) {
        guard var db = database else { return }
        let column = KanbanColumn(name: name, color: "#3B82F6", sortOrder: db.kanbanColumns.count)
        db.kanbanColumns.append(column)
        storage.updateDatabase(db)
        self.database = db
    }
    
    func updateColumn(id: UUID, name: String) {
        guard var db = database else { return }
        if let index = db.kanbanColumns.firstIndex(where: { $0.id == id }) {
            db.kanbanColumns[index].name = name
            storage.updateDatabase(db)
            self.database = db
        }
    }
    
    func deleteColumn(_ id: UUID) {
        guard var db = database else { return }
        db.kanbanColumns.removeAll { $0.id == id }
        storage.updateDatabase(db)
        self.database = db
    }
    
    func reorderColumns(_ columns: [KanbanColumn]) {
        guard var db = database else { return }
        db.kanbanColumns = columns.enumerated().map { index, column in
            var col = column
            col.sortOrder = index
            return col
        }
        storage.updateDatabase(db)
        self.database = db
    }
    
    // MARK: - Card Operations
    
    func addCard(titled title: String, to columnID: UUID) {
        guard let column = columns.first(where: { $0.id == columnID }) else { return }
        let newCard = WorkspaceItem.task(title: title, workspaceID: databaseID, status: column.name)
        storage.addItem(newCard)
        selectedCardID = newCard.id
    }
    
    func updateCard(id: UUID, columnID: UUID) {
          guard var card = storage.item(withID: id),
              let column = columns.first(where: { $0.id == columnID }) else { return }
          card.setStatus(column.name)
        storage.updateItem(card)
    }
    
    func moveCard(id: UUID, to columnID: UUID) {
        updateCard(id: id, columnID: columnID)
    }
    
    func deleteCard(_ id: UUID) {
        if selectedCardID == id {
            selectedCardID = nil
        }
        storage.deleteItem(id)
    }
    
    func selectCard(_ id: UUID) {
        selectedCardID = id
    }
    
    // MARK: - Expansion State
    
    func toggleColumnExpansion(_ columnID: UUID) {
        if expandedColumns.contains(columnID) {
            expandedColumns.remove(columnID)
        } else {
            expandedColumns.insert(columnID)
        }
    }
    
    func isColumnExpanded(_ columnID: UUID) -> Bool {
        expandedColumns.contains(columnID)
    }
    
    // MARK: - Statistics
    
    func cardCount(in columnID: UUID) -> Int {
        cardsInColumn(columnID).count
    }
    
    var totalCards: Int {
        cards.count
    }
    
    var completedCards: Int {
        cards.filter { $0.statusValue == "Done" }.count
    }
    
    var completionPercentage: Double {
        guard totalCards > 0 else { return 0 }
        return Double(completedCards) / Double(totalCards) * 100
    }
}

// MARK: - Drag & Drop Helper

extension KanbanBoardViewModel {
    
    func canDropCard(_ cardID: UUID, toColumn columnID: UUID) -> Bool {
        // Permitir drop en cualquier columna válida del database
        return columns.contains { $0.id == columnID }
    }
    
    func performDrop(_ cardID: UUID, toColumn columnID: UUID) {
        moveCard(id: cardID, to: columnID)
        draggedCardID = nil
        draggedFromColumn = nil
    }
}
