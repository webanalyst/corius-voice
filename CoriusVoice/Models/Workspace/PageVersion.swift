import Foundation

// MARK: - Page Version

struct PageVersion: Identifiable, Codable, Hashable {
    let id: UUID
    let pageID: UUID
    let title: String
    let icon: String
    let coverImageURL: String?
    let blocks: [Block]
    let properties: [String: PropertyValue]
    let createdAt: Date
    let note: String?

    init(page: WorkspaceItem, note: String? = nil) {
        self.id = UUID()
        self.pageID = page.id
        self.title = page.title
        self.icon = page.icon
        self.coverImageURL = page.coverImageURL
        self.blocks = page.blocks
        self.properties = page.properties
        self.createdAt = Date()
        self.note = note
    }
}
