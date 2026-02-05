import Foundation

// MARK: - Page Comment

struct PageComment: Identifiable, Codable, Hashable {
    let id: UUID
    var author: String?
    var content: String
    let createdAt: Date

    init(id: UUID = UUID(), author: String? = nil, content: String, createdAt: Date = Date()) {
        self.id = id
        self.author = author
        self.content = content
        self.createdAt = createdAt
    }

    var displayAuthor: String {
        author?.isEmpty == false ? author! : "You"
    }
}
