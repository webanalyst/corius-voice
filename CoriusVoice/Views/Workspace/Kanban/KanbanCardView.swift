import SwiftUI

// MARK: - Kanban Card View

struct KanbanCardView: View {
    let item: WorkspaceItem
    let database: Database?
    @State private var isHovered = false

    init(item: WorkspaceItem, database: Database? = nil) {
        self.item = item
        self.database = database
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            HStack(alignment: .top, spacing: 8) {
                // Icon based on type
                Image(systemName: iconForItem)
                    .foregroundColor(iconColor)
                    .font(.caption)
                
                Text(item.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 0)
            }
            
            // Properties row
            HStack(spacing: 8) {
                // Priority badge if set
                if let priority = priorityValue {
                    PriorityBadge(priority: priority)
                }
                
                // Due date if set
                if let dueDate = dueDateValue {
                    DueDateBadge(date: dueDate)
                }
                
                Spacer()
                
                // Session indicator
                if item.sessionID != nil {
                    Image(systemName: "waveform")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
            }
            
            // Tags/Labels
            if !tagsValue.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tagsValue, id: \.self) { tag in
                            TagBadge(name: tag)
                        }
                    }
                }
            }
            
            // Footer with date
            HStack {
                Text(item.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Quick complete button for tasks
                if item.itemType == .task {
                    Button(action: {
                        // TODO: Mark as done
                    }) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor))
                .shadow(color: Color.black.opacity(isHovered ? 0.15 : 0.05), radius: isHovered ? 4 : 2, y: isHovered ? 2 : 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(isHovered ? 0.3 : 0), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contentShape(Rectangle())
    }
    
    // MARK: - Computed Properties
    
    private var iconForItem: String {
        switch item.itemType {
        case .task:
            return statusValue == "Done" ? "checkmark.circle.fill" : "circle"
        case .session:
            return "waveform"
        case .page:
            return "doc.text"
        case .database:
            return "tablecells"
        }
    }
    
    private var iconColor: Color {
        switch item.itemType {
        case .task:
            return statusValue == "Done" ? .green : .secondary
        case .session:
            return .accentColor
        default:
            return .secondary
        }
    }
    
    private var priorityValue: String? {
        if case .select(let priority) = propertyValue(for: .priority, preferredName: "Priority") {
            return priority
        }
        return nil
    }
    
    private var dueDateValue: Date? {
        if case .date(let date) = propertyValue(for: .date, preferredName: "Due Date") {
            return date
        }
        return nil
    }
    
    private var tagsValue: [String] {
        if case .multiSelect(let tags) = propertyValue(for: .multiSelect, preferredName: "Tags") {
            return tags
        }
        return []
    }

    private var statusValue: String? {
        if case .select(let status) = propertyValue(for: .status, preferredName: "Status") {
            return status
        }
        return item.statusValue
    }

    private func propertyValue(for type: PropertyType, preferredName: String? = nil) -> PropertyValue? {
        if let database {
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
}

// MARK: - Priority Badge

struct PriorityBadge: View {
    let priority: String
    
    private var color: Color {
        switch priority.lowercased() {
        case "urgent": return .red
        case "high": return .orange
        case "medium": return .yellow
        case "low": return .gray
        default: return .gray
        }
    }
    
    private var icon: String {
        switch priority.lowercased() {
        case "urgent": return "exclamationmark.triangle.fill"
        case "high": return "arrow.up"
        case "medium": return "minus"
        case "low": return "arrow.down"
        default: return "minus"
        }
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
            Text(priority)
        }
        .font(.caption2)
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .cornerRadius(4)
    }
}

// MARK: - Due Date Badge

struct DueDateBadge: View {
    let date: Date
    
    private var isOverdue: Bool {
        date < Date()
    }
    
    private var isDueSoon: Bool {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        return date < tomorrow && !isOverdue
    }
    
    private var color: Color {
        if isOverdue { return .red }
        if isDueSoon { return .orange }
        return .secondary
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "calendar")
            Text(formattedDate)
        }
        .font(.caption2)
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .cornerRadius(4)
    }
}

// MARK: - Tag Badge

struct TagBadge: View {
    let name: String
    var color: Color = .accentColor
    
    var body: some View {
        Text(name)
            .font(.caption2)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .cornerRadius(4)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        KanbanCardView(item: {
            var item = WorkspaceItem.task(title: "Implement Kanban board with drag and drop", workspaceID: UUID())
            item.properties["priority"] = .select("High")
            item.properties["dueDate"] = .date(Date().addingTimeInterval(86400))
            item.properties["tags"] = .multiSelect(["Feature", "UI"])
            return item
        }())
        
        KanbanCardView(item: WorkspaceItem.task(title: "Simple task", workspaceID: UUID()))
        
        KanbanCardView(item: {
            var item = WorkspaceItem.task(title: "Overdue task!", workspaceID: UUID())
            item.properties["priority"] = .select("Urgent")
            item.properties["dueDate"] = .date(Date().addingTimeInterval(-86400))
            return item
        }())
    }
    .padding()
    .frame(width: 300)
}
