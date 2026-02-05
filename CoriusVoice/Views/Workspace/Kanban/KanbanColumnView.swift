import SwiftUI
import UniformTypeIdentifiers

// MARK: - Kanban Column View

struct KanbanColumnView: View {
    let column: KanbanColumn
    let items: [WorkspaceItem]
    let database: Database?
    let onAddTask: () -> Void
    let onSelectItem: (WorkspaceItem) -> Void
    let onMoveItem: (UUID, UUID) -> Void
    @Binding var draggedItem: WorkspaceItem?
    
    @State private var isTargeted = false
    @State private var showingQuickAdd = false
    @State private var quickAddTitle = ""
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    
    private let columnWidth: CGFloat = 280
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Column Header
            columnHeader
            
            // Cards
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(items) { item in
                        KanbanCardView(item: item, database: database)
                            .onTapGesture {
                                onSelectItem(item)
                            }
                            .onDrag {
                                draggedItem = item
                                return NSItemProvider(object: item.id.uuidString as NSString)
                            }
                    }
                    
                    // Quick add field
                    if showingQuickAdd {
                        quickAddView
                    }
                    
                    // Add card button
                    addCardButton
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(width: columnWidth)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(isTargeted ? 0.8 : 0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }
    
    // MARK: - Column Header
    
    private var columnHeader: some View {
        HStack(spacing: 8) {
            // Color indicator
            Circle()
                .fill(Color(hex: column.color) ?? .gray)
                .frame(width: 10, height: 10)
            
            // Column name
            Text(column.name)
                .font(.headline)
                .foregroundColor(.primary)
            
            // Item count
            Text("\(items.count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
            
            Spacer()
            
            // Column menu
            Menu {
                Button(action: onAddTask) {
                    Label("Add Task", systemImage: "plus")
                }
                Divider()
                Button(action: {
                    // TODO: Edit column
                }) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: {
                    // TODO: Delete column
                }) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
    
    // MARK: - Quick Add View
    
    private var quickAddView: some View {
        VStack(spacing: 8) {
            TextField("Task name...", text: $quickAddTitle)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .onSubmit {
                    submitQuickAdd()
                }
            
            HStack {
                Button("Cancel") {
                    quickAddTitle = ""
                    showingQuickAdd = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Add") {
                    submitQuickAdd()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(quickAddTitle.isEmpty)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Add Card Button
    
    private var addCardButton: some View {
        Button(action: {
            showingQuickAdd = true
        }) {
            HStack {
                Image(systemName: "plus")
                Text("Add task")
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .opacity(showingQuickAdd ? 0 : 1)
    }
    
    // MARK: - Actions
    
    private func submitQuickAdd() {
        guard !quickAddTitle.isEmpty else { return }
        
        if let databaseID = items.first?.workspaceID ?? storage.databases.first?.id {
            _ = storage.createTask(
                title: quickAddTitle,
                databaseID: databaseID,
                status: column.name
            )
        }
        
        quickAddTitle = ""
        showingQuickAdd = false
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadObject(ofClass: NSString.self) { object, error in
            guard let idString = object as? String,
                  let itemID = UUID(uuidString: idString) else { return }
            
            DispatchQueue.main.async {
                onMoveItem(itemID, column.id)
                draggedItem = nil
            }
        }
        
        return true
    }
}

// MARK: - Preview

#Preview {
    HStack {
        KanbanColumnView(
            column: KanbanColumn(name: "Todo", color: "#6B7280", sortOrder: 0),
            items: [
                WorkspaceItem.task(title: "Task 1", workspaceID: UUID()),
                WorkspaceItem.task(title: "Task 2", workspaceID: UUID()),
            ],
            database: nil,
            onAddTask: {},
            onSelectItem: { _ in },
            onMoveItem: { _, _ in },
            draggedItem: .constant(nil)
        )
    }
    .padding()
    .frame(height: 500)
}
