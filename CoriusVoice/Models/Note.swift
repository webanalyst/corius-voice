import Foundation

struct Note: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var content: String
    let createdAt: Date
    var updatedAt: Date
    var tags: [String] = []

    init(id: UUID = UUID(), title: String, content: String, createdAt: Date = Date(), updatedAt: Date = Date(), tags: [String] = []) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: updatedAt)
    }

    var preview: String {
        let maxLength = 100
        if content.count <= maxLength {
            return content
        }
        return String(content.prefix(maxLength)) + "..."
    }

    mutating func update(title: String? = nil, content: String? = nil, tags: [String]? = nil) {
        if let title = title {
            self.title = title
        }
        if let content = content {
            self.content = content
        }
        if let tags = tags {
            self.tags = tags
        }
        self.updatedAt = Date()
    }
}
