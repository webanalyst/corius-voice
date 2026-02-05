import Foundation

// MARK: - Property Types

/// Types of properties that can be attached to workspace items
enum PropertyType: String, Codable, CaseIterable {
    case text = "text"
    case number = "number"
    case select = "select"
    case multiSelect = "multi_select"
    case date = "date"
    case checkbox = "checkbox"
    case url = "url"
    case email = "email"
    case phone = "phone"
    case person = "person"          // Assign to a speaker/person
    case relation = "relation"      // Link to another item
    case rollup = "rollup"          // Aggregate data from relations
    case formula = "formula"        // Computed value
    case status = "status"          // Special for Kanban
    case priority = "priority"      // High/Medium/Low
    case createdTime = "created_time"   // Auto timestamp
    case lastEdited = "last_edited"     // Auto timestamp
    case createdBy = "created_by"       // Auto person

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .number: return "Number"
        case .select: return "Select"
        case .multiSelect: return "Multi-select"
        case .date: return "Date"
        case .checkbox: return "Checkbox"
        case .url: return "URL"
        case .email: return "Email"
        case .phone: return "Phone"
        case .person: return "Person"
        case .relation: return "Relation"
        case .rollup: return "Rollup"
        case .formula: return "Formula"
        case .status: return "Status"
        case .priority: return "Priority"
        case .createdTime: return "Created time"
        case .lastEdited: return "Last edited"
        case .createdBy: return "Created by"
        }
    }
}

// MARK: - Relation Configuration

/// Configuration for a relation property
struct RelationConfig: Codable, Hashable {
    var targetDatabaseId: UUID      // The database this relation points to
    var isTwoWay: Bool              // Whether to create a synced relation in target
    var reversePropertyId: UUID?    // The property ID in target database
    var reverseName: String?        // Name of the reverse relation
    
    init(targetDatabaseId: UUID, isTwoWay: Bool = false, reversePropertyId: UUID? = nil, reverseName: String? = nil) {
        self.targetDatabaseId = targetDatabaseId
        self.isTwoWay = isTwoWay
        self.reversePropertyId = reversePropertyId
        self.reverseName = reverseName
    }
}

// MARK: - Rollup Configuration

/// Configuration for a rollup property
struct RollupConfig: Codable, Hashable {
    var relationPropertyId: UUID    // The relation property to roll up from
    var targetPropertyId: UUID      // The property to aggregate in related items
    var calculation: RollupCalculation
    
    enum RollupCalculation: String, Codable, CaseIterable {
        case showOriginal = "show_original"     // Show all values
        case countAll = "count_all"             // Count all
        case countValues = "count_values"       // Count non-empty
        case countUnique = "count_unique"       // Count unique
        case countEmpty = "count_empty"         // Count empty
        case percentEmpty = "percent_empty"     
        case percentNotEmpty = "percent_not_empty"
        case sum = "sum"                        // Sum numbers
        case average = "average"                // Average numbers
        case median = "median"                  
        case min = "min"                        
        case max = "max"                        
        case range = "range"                    // Max - Min
        case earliest = "earliest"              // Earliest date
        case latest = "latest"                  // Latest date
        case dateRange = "date_range"           // Date span
        case showUnique = "show_unique"         // Unique values
        case checked = "checked"                // Count checked
        case unchecked = "unchecked"            // Count unchecked
        
        var displayName: String {
            switch self {
            case .showOriginal: return "Show original"
            case .countAll: return "Count all"
            case .countValues: return "Count values"
            case .countUnique: return "Count unique"
            case .countEmpty: return "Count empty"
            case .percentEmpty: return "Percent empty"
            case .percentNotEmpty: return "Percent not empty"
            case .sum: return "Sum"
            case .average: return "Average"
            case .median: return "Median"
            case .min: return "Min"
            case .max: return "Max"
            case .range: return "Range"
            case .earliest: return "Earliest date"
            case .latest: return "Latest date"
            case .dateRange: return "Date range"
            case .showUnique: return "Show unique"
            case .checked: return "Checked"
            case .unchecked: return "Unchecked"
            }
        }
        
