import Foundation

// MARK: - Linked Database

/// A view of another database that syncs automatically
/// Similar to Notion's linked database feature
struct LinkedDatabase: Identifiable, Codable, Hashable {
    let id: UUID
    let sourceId: UUID              // The original database ID
    var title: String               // Display title (can differ from source)
    var filter: DatabaseFilter?     // Optional filter applied to this view
    var sortRules: [SortRule]       // Sort rules for this view
    var visibleProperties: [UUID]   // Which properties to show
    var viewType: LinkedViewType    // How to display (table, board, etc)
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        sourceId: UUID,
        title: String? = nil,
        filter: DatabaseFilter? = nil,
        sortRules: [SortRule] = [],
        visibleProperties: [UUID] = [],
        viewType: LinkedViewType = .table
    ) {
        self.id = id
        self.sourceId = sourceId
        self.title = title ?? "Linked Database"
        self.filter = filter
        self.sortRules = sortRules
        self.visibleProperties = visibleProperties
        self.viewType = viewType
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Database Filter

/// Filters to apply to database views
struct DatabaseFilter: Codable, Hashable {
    var conditions: [FilterCondition]
    var logic: FilterLogic
    
    enum FilterLogic: String, Codable {
        case and = "and"
        case or = "or"
    }
    
    init(conditions: [FilterCondition] = [], logic: FilterLogic = .and) {
        self.conditions = conditions
        self.logic = logic
    }
}

// MARK: - Filter Condition

struct FilterCondition: Identifiable, Codable, Hashable {
    let id: UUID
    var propertyId: UUID
    var operation: LinkedFilterOperation
    var value: FilterValue
    
    init(id: UUID = UUID(), propertyId: UUID, operation: LinkedFilterOperation, value: FilterValue) {
        self.id = id
        self.propertyId = propertyId
        self.operation = operation
        self.value = value
    }
}

// MARK: - Filter Operation (Extended)

enum LinkedFilterOperation: String, Codable, CaseIterable {
    // Text operations
    case equals = "equals"
    case notEquals = "not_equals"
    case contains = "contains"
    case notContains = "not_contains"
    case startsWith = "starts_with"
    case endsWith = "ends_with"
    case isEmpty = "is_empty"
    case isNotEmpty = "is_not_empty"
    
    // Number operations
    case greaterThan = "greater_than"
    case lessThan = "less_than"
    case greaterOrEqual = "greater_or_equal"
    case lessOrEqual = "less_or_equal"
    
    // Date operations
    case isBefore = "is_before"
    case isAfter = "is_after"
    case isOnOrBefore = "is_on_or_before"
    case isOnOrAfter = "is_on_or_after"
    case pastWeek = "past_week"
    case pastMonth = "past_month"
    case pastYear = "past_year"
    case nextWeek = "next_week"
    case nextMonth = "next_month"
    case nextYear = "next_year"
    
    // Checkbox
    case isChecked = "is_checked"
    case isNotChecked = "is_not_checked"
    
    // Relation
    case relationContains = "relation_contains"
    case relationNotContains = "relation_not_contains"
    
    var displayName: String {
        switch self {
        case .equals: return "is"
        case .notEquals: return "is not"
        case .contains: return "contains"
        case .notContains: return "does not contain"
        case .startsWith: return "starts with"
        case .endsWith: return "ends with"
        case .isEmpty: return "is empty"
        case .isNotEmpty: return "is not empty"
        case .greaterThan: return ">"
        case .lessThan: return "<"
        case .greaterOrEqual: return "≥"
        case .lessOrEqual: return "≤"
        case .isBefore: return "is before"
        case .isAfter: return "is after"
        case .isOnOrBefore: return "is on or before"
        case .isOnOrAfter: return "is on or after"
        case .pastWeek: return "is within past week"
        case .pastMonth: return "is within past month"
        case .pastYear: return "is within past year"
        case .nextWeek: return "is within next week"
        case .nextMonth: return "is within next month"
        case .nextYear: return "is within next year"
        case .isChecked: return "is checked"
        case .isNotChecked: return "is not checked"
        case .relationContains: return "contains"
        case .relationNotContains: return "does not contain"
        }
    }
    
    static func operations(for type: PropertyType) -> [LinkedFilterOperation] {
        switch type {
        case .text, .url, .email, .phone:
            return [.equals, .notEquals, .contains, .notContains, .startsWith, .endsWith, .isEmpty, .isNotEmpty]
        case .number:
            return [.equals, .notEquals, .greaterThan, .lessThan, .greaterOrEqual, .lessOrEqual, .isEmpty, .isNotEmpty]
        case .select, .status, .priority:
            return [.equals, .notEquals, .isEmpty, .isNotEmpty]
        case .multiSelect:
            return [.contains, .notContains, .isEmpty, .isNotEmpty]
        case .date, .createdTime, .lastEdited:
            return [.equals, .isBefore, .isAfter, .isOnOrBefore, .isOnOrAfter, .pastWeek, .pastMonth, .pastYear, .nextWeek, .nextMonth, .nextYear, .isEmpty, .isNotEmpty]
        case .checkbox:
            return [.isChecked, .isNotChecked]
        case .person, .relation, .createdBy:
            return [.relationContains, .relationNotContains, .isEmpty, .isNotEmpty]
        case .rollup, .formula:
            return [.isEmpty, .isNotEmpty]
        }
    }
}

// MARK: - Filter Value

enum FilterValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case date(Date)
    case bool(Bool)
    case id(UUID)
    case ids([UUID])
    case none
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case type, value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let value):
            try container.encode("string", forKey: .type)
            try container.encode(value, forKey: .value)
        case .number(let value):
            try container.encode("number", forKey: .type)
            try container.encode(value, forKey: .value)
        case .date(let value):
            try container.encode("date", forKey: .type)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode("bool", forKey: .type)
            try container.encode(value, forKey: .value)
        case .id(let value):
            try container.encode("id", forKey: .type)
            try container.encode(value, forKey: .value)
        case .ids(let values):
            try container.encode("ids", forKey: .type)
            try container.encode(values, forKey: .value)
        case .none:
            try container.encode("none", forKey: .type)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "string":
            self = .string(try container.decode(String.self, forKey: .value))
        case "number":
            self = .number(try container.decode(Double.self, forKey: .value))
        case "date":
            self = .date(try container.decode(Date.self, forKey: .value))
        case "bool":
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case "id":
            self = .id(try container.decode(UUID.self, forKey: .value))
        case "ids":
            self = .ids(try container.decode([UUID].self, forKey: .value))
        default:
            self = .none
        }
    }
}

