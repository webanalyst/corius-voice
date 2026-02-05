import SwiftUI

// MARK: - Workspace View

struct WorkspaceView: View {
    @StateObject private var viewModel = WorkspaceViewModel()
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @State private var selectedItem: WorkspaceSidebarItem? = .tasks
    @State private var showingNewDatabase = false
    @State private var sidebarWidth: CGFloat = 240
    @State private var searchSelectedItem: WorkspaceItem?
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebarContent
                .frame(width: 240)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Detail Content
            detailContent
        }
        .sheet(isPresented: $showingNewDatabase) {
            NewDatabaseSheet()
        }
        .sheet(item: $searchSelectedItem) { item in
            ItemDetailSheet(item: item)
        }
        .onChange(of: storage.lastUpdate) { _, _ in
            viewModel.refreshIndexes()
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider()
                .padding(.horizontal, 12)
            
            // Quick access
            VStack(alignment: .leading, spacing: 2) {
                SidebarRow(
                    icon: "house",
                    title: "Home",
                    isSelected: selectedItem == .home,
                    action: { selectedItem = .home }
                )
                
                SidebarRow(
                    icon: "clock",
                    title: "Recent",
                    isSelected: selectedItem == .recent,
                    action: { selectedItem = .recent }
                )
                
                SidebarRow(
                    icon: "star",
                    title: "Favorites",
                    badge: storage.favoriteItems.count,
                    isSelected: selectedItem == .favorites,
                    action: { selectedItem = .favorites }
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            
            Divider()
                .padding(.horizontal, 12)
            
            // Pages section
            PagesSection(
                isSelected: { selectedItem == $0 },
                onSelect: { selectedItem = $0 },
                searchText: viewModel.searchText
            )
            
            Divider()
                .padding(.horizontal, 12)
            
            // Databases section
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("BOARDS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: { showingNewDatabase = true }) {
                        Image(systemName: "plus")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
                
                ForEach(storage.databases) { database in
                    SidebarRow(
                        icon: database.icon,
                        title: database.name,
                        iconColor: Color(hex: database.kanbanColumns.first?.color ?? "#3B82F6"),
                        badge: storage.items(inDatabase: database.id).count,
                        isSelected: selectedItem == .database(database.id),
                        action: { selectedItem = .database(database.id) }
                    )
                }
            }
            .padding(.horizontal, 8)
            
            Spacer()
            
            Divider()
                .padding(.horizontal, 12)
            
            // Settings
            VStack(alignment: .leading, spacing: 2) {
                SidebarRow(
                    icon: "trash",
                    title: "Trash",
                    isSelected: selectedItem == .trash,
                    action: { selectedItem = .trash }
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Detail Content
    
    @ViewBuilder
    private var detailContent: some View {
        if !viewModel.searchText.trimmed.isEmpty {
            WorkspaceSearchResultsView(
                query: viewModel.searchText,
                results: viewModel.searchResults,
                snippetProvider: { viewModel.snippet(for: $0, query: viewModel.searchText) },
                onOpen: openSearchResult
            )
        } else {
        switch selectedItem {
        case .home:
            HomeWorkspaceView()
            
        case .recent:
            RecentItemsView()
            
        case .favorites:
            FavoritesView()
            
        case .tasks:
            if let firstDB = storage.databases.first {
                KanbanBoardView(database: firstDB)
            } else {
                emptyStateView
            }
            
        case .page(let id):
            if storage.item(withID: id) != nil {
                PageView(itemID: id)
            } else {
                Text("Page not found")
                    .foregroundColor(.secondary)
            }
            
        case .database(let id):
            if let database = storage.database(withID: id) {
                KanbanBoardView(database: database)
            } else {
                Text("Database not found")
                    .foregroundColor(.secondary)
            }
            
        case .trash:
            TrashView()
            
        case .none:
            emptyStateView
        }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No workspace selected")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Select or create a board from the sidebar")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: { showingNewDatabase = true }) {
                Label("Create Board", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openSearchResult(_ item: WorkspaceItem) {
        viewModel.clearSearch()
        switch item.itemType {
        case .page:
            selectedItem = .page(item.id)
        case .database:
            selectedItem = .database(item.id)
        case .task:
            if let dbID = item.workspaceID {
                selectedItem = .database(dbID)
            }
            searchSelectedItem = item
        case .session:
            searchSelectedItem = item
        }
    }
}

// MARK: - Search Results

struct WorkspaceSearchResultsView: View {
    let query: String
    let results: [WorkspaceItem]
    let snippetProvider: (WorkspaceItem) -> String
    let onOpen: (WorkspaceItem) -> Void
    @ObservedObject private var storage = WorkspaceStorageServiceOptimized.shared

    private var groupedResults: [(WorkspaceItemType, [WorkspaceItem])] {
        let order: [WorkspaceItemType] = [.page, .database, .task, .session]
        return order.compactMap { type in
            let items = results.filter { $0.itemType == type }
            return items.isEmpty ? nil : (type, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(groupedResults, id: \.0) { type, items in
                            sectionHeader(type)
                            ForEach(items) { item in
                                resultRow(item)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Search")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("“\(query.trimmed)” • \(results.count) results")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No results found")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Try searching for titles, content, or properties.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionHeader(_ type: WorkspaceItemType) -> some View {
        Text(type.displayName.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.top, 8)
    }

    private func resultRow(_ item: WorkspaceItem) -> some View {
        Button(action: { onOpen(item) }) {
            HStack(alignment: .top, spacing: 12) {
                WorkspaceIconView(name: item.icon)
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.displayTitle)
                        .font(.headline)
                        .foregroundColor(.primary)

                    let snippet = snippetProvider(item)
                    if !snippet.isEmpty {
                        Text(snippet)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Text(contextLine(for: item))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(item.updatedAt.relativeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func contextLine(for item: WorkspaceItem) -> String {
        var parts: [String] = [item.itemType.displayName]
        if let dbID = item.workspaceID,
           let database = storage.database(withID: dbID),
           item.itemType != .database {
            parts.append("in \(database.name)")
        }
        return parts.joined(separator: " • ")
    }
}

// MARK: - Sidebar Item

enum WorkspaceSidebarItem: Hashable {
    case home
    case recent
    case favorites
    case tasks
    case page(UUID)
    case database(UUID)
    case trash
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let icon: String
    let title: String
    var iconColor: Color? = nil
    var badge: Int = 0
    var isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(iconColor ?? (isSelected ? .accentColor : .secondary))
                    .frame(width: 20)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Spacer()
                
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pages Section

struct PagesSection: View {
    let isSelected: (WorkspaceSidebarItem) -> Bool
    let onSelect: (WorkspaceSidebarItem) -> Void
    let searchText: String

    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var allPages: [WorkspaceItem] {
        storage.items(ofType: .page)
    }

    private var filteredPages: [WorkspaceItem] {
        guard !trimmedQuery.isEmpty else { return allPages }
        let lower = trimmedQuery.lowercased()
        return allPages.filter { $0.title.lowercased().contains(lower) }
    }

    private var rootPages: [WorkspaceItem] {
        filteredPages.filter { $0.parentID == nil }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("PAGES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: createPage) {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)

            if trimmedQuery.isEmpty {
                PagesTreeList(
                    pages: filteredPages,
                    parentID: nil,
                    depth: 0,
                    isSelected: isSelected,
                    onSelect: onSelect
                )
            } else {
                ForEach(filteredPages.sorted { $0.updatedAt > $1.updatedAt }) { page in
                    pageButton(page, depth: 0)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private func pageButton(_ page: WorkspaceItem, depth: Int) -> some View {
        let selected = isSelected(.page(page.id))
        return Button(action: { onSelect(.page(page.id)) }) {
            HStack(spacing: 10) {
                WorkspaceIconView(name: page.icon)
                    .font(.body)
                    .foregroundColor(selected ? .accentColor : .secondary)
                    .frame(width: 20)

                Text(page.displayTitle)
                    .font(.body)
                    .foregroundColor(selected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .padding(.leading, CGFloat(depth) * 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func createPage() {
        let page = WorkspaceItem.page(title: "Untitled", icon: "doc.text", parentID: nil)
        _ = storage.createItem(page)
        onSelect(.page(page.id))
    }
}

private struct PagesTreeList: View {
    let pages: [WorkspaceItem]
    let parentID: UUID?
    let depth: Int
    let isSelected: (WorkspaceSidebarItem) -> Bool
    let onSelect: (WorkspaceSidebarItem) -> Void

    private var children: [WorkspaceItem] {
        pages.filter { $0.parentID == parentID }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ForEach(children) { page in
            PagesTreeRow(
                page: page,
                depth: depth,
                isSelected: isSelected,
                onSelect: onSelect
            )
            PagesTreeList(
                pages: pages,
                parentID: page.id,
                depth: depth + 1,
                isSelected: isSelected,
                onSelect: onSelect
            )
        }
    }
}

private struct PagesTreeRow: View {
    let page: WorkspaceItem
    let depth: Int
    let isSelected: (WorkspaceSidebarItem) -> Bool
    let onSelect: (WorkspaceSidebarItem) -> Void

    var body: some View {
        let selected = isSelected(.page(page.id))
        return Button(action: { onSelect(.page(page.id)) }) {
            HStack(spacing: 10) {
                WorkspaceIconView(name: page.icon)
                    .font(.body)
                    .foregroundColor(selected ? .accentColor : .secondary)
                    .frame(width: 20)

                Text(page.displayTitle)
                    .font(.body)
                    .foregroundColor(selected ? .primary : .secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .padding(.leading, CGFloat(depth) * 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - New Database Sheet

struct NewDatabaseSheet: View {
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var selectedTemplate: DatabaseTemplate = .taskBoard
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Create New Board")
                .font(.headline)
            
            TextField("Board name...", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            // Templates
            VStack(alignment: .leading, spacing: 8) {
                Text("Template")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(DatabaseTemplate.allCases, id: \.self) { template in
                    TemplateRow(
                        template: template,
                        isSelected: selectedTemplate == template,
                        action: { selectedTemplate = template }
                    )
                }
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Create") {
                    createDatabase()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
    
    private func createDatabase() {
        let database: Database
        switch selectedTemplate {
        case .taskBoard:
            database = .taskBoard(name: name)
        case .projectBoard:
            database = .projectBoard(name: name)
        case .meetingNotes:
            database = .meetingNotes(name: name)
        }
        
        Task {
            await MainActor.run {
                storage.saveDatabase(database)
                dismiss()
            }
        }
    }
}

enum DatabaseTemplate: String, CaseIterable {
    case taskBoard = "Task Board"
    case projectBoard = "Project Board"
    case meetingNotes = "Meeting Notes"
    
    var icon: String {
        switch self {
        case .taskBoard: return "checkmark.square"
        case .projectBoard: return "rectangle.3.group"
        case .meetingNotes: return "person.3"
        }
    }
    
    var description: String {
        switch self {
        case .taskBoard: return "Simple todo/doing/done workflow"
        case .projectBoard: return "Backlog, sprint planning, review"
        case .meetingNotes: return "Track meetings with recordings"
        }
    }
}

struct TemplateRow: View {
    let template: DatabaseTemplate
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.rawValue)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Text(template.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Placeholder Views

struct HomeWorkspaceView: View {
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("Welcome back!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Here's what's happening in your workspace")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                // Quick stats
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    StatCard(
                        title: "Total Tasks",
                        value: "\(storage.items.count)",
                        icon: "checkmark.square",
                        color: .blue
                    )
                    
                    StatCard(
                        title: "In Progress",
                        value: "\(storage.items.filter { storage.statusValue(for: $0) == "In Progress" }.count)",
                        icon: "arrow.right.circle",
                        color: .orange
                    )
                    
                    StatCard(
                        title: "Completed",
                        value: "\(storage.items.filter { storage.statusValue(for: $0) == "Done" }.count)",
                        icon: "checkmark.circle",
                        color: .green
                    )
                }
                
                // Recent items
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent")
                        .font(.headline)
                    
                    ForEach(storage.recentItems(limit: 5)) { item in
                        HStack {
                            WorkspaceIconView(name: item.icon)
                                .foregroundColor(.secondary)
                            Text(item.displayTitle)
                            Spacer()
                            Text(item.formattedDate)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Spacer()
            }
            .padding(24)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct RecentItemsView: View {
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @StateObject private var lazyLoader = LazyLoadingService(pageSize: 50)
    
    var body: some View {
        List(lazyLoader.items) { item in
            HStack {
                WorkspaceIconView(name: item.icon)
                    .foregroundColor(.secondary)
                Text(item.displayTitle)
                Spacer()
                Text(item.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Recent")
        .onAppear {
            refreshItems()
        }
        .onChange(of: storage.lastUpdate) { _, _ in
            refreshItems()
        }
    }

    private func refreshItems() {
        let items = storage.recentItems(limit: 200)
        lazyLoader.initialize(with: items)
    }
}

struct FavoritesView: View {
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @StateObject private var lazyLoader = LazyLoadingService(pageSize: 50)
    
    var body: some View {
        Group {
            if lazyLoader.items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "star")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No favorites yet")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Star items to see them here")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(lazyLoader.items) { item in
                    HStack {
                        WorkspaceIconView(name: item.icon)
                            .foregroundColor(.secondary)
                        Text(item.displayTitle)
                        Spacer()
                    }
                }
                .navigationTitle("Favorites")
            }
        }
        .onAppear {
            refreshItems()
        }
        .onChange(of: storage.lastUpdate) { _, _ in
            refreshItems()
        }
    }

    private func refreshItems() {
        lazyLoader.initialize(with: storage.favoriteItems)
    }
}

struct TrashView: View {
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @StateObject private var lazyLoader = LazyLoadingService(pageSize: 50)
    
    private var archivedItems: [WorkspaceItem] {
        lazyLoader.items
    }
    
    var body: some View {
        Group {
            if archivedItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "trash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Trash is empty")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(archivedItems) { item in
                    HStack {
                        WorkspaceIconView(name: item.icon)
                            .foregroundColor(.secondary)
                        Text(item.displayTitle)
                        Spacer()
                        Button("Restore") {
                            var restored = item
                            restored.isArchived = false
                            Task {
                                await MainActor.run {
                                    storage.saveItem(restored)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .navigationTitle("Trash")
            }
        }
        .onAppear {
            refreshItems()
        }
        .onChange(of: storage.lastUpdate) { _, _ in
            refreshItems()
        }
    }

    private func refreshItems() {
        let items = storage.items.filter { $0.isArchived }
        lazyLoader.initialize(with: items)
    }
}

// MARK: - Preview

#Preview {
    WorkspaceView()
        .frame(width: 1200, height: 800)
}
