import Foundation

struct Snippet: Identifiable, Codable, Equatable {
    let id: UUID
    var trigger: String
    var content: String
    var isEnabled: Bool = true

    init(id: UUID = UUID(), trigger: String, content: String, isEnabled: Bool = true) {
        self.id = id
        self.trigger = trigger
        self.content = content
        self.isEnabled = isEnabled
    }

    var preview: String {
        let maxLength = 50
        if content.count <= maxLength {
            return content
        }
        return String(content.prefix(maxLength)) + "..."
    }
}