        var applicableTypes: [PropertyType] {
            switch self {
            case .showOriginal, .countAll, .countValues, .countUnique, .countEmpty, .percentEmpty, .percentNotEmpty, .showUnique:
                return PropertyType.allCases
            case .sum, .average, .median, .min, .max, .range:
                return [.number]
            case .earliest, .latest, .dateRange:
                return [.date, .createdTime, .lastEdited]
            case .checked, .unchecked:
                return [.checkbox]
            }
        }
    }
}

// MARK: - Property Value

/// The actual value of a property
enum PropertyValue: Codable, Hashable {
    case text(String)
    case number(Double)
    case select(String)
    case multiSelect([String])
    case date(Date)
    case checkbox(Bool)
    case url(String)
    case email(String)
    case phone(String)
    case person(UUID)               // Speaker/Person ID
    case relation(UUID)             // Related item ID
    case relations([UUID])          // Multiple relations
    case empty
    
    // MARK: - Display Value
    
    var displayValue: String {
        switch self {
        case .text(let value): return value
        case .number(let value): return String(format: "%.2f", value)
        case .select(let value): return value
        case .multiSelect(let values): return values.joined(separator: ", ")
        case .date(let value):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: value)
        case .checkbox(let value): return value ? "✓" : "○"
        case .url(let value): return value
        case .email(let value): return value
        case .phone(let value): return value
        case .person: return "Person"
        case .relation: return "Related"
        case .relations(let ids): return "\(ids.count) items"
        case .empty: return ""
        }
    }
    
    var isEmpty: Bool {
        switch self {
        case .text(let value): return value.isEmpty
        case .multiSelect(let values): return values.isEmpty
        case .relations(let ids): return ids.isEmpty
        case .empty: return true
        default: return false
        }
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case type, value
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .value)
        case .number(let value):
            try container.encode("number", forKey: .type)
            try container.encode(value, forKey: .value)
        case .select(let value):
            try container.encode("select", forKey: .type)
            try container.encode(value, forKey: .value)
        case .multiSelect(let values):
            try container.encode("multiSelect", forKey: .type)
            try container.encode(values, forKey: .value)
        case .date(let value):
            try container.encode("date", forKey: .type)
            try container.encode(value, forKey: .value)
        case .checkbox(let value):
            try container.encode("checkbox", forKey: .type)
            try container.encode(value, forKey: .value)
        case .url(let value):
            try container.encode("url", forKey: .type)
            try container.encode(value, forKey: .value)
        case .email(let value):
            try container.encode("email", forKey: .type)
            try container.encode(value, forKey: .value)
        case .phone(let value):
            try container.encode("phone", forKey: .type)
            try container.encode(value, forKey: .value)
        case .person(let id):
            try container.encode("person", forKey: .type)
            try container.encode(id, forKey: .value)
        case .relation(let id):
            try container.encode("relation", forKey: .type)
            try container.encode(id, forKey: .value)
        case .relations(let ids):
            try container.encode("relations", forKey: .type)
            try container.encode(ids, forKey: .value)
        case .empty:
            try container.encode("empty", forKey: .type)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .value))
        case "number":
            self = .number(try container.decode(Double.self, forKey: .value))
        case "select":
            self = .select(try container.decode(String.self, forKey: .value))
        case "multiSelect":
            self = .multiSelect(try container.decode([String].self, forKey: .value))
        case "date":
            self = .date(try container.decode(Date.self, forKey: .value))
        case "checkbox":
            self = .checkbox(try container.decode(Bool.self, forKey: .value))
        case "url":
            self = .url(try container.decode(String.self, forKey: .value))
        case "email":
            self = .email(try container.decode(String.self, forKey: .value))
        case "phone":
            self = .phone(try container.decode(String.self, forKey: .value))
        case "person":
            self = .person(try container.decode(UUID.self, forKey: .value))
        case "relation":
            self = .relation(try container.decode(UUID.self, forKey: .value))
        case "relations":
            self = .relations(try container.decode([UUID].self, forKey: .value))
        default:
            self = .empty
        }
    }
}

// MARK: - Property Definition