// MARK: - Sort Rule

struct SortRule: Identifiable, Codable, Hashable {
    let id: UUID
    var propertyId: UUID
    var direction: SortDirection
    
    enum SortDirection: String, Codable {
        case ascending = "ascending"
        case descending = "descending"
    }
    
    init(id: UUID = UUID(), propertyId: UUID, direction: SortDirection = .ascending) {
        self.id = id
        self.propertyId = propertyId
        self.direction = direction
    }
}

// MARK: - Linked View Type

enum LinkedViewType: String, Codable, CaseIterable {
    case table = "table"
    case board = "board"        // Kanban
    case list = "list"          // Simple list
    case gallery = "gallery"    // Card grid
    case calendar = "calendar"  // Calendar view
    case timeline = "timeline"  // Gantt-like
    
    var icon: String {
        switch self {
        case .table: return "tablecells"
        case .board: return "square.split.2x2"
        case .list: return "list.bullet"
        case .gallery: return "square.grid.2x2"
        case .calendar: return "calendar"
        case .timeline: return "chart.bar.xaxis"
        }
    }
    
    var displayName: String {
        switch self {
        case .table: return "Table"
        case .board: return "Board"
        case .list: return "List"
        case .gallery: return "Gallery"
        case .calendar: return "Calendar"
        case .timeline: return "Timeline"
        }
    }
}
