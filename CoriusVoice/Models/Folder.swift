import Foundation

// MARK: - Folder Model

/// Represents a folder for organizing recording sessions
/// Supports hierarchical structure with parent-child relationships
struct Folder: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var parentID: UUID?          // nil = root level folder
    var icon: String             // SF Symbol name
    var color: String?           // Hex color (optional)
    let isSystem: Bool           // true for INBOX (cannot be deleted/renamed)
    let createdAt: Date
    var sortOrder: Int

    // For AI classification
    var classificationKeywords: [String]
    var classificationDescription: String?

    // MARK: - System Folder IDs

    /// Fixed UUID for the INBOX folder (never changes)
    static let inboxID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    // MARK: - Default System Folders

    /// The default INBOX folder where new sessions are placed
    static var inbox: Folder {
        Folder(
            id: inboxID,
            name: "Inbox",
            parentID: nil,
            icon: "tray.fill",
            color: "#3B82F6",  // Blue
            isSystem: true,
            createdAt: Date(timeIntervalSince1970: 0),  // Always first
            sortOrder: 0,
            classificationKeywords: [],
            classificationDescription: "Default inbox for unclassified sessions"
        )
    }

    // MARK: - Initializers

    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        icon: String = "folder.fill",
        color: String? = nil,
        isSystem: Bool = false,
        createdAt: Date = Date(),
        sortOrder: Int = 100,
        classificationKeywords: [String] = [],
        classificationDescription: String? = nil
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.icon = icon
        self.color = color
        self.isSystem = isSystem
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.classificationKeywords = classificationKeywords
        self.classificationDescription = classificationDescription
    }

    // MARK: - Computed Properties

    /// Whether this folder is the INBOX
    var isInbox: Bool {
        id == Self.inboxID
    }

    /// Whether this folder is a root folder (no parent)
    var isRoot: Bool {
        parentID == nil
    }

    // MARK: - Preset Colors

    static let presetColors: [String] = [
        "#3B82F6",  // Blue
        "#10B981",  // Green
        "#F59E0B",  // Amber
        "#EF4444",  // Red
        "#8B5CF6",  // Purple
        "#EC4899",  // Pink
        "#06B6D4",  // Cyan
        "#F97316",  // Orange
        "#6366F1",  // Indigo
        "#84CC16",  // Lime
    ]

    // MARK: - Preset Icons

    static let presetIcons: [String] = [
        "folder.fill",
        "briefcase.fill",
        "building.2.fill",
        "person.3.fill",
        "lightbulb.fill",
        "book.fill",
        "graduationcap.fill",
        "heart.fill",
        "star.fill",
        "flag.fill",
        "tag.fill",
        "doc.text.fill",
        "calendar",
        "clock.fill",
        "checkmark.circle.fill",
        "archivebox.fill",
    ]
}

// MARK: - Folder Tree Helpers

extension Array where Element == Folder {
    /// Get children of a specific folder
    func children(of parentID: UUID?) -> [Folder] {
        self.filter { $0.parentID == parentID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Get all root folders
    var rootFolders: [Folder] {
        children(of: nil)
    }

    /// Get all descendants of a folder (recursive)
    func descendants(of folderID: UUID) -> [Folder] {
        var result: [Folder] = []
        let directChildren = children(of: folderID)

        for child in directChildren {
            result.append(child)
            result.append(contentsOf: descendants(of: child.id))
        }

        return result
    }

    /// Get the full path to a folder (list of parent names)
    func path(to folderID: UUID) -> [Folder] {
        var path: [Folder] = []
        var currentID: UUID? = folderID

        while let id = currentID, let folder = first(where: { $0.id == id }) {
            path.insert(folder, at: 0)
            currentID = folder.parentID
        }

        return path
    }

    /// Get depth level of a folder (0 = root)
    func depth(of folderID: UUID) -> Int {
        path(to: folderID).count - 1
    }

    /// Check if moving a folder would create a cycle
    func wouldCreateCycle(moving folderID: UUID, to newParentID: UUID?) -> Bool {
        guard let newParentID = newParentID else { return false }

        // Can't move to itself
        if folderID == newParentID { return true }

        // Can't move to any of its descendants
        let descendantIDs = Set(descendants(of: folderID).map { $0.id })
        return descendantIDs.contains(newParentID)
    }
}
