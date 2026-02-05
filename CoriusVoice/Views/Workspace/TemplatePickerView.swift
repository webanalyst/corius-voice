import SwiftUI

// MARK: - Template Picker View

struct TemplatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var templateService = TemplateService.shared
    
    let onSelect: (Template) -> Void
    
    @State private var searchText = ""
    @State private var selectedCategory: TemplateCategory?
    @State private var selectedType: TemplateType?
    @State private var showingCreateTemplate = false
    
    private var filteredTemplates: [Template] {
        var templates = templateService.allTemplates
        
        // Filter by category
        if let category = selectedCategory {
            templates = templates.filter { $0.category == category }
        }
        
        // Filter by type
        if let type = selectedType {
            templates = templates.filter { $0.templateType == type }
        }
        
        // Filter by search
        if !searchText.isEmpty {
            templates = templateService.searchTemplates(query: searchText)
        }
        
        return templates
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search templates...", text: $searchText)
                        .textFieldStyle(.plain)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                HStack(spacing: 0) {
                    // Sidebar
                    VStack(alignment: .leading, spacing: 0) {
                        // Quick access
                        Group {
                            SidebarSection(title: "Quick Access")
                            
                            SidebarButton(
                                icon: "clock",
                                title: "Recent",
                                isSelected: selectedCategory == nil && selectedType == nil && searchText.isEmpty
                            ) {
                                selectedCategory = nil
                                selectedType = nil
                            }
                            
                            SidebarButton(
                                icon: "star",
                                title: "Favorites",
                                isSelected: false
                            ) {
                                // Show favorites
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Types
                        Group {
                            SidebarSection(title: "Types")
                            
                            ForEach(TemplateType.allCases, id: \.self) { type in
                                SidebarButton(
                                    icon: type.icon,
                                    title: type.displayName,
                                    isSelected: selectedType == type
                                ) {
                                    selectedType = type
                                    selectedCategory = nil
                                }
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // Categories
                        Group {
                            SidebarSection(title: "Categories")
                            
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(TemplateCategory.allCases, id: \.self) { category in
                                        SidebarButton(
                                            icon: category.icon,
                                            title: category.displayName,
                                            isSelected: selectedCategory == category
                                        ) {
                                            selectedCategory = category
                                            selectedType = nil
                                        }
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .frame(width: 180)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    
                    Divider()
                    
                    // Templates grid
                    ScrollView {
                        if selectedCategory == nil && selectedType == nil && searchText.isEmpty {
                            // Show recent and suggested
                            RecentAndSuggestedSection(
                                templateService: templateService,
                                onSelect: selectTemplate
                            )
                        } else {
                            // Show filtered templates
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)
                            ], spacing: 16) {
                                ForEach(filteredTemplates) { template in
                                    TemplateCard(
                                        template: template,
                                        isFavorite: templateService.isFavorite(template),
                                        onSelect: { selectTemplate(template) },
                                        onToggleFavorite: { templateService.toggleFavorite(template) }
                                    )
                                }
                            }
                            .padding(20)
                        }
                    }
                }
            }
            .frame(minWidth: 700, minHeight: 500)
            .navigationTitle("Choose a Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectTemplate(.blankPage)
                    } label: {
                        Label("Blank Page", systemImage: "doc")
                    }
                }
            }
        }
    }
    
    private func selectTemplate(_ template: Template) {
        onSelect(template)
        dismiss()
    }
}

// MARK: - Sidebar Components

private struct SidebarSection: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

private struct SidebarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundColor(isSelected ? .accentColor : .primary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}

// MARK: - Recent and Suggested Section

private struct RecentAndSuggestedSection: View {
    @ObservedObject var templateService: TemplateService
    let onSelect: (Template) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Recent templates
            if !templateService.getRecentTemplates().isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent")
                        .font(.headline)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(templateService.getRecentTemplates().prefix(5)) { template in
                                TemplateCardSmall(template: template, onSelect: { onSelect(template) })
                            }
                        }
                    }
                }
            }
            
            // Suggested for you
            VStack(alignment: .leading, spacing: 12) {
                Text("Suggested")
                    .font(.headline)
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)
                ], spacing: 16) {
                    ForEach([Template.meetingNotes, .taskTracker, .projectBrief, .dailyJournal]) { template in
                        TemplateCard(
                            template: template,
                            isFavorite: templateService.isFavorite(template),
                            onSelect: { onSelect(template) },
                            onToggleFavorite: { templateService.toggleFavorite(template) }
                        )
                    }
                }
            }
            
            // All templates
            VStack(alignment: .leading, spacing: 12) {
                Text("All Templates")
                    .font(.headline)
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)
                ], spacing: 16) {
                    ForEach(templateService.allTemplates) { template in
                        TemplateCard(
                            template: template,
                            isFavorite: templateService.isFavorite(template),
                            onSelect: { onSelect(template) },
                            onToggleFavorite: { templateService.toggleFavorite(template) }
                        )
                    }
                }
            }
        }
        .padding(20)
    }
}

