import Foundation

// MARK: - Workspace Item Type

enum WorkspaceItemType: String, Codable, CaseIterable {
    case page = "page"              // Document/note with blocks
    case database = "database"      // Kanban, Table, List, Calendar
    case session = "session"        // Recording session (special type)
    case task = "task"              // Individual task item
}

// MARK: - Workspace Item Protocol

/// Base protocol for all workspace items (pages, databases, sessions, tasks)
protocol WorkspaceItemProtocol: Identifiable, Codable {
    var id: UUID { get }
    var title: String { get set }
    var icon: String { get set }
    var coverImageURL: String? { get set }
    var parentID: UUID? { get set }
    var workspaceID: UUID? { get set }
    var createdAt: Date { get }
    var updatedAt: Date { get set }
    var itemType: WorkspaceItemType { get }
    var isFavorite: Bool { get set }
    var isArchived: Bool { get set }
}

// MARK: - Workspace Item (Concrete Implementation)

/// A flexible workspace item that can represent pages, tasks, or database entries
struct WorkspaceItem: WorkspaceItemProtocol, Hashable {
    let id: UUID
    var title: String
    var icon: String
    var coverImageURL: String?
    var parentID: UUID?
    var workspaceID: UUID?         // Which database/workspace it belongs to
    let createdAt: Date
    var updatedAt: Date
    let itemType: WorkspaceItemType
    var isFavorite: Bool
    var isArchived: Bool
    
    // Content (for pages)
    var blocks: [Block]
    
    // Properties (for database items)
    var properties: [String: PropertyValue]
    
    // For sessions - reference to the actual session
    var sessionID: UUID?

    // Comments
    var comments: [PageComment]
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        icon: String = "doc.text",
        coverImageURL: String? = nil,
        parentID: UUID? = nil,
        workspaceID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        itemType: WorkspaceItemType = .page,
        isFavorite: Bool = false,
        isArchived: Bool = false,
        blocks: [Block] = [],
        properties: [String: PropertyValue] = [:],
        sessionID: UUID? = nil,
        comments: [PageComment] = []
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.coverImageURL = coverImageURL
        self.parentID = parentID
        self.workspaceID = workspaceID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.itemType = itemType
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.blocks = blocks
        self.properties = properties
        self.sessionID = sessionID
        self.comments = comments
    }
    
    // MARK: - Factory Methods
    
    /// Create a new page
    static func page(title: String = "Untitled", icon: String = "doc.text", parentID: UUID? = nil) -> WorkspaceItem {
        WorkspaceItem(
            title: title,
            icon: icon,
            parentID: parentID,
            itemType: .page
        )
    }
    
    /// Create a new task
    static func task(title: String, workspaceID: UUID, status: String = "todo") -> WorkspaceItem {
        var item = WorkspaceItem(
            title: title,
            icon: "circle",
            workspaceID: workspaceID,
            itemType: .task
        )
        item.properties["status"] = .select(status)
        return item
    }
    
    /// Create from a recording session
    static func fromSession(_ session: RecordingSession) -> WorkspaceItem {
        WorkspaceItem(
            id: session.id,
            title: session.displayTitle,
            icon: "waveform",
            createdAt: session.startDate,
            updatedAt: session.startDate,
            itemType: .session,
            sessionID: session.id
        )
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: WorkspaceItem, rhs: WorkspaceItem) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Helpers
    
    var displayTitle: String {
        title.isEmpty ? "Untitled" : title
    }
    
    var statusValue: String? {
        if case .select(let status) = properties["status"] {
            return status
        }
        return nil
    }
    
    mutating func setStatus(_ status: String) {
        properties["status"] = .select(status)
        updatedAt = Date()
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: updatedAt)
    }

    // MARK: - Duplication

    func duplicated(clearProperties: Bool = false) -> WorkspaceItem {
        let newTitle = title.isEmpty ? "Untitled (Copy)" : "\(title) (Copy)"
        let newBlocks = blocks.map { $0.duplicated() }
        let newProperties: [String: PropertyValue] = clearProperties 
            ? properties.mapValues { $0.cleared() }
            : properties
        
        return WorkspaceItem(
            id: UUID(),
            title: newTitle,
            icon: icon,
            coverImageURL: coverImageURL,
            parentID: parentID,
            workspaceID: workspaceID,
            createdAt: Date(),
            updatedAt: Date(),
            itemType: itemType,
            isFavorite: false,
            isArchived: false,
            blocks: newBlocks,
            properties: newProperties,
            sessionID: sessionID,
            comments: []
        )
    }
}

extension PropertyValue {
    func cleared() -> PropertyValue {
        switch self {
        case .text:
            return .text("")
        case .url:
            return .url("")
        case .email:
            return .email("")
        case .phone:
            return .phone("")
        case .number:
            return .number(0)
        case .select, .multiSelect, .relation, .relations, .person, .date:
            return .empty
        case .checkbox:
            return .checkbox(false)
        case .empty:
            return .empty
        }
    }
}

// MARK: - Workspace

/// A workspace container (like a Notion workspace)
struct Workspace: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var color: String?
    let createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
    
    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder.fill",
        color: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }
    
    // MARK: - Default Workspaces
    
    static let personalID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
    
    static var personal: Workspace {
        Workspace(
            id: personalID,
            name: "Personal",
            icon: "person.fill",
            color: "#3B82F6",
            sortOrder: 0
        )
    }
}
