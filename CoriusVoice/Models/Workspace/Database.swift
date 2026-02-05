import Foundation

// MARK: - Database View Type

/// How to display a database
enum DatabaseViewType: String, Codable, CaseIterable {
    case kanban = "kanban"
    case table = "table"
    case list = "list"
    case calendar = "calendar"
    case gallery = "gallery"
    
    var icon: String {
        switch self {
        case .kanban: return "rectangle.split.3x1"
        case .table: return "tablecells"
        case .list: return "list.bullet"
        case .calendar: return "calendar"
        case .gallery: return "square.grid.2x2"
        }
    }
    
    var displayName: String {
        switch self {
        case .kanban: return "Kanban"
        case .table: return "Table"
        case .list: return "List"
        case .calendar: return "Calendar"
        case .gallery: return "Gallery"
        }
    }
}

// MARK: - Database

/// A database that can contain items and be viewed in different ways
struct Database: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var description: String?
    var coverImageURL: String?
    var parentID: UUID?             // Parent page/workspace
    let createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var isArchived: Bool
    
    // View settings
    var defaultView: DatabaseViewType
    var views: [DatabaseView]
    
    // Schema
    var properties: [PropertyDefinition]
    
    // Kanban specific
    var kanbanGroupBy: String       // Property name to group by (usually "status")
    var kanbanColumns: [KanbanColumn]
    
    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "tablecells",
        description: String? = nil,
        coverImageURL: String? = nil,
        parentID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFavorite: Bool = false,
        isArchived: Bool = false,
        defaultView: DatabaseViewType = .kanban,
        views: [DatabaseView] = [],
        properties: [PropertyDefinition] = [],
        kanbanGroupBy: String = "status",
        kanbanColumns: [KanbanColumn] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.coverImageURL = coverImageURL
        self.parentID = parentID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.defaultView = defaultView
        self.views = views
        self.properties = properties
        self.kanbanGroupBy = kanbanGroupBy
        self.kanbanColumns = kanbanColumns
    }
    
    // MARK: - Factory Methods
    
    /// Create a standard Kanban board for tasks
    static func taskBoard(name: String, parentID: UUID? = nil) -> Database {
        let columns = KanbanColumn.defaultColumns
        
        return Database(
            name: name,
            icon: "checkmark.square",
            parentID: parentID,
            defaultView: .kanban,
            properties: [
                .status(options: columns.map { $0.toSelectOption() }),
                .priority(),
                .dueDate(),
                .assignee()
            ],
            kanbanGroupBy: "status",
            kanbanColumns: columns
        )
    }
    
    /// Create a project board
    static func projectBoard(name: String, parentID: UUID? = nil) -> Database {
        let columns: [KanbanColumn] = [
            KanbanColumn(name: "Backlog", color: "#6B7280", icon: "tray", sortOrder: 0),
            KanbanColumn(name: "Todo", color: "#3B82F6", icon: "circle", sortOrder: 1),
            KanbanColumn(name: "In Progress", color: "#F59E0B", icon: "arrow.right.circle", sortOrder: 2),
            KanbanColumn(name: "Review", color: "#8B5CF6", icon: "eye", sortOrder: 3),
            KanbanColumn(name: "Done", color: "#10B981", icon: "checkmark.circle", sortOrder: 4)
        ]
        
        return Database(
            name: name,
            icon: "rectangle.3.group",
            parentID: parentID,
            defaultView: .kanban,
            properties: [
                .status(options: columns.map { $0.toSelectOption() }),
                .priority(),
                .dueDate(),
                .assignee(),
                PropertyDefinition(name: "Tags", type: .multiSelect, sortOrder: 4)
            ],
            kanbanGroupBy: "status",
            kanbanColumns: columns
        )
    }
    
    /// Create a meeting notes database
    static func meetingNotes(name: String = "Meeting Notes", parentID: UUID? = nil) -> Database {
        Database(
            name: name,
            icon: "person.3",
            parentID: parentID,
            defaultView: .list,
            properties: [
                PropertyDefinition(name: "Date", type: .date, isRequired: true, sortOrder: 0),
                PropertyDefinition(name: "Attendees", type: .multiSelect, sortOrder: 1),
                PropertyDefinition(name: "Type", type: .select, options: [
                    SelectOption(name: "Standup", color: "#3B82F6"),
                    SelectOption(name: "Planning", color: "#10B981"),
                    SelectOption(name: "Review", color: "#F59E0B"),
                    SelectOption(name: "One-on-one", color: "#8B5CF6"),
                    SelectOption(name: "Retro", color: "#EC4899"),
                    SelectOption(name: "Other", color: "#6B7280")
                ], sortOrder: 2),
                PropertyDefinition(name: "Project", type: .text, sortOrder: 3),
                PropertyDefinition(name: "Owner", type: .person, sortOrder: 4),
                PropertyDefinition(name: "Status", type: .status, options: [
                    SelectOption(name: "Planned", color: "#3B82F6", icon: "calendar", sortOrder: 0),
                    SelectOption(name: "In Progress", color: "#F59E0B", icon: "arrow.right.circle", sortOrder: 1),
                    SelectOption(name: "Completed", color: "#10B981", icon: "checkmark.circle", sortOrder: 2)
                ], sortOrder: 5),
                PropertyDefinition(name: "Summary", type: .text, sortOrder: 6),
                PropertyDefinition(name: "Decisions", type: .text, sortOrder: 7),
                PropertyDefinition(name: "Next Steps", type: .text, sortOrder: 8),
                PropertyDefinition(name: "Actions", type: .relation, sortOrder: 9),
                PropertyDefinition(name: "Action Count", type: .number, sortOrder: 10),
                PropertyDefinition(name: "Recording", type: .relation, sortOrder: 11)
            ]
        )
    }

    /// Create a meeting action items database
    static func meetingActions(name: String = "Meeting Actions", parentID: UUID? = nil) -> Database {
        Database(
            name: name,
            icon: "checkmark.circle",
            parentID: parentID,
            defaultView: .list,
            properties: [
                PropertyDefinition(name: "Status", type: .status, options: [
                    SelectOption(name: "Todo", color: "#6B7280", icon: "circle", sortOrder: 0),
                    SelectOption(name: "In Progress", color: "#3B82F6", icon: "arrow.right.circle", sortOrder: 1),
                    SelectOption(name: "Done", color: "#10B981", icon: "checkmark.circle", sortOrder: 2)
                ], sortOrder: 0),
                PropertyDefinition(name: "Owner", type: .person, sortOrder: 1),
                PropertyDefinition(name: "Due Date", type: .date, sortOrder: 2),
                PropertyDefinition(name: "Priority", type: .priority, sortOrder: 3),
                PropertyDefinition(name: "Meeting", type: .relation, sortOrder: 4),
                PropertyDefinition(name: "Session", type: .relation, sortOrder: 5),
                PropertyDefinition(name: "Source Quote", type: .text, sortOrder: 6)
            ]
        )
    }
    
    // MARK: - Helpers
    
    func column(forStatus status: String) -> KanbanColumn? {
        kanbanColumns.first { $0.name.lowercased() == status.lowercased() }
    }
    
    var sortedColumns: [KanbanColumn] {
        kanbanColumns.sorted { $0.sortOrder < $1.sortOrder }
    }
}

