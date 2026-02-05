import Foundation

// MARK: - Session Label Model

/// A colored label/tag for categorizing recording sessions
/// Sessions can have multiple labels assigned
struct SessionLabel: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var color: String            // Hex color
    var icon: String?            // Optional SF Symbol
    let createdAt: Date
    var sortOrder: Int

    // MARK: - Initializers

    init(
        id: UUID = UUID(),
        name: String,
        color: String,
        icon: String? = nil,
        createdAt: Date = Date(),
        sortOrder: Int = 100
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    // MARK: - Preset Colors

    static let presetColors: [String] = [
        "#EF4444",  // Red
        "#F97316",  // Orange
        "#F59E0B",  // Amber
        "#EAB308",  // Yellow
        "#84CC16",  // Lime
        "#10B981",  // Green
        "#14B8A6",  // Teal
        "#06B6D4",  // Cyan
        "#3B82F6",  // Blue
        "#6366F1",  // Indigo
        "#8B5CF6",  // Purple
        "#A855F7",  // Violet
        "#EC4899",  // Pink
        "#F43F5E",  // Rose
        "#6B7280",  // Gray
        "#78716C",  // Stone
    ]

    // MARK: - Default Labels

    /// Create default starter labels
    static var defaultLabels: [SessionLabel] {
        [
            SessionLabel(name: "Important", color: "#EF4444", icon: "exclamationmark.circle.fill", sortOrder: 1),
            SessionLabel(name: "Review", color: "#F59E0B", icon: "eye.fill", sortOrder: 2),
            SessionLabel(name: "Follow-up", color: "#3B82F6", icon: "arrow.uturn.forward.circle.fill", sortOrder: 3),
            SessionLabel(name: "Archive", color: "#6B7280", icon: "archivebox.fill", sortOrder: 4),
        ]
    }

    // MARK: - Preset Icons

    static let presetIcons: [String] = [
        "circle.fill",
        "star.fill",
        "heart.fill",
        "flag.fill",
        "bookmark.fill",
        "tag.fill",
        "exclamationmark.circle.fill",
        "checkmark.circle.fill",
        "eye.fill",
        "arrow.uturn.forward.circle.fill",
        "clock.fill",
        "calendar",
        "person.fill",
        "briefcase.fill",
        "lightbulb.fill",
        "archivebox.fill",
    ]
}

// MARK: - Label Helpers

extension Array where Element == SessionLabel {
    /// Sort labels by sort order
    var sorted: [SessionLabel] {
        self.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Find label by ID
    func label(withID id: UUID) -> SessionLabel? {
        first { $0.id == id }
    }

    /// Find labels by IDs
    func labels(withIDs ids: [UUID]) -> [SessionLabel] {
        let idSet = Set(ids)
        return filter { idSet.contains($0.id) }
    }
}