/// Defines a property schema for a database
struct PropertyDefinition: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: PropertyType
    var options: [SelectOption]?    // For select/multi-select
    var relationConfig: RelationConfig?  // For relation type
    var rollupConfig: RollupConfig?      // For rollup type
    var formula: String?                 // For formula type
    var isRequired: Bool
    var isHidden: Bool
    var sortOrder: Int

    var storageKey: String {
        id.uuidString
    }

    static func legacyKey(for name: String) -> String {
        let parts = name.split(separator: " ").map { String($0) }
        guard let first = parts.first else { return name.lowercased() }
        let rest = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        return ([first.lowercased()] + rest).joined()
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        type: PropertyType,
        options: [SelectOption]? = nil,
        relationConfig: RelationConfig? = nil,
        rollupConfig: RollupConfig? = nil,
        formula: String? = nil,
        isRequired: Bool = false,
        isHidden: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.options = options
        self.relationConfig = relationConfig
        self.rollupConfig = rollupConfig
        self.formula = formula
        self.isRequired = isRequired
        self.isHidden = isHidden
        self.sortOrder = sortOrder
    }
    
    // MARK: - Common Property Definitions
    
    static func status(options: [SelectOption] = SelectOption.defaultStatuses) -> PropertyDefinition {
        PropertyDefinition(
            name: "Status",
            type: .status,
            options: options,
            isRequired: true,
            sortOrder: 0
        )
    }
    
    static func priority() -> PropertyDefinition {
        PropertyDefinition(
            name: "Priority",
            type: .priority,
            options: SelectOption.priorities,
            sortOrder: 1
        )
    }
    
    static func dueDate() -> PropertyDefinition {
        PropertyDefinition(
            name: "Due Date",
            type: .date,
            sortOrder: 2
        )
    }
    
    static func assignee() -> PropertyDefinition {
        PropertyDefinition(
            name: "Assignee",
            type: .person,
            sortOrder: 3
        )
    }
    
    static func relation(name: String, targetDatabaseId: UUID, isTwoWay: Bool = false) -> PropertyDefinition {
        PropertyDefinition(
            name: name,
            type: .relation,
            relationConfig: RelationConfig(targetDatabaseId: targetDatabaseId, isTwoWay: isTwoWay),
            sortOrder: 10
        )
    }
    
    static func rollup(name: String, relationPropertyId: UUID, targetPropertyId: UUID, calculation: RollupConfig.RollupCalculation) -> PropertyDefinition {
        PropertyDefinition(
            name: name,
            type: .rollup,
            rollupConfig: RollupConfig(
                relationPropertyId: relationPropertyId,
                targetPropertyId: targetPropertyId,
                calculation: calculation
            ),
            sortOrder: 11
        )
    }
    
    static func createdTime() -> PropertyDefinition {
        PropertyDefinition(
            name: "Created",
            type: .createdTime,
            isHidden: false,
            sortOrder: 98
        )
    }
    
    static func lastEdited() -> PropertyDefinition {
        PropertyDefinition(
            name: "Last edited",
            type: .lastEdited,
            isHidden: false,
            sortOrder: 99
        )
    }
}

// MARK: - Select Option

/// An option for select/multi-select properties
struct SelectOption: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: String
    var icon: String?
    var sortOrder: Int
    
    init(
        id: UUID = UUID(),
        name: String,
        color: String,
        icon: String? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.sortOrder = sortOrder
    }
    
    // MARK: - Default Options
    
    static let defaultStatuses: [SelectOption] = [
        SelectOption(name: "Todo", color: "#6B7280", icon: "circle", sortOrder: 0),
        SelectOption(name: "In Progress", color: "#3B82F6", icon: "arrow.right.circle.fill", sortOrder: 1),
        SelectOption(name: "In Review", color: "#F59E0B", icon: "eye.circle.fill", sortOrder: 2),
        SelectOption(name: "Done", color: "#10B981", icon: "checkmark.circle.fill", sortOrder: 3)
    ]
    
    static let priorities: [SelectOption] = [
        SelectOption(name: "Low", color: "#6B7280", icon: "arrow.down", sortOrder: 0),
        SelectOption(name: "Medium", color: "#F59E0B", icon: "minus", sortOrder: 1),
        SelectOption(name: "High", color: "#EF4444", icon: "arrow.up", sortOrder: 2),
        SelectOption(name: "Urgent", color: "#DC2626", icon: "exclamationmark.triangle.fill", sortOrder: 3)
    ]
}
