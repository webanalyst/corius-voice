import SwiftUI

// MARK: - Kanban Board View

struct KanbanBoardView: View {
    let database: Database
    @StateObject private var viewModel: KanbanBoardViewModel
    @ObservedObject private var storage = WorkspaceStorageServiceOptimized.shared
    private let queryCache = QueryCache()
    @State private var showingAddTask = false
    @State private var addTaskColumn: KanbanColumn?
    @State private var newTaskTitle = ""
    @State private var selectedItem: WorkspaceItem?
    @State private var showingColumnEditor = false
    @State private var searchText = ""
    @State private var draggedItem: WorkspaceItem?
    @State private var selectedViewType: DatabaseViewType
    @State private var selectedViewID: UUID?
    @State private var showingViewOptions = false
    @State private var showingAddView = false
    @State private var showingProperties = false
    @State private var newViewName = ""
    @State private var newViewType: DatabaseViewType = .table
    @State private var editingView: DatabaseView?

    init(database: Database) {
        self.database = database
        _selectedViewType = State(initialValue: database.defaultView)
        _viewModel = StateObject(wrappedValue: KanbanBoardViewModel(databaseID: database.id))
        _selectedViewID = State(initialValue: database.views.first?.id)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()

            // Content
            Group {
                switch selectedViewType {
                case .kanban:
                    kanbanContent
                case .table:
                    TableDatabaseView(
                        database: database,
                        searchText: searchText,
                        view: selectedView,
                        onSelectItem: { selectedItem = $0 },
                        onAddProperty: { showingProperties = true }
                    )
                case .list:
                    ListDatabaseView(database: database, searchText: searchText, view: selectedView, onSelectItem: { selectedItem = $0 })
                case .calendar:
                    CalendarDatabaseView(database: database, searchText: searchText, view: selectedView, onSelectItem: { selectedItem = $0 })
                case .gallery:
                    GalleryDatabaseView(database: database, searchText: searchText, view: selectedView, onSelectItem: { selectedItem = $0 })
                @unknown default:
                    tablePlaceholderView
                }
            }
        }
        .sheet(isPresented: $showingAddTask) {
            addTaskSheet
        }
        .sheet(item: $selectedItem) { item in
            ItemDetailSheet(item: item)
        }
        .sheet(isPresented: $showingViewOptions) {
            ViewOptionsSheet(
                database: databaseBinding,
                selectedViewID: $selectedViewID,
                onApplyView: { applyView($0) }
            )
        }
        .sheet(isPresented: $showingAddView) {
            AddDatabaseViewSheet(
                database: databaseBinding,
                name: $newViewName,
                selectedType: $newViewType,
                onSave: { view in
                    applyView(view)
                    newViewName = ""
                }
            )
        }
        .sheet(item: $editingView) { view in
            RenameDatabaseViewSheet(
                database: databaseBinding,
                view: view,
                onSave: { updated in
                    applyView(updated)
                }
            )
        }
        .sheet(isPresented: $showingProperties) {
            DatabasePropertiesSheet(database: databaseBinding)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 16) {
            // Database icon and name
            HStack(spacing: 8) {
                Image(systemName: database.icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                Text(database.name)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            Spacer()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search tasks...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 200)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            
            // View switcher
            Menu {
                ForEach(availableViews) { view in
                    Button(action: {
                        applyView(view)
                    }) {
                        Label(view.name, systemImage: view.type.icon)
                    }
                }
                Divider()
                Button("Rename view…") {
                    editingView = selectedView
                }
                Button(role: .destructive, action: deleteSelectedView) {
                    Label("Delete view", systemImage: "trash")
                }
                .disabled(selectedView == nil)
                Divider()
                Button("New view…") {
                    showingAddView = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: selectedViewType.icon)
                    Text(selectedViewName)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)
            
            Button(action: { showingViewOptions = true }) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Filter & sort")

            Button(action: { showingProperties = true }) {
                Image(systemName: "list.bullet.rectangle")
            }
            .buttonStyle(.borderless)
            .help("Properties")
            
            // Add task button
            Button(action: {
                addTaskColumn = database.sortedColumns.first
                showingAddTask = true
            }) {
                Label("New Task", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Saved Views

    private var availableViews: [DatabaseView] {
        let views = currentDatabase.views
        if views.isEmpty {
            return [DatabaseView(name: currentDatabase.defaultView.displayName, type: currentDatabase.defaultView)]
        }
        return views
    }

    private var selectedViewName: String {
        if let view = selectedView {
            return view.name
        }
        return selectedViewType.displayName
    }

    private var selectedView: DatabaseView? {
        guard let id = selectedViewID else { return nil }
        return currentDatabase.views.first { $0.id == id }
    }

    private var databaseBinding: Binding<Database> {
        Binding(
            get: { currentDatabase },
            set: { updated in
                storage.updateDatabase(updated)
            }
        )
    }

    private func applyView(_ view: DatabaseView) {
        if currentDatabase.views.contains(where: { $0.id == view.id }) {
            selectedViewID = view.id
        } else {
            selectedViewID = nil
        }
        selectedViewType = view.type
    }

    private func deleteSelectedView() {
        guard let view = selectedView else { return }
        var updated = currentDatabase
        updated.views.removeAll { $0.id == view.id }
        storage.updateDatabase(updated)
        selectedViewID = updated.views.first?.id
        if let newView = updated.views.first {
            selectedViewType = newView.type
        } else {
            selectedViewType = updated.defaultView
        }
    }

    private var currentDatabase: Database {
        storage.database(withID: database.id) ?? database
    }

    // MARK: - Kanban Content

    private var kanbanContent: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(database.sortedColumns) { column in
                    KanbanColumnView(
                        column: column,
                        items: filteredItems(forColumn: column),
                        database: currentDatabase,
                        onAddTask: {
                            addTaskColumn = column
                            showingAddTask = true
                        },
                        onSelectItem: { item in
                            selectedItem = item
                        },
                        onMoveItem: { itemID, targetStatus in
                            viewModel.moveCard(id: itemID, to: targetStatus)
                        },
                        draggedItem: $draggedItem
                    )
                }
                
                // Add column button
                addColumnButton
            }
            .padding()
        }
    }

    private var tablePlaceholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedViewType.icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("\(selectedViewType.displayName) view is not ready yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Switch to Table or Kanban for now.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Add Column Button
    
    private var addColumnButton: some View {
        Button(action: {
            showingColumnEditor = true
        }) {
            VStack {
                Image(systemName: "plus")
                    .font(.title2)
                Text("Add Column")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .frame(width: 280, height: 100)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundColor(.secondary.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingColumnEditor) {
            AddColumnSheet(databaseID: database.id)
        }
    }
    
    // MARK: - Add Task Sheet
    
    private var addTaskSheet: some View {
        VStack(spacing: 20) {
            Text("New Task")
                .font(.headline)
            
            TextField("Task title...", text: $newTaskTitle)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            HStack {
                Button("Cancel") {
                    newTaskTitle = ""
                    showingAddTask = false
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Create") {
                    if !newTaskTitle.isEmpty, let column = addTaskColumn {
                        viewModel.addCard(titled: newTaskTitle, to: column.id)
                        newTaskTitle = ""
                        showingAddTask = false
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(newTaskTitle.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
    
    // MARK: - Helpers
    
    private func filteredItems(forColumn column: KanbanColumn) -> [WorkspaceItem] {
        var items = viewModel.cardsInColumn(column.id)
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            items = queryCache.cachedSearch(text: trimmedQuery, in: items)
        }
        items = applyFilters(selectedView?.filters ?? [], to: items, database: database)
        items = applySorts(selectedView?.sorts ?? [], to: items, database: database)
        return items
    }
}

// MARK: - Add Column Sheet

struct AddColumnSheet: View {
    let databaseID: UUID
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var columnName = ""
    @State private var selectedColor = "#3B82F6"
    
    private let colors = [
        "#EF4444", "#F97316", "#F59E0B", "#10B981",
        "#14B8A6", "#3B82F6", "#6366F1", "#8B5CF6",
        "#EC4899", "#6B7280"
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Column")
                .font(.headline)
            
            TextField("Column name...", text: $columnName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
            
            // Color picker
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30)), count: 5), spacing: 8) {
                ForEach(colors, id: \.self) { color in
                    Circle()
                        .fill(Color(hex: color) ?? .gray)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                        )
                        .onTapGesture {
                            selectedColor = color
                        }
                }
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Add") {
                    if !columnName.isEmpty {
                        storage.addColumn(to: databaseID, name: columnName, color: selectedColor)
                        dismiss()
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(columnName.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 320)
    }
}

// MARK: - Table Database View

struct TableDatabaseView: View {
    let database: Database
    let searchText: String
    let view: DatabaseView?
    let onSelectItem: (WorkspaceItem) -> Void
    let onAddProperty: () -> Void
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared

    private var properties: [PropertyDefinition] {
        database.properties.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var visibleProperties: [PropertyDefinition] {
        let base = properties.filter { !$0.isHidden }
        guard let view, !view.visibleProperties.isEmpty else { return base }
        let visible = Set(view.visibleProperties)
        return base.filter { visible.contains($0.id) }
    }

    private var items: [WorkspaceItem] {
        var results = storage.items(inDatabase: database.id)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter { $0.title.lowercased().contains(query) }
        }
        return results.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var filteredItems: [WorkspaceItem] {
        applyFilters(view?.filters ?? [], to: items, database: database)
    }

    private var sortedItems: [WorkspaceItem] {
        applySorts(view?.sorts ?? [], to: filteredItems, database: database)
    }

    private var statusPropertyName: String? {
        database.properties.first { $0.type == .status }?.name
    }

    private var datePropertyName: String? {
        database.properties.first { $0.type == .date }?.name
    }

    private var priorityPropertyName: String? {
        database.properties.first { $0.type == .priority }?.name
    }

    var body: some View {
        VStack(spacing: 0) {
            tableToolbar

            Divider()

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 8) {
                    Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                        headerRow

                        ForEach(sortedItems) { item in
                            TableRowView(
                                item: binding(for: item),
                                properties: visibleProperties,
                                database: database,
                                onOpen: { onSelectItem(item) },
                                onDuplicate: { duplicate(item) },
                                onDelete: { storage.deleteItem(item.id) }
                            )
                        }
                    }

                    Button(action: addRow) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("New")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private var tableToolbar: some View {
        HStack(spacing: 12) {
            Button(action: addRow) {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            Spacer()

            Text("\(sortedItems.count) items")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private var headerRow: some View {
        GridRow {
            Text("Title")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(minWidth: 160, alignment: .leading)

            ForEach(visibleProperties) { property in
                Text(property.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 140, alignment: .leading)
            }

            Button(action: onAddProperty) {
                Image(systemName: "plus")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, alignment: .leading)
        }
        .padding(.bottom, 4)
    }

    private func addRow() {
        _ = storage.createTask(title: "New Item", databaseID: database.id)
    }

    private func duplicate(_ item: WorkspaceItem) {
        var duplicated = item.duplicated()
        duplicated.updatedAt = Date()
        storage.addItem(duplicated)
    }

    private func binding(for item: WorkspaceItem) -> Binding<WorkspaceItem> {
        Binding(
            get: { storage.item(withID: item.id) ?? item },
            set: { updated in
                storage.updateItem(updated)
            }
        )
    }
}

struct ListDatabaseView: View {
    let database: Database
    let searchText: String
    let view: DatabaseView?
    let onSelectItem: (WorkspaceItem) -> Void
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared

    private var items: [WorkspaceItem] {
        var results = storage.items(inDatabase: database.id)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter { $0.title.lowercased().contains(query) }
        }
        return results.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var filteredItems: [WorkspaceItem] {
        applyFilters(view?.filters ?? [], to: items, database: database)
    }

    private var sortedItems: [WorkspaceItem] {
        applySorts(view?.sorts ?? [], to: filteredItems, database: database)
    }

    private var statusPropertyName: String? {
        database.properties.first { $0.type == .status }?.name
    }

    private var datePropertyName: String? {
        database.properties.first { $0.type == .date }?.name
    }

    var body: some View {
        VStack(spacing: 0) {
            listToolbar

            Divider()

            List(sortedItems) { item in
                Button(action: { onSelectItem(item) }) {
                    listRow(for: item)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private var listToolbar: some View {
        HStack(spacing: 12) {
            Button(action: addRow) {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            Spacer()

            Text("\(sortedItems.count) items")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func listRow(for item: WorkspaceItem) -> some View {
        HStack(spacing: 12) {
            WorkspaceIconView(name: item.icon)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let status = statusValue(for: item) {
                    Text(status)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(4)
                }
            }

            Spacer()

            if let date = dateValue(for: item) {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusValue(for item: WorkspaceItem) -> String? {
        if let definition = database.properties.first(where: { $0.type == .status }) {
            guard isPropertyVisible(definition) else { return nil }
            if case .select(let value) = propertyValue(for: item, definition: definition) {
                return value
            }
        } else {
            return item.statusValue
        }
        return nil
    }

    private func dateValue(for item: WorkspaceItem) -> Date? {
        guard let definition = database.properties.first(where: { $0.type == .date }),
              isPropertyVisible(definition) else { return nil }
        if case .date(let value) = propertyValue(for: item, definition: definition) {
            return value
        }
        return nil
    }

    private func propertyValue(for item: WorkspaceItem, definition: PropertyDefinition) -> PropertyValue {
        item.properties[definition.storageKey]
            ?? item.properties[PropertyDefinition.legacyKey(for: definition.name)]
            ?? .empty
    }

    private func isPropertyVisible(_ definition: PropertyDefinition) -> Bool {
        guard !definition.isHidden else { return false }
        guard let view, !view.visibleProperties.isEmpty else { return true }
        return view.visibleProperties.contains(definition.id)
    }

    private func addRow() {
        _ = storage.createTask(title: "New Item", databaseID: database.id)
    }
}

struct CalendarDatabaseView: View {
    let database: Database
    let searchText: String
    let view: DatabaseView?
    let onSelectItem: (WorkspaceItem) -> Void
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared

    private var calendar: Calendar { Calendar.current }

    private var calendarProperty: PropertyDefinition? {
        if let view, let id = view.calendarPropertyId,
           let match = database.properties.first(where: { $0.id == id }) {
            return match
        }
        return database.properties.first { definition in
            switch definition.type {
            case .date, .createdTime, .lastEdited:
                return true
            default:
                return false
            }
        }
    }

    private var items: [WorkspaceItem] {
        guard calendarProperty != nil else { return [] }
        var results = storage.items(inDatabase: database.id)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter { $0.title.lowercased().contains(query) }
        }
        return results.filter { dateValue(for: $0) != nil }
    }

    private var filteredItems: [WorkspaceItem] {
        applyFilters(view?.filters ?? [], to: items, database: database)
    }

    private var sortedItems: [WorkspaceItem] {
        applySorts(view?.sorts ?? [], to: filteredItems, database: database)
    }

    private var monthStart: Date {
        let components = calendar.dateComponents([.year, .month], from: Date())
        return calendar.date(from: components) ?? Date()
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
    }

    private var firstWeekdayOffset: Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday + 6) % 7
    }

    private var itemsByDay: [Int: [WorkspaceItem]] {
        var result: [Int: [WorkspaceItem]] = [:]
        for item in sortedItems {
            guard let date = dateValue(for: item) else { continue }
            let day = calendar.component(.day, from: date)
            if calendar.isDate(date, equalTo: monthStart, toGranularity: .month) {
                result[day, default: []].append(item)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            calendarToolbar

            Divider()

            ScrollView {
                if calendarProperty == nil {
                    calendarEmptyState
                } else {
                    calendarGrid
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private var calendarToolbar: some View {
        HStack(spacing: 12) {
            Button(action: addRow) {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                Text(monthStart.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                if let calendarProperty {
                    Text(calendarProperty.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text("\(sortedItems.count) items")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var calendarEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("Add a date property to use Calendar view.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(24)
    }

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(calendar.shortWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<firstWeekdayOffset, id: \.self) { _ in
                    Color.clear.frame(height: 80)
                }

                ForEach(1...daysInMonth, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(day)")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if let dayItems = itemsByDay[day] {
                            ForEach(dayItems.prefix(3)) { item in
                                Button(action: { onSelectItem(item) }) {
                                    Text(item.displayTitle)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }

                            if dayItems.count > 3 {
                                Text("+\(dayItems.count - 3)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                    .cornerRadius(8)
                }
            }
        }
        .padding(12)
    }

    private func dateValue(for item: WorkspaceItem) -> Date? {
        guard let definition = calendarProperty else { return nil }
        switch definition.type {
        case .createdTime:
            return item.createdAt
        case .lastEdited:
            return item.updatedAt
        default:
            break
        }
        if case .date(let value) = propertyValue(for: item, definition: definition) {
            return value
        }
        return nil
    }

    private func propertyValue(for item: WorkspaceItem, definition: PropertyDefinition) -> PropertyValue {
        item.properties[definition.storageKey]
            ?? item.properties[PropertyDefinition.legacyKey(for: definition.name)]
            ?? .empty
    }

    private func addRow() {
        _ = storage.createTask(title: "New Item", databaseID: database.id)
    }
}

struct GalleryDatabaseView: View {
    let database: Database
    let searchText: String
    let view: DatabaseView?
    let onSelectItem: (WorkspaceItem) -> Void
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared

    private var items: [WorkspaceItem] {
        var results = storage.items(inDatabase: database.id)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            results = results.filter { $0.title.lowercased().contains(query) }
        }
        return results.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var filteredItems: [WorkspaceItem] {
        applyFilters(view?.filters ?? [], to: items, database: database)
    }

    private var sortedItems: [WorkspaceItem] {
        applySorts(view?.sorts ?? [], to: filteredItems, database: database)
    }

    private var statusPropertyName: String? {
        database.properties.first { $0.type == .status }?.name
    }

    private var datePropertyName: String? {
        database.properties.first { $0.type == .date }?.name
    }

    var body: some View {
        VStack(spacing: 0) {
            galleryToolbar

            Divider()

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    ForEach(sortedItems) { item in
                        Button(action: { onSelectItem(item) }) {
                            galleryCard(for: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private var galleryToolbar: some View {
        HStack(spacing: 12) {
            Button(action: addRow) {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(.borderless)

            Spacer()

            Text("\(sortedItems.count) items")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func galleryCard(for item: WorkspaceItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.displayTitle)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)

            if let status = statusValue(for: item) {
                Text(status)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(4)
            }

            if let date = dateValue(for: item) {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text("Updated \(item.updatedAt.relativeString)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
        .cornerRadius(10)
    }

    private func statusValue(for item: WorkspaceItem) -> String? {
        if let definition = database.properties.first(where: { $0.type == .status }) {
            guard isPropertyVisible(definition) else { return nil }
            if case .select(let value) = propertyValue(for: item, definition: definition) {
                return value
            }
        } else {
            return item.statusValue
        }
        return nil
    }

    private func dateValue(for item: WorkspaceItem) -> Date? {
        guard let definition = database.properties.first(where: { $0.type == .date }),
              isPropertyVisible(definition) else { return nil }
        if case .date(let value) = propertyValue(for: item, definition: definition) {
            return value
        }
        return nil
    }

    private func propertyValue(for item: WorkspaceItem, definition: PropertyDefinition) -> PropertyValue {
        item.properties[definition.storageKey]
            ?? item.properties[PropertyDefinition.legacyKey(for: definition.name)]
            ?? .empty
    }

    private func isPropertyVisible(_ definition: PropertyDefinition) -> Bool {
        guard !definition.isHidden else { return false }
        guard let view, !view.visibleProperties.isEmpty else { return true }
        return view.visibleProperties.contains(definition.id)
    }

    private func addRow() {
        _ = storage.createTask(title: "New Item", databaseID: database.id)
    }
}

struct ViewOptionsSheet: View {
    @Binding var database: Database
    @Binding var selectedViewID: UUID?
    let onApplyView: (DatabaseView) -> Void
    @Environment(\.dismiss) private var dismiss

    private var selectedView: DatabaseView? {
        guard let id = selectedViewID else { return nil }
        return database.views.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Views") {
                    Picker("Current view", selection: Binding(
                        get: { selectedViewID ?? database.views.first?.id },
                        set: { selectedViewID = $0 }
                    )) {
                        ForEach(database.views) { view in
                            Text(view.name).tag(Optional(view.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                if let view = selectedView,
                   let index = database.views.firstIndex(where: { $0.id == view.id }) {
                    FilterEditorView(view: $database.views[index], database: database)
                    SortEditorView(view: $database.views[index], database: database)
                    if view.type == .calendar {
                        CalendarSettingsView(view: $database.views[index], database: database)
                    }
                    VisiblePropertiesEditorView(view: $database.views[index], database: database)
                } else {
                    Text("Create a view to add filters and sorts.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("View options")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if let view = selectedView {
                            onApplyView(view)
                        }
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 520, height: 520)
    }
}

struct FilterEditorView: View {
    @Binding var view: DatabaseView
    let database: Database

    var body: some View {
        Section("Filters") {
            if view.filters.isEmpty {
                Text("No filters applied")
                    .foregroundColor(.secondary)
            }

            ForEach(view.filters) { filter in
                FilterRow(
                    filter: binding(for: filter),
                    properties: database.properties,
                    onDelete: {
                        view.filters.removeAll { $0.id == filter.id }
                    }
                )
            }

            Button("Add filter") {
                if let property = database.properties.first {
                    view.filters.append(
                        ViewFilter(
                            propertyName: property.name,
                            propertyId: property.id,
                            operation: .equals,
                            value: defaultValue(for: property.type)
                        )
                    )
                } else {
                    view.filters.append(
                        ViewFilter(
                            propertyName: "Title",
                            operation: .contains,
                            value: .text("")
                        )
                    )
                }
            }
        }
    }

    private func binding(for filter: ViewFilter) -> Binding<ViewFilter> {
        Binding(
            get: { filter },
            set: { newValue in
                if let index = view.filters.firstIndex(where: { $0.id == filter.id }) {
                    view.filters[index] = newValue
                }
            }
        )
    }

    private func defaultValue(for type: PropertyType) -> PropertyValue {
        switch type {
        case .number:
            return .number(0)
        case .date, .createdTime, .lastEdited:
            return .date(Date())
        case .checkbox:
            return .checkbox(false)
        default:
            return .text("")
        }
    }

}

struct FilterRow: View {
    @Binding var filter: ViewFilter
    let properties: [PropertyDefinition]
    let onDelete: () -> Void

    private var titleProperty: PropertyDefinition {
        PropertyDefinition(name: "Title", type: .text)
    }

    private var selectedProperty: PropertyDefinition {
        if filter.propertyName.lowercased() == "title" {
            return titleProperty
        }
        if let id = filter.propertyId,
           let match = properties.first(where: { $0.id == id }) {
            return match
        }
        if let match = properties.first(where: { $0.name == filter.propertyName }) {
            return match
        }
        return properties.first ?? PropertyDefinition(name: "Title", type: .text)
    }

    var body: some View {
        HStack(spacing: 12) {
            Picker("Property", selection: propertySelection) {
                Text("Title").tag(Optional<UUID>.none)
                ForEach(properties) { property in
                    Text(property.name).tag(Optional(property.id))
                }
            }
            .frame(width: 160)

            Picker("Operation", selection: $filter.operation) {
                ForEach(availableOperations, id: \.self) { operation in
                    Text(operation.displayName).tag(operation)
                }
            }
            .frame(width: 140)

            FilterValueField(value: $filter.value, type: selectedProperty.type)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private var propertySelection: Binding<UUID?> {
        Binding(
            get: { filter.propertyName.lowercased() == "title" ? nil : (filter.propertyId ?? selectedProperty.id) },
            set: { newID in
                filter.propertyId = newID
                if let id = newID, let property = properties.first(where: { $0.id == id }) {
                    filter.propertyName = property.name
                    filter.value = defaultValue(for: property.type)
                    filter.operation = FilterOperation.allCases.first ?? .equals
                } else if newID == nil {
                    filter.propertyName = "Title"
                    filter.value = .text("")
                    filter.operation = .contains
                }
            }
        )
    }

    private var availableOperations: [FilterOperation] {
        switch selectedProperty.type {
        case .text, .url, .email, .phone:
            return [.equals, .notEquals, .contains, .notContains, .isEmpty, .isNotEmpty]
        case .number:
            return [.equals, .notEquals, .greaterThan, .lessThan, .isEmpty, .isNotEmpty]
        case .select, .status, .priority:
            return [.equals, .notEquals, .isEmpty, .isNotEmpty]
        case .multiSelect:
            return [.contains, .notContains, .isEmpty, .isNotEmpty]
        case .date, .createdTime, .lastEdited:
            return [.equals, .greaterThan, .lessThan, .isEmpty, .isNotEmpty]
        case .checkbox:
            return [.equals, .notEquals]
        case .person, .relation, .createdBy:
            return [.equals, .notEquals, .isEmpty, .isNotEmpty]
        case .rollup, .formula:
            return [.isEmpty, .isNotEmpty]
        }
    }

    private func defaultValue(for type: PropertyType) -> PropertyValue {
        switch type {
        case .number:
            return .number(0)
        case .date, .createdTime, .lastEdited:
            return .date(Date())
        case .checkbox:
            return .checkbox(false)
        default:
            return .text("")
        }
    }
}

struct FilterValueField: View {
    @Binding var value: PropertyValue
    let type: PropertyType

    var body: some View {
        switch type {
        case .number:
            TextField("Value", text: Binding(
                get: {
                    if case .number(let number) = value { return String(number) }
                    return ""
                },
                set: { value = .number(Double($0) ?? 0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 120)

        case .date, .createdTime, .lastEdited:
            DatePicker("", selection: Binding(
                get: {
                    if case .date(let date) = value { return date }
                    return Date()
                },
                set: { value = .date($0) }
            ), displayedComponents: [.date])
            .labelsHidden()

        case .checkbox:
            Toggle("", isOn: Binding(
                get: {
                    if case .checkbox(let flag) = value { return flag }
                    return false
                },
                set: { value = .checkbox($0) }
            ))
            .labelsHidden()

        default:
            TextField("Value", text: Binding(
                get: { value.displayValue },
                set: { value = .text($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 160)
        }
    }
}

struct SortEditorView: View {
    @Binding var view: DatabaseView
    let database: Database

    var body: some View {
        Section("Sorts") {
            if view.sorts.isEmpty {
                Text("No sorts applied")
                    .foregroundColor(.secondary)
            }

            ForEach(view.sorts) { sort in
                SortRow(
                    sort: binding(for: sort),
                    properties: database.properties,
                    onDelete: {
                        view.sorts.removeAll { $0.id == sort.id }
                    }
                )
            }

            Button("Add sort") {
                if let property = database.properties.first {
                    view.sorts.append(ViewSort(propertyName: property.name, propertyId: property.id, ascending: true))
                } else {
                    view.sorts.append(ViewSort(propertyName: "Title", ascending: true))
                }
            }
        }
    }

    private func binding(for sort: ViewSort) -> Binding<ViewSort> {
        Binding(
            get: { sort },
            set: { newValue in
                if let index = view.sorts.firstIndex(where: { $0.id == sort.id }) {
                    view.sorts[index] = newValue
                }
            }
        )
    }
}

struct SortRow: View {
    @Binding var sort: ViewSort
    let properties: [PropertyDefinition]
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Picker("Property", selection: propertySelection) {
                Text("Title").tag(Optional<UUID>.none)
                ForEach(properties) { property in
                    Text(property.name).tag(Optional(property.id))
                }
            }
            .frame(width: 160)

            Picker("Direction", selection: $sort.ascending) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            }
            .frame(width: 140)

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private var propertySelection: Binding<UUID?> {
        Binding(
            get: { sort.propertyName.lowercased() == "title" ? nil : (sort.propertyId ?? properties.first?.id) },
            set: { newID in
                sort.propertyId = newID
                if let id = newID, let property = properties.first(where: { $0.id == id }) {
                    sort.propertyName = property.name
                } else if newID == nil {
                    sort.propertyName = "Title"
                }
            }
        )
    }
}

struct VisiblePropertiesEditorView: View {
    @Binding var view: DatabaseView
    let database: Database

    private var sortedProperties: [PropertyDefinition] {
        database.properties
            .filter { !$0.isHidden }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Section("Properties") {
            Toggle("Title", isOn: .constant(true))
                .disabled(true)

            ForEach(sortedProperties) { property in
                Toggle(property.name, isOn: binding(for: property))
            }

            if !view.visibleProperties.isEmpty {
                Button("Show all properties") {
                    view.visibleProperties = []
                }
            }
            if database.properties.contains(where: { $0.isHidden }) {
                Text("Hidden properties are not shown in views.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func binding(for property: PropertyDefinition) -> Binding<Bool> {
        Binding(
            get: {
                guard !view.visibleProperties.isEmpty else { return true }
                return view.visibleProperties.contains(property.id)
            },
            set: { isOn in
                if view.visibleProperties.isEmpty {
                    if !isOn {
                        view.visibleProperties = database.properties.map(\.id).filter { $0 != property.id }
                    }
                    return
                }

                if isOn {
                    if !view.visibleProperties.contains(property.id) {
                        view.visibleProperties.append(property.id)
                    }
                    let all = Set(database.properties.map(\.id))
                    if Set(view.visibleProperties) == all {
                        view.visibleProperties = []
                    }
                } else {
                    view.visibleProperties.removeAll { $0 == property.id }
                }
            }
        )
    }
}

struct CalendarSettingsView: View {
    @Binding var view: DatabaseView
    let database: Database

    private var dateProperties: [PropertyDefinition] {
        database.properties.filter { definition in
            switch definition.type {
            case .date, .createdTime, .lastEdited:
                return true
            default:
                return false
            }
        }
        .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Section("Calendar") {
            if dateProperties.isEmpty {
                Text("Add a date property to use Calendar view.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Picker("Date property", selection: Binding(
                    get: { view.calendarPropertyId },
                    set: { view.calendarPropertyId = $0 }
                )) {
                    Text("Auto").tag(Optional<UUID>.none)
                    ForEach(dateProperties) { property in
                        Text(property.name).tag(Optional(property.id))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

struct AddDatabaseViewSheet: View {
    @Binding var database: Database
    @Binding var name: String
    @Binding var selectedType: DatabaseViewType
    let onSave: (DatabaseView) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("New view")
                .font(.headline)

            TextField("View name", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("Type", selection: $selectedType) {
                ForEach(DatabaseViewType.allCases, id: \.self) { viewType in
                    Text(viewType.displayName).tag(viewType)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Create") {
                    let view = DatabaseView(name: name.isEmpty ? selectedType.displayName : name, type: selectedType)
                    database.views.append(view)
                    onSave(view)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

struct RenameDatabaseViewSheet: View {
    @Binding var database: Database
    @State var view: DatabaseView
    let onSave: (DatabaseView) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename view")
                .font(.headline)

            TextField("View name", text: $view.name)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    if let index = database.views.firstIndex(where: { $0.id == view.id }) {
                        database.views[index].name = view.name
                        onSave(database.views[index])
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

private func applyFilters(_ filters: [ViewFilter], to items: [WorkspaceItem], database: Database) -> [WorkspaceItem] {
    guard !filters.isEmpty else { return items }
    return items.filter { item in
        filters.allSatisfy { filter in
            matchesFilter(filter, item: item, database: database)
        }
    }
}

private func matchesFilter(_ filter: ViewFilter, item: WorkspaceItem, database: Database) -> Bool {
    let key = storageKey(for: filter, in: database)
    let value: PropertyValue
    if filter.propertyName.lowercased() == "title" {
        value = .text(item.title)
    } else {
        value = resolvedPropertyValue(for: item, propertyName: filter.propertyName, propertyId: filter.propertyId, key: key, database: database)
    }

    switch filter.operation {
    case .equals:
        return compareValue(value, to: filter.value) == .orderedSame
    case .notEquals:
        return compareValue(value, to: filter.value) != .orderedSame
    case .contains:
        return value.displayValue.localizedCaseInsensitiveContains(filter.value.displayValue)
    case .notContains:
        return !value.displayValue.localizedCaseInsensitiveContains(filter.value.displayValue)
    case .isEmpty:
        return value.isEmpty
    case .isNotEmpty:
        return !value.isEmpty
    case .greaterThan:
        return compareValue(value, to: filter.value) == .orderedDescending
    case .lessThan:
        return compareValue(value, to: filter.value) == .orderedAscending
    }
}

private func applySorts(_ sorts: [ViewSort], to items: [WorkspaceItem], database: Database) -> [WorkspaceItem] {
    guard !sorts.isEmpty else { return items }
    return items.sorted { lhs, rhs in
        for sort in sorts {
            let key = storageKey(for: sort, in: database)
            let leftValue = resolvedPropertyValue(for: lhs, propertyName: sort.propertyName, propertyId: sort.propertyId, key: key, database: database)
            let rightValue = resolvedPropertyValue(for: rhs, propertyName: sort.propertyName, propertyId: sort.propertyId, key: key, database: database)
            if leftValue.displayValue == rightValue.displayValue { continue }
            let order = compareValue(leftValue, to: rightValue)
            return sort.ascending ? order == .orderedAscending : order == .orderedDescending
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}

private func resolvedPropertyValue(
    for item: WorkspaceItem,
    propertyName: String,
    propertyId: UUID?,
    key: String,
    database: Database
) -> PropertyValue {
    if propertyName.lowercased() == "title" {
        return .text(item.title)
    }
    let definition = propertyDefinition(for: propertyName, propertyId: propertyId, database: database)
    if let definition,
       definition.type == .rollup || definition.type == .formula
        || definition.type == .createdTime || definition.type == .lastEdited || definition.type == .createdBy {
        return PropertyValueResolver.value(
            for: item,
            definition: definition,
            database: database,
            storage: WorkspaceStorageServiceOptimized.shared
        )
    }
    let legacyKey = PropertyDefinition.legacyKey(for: propertyName)
    return item.properties[key] ?? item.properties[legacyKey] ?? .empty
}

private func propertyDefinition(for propertyName: String, propertyId: UUID?, database: Database) -> PropertyDefinition? {
    if let id = propertyId, let def = database.properties.first(where: { $0.id == id }) {
        return def
    }
    return database.properties.first(where: { $0.name == propertyName })
}

private func compareValue(_ lhs: PropertyValue, to rhs: PropertyValue) -> ComparisonResult {
    switch (lhs, rhs) {
    case (.number(let left), .number(let right)):
        return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
    case (.date(let left), .date(let right)):
        return left.compare(right)
    default:
        let leftText = lhs.displayValue
        let rightText = rhs.displayValue
        return leftText.localizedStandardCompare(rightText)
    }
}

private func storageKey(for filter: ViewFilter, in database: Database) -> String {
    if let id = filter.propertyId {
        return id.uuidString
    }
    if let definition = database.properties.first(where: { $0.name == filter.propertyName }) {
        return definition.storageKey
    }
    return PropertyDefinition.legacyKey(for: filter.propertyName)
}

private func storageKey(for sort: ViewSort, in database: Database) -> String {
    if let id = sort.propertyId {
        return id.uuidString
    }
    if let definition = database.properties.first(where: { $0.name == sort.propertyName }) {
        return definition.storageKey
    }
    return PropertyDefinition.legacyKey(for: sort.propertyName)
}

struct DatabasePropertiesSheet: View {
    @Binding var database: Database
    @ObservedObject private var storage = WorkspaceStorageServiceOptimized.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingReorder = false

    private var sortedProperties: [PropertyDefinition] {
        database.properties.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showingReorder {
                    ReorderPropertiesView(
                        properties: sortedProperties,
                        onMove: moveProperties
                    )
                } else {
                    List {
                        ForEach(sortedProperties) { property in
                            PropertyDefinitionRow(
                                property: binding(for: property),
                                database: database,
                                onRename: { id, oldName, newName in
                                    renameProperty(id: id, from: oldName, to: newName)
                                },
                                onDelete: {
                                    deleteProperty(property)
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Properties")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: addProperty) {
                        Label("Add property", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button(showingReorder ? "Done" : "Reorder") {
                        showingReorder.toggle()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(width: 560, height: 520)
    }

    private func binding(for property: PropertyDefinition) -> Binding<PropertyDefinition> {
        Binding(
            get: { property },
            set: { updated in
                if let index = database.properties.firstIndex(where: { $0.id == property.id }) {
                    database.properties[index] = updated
                }
            }
        )
    }

    private func addProperty() {
        let nextSort = (database.properties.map { $0.sortOrder }.max() ?? 0) + 1
        let newProperty = PropertyDefinition(
            name: "New property",
            type: .text,
            sortOrder: nextSort
        )
        database.properties.append(newProperty)
    }

    private func moveProperties(from sourceIndex: Int, to destinationIndex: Int) {
        var updated = sortedProperties
        let item = updated.remove(at: sourceIndex)
        let safeIndex = min(destinationIndex, updated.count)
        updated.insert(item, at: safeIndex)
        for index in updated.indices {
            updated[index].sortOrder = index
        }
        database.properties = updated
    }

    private func deleteProperty(_ property: PropertyDefinition) {
        database.properties.removeAll { $0.id == property.id }
        let key = property.storageKey
        let legacyKey = PropertyDefinition.legacyKey(for: property.name)
        let items = storage.items(inDatabase: database.id)
        for var item in items {
            let removed = item.properties.removeValue(forKey: key) != nil
            let removedLegacy = item.properties.removeValue(forKey: legacyKey) != nil
            if removed || removedLegacy {
                storage.updateItem(item)
            }
        }
        for index in database.views.indices {
            database.views[index].filters.removeAll { filter in
                filter.propertyId == property.id || filter.propertyName == property.name
            }
            database.views[index].sorts.removeAll { sort in
                sort.propertyId == property.id || sort.propertyName == property.name
            }
            database.views[index].visibleProperties.removeAll { $0 == property.id }
            if database.views[index].calendarPropertyId == property.id {
                database.views[index].calendarPropertyId = nil
            }
        }
    }

    private func renameProperty(id: UUID, from oldName: String, to newName: String) {
        for index in database.views.indices {
            database.views[index].filters = database.views[index].filters.map { filter in
                guard filter.propertyName == oldName || filter.propertyId == id else { return filter }
                return ViewFilter(
                    id: filter.id,
                    propertyName: newName,
                    propertyId: filter.propertyId,
                    operation: filter.operation,
                    value: filter.value
                )
            }
            database.views[index].sorts = database.views[index].sorts.map { sort in
                guard sort.propertyName == oldName || sort.propertyId == id else { return sort }
                return ViewSort(
                    id: sort.id,
                    propertyName: newName,
                    propertyId: sort.propertyId,
                    ascending: sort.ascending
                )
            }
        }
    }
}

struct PropertyDefinitionRow: View {
    @Binding var property: PropertyDefinition
    let database: Database
    let onRename: (UUID, String, String) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Name", text: $property.name)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: property.name) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        onRename(property.id, oldValue, newValue)
                    }

                Spacer()

                Picker("", selection: $property.type) {
                    ForEach(PropertyType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 16) {
                Toggle("Required", isOn: $property.isRequired)
                Toggle("Hidden", isOn: $property.isHidden)
            }
            .toggleStyle(.switch)

            if property.type == .relation {
                RelationPropertyEditor(definition: $property, database: database)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                    .cornerRadius(8)
            }

            if property.type == .rollup {
                RollupPropertyEditor(definition: $property, database: database)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                    .cornerRadius(8)
            }

            if property.type == .formula {
                TextField("Formula", text: Binding(
                    get: { property.formula ?? "" },
                    set: { property.formula = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            if property.type == .select || property.type == .multiSelect || property.type == .status || property.type == .priority {
                SelectOptionsEditor(options: optionsBinding)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 8)
        .onChange(of: property.type) { _, newValue in
            applyTypeDefaults(newValue)
        }
    }

    private var optionsBinding: Binding<[SelectOption]> {
        Binding(
            get: { property.options ?? [] },
            set: { property.options = $0 }
        )
    }

    private func applyTypeDefaults(_ type: PropertyType) {
        switch type {
        case .status:
            property.options = SelectOption.defaultStatuses
            property.isRequired = true
        case .priority:
            property.options = SelectOption.priorities
        case .select, .multiSelect:
            if property.options?.isEmpty != false {
                property.options = [SelectOption(name: "Option 1", color: "#3B82F6", sortOrder: 0)]
            }
        default:
            property.options = nil
        }

        if type != .relation {
            property.relationConfig = nil
        }
        if type != .rollup {
            property.rollupConfig = nil
        }
        if type != .formula {
            property.formula = nil
        }
    }
}

private struct SelectOptionsEditor: View {
    @Binding var options: [SelectOption]
    @State private var newOptionName = ""
    @State private var newOptionColor = "#3B82F6"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Options")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            ForEach($options) { $option in
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: option.color) ?? .gray)
                        .frame(width: 10, height: 10)

                    TextField("Option", text: $option.name)
                        .textFieldStyle(.roundedBorder)

                    TextField("#3B82F6", text: $option.color)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)

                    Button(role: .destructive) {
                        options.removeAll { $0.id == option.id }
                        normalizeSort()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 8) {
                TextField("New option", text: $newOptionName)
                    .textFieldStyle(.roundedBorder)

                TextField("#3B82F6", text: $newOptionColor)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)

                Button(action: addOption) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(newOptionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
    }

    private func addOption() {
        let trimmed = newOptionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        options.append(SelectOption(name: trimmed, color: newOptionColor, sortOrder: options.count))
        normalizeSort()
        newOptionName = ""
    }

    private func normalizeSort() {
        for index in options.indices {
            options[index].sortOrder = index
        }
    }
}

private struct ReorderPropertiesView: View {
    let properties: [PropertyDefinition]
    let onMove: (Int, Int) -> Void

    @State private var draggedID: UUID?
    @State private var targetID: UUID?

    var body: some View {
        List {
            ForEach(properties) { property in
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundColor(.secondary)
                    Text(property.name)
                        .font(.body)
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onDrag {
                    draggedID = property.id
                    return NSItemProvider(object: property.id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: PropertyReorderDropDelegate(
                    properties: properties,
                    draggedID: $draggedID,
                    targetID: property.id,
                    onMove: onMove
                ))
            }
        }
    }
}

private struct PropertyReorderDropDelegate: DropDelegate {
    let properties: [PropertyDefinition]
    @Binding var draggedID: UUID?
    let targetID: UUID
    let onMove: (Int, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedID,
              draggedID != targetID,
              let fromIndex = properties.firstIndex(where: { $0.id == draggedID }),
              let toIndex = properties.firstIndex(where: { $0.id == targetID })
        else { return }
        onMove(fromIndex, toIndex)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}

struct TableRowView: View {
    @Binding var item: WorkspaceItem
    let properties: [PropertyDefinition]
    let database: Database
    let onOpen: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @State private var isHovered = false

    var body: some View {
        GridRow {
            HStack(spacing: 8) {
                WorkspaceIconView(name: item.icon)
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Title", text: $item.title)
                    .textFieldStyle(.plain)
                    .onChange(of: item.title) { _, _ in
                        storage.updateItem(item)
                    }

                Spacer(minLength: 0)

                if isHovered {
                    Button(action: onOpen) {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minWidth: 160, alignment: .leading)

            ForEach(properties) { property in
                TablePropertyCell(
                    item: $item,
                    definition: property,
                    database: database
                )
                .frame(minWidth: 140, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
        .cornerRadius(6)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Duplicate") { onDuplicate() }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Text("Delete")
            }
        }
    }
}

struct TablePropertyCell: View {
    @Binding var item: WorkspaceItem
    let definition: PropertyDefinition
    let database: Database
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared

    private var key: String {
        definition.storageKey
    }

    private var legacyKey: String {
        PropertyDefinition.legacyKey(for: definition.name)
    }

    private var computedValue: PropertyValue {
        PropertyValueResolver.value(for: item, definition: definition, database: database, storage: storage)
    }

    private var bindingValue: Binding<PropertyValue> {
        Binding(
            get: { item.properties[key] ?? item.properties[legacyKey] ?? .empty },
            set: { newValue in
                item.properties[key] = newValue
                item.properties.removeValue(forKey: legacyKey)
                storage.updateItem(item)
            }
        )
    }

    var body: some View {
        switch definition.type {
        case .text:
            TextField("", text: bindingValue.textBinding)
                .textFieldStyle(.plain)

        case .number:
            TextField("", text: bindingValue.numberBinding)
                .textFieldStyle(.plain)

        case .select, .status:
            Picker("", selection: bindingValue.selectBinding) {
                ForEach(selectOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

        case .priority:
            Picker("", selection: bindingValue.selectBinding) {
                ForEach(selectOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

        case .multiSelect:
            TextField("", text: bindingValue.multiSelectBinding)
                .textFieldStyle(.plain)

        case .date:
            DatePicker("", selection: bindingValue.dateBinding, displayedComponents: [.date])
                .datePickerStyle(.compact)

        case .checkbox:
            Toggle("", isOn: bindingValue.checkboxBinding)
                .labelsHidden()

        case .url:
            TextField("", text: bindingValue.urlBinding)
                .textFieldStyle(.plain)

        case .email:
            TextField("", text: bindingValue.emailBinding)
                .textFieldStyle(.plain)

        case .phone:
            TextField("", text: bindingValue.phoneBinding)
                .textFieldStyle(.plain)

        case .person, .relation:
            RelationCell(
                title: definition.name,
                allItems: relationCandidates,
                selected: relatedItems,
                isMulti: bindingValue.isMultiRelation,
                onSelect: updateRelationSelection
            )
            
        case .rollup:
            // Rollup values are computed, show as read-only
            Text(computedValue.displayValue)
                .foregroundColor(.secondary)
                .font(.subheadline)
            
        case .formula:
            // Formula values are computed, show as read-only
            Text(computedValue.displayValue)
                .foregroundColor(.secondary)
                .font(.subheadline)
            
        case .createdTime, .lastEdited:
            // Auto timestamps, read-only
            Text(computedValue.displayValue)
                .foregroundColor(.secondary)
                .font(.caption)
            
        case .createdBy:
            // Auto person, read-only
            HStack(spacing: 4) {
                Image(systemName: "person.circle")
                    .foregroundColor(.secondary)
                Text(computedValue.displayValue)
                    .foregroundColor(.secondary)
            }
            .font(.caption)

        }
    }

    private var selectOptions: [String] {
        if let options = definition.options?.map({ $0.name }) {
            return options
        }
        if definition.type == .status {
            return database.kanbanColumns.map { $0.name }
        }
        if definition.type == .priority {
            return SelectOption.priorities.map { $0.name }
        }
        return []
    }

    private var relatedItems: [WorkspaceItem] {
        switch bindingValue.wrappedValue {
        case .relation(let id):
            return storage.items.filter { $0.id == id }
        case .relations(let ids):
            return storage.items.filter { ids.contains($0.id) }
        default:
            return []
        }
    }

    private var relationCandidates: [WorkspaceItem] {
        if let targetId = definition.relationConfig?.targetDatabaseId {
            return storage.items(inDatabase: targetId).filter { !$0.isArchived }
        }
        return storage.items.filter { $0.itemType != .session && !$0.isArchived }
    }

    private func updateRelationSelection(_ selection: [WorkspaceItem]) {
        let previous = bindingValue.wrappedValue
        let newValue: PropertyValue
        if bindingValue.isMultiRelation {
            newValue = .relations(selection.map { $0.id })
        } else {
            newValue = selection.first.map { .relation($0.id) } ?? .empty
        }

        item.properties[key] = newValue
        item.properties.removeValue(forKey: legacyKey)
        storage.updateItem(item)
        updateReverseRelations(previous: previous, current: newValue)
    }

    private func updateReverseRelations(previous: PropertyValue, current: PropertyValue) {
        guard let config = definition.relationConfig,
              config.isTwoWay,
              let reverseId = config.reversePropertyId else {
            return
        }

        let previousIds = Set(relationIds(from: previous))
        let currentIds = Set(relationIds(from: current))
        let added = currentIds.subtracting(previousIds)
        let removed = previousIds.subtracting(currentIds)

        for id in added {
            updateReverseRelation(targetID: id, reverseId: reverseId, add: true)
        }
        for id in removed {
            updateReverseRelation(targetID: id, reverseId: reverseId, add: false)
        }
    }

    private func updateReverseRelation(targetID: UUID, reverseId: UUID, add: Bool) {
        guard var target = storage.item(withID: targetID) else { return }
        let reverseKey = reverseId.uuidString
        var value = target.properties[reverseKey] ?? .empty

        switch value {
        case .relation(let existingId):
            if add {
                if existingId != item.id {
                    value = .relations([existingId, item.id])
                }
            } else if existingId == item.id {
                value = .empty
            }
        case .relations(var ids):
            if add {
                if !ids.contains(item.id) {
                    ids.append(item.id)
                }
            } else {
                ids.removeAll { $0 == item.id }
            }
            if ids.isEmpty {
                value = .empty
            } else if ids.count == 1 {
                value = .relation(ids[0])
            } else {
                value = .relations(ids)
            }
        case .empty:
            if add {
                value = .relation(item.id)
            }
        default:
            if add {
                value = .relation(item.id)
            }
        }

        target.properties[reverseKey] = value
        storage.updateItem(target)
    }

    private func relationIds(from value: PropertyValue) -> [UUID] {
        switch value {
        case .relation(let id):
            return [id]
        case .relations(let ids):
            return ids
        default:
            return []
        }
    }

}

struct RelationCell: View {
    let title: String
    let allItems: [WorkspaceItem]
    let selected: [WorkspaceItem]
    let isMulti: Bool
    let onSelect: ([WorkspaceItem]) -> Void
    @State private var showingPicker = false

    var body: some View {
        Button(action: { showingPicker = true }) {
            HStack(spacing: 6) {
                if selected.isEmpty {
                    Text("Add relation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(selected.prefix(2)) { item in
                        Text(item.displayTitle)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    if selected.count > 2 {
                        Text("+\(selected.count - 2)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPicker) {
            RelationPickerView(
                title: title,
                allItems: allItems,
                selected: selected,
                isMulti: isMulti,
                onSelect: { selection in
                    onSelect(selection)
                    showingPicker = false
                }
            )
        }
    }
}

struct RelationPickerView: View {
    let title: String
    let allItems: [WorkspaceItem]
    let selected: [WorkspaceItem]
    let isMulti: Bool
    let onSelect: ([WorkspaceItem]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedIDs: Set<UUID> = []

    private var filtered: [WorkspaceItem] {
        if searchText.isEmpty { return allItems }
        let query = searchText.lowercased()
        return allItems.filter { $0.displayTitle.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search items...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)

            List(filtered) { item in
                Button(action: { toggle(item) }) {
                    HStack {
                        WorkspaceIconView(name: item.icon)
                        Text(item.displayTitle)
                        Spacer()
                        if selectedIDs.contains(item.id) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Apply") {
                    let selection = allItems.filter { selectedIDs.contains($0.id) }
                    onSelect(selection)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 420, height: 480)
        .onAppear {
            selectedIDs = Set(selected.map { $0.id })
        }
    }

    private func toggle(_ item: WorkspaceItem) {
        if isMulti {
            if selectedIDs.contains(item.id) {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
            }
        } else {
            selectedIDs = [item.id]
        }
    }
}

extension Binding where Value == PropertyValue {
    var textBinding: Binding<String> {
        Binding<String>(
            get: {
                if case .text(let value) = wrappedValue { return value }
                if case .url(let value) = wrappedValue { return value }
                if case .email(let value) = wrappedValue { return value }
                if case .phone(let value) = wrappedValue { return value }
                return ""
            },
            set: { wrappedValue = .text($0) }
        )
    }

    var numberBinding: Binding<String> {
        Binding<String>(
            get: {
                if case .number(let value) = wrappedValue { return String(value) }
                return ""
            },
            set: { wrappedValue = .number(Double($0) ?? 0) }
        )
    }

    var selectBinding: Binding<String> {
        Binding<String>(
            get: {
                if case .select(let value) = wrappedValue { return value }
                return ""
            },
            set: { wrappedValue = .select($0) }
        )
    }

    var multiSelectBinding: Binding<String> {
        Binding<String>(
            get: {
                if case .multiSelect(let values) = wrappedValue { return values.joined(separator: ", ") }
                return ""
            },
            set: {
                let values = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                wrappedValue = .multiSelect(values)
            }
        )
    }

    var dateBinding: Binding<Date> {
        Binding<Date>(
            get: {
                if case .date(let value) = wrappedValue { return value }
                return Date()
            },
            set: { wrappedValue = .date($0) }
        )
    }

    var checkboxBinding: Binding<Bool> {
        Binding<Bool>(
            get: {
                if case .checkbox(let value) = wrappedValue { return value }
                return false
            },
            set: { wrappedValue = .checkbox($0) }
        )
    }

    var urlBinding: Binding<String> {
        Binding<String>(
            get: {
                if case .url(let value) = wrappedValue { return value }
                return ""
            },
            set: { wrappedValue = .url($0) }
        )
    }

    var emailBinding: Binding<String> {
        Binding<String>(
            get: {
                if case .email(let value) = wrappedValue { return value }
                return ""
            },
            set: { wrappedValue = .email($0) }
        )
    }

    var phoneBinding: Binding<String> {
        Binding<String>(
            get: {
                if case .phone(let value) = wrappedValue { return value }
                return ""
            },
            set: { wrappedValue = .phone($0) }
        )
    }

    var isMultiRelation: Bool {
        if case .relations = wrappedValue { return true }
        return false
    }
}

// MARK: - Item Detail Sheet

struct ItemDetailSheet: View {
    @State var item: WorkspaceItem
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                WorkspaceIconView(name: item.icon)
                    .font(.title2)
                
                TextField("Title", text: $item.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .textFieldStyle(.plain)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Properties
            if let status = storage.statusValue(for: item) {
                HStack {
                    Text("Status")
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .leading)
                    
                    Text(status)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            HStack {
                Text("Created")
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .leading)
                
                Text(item.formattedDate)
            }
            
            Divider()
            
            // Content area (future: block editor)
            Text("Notes")
                .font(.headline)
            
            CommitTextView(
                text: Binding(
                    get: { item.blocks.first?.content ?? "" },
                    set: { newValue in
                        if item.blocks.isEmpty {
                            item.blocks.append(Block.paragraph(newValue))
                        } else {
                            item.blocks[0].content = newValue
                        }
                    }
                ),
                onCommit: {
                    item.updatedAt = Date()
                },
                onCancel: { }
            )
            .frame(minHeight: 150)
            
            Spacer()
            
            // Actions
            HStack {
                Button(role: .destructive) {
                    storage.deleteItem(item.id)
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                
                Spacer()
                
                Button("Save") {
                    item.updatedAt = Date()
                    storage.saveItem(item)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500, height: 450)
    }
}

// MARK: - Preview

#Preview {
    KanbanBoardView(database: .taskBoard(name: "My Tasks"))
}
