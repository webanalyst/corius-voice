import SwiftUI

// MARK: - Block Editor View

/// Main editor view for editing pages with blocks (Notion-like)
struct BlockEditorView: View {
    @Binding var item: WorkspaceItem
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @State private var focusedBlockID: UUID?
    @State private var showingBlockMenu = false
    @State private var blockMenuPosition: CGPoint = .zero
    @State private var insertIndex: Int = 0
    @State private var draggedBlockID: UUID?
    @State private var dropTargetID: UUID?
    @State private var dropPosition: DropIndicatorView.DropPosition = .below
    @FocusState private var isEditorFocused: Bool
    @State private var saveTask: Task<Void, Never>?

    private let saveDelay: UInt64 = 400_000_000 // 0.4s
    
    var body: some View {
        VStack(spacing: 0) {
            // Page header
            pageHeader
            
            Divider()
            
            // Blocks editor
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(item.blocks.enumerated()), id: \.element.id) { index, block in
                            DraggableBlockRow(
                                block: binding(for: block),
                                index: index,
                                isFocused: focusedBlockID == block.id,
                                draggedID: $draggedBlockID,
                                dropTargetID: $dropTargetID,
                                dropPosition: $dropPosition,
                                blocks: $item.blocks,
                                onFocus: { focusedBlockID = block.id },
                                onInsertBelow: { insertBlockBelow(at: index) },
                                onDelete: { deleteBlock(at: index) },
                                onMoveUp: { moveBlock(from: index, direction: -1) },
                                onMoveDown: { moveBlock(from: index, direction: 1) },
                                onChangeType: { showBlockMenu(at: index) },
                                onDuplicate: { duplicateBlock(at: index) },
                                onReorder: { saveChanges() },
                                onDropInside: { droppedID, targetID in
                                    handleDropInside(droppedID: droppedID, targetID: targetID)
                                }
                            )
                            .id(block.id)
                        }
                        
                        // Empty state / Add first block
                        if item.blocks.isEmpty {
                            emptyState
                        } else {
                            // Add block button at bottom
                            addBlockButton
                        }
                    }
                    .padding()
                }
                .onChange(of: focusedBlockID) { oldValue, newValue in
                    if let id = newValue {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingBlockMenu) {
            BlockTypeMenu(
                onSelect: { type in
                    insertBlock(ofType: type, at: insertIndex)
                    showingBlockMenu = false
                }
            )
        }
        .onChange(of: item.blocks) { _, _ in scheduleSave() }
        .onChange(of: item.title) { _, _ in scheduleSave() }
        .onChange(of: item.icon) { _, _ in scheduleSave() }
        .onChange(of: item.coverImageURL) { _, _ in scheduleSave() }
        .onDisappear {
            persistNow()
        }
    }
    
    // MARK: - Drop Inside Handler
    
    private func handleDropInside(droppedID: UUID, targetID: UUID) {
        guard let droppedIndex = item.blocks.firstIndex(where: { $0.id == droppedID }),
              let targetIndex = item.blocks.firstIndex(where: { $0.id == targetID }) else { return }
        
        let droppedBlock = item.blocks[droppedIndex]
        let targetBlock = item.blocks[targetIndex]
        
        // Only allow dropping inside toggle or column blocks
        guard targetBlock.type == .toggle || targetBlock.type == .column || targetBlock.type == .columnList else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            // Remove from current position
            item.blocks.remove(at: droppedIndex)
            
            // Add as child of target
            if let newTargetIndex = item.blocks.firstIndex(where: { $0.id == targetID }) {
                item.blocks[newTargetIndex].children.append(droppedBlock)
            }
        }
        
        saveChanges()
    }
    
    // MARK: - Page Header
    
    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon picker
            HStack {
                IconPicker(selectedIcon: $item.icon)
                
                Spacer()
                
                // Cover image button
                if item.coverImageURL == nil {
                    Button("Add cover") {
                        // TODO: Cover picker
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            
            // Title
            TextField("Untitled", text: $item.title)
                .font(.system(size: 32, weight: .bold))
                .textFieldStyle(.plain)
            
            // Properties (if task)
            if item.itemType == .task {
                taskPropertiesView
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var taskPropertiesView: some View {
        HStack(spacing: 16) {
            // Status
            if let status = propertyValue(for: .status, preferredName: "Status") {
                PropertyBadge(label: "Status", value: status)
            }
            
            // Priority
            if let priority = propertyValue(for: .priority, preferredName: "Priority") {
                PropertyBadge(label: "Priority", value: priority)
            }
            
            // Due date
            if let dueDate = propertyValue(for: .date, preferredName: "Due Date") {
                PropertyBadge(label: "Due", value: dueDate)
            }
            
            Spacer()
        }
        .padding(.top, 8)
    }

    private func propertyValue(for type: PropertyType, preferredName: String? = nil) -> PropertyValue? {
        if let workspaceID = item.workspaceID,
           let database = storage.database(withID: workspaceID) {
            if let preferredName,
               let named = database.properties.first(where: { $0.name == preferredName }) {
                return item.properties[named.storageKey]
                    ?? item.properties[PropertyDefinition.legacyKey(for: named.name)]
            }
            if let definition = database.properties.first(where: { $0.type == type }) {
                return item.properties[definition.storageKey]
                    ?? item.properties[PropertyDefinition.legacyKey(for: definition.name)]
            }
        }

        if let preferredName {
            return item.properties[PropertyDefinition.legacyKey(for: preferredName)]
        }
        return nil
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        Button(action: { insertBlock(ofType: .paragraph, at: 0) }) {
            HStack {
                Image(systemName: "plus")
                    .foregroundColor(.secondary)
                Text("Click to add content, or press '/' for commands")
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    private var addBlockButton: some View {
        Button(action: { insertBlock(ofType: .paragraph, at: item.blocks.count) }) {
            HStack {
                Image(systemName: "plus")
                    .font(.caption)
                Text("Add a block")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .opacity(0.6)
        .padding(.top, 8)
    }
    
    // MARK: - Block Operations
    
    private func binding(for block: Block) -> Binding<Block> {
        guard let index = item.blocks.firstIndex(where: { $0.id == block.id }) else {
            return .constant(block)
        }
        return $item.blocks[index]
    }
    
    private func insertBlock(ofType type: BlockType, at index: Int) {
        let newBlock = Block(type: type, content: "")
        withAnimation(.easeInOut(duration: 0.2)) {
            if index >= item.blocks.count {
                item.blocks.append(newBlock)
            } else {
                item.blocks.insert(newBlock, at: index)
            }
        }
        focusedBlockID = newBlock.id
        saveChanges()
    }
    
    private func insertBlockBelow(at index: Int) {
        showBlockMenu(at: index + 1)
    }
    
    private func showBlockMenu(at index: Int) {
        insertIndex = index
        showingBlockMenu = true
    }
    
    private func deleteBlock(at index: Int) {
        guard index < item.blocks.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            item.blocks.remove(at: index)
        }
        // Focus previous block
        if index > 0 && !item.blocks.isEmpty {
            focusedBlockID = item.blocks[index - 1].id
        }
        saveChanges()
    }
    
    private func moveBlock(from index: Int, direction: Int) {
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < item.blocks.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            item.blocks.swapAt(index, newIndex)
        }
        saveChanges()
    }

    private func duplicateBlock(at index: Int) {
        guard index < item.blocks.count else { return }
        let original = item.blocks[index]
        let duplicated = Block(
            id: UUID(),
            type: original.type,
            content: original.content,
            richTextData: original.richTextData,
            checked: original.checked,
            language: original.language,
            url: original.url,
            icon: original.icon,
            color: original.color,
            children: original.children,
            isExpanded: original.isExpanded,
            sessionID: original.sessionID,
            metadata: original.metadata,
            createdAt: Date(),
            updatedAt: Date()
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            let insertIndex = min(index + 1, item.blocks.count)
            item.blocks.insert(duplicated, at: insertIndex)
        }
        focusedBlockID = duplicated.id
        saveChanges()
    }
    
    private func saveChanges() {
        persistNow()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: saveDelay)
            if Task.isCancelled { return }
            await MainActor.run {
                persistNow()
            }
        }
    }

    private func persistNow() {
        saveTask?.cancel()
        item.updatedAt = Date()
        storage.updateItem(item)
        storage.syncSyncedBlocks()
    }
}

// MARK: - Draggable Block Row

/// Combines BlockRowView with enhanced drag & drop capabilities
struct DraggableBlockRow: View {
    @Binding var block: Block
    let index: Int
    let isFocused: Bool
    @Binding var draggedID: UUID?
    @Binding var dropTargetID: UUID?
    @Binding var dropPosition: DropIndicatorView.DropPosition
    @Binding var blocks: [Block]
    let onFocus: () -> Void
    let onInsertBelow: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onChangeType: () -> Void
    let onDuplicate: () -> Void
    let onReorder: () -> Void
    let onDropInside: (UUID, UUID) -> Void
    
    @State private var isDragging = false
    
    private var canAcceptChildren: Bool {
        block.type == .toggle || block.type == .column || block.type == .columnList
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top drop indicator
            if dropTargetID == block.id && dropPosition == .above {
                dropIndicator
            }
            
            // Block content
            BlockRowView(
                block: $block,
                index: index,
                isFocused: isFocused,
                onFocus: onFocus,
                onInsertBelow: onInsertBelow,
                onDelete: onDelete,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
                onChangeType: onChangeType,
                onDuplicate: onDuplicate
            )
            .opacity(draggedID == block.id ? 0.4 : 1.0)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        (dropTargetID == block.id && dropPosition == .inside && canAcceptChildren)
                            ? Color.accentColor
                            : Color.clear,
                        lineWidth: 2
                    )
            )
            .scaleEffect(isDragging ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isDragging)
            .onDrag {
                isDragging = true
                draggedID = block.id
                return NSItemProvider(object: block.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: AdvancedBlockDropDelegate(
                blocks: $blocks,
                draggedID: $draggedID,
                dropTargetID: $dropTargetID,
                dropPosition: $dropPosition,
                targetID: block.id,
                targetIndex: index,
                canAcceptChildren: canAcceptChildren,
                onReorder: onReorder,
                onDropInside: onDropInside
            ))
            
            // Bottom drop indicator
            if dropTargetID == block.id && dropPosition == .below {
                dropIndicator
            }
        }
        .onChange(of: draggedID) { _, newValue in
            if newValue == nil {
                isDragging = false
            }
        }
    }
    
    private var dropIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
            
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .padding(.vertical, 2)
        .padding(.leading, 40)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .animation(.easeInOut(duration: 0.15), value: dropTargetID)
    }
}

// MARK: - Property Badge

struct PropertyBadge: View {
    let label: String
    let value: PropertyValue
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            switch value {
            case .text(let text):
                Text(text)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
                    
            case .select(let optionName):
                Text(optionName)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .foregroundColor(Color.accentColor)
                    .cornerRadius(4)
                    
            case .date(let date):
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
                    
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Block Type Menu

struct BlockTypeMenu: View {
    let onSelect: (BlockType) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private var filteredTypes: [BlockTypeCategory] {
        BlockTypeCategory.all.map { category in
            BlockTypeCategory(
                name: category.name,
                types: category.types.filter { type in
                    searchText.isEmpty || type.displayName.localizedCaseInsensitiveContains(searchText)
                }
            )
        }.filter { !$0.types.isEmpty }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search block type...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            // Block types
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredTypes, id: \.name) { category in
                        Section {
                            ForEach(category.types, id: \.self) { type in
                                BlockTypeRow(type: type) {
                                    onSelect(type)
                                }
                            }
                        } header: {
                            Text(category.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                        }
                    }
                }
            }
        }
        .frame(width: 300, height: 400)
    }
}