// MARK: - Database View

/// A saved view configuration for a database
struct DatabaseView: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: DatabaseViewType
    var filters: [ViewFilter]
    var sorts: [ViewSort]
    var visibleProperties: [UUID]   // Property IDs to show
    var groupBy: String?
    var calendarPropertyId: UUID?
    
    init(
        id: UUID = UUID(),
        name: String,
        type: DatabaseViewType,
        filters: [ViewFilter] = [],
        sorts: [ViewSort] = [],
        visibleProperties: [UUID] = [],
        groupBy: String? = nil,
        calendarPropertyId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.filters = filters
        self.sorts = sorts
        self.visibleProperties = visibleProperties
        self.groupBy = groupBy
        self.calendarPropertyId = calendarPropertyId
    }
}

// MARK: - View Filter

struct ViewFilter: Identifiable, Codable, Hashable {
    let id: UUID
    var propertyName: String
    var propertyId: UUID?
    var operation: FilterOperation
    var value: PropertyValue
    
    init(
        id: UUID = UUID(),
        propertyName: String,
        propertyId: UUID? = nil,
        operation: FilterOperation,
        value: PropertyValue
    ) {
        self.id = id
        self.propertyName = propertyName
        self.propertyId = propertyId
        self.operation = operation
        self.value = value
    }
}

enum FilterOperation: String, Codable, CaseIterable {
    case equals = "equals"
    case notEquals = "not_equals"
    case contains = "contains"
    case notContains = "not_contains"
    case isEmpty = "is_empty"
    case isNotEmpty = "is_not_empty"
    case greaterThan = "greater_than"
    case lessThan = "less_than"

    var displayName: String {
        switch self {
        case .equals: return "is"
        case .notEquals: return "is not"
        case .contains: return "contains"
        case .notContains: return "does not contain"
        case .isEmpty: return "is empty"
        case .isNotEmpty: return "is not empty"
        case .greaterThan: return ">"
        case .lessThan: return "<"
        }
    }
}

// MARK: - View Sort

struct ViewSort: Identifiable, Codable, Hashable {
    let id: UUID
    var propertyName: String
    var propertyId: UUID?
    var ascending: Bool
    
    init(
        id: UUID = UUID(),
        propertyName: String,
        propertyId: UUID? = nil,
        ascending: Bool = true
    ) {
        self.id = id
        self.propertyName = propertyName
        self.propertyId = propertyId
        self.ascending = ascending
    }
}

// MARK: - Kanban Column

/// A column in a Kanban board
struct KanbanColumn: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: String
    var icon: String?
    var sortOrder: Int
    var limit: Int?                 // WIP limit (optional)
    var isCollapsed: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        color: String,
        icon: String? = nil,
        sortOrder: Int = 0,
        limit: Int? = nil,
        isCollapsed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.sortOrder = sortOrder
        self.limit = limit
        self.isCollapsed = isCollapsed
    }
    
    // MARK: - Default Columns
    
    static let defaultColumns: [KanbanColumn] = [
        KanbanColumn(name: "Todo", color: "#6B7280", icon: "circle", sortOrder: 0),
        KanbanColumn(name: "In Progress", color: "#3B82F6", icon: "arrow.right.circle.fill", sortOrder: 1),
        KanbanColumn(name: "Done", color: "#10B981", icon: "checkmark.circle.fill", sortOrder: 2)
    ]
    
    func toSelectOption() -> SelectOption {
        SelectOption(
            id: id,
            name: name,
            color: color,
            icon: icon,
            sortOrder: sortOrder
        )
    }
}