// MARK: - Template Card

struct TemplateCard: View {
    let template: Template
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(categoryColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: template.icon)
                            .font(.system(size: 18))
                            .foregroundColor(categoryColor)
                    }
                    
                    Spacer()
                    
                    if template.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundColor(isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered || isFavorite ? 1 : 0)
                }
                
                // Title & Description
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text(template.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(height: 32, alignment: .top)
                }
                
                // Tags
                HStack(spacing: 4) {
                    Image(systemName: template.templateType.icon)
                        .font(.caption2)
                    Text(template.templateType.displayName)
                        .font(.caption2)
                    
                    Spacer()
                    
                    Image(systemName: template.category.icon)
                        .font(.caption2)
                    Text(template.category.displayName)
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isHovered ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
    
    private var categoryColor: Color {
        switch template.category {
        case .personal: return .blue
        case .work: return .orange
        case .education: return .green
        case .design: return .pink
        case .engineering: return .purple
        case .marketing: return .red
        case .hr: return .teal
        case .sales: return .yellow
        case .support: return .cyan
        case .custom: return .indigo
        }
    }
}

// MARK: - Template Card Small

struct TemplateCardSmall: View {
    let template: Template
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text(template.templateType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovered ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Save as Template Sheet

struct SaveAsTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var templateService = TemplateService.shared
    
    let item: WorkspaceItem
    let onSave: (Template) -> Void
    
    @State private var name: String
    @State private var description = ""
    @State private var category: TemplateCategory = .custom
    @State private var icon: String
    
    init(item: WorkspaceItem, onSave: @escaping (Template) -> Void) {
        self.item = item
        self.onSave = onSave
        _name = State(initialValue: "\(item.title) Template")
        _icon = State(initialValue: item.icon)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Save as Template")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
            }
            
            Divider()
            
            // Form
            VStack(alignment: .leading, spacing: 16) {
                // Icon & Name
                HStack(spacing: 12) {
                    IconPicker(selectedIcon: $icon)
                    
                    TextField("Template name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Description
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    CommitTextView(
                        text: $description,
                        onCommit: { },
                        onCancel: { }
                    )
                    .frame(minHeight: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                }
                
                // Category
                VStack(alignment: .leading, spacing: 4) {
                    Text("Category")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Category", selection: $category) {
                        ForEach(TemplateCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            
            Divider()
            
            // Preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name.isEmpty ? "Untitled Template" : name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(description.isEmpty ? "No description" : description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.itemType == .database ? "Database" : "Page")
                            .font(.caption)
                        Text(category.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Spacer()
            
            // Actions
            HStack {
                Spacer()
                
                Button("Save Template") {
                    let template = templateService.createTemplate(
                        from: item,
                        name: name,
                        description: description,
                        category: category,
                        icon: icon
                    )
                    onSave(template)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 450, height: 450)
    }
}

// MARK: - Icon Picker

struct IconPicker: View {
    @Binding var selectedIcon: String
    @State private var showingPicker = false
    
    private let commonIcons = [
        "doc.text", "doc", "folder", "book", "note.text",
        "list.bullet", "checkmark.square", "tablecells",
        "calendar", "clock", "star", "heart", "flag",
        "person", "person.2", "person.3", "briefcase",
        "lightbulb", "gear", "wrench", "hammer",
        "paintbrush", "pencil", "chart.bar", "chart.pie"
    ]
    
    var body: some View {
        Button {
            showingPicker.toggle()
        } label: {
            WorkspaceIconView(name: selectedIcon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPicker) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40)), count: 6), spacing: 8) {
                ForEach(commonIcons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                        showingPicker = false
                    } label: {
                        WorkspaceIconView(name: icon)
                            .font(.title3)
                            .foregroundColor(selectedIcon == icon ? .white : .primary)
                            .frame(width: 36, height: 36)
                            .background(selectedIcon == icon ? Color.accentColor : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - Preview

#Preview {
    TemplatePickerView { template in
        print("Selected: \(template.name)")
    }
}