struct BlockTypeRow: View {
    let type: BlockType
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.body)
                    Text(type.descriptionText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Block Type Category

struct BlockTypeCategory {
    let name: String
    let types: [BlockType]
    
    static let all: [BlockTypeCategory] = [
        BlockTypeCategory(name: "Basic", types: [
            .paragraph, .heading1, .heading2, .heading3
        ]),
        BlockTypeCategory(name: "Lists", types: [
            .bulletList, .numberedList, .todo, .toggle
        ]),
        BlockTypeCategory(name: "Media", types: [
            .image, .video, .audio, .file
        ]),
        BlockTypeCategory(name: "Advanced", types: [
            .code, .quote, .callout, .divider, .table, .syncedBlock
        ]),
        BlockTypeCategory(name: "Layout", types: [
            .columnList
        ]),
        BlockTypeCategory(name: "Embeds", types: [
            .sessionEmbed, .databaseEmbed, .bookmark, .embed, .pageLink
        ]),
        BlockTypeCategory(name: "Meeting", types: [
            .meetingAttendees, .meetingAgenda, .meetingNotes, .meetingDecisions, .meetingActionItems, .meetingNextSteps
        ])
    ]
}

// MARK: - Block Type Description Extension

extension BlockType {
    var descriptionText: String {
        switch self {
        case .paragraph: return "Plain text paragraph"
        case .heading1: return "Large section heading"
        case .heading2: return "Medium section heading"
        case .heading3: return "Small section heading"
        case .bulletList: return "Unordered list item"
        case .numberedList: return "Ordered list item"
        case .todo: return "Task with checkbox"
        case .toggle: return "Collapsible content"
        case .quote: return "Quoted text"
        case .callout: return "Highlighted information"
        case .code: return "Code snippet"
        case .divider: return "Visual separator"
        case .image: return "Upload or embed image"
        case .video: return "Embed video"
        case .audio: return "Audio player"
        case .file: return "File attachment"
        case .bookmark: return "Web page preview"
        case .embed: return "Embed any URL"
        case .table: return "Simple table"
        case .sessionEmbed: return "Embed recording session"
        case .databaseEmbed: return "Linked database view"
        case .pageLink: return "Link to another page"
        case .columnList: return "Multi-column layout"
        case .syncedBlock: return "Mirror content across pages"
        case .meetingAgenda: return "Meeting agenda section"
        case .meetingNotes: return "Meeting discussion notes"
        case .meetingDecisions: return "Meeting decisions"
        case .meetingActionItems: return "Meeting action items"
        case .meetingNextSteps: return "Meeting next steps"
        case .meetingAttendees: return "Meeting attendees"
        default: return "Content block"
        }
    }
}
