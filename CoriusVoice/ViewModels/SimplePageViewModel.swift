import Foundation
import SwiftUI

// MARK: - Simple Page View Model

/// ViewModel para gestionar la lógica de edición de páginas con bloques
@MainActor
class SimplePageViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    let storage: any WorkspaceStorageProtocol
    
    // MARK: - Published State
    
    @Published var item: WorkspaceItem {
        didSet {
            debouncedSave()
        }
    }
    @Published var focusedBlockID: UUID?
    @Published var showingBlockMenu = false
    @Published var blockMenuPosition: CGPoint = .zero
    @Published var insertIndex: Int = 0
    @Published var draggedBlockID: UUID?
    @Published var dropTargetID: UUID?
    @Published var dropPosition: DropIndicatorView.DropPosition = .below
    @Published var lastSaved: Date = Date()
    
    // MARK: - Private State
    
    private var saveTask: Task<Void, Never>?
    private let DEBOUNCE_INTERVAL: UInt64 = 500_000_000 // 0.5 segundos
    
    // MARK: - Initialization
    
    init(item: WorkspaceItem, storage: any WorkspaceStorageProtocol = WorkspaceStorageServiceOptimized.shared) {
        self.item = item
        self.storage = storage
    }
    
    // MARK: - Block Management
    
    func addBlock(at index: Int, type: BlockType = .paragraph) {
        let newBlock = Block(
            id: UUID(),
            type: type,
            content: ""
        )
        
        item.blocks.insert(newBlock, at: index)
        focusedBlockID = newBlock.id
        debouncedSave()
    }
    
    func deleteBlock(_ id: UUID) {
        guard let index = item.blocks.firstIndex(where: { $0.id == id }) else { return }
        item.blocks.remove(at: index)
        if focusedBlockID == id {
            focusedBlockID = nil
        }
        debouncedSave()
    }
    
    func updateBlock(_ id: UUID, type: BlockType? = nil, content: String? = nil) {
        guard let index = item.blocks.firstIndex(where: { $0.id == id }) else { return }
        
        if let type = type {
            item.blocks[index].type = type
        }
        if let content = content {
            item.blocks[index].content = content
        }
        
        debouncedSave()
    }
    
    func moveBlock(from: Int, to: Int) {
        guard from != to, from >= 0, from < item.blocks.count,
              to >= 0, to < item.blocks.count else { return }
        
        let block = item.blocks.remove(at: from)
        item.blocks.insert(block, at: to)
        debouncedSave()
    }
    
    func duplicateBlock(_ id: UUID) {
        guard let index = item.blocks.firstIndex(where: { $0.id == id }) else { return }
        let original = item.blocks[index]
        let duplicate = Block(
            id: UUID(),
            type: original.type,
            content: original.content
        )
        item.blocks.insert(duplicate, at: index + 1)
        debouncedSave()
    }
    
    func changeBlockType(_ id: UUID, to newType: BlockType) {
        guard let index = item.blocks.firstIndex(where: { $0.id == id }) else { return }
        item.blocks[index].type = newType
        debouncedSave()
    }
    
    // MARK: - Title & Metadata
    
    func updateTitle(_ newTitle: String) {
        item.title = newTitle
        debouncedSave()
    }
    
    func updateIcon(_ newIcon: String) {
        item.icon = newIcon
        debouncedSave()
    }

    func toggleFavorite() {
        item.isFavorite.toggle()
        debouncedSave()
    }
    
    // MARK: - Focus Management
    
    func focusBlock(_ id: UUID?) {
        focusedBlockID = id
    }
    
    // MARK: - Saving
    
    private func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: DEBOUNCE_INTERVAL)
            if !Task.isCancelled {
                await save()
            }
        }
    }
    
    private func save() async {
        storage.updateItem(item)
        lastSaved = Date()
    }
    
    func forceSave() async {
        saveTask?.cancel()
        await save()
    }

    func markDirty() {
        debouncedSave()
    }
    
    // MARK: - State Queries
    
    var isSaving: Bool {
        saveTask != nil && !saveTask!.isCancelled
    }
    
    var blockCount: Int {
        item.blocks.count
    }
    
    func block(withID id: UUID) -> Block? {
        item.blocks.first { $0.id == id }
    }
}

// MARK: - Block Operations Helper

extension SimplePageViewModel {
    
    /// Obtener índice de bloque
    func index(of blockID: UUID) -> Int? {
        item.blocks.firstIndex { $0.id == blockID }
    }
    
    /// Calcular altura estimada de bloque
    func estimatedBlockHeight(_ block: Block) -> CGFloat {
        switch block.type {
        case .paragraph, .heading1, .heading2, .heading3:
            return CGFloat(50 + (block.content.count / 80 * 20))
        case .bulletList, .numberedList, .toggle:
            return CGFloat(max(50, block.content.split(separator: "\n").count * 25))
        case .todo:
            return 40
        case .quote:
            return CGFloat(60 + (block.content.count / 60 * 15))
        case .code:
            return CGFloat(80 + (block.content.split(separator: "\n").count * 18))
        case .image, .video:
            return 300
        case .audio:
            return 60
        case .divider:
            return 20
        case .table:
            return 300
        default:
            return 60
        }
    }
}
