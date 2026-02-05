import Foundation

// MARK: - Block Types

/// Types of content blocks (like Notion blocks)
enum BlockType: String, Codable, CaseIterable {
    case paragraph = "paragraph"
    case heading1 = "heading_1"
    case heading2 = "heading_2"
    case heading3 = "heading_3"
    case bulletList = "bulleted_list"
    case numberedList = "numbered_list"
    case todo = "to_do"
    case toggle = "toggle"
    case quote = "quote"
    case callout = "callout"
    case divider = "divider"
    case code = "code"
    case image = "image"
    case audio = "audio"
    case video = "video"
    case file = "file"
    case bookmark = "bookmark"
    case embed = "embed"
    case sessionEmbed = "session_embed"     // Embed a transcribed session
    case databaseEmbed = "database_embed"   // Embed a database view
    case pageLink = "page_link"             // Link to another page
    case table = "table"
    case tableRow = "table_row"
    case columnList = "column_list"
    case column = "column"
    case syncedBlock = "synced_block"
    case meetingAgenda = "meeting_agenda"
    case meetingNotes = "meeting_notes"
    case meetingDecisions = "meeting_decisions"
    case meetingActionItems = "meeting_action_items"
    case meetingNextSteps = "meeting_next_steps"
    case meetingAttendees = "meeting_attendees"
    
    var icon: String {
        switch self {
        case .paragraph: return "text.alignleft"
        case .heading1: return "textformat.size.larger"
        case .heading2: return "textformat.size"
        case .heading3: return "textformat.size.smaller"
        case .bulletList: return "list.bullet"
        case .numberedList: return "list.number"
        case .todo: return "checkmark.square"
        case .toggle: return "chevron.right"
        case .quote: return "text.quote"
        case .callout: return "exclamationmark.bubble"
        case .divider: return "minus"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "play.rectangle"
        case .file: return "doc"
        case .bookmark: return "bookmark"
        case .embed: return "link"
        case .sessionEmbed: return "waveform.circle"
        case .databaseEmbed: return "rectangle.split.3x1"
        case .pageLink: return "link"
        case .table: return "tablecells"
        case .tableRow: return "rectangle.split.1x2"
        case .columnList: return "rectangle.split.2x1"
        case .column: return "rectangle"
        case .syncedBlock: return "arrow.triangle.2.circlepath"
        case .meetingAgenda: return "list.bullet.rectangle"
        case .meetingNotes: return "note.text"
        case .meetingDecisions: return "checkmark.seal"
        case .meetingActionItems: return "checkmark.circle"
        case .meetingNextSteps: return "arrow.forward.circle"
        case .meetingAttendees: return "person.2"
        }
    }
    
    var displayName: String {
        switch self {
        case .paragraph: return "Text"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .bulletList: return "Bulleted List"
        case .numberedList: return "Numbered List"
        case .todo: return "To-do"
        case .toggle: return "Toggle"
        case .quote: return "Quote"
        case .callout: return "Callout"
        case .divider: return "Divider"
        case .code: return "Code"
        case .image: return "Image"
        case .audio: return "Audio"
        case .video: return "Video"
        case .file: return "File"
        case .bookmark: return "Bookmark"
        case .embed: return "Embed"
        case .sessionEmbed: return "Session"
        case .databaseEmbed: return "Database"
        case .pageLink: return "Page Link"
        case .table: return "Table"
        case .tableRow: return "Table Row"
        case .columnList: return "Columns"
        case .column: return "Column"
        case .syncedBlock: return "Synced Block"
        case .meetingAgenda: return "Agenda"
        case .meetingNotes: return "Notes"
        case .meetingDecisions: return "Decisions"
        case .meetingActionItems: return "Action Items"
        case .meetingNextSteps: return "Next Steps"
        case .meetingAttendees: return "Attendees"
        }
    }
}

// MARK: - Block

/// A content block (like Notion blocks)
struct Block: Identifiable, Codable, Hashable {
    let id: UUID
    var type: BlockType
    var content: String
    var richTextData: Data?
    var checked: Bool?              // For todo blocks
    var language: String?           // For code blocks
    var url: String?                // For media/embed blocks
    var icon: String?               // For callout blocks
    var color: String?              // For callout/background color
    var children: [Block]           // For nested blocks (toggle, etc.)
    var isExpanded: Bool            // For toggle blocks
    var sessionID: UUID?            // For session embed blocks
    var metadata: [String: String]  // Additional metadata
    
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        type: BlockType = .paragraph,
        content: String = "",
        richTextData: Data? = nil,
        checked: Bool? = nil,
        language: String? = nil,
        url: String? = nil,
        icon: String? = nil,
        color: String? = nil,
        children: [Block] = [],
        isExpanded: Bool = true,
        sessionID: UUID? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.richTextData = richTextData
        self.checked = checked
        self.language = language
        self.url = url
        self.icon = icon
        self.color = color
        self.children = children
        self.isExpanded = isExpanded
        self.sessionID = sessionID
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Factory Methods
    
    static func paragraph(_ content: String = "") -> Block {
        Block(type: .paragraph, content: content)
    }
    
    static func heading1(_ content: String) -> Block {
        Block(type: .heading1, content: content)
    }
    
    static func heading2(_ content: String) -> Block {
        Block(type: .heading2, content: content)
    }
    
    static func heading3(_ content: String) -> Block {
        Block(type: .heading3, content: content)
    }
    
    static func bullet(_ content: String) -> Block {
        Block(type: .bulletList, content: content)
    }
    
    static func numbered(_ content: String) -> Block {
        Block(type: .numberedList, content: content)
    }
    
    static func todo(_ content: String, checked: Bool = false) -> Block {
        Block(type: .todo, content: content, checked: checked)
    }
    
    static func quote(_ content: String) -> Block {
        Block(type: .quote, content: content)
    }
    
    static func callout(_ content: String, icon: String = "💡", color: String = "#FEF3C7") -> Block {
        Block(type: .callout, content: content, icon: icon, color: color)
    }
    
    static func code(_ content: String, language: String = "swift") -> Block {
        Block(type: .code, content: content, language: language)
    }
    
    static func divider() -> Block {
        Block(type: .divider)
    }
    
    static func toggle(_ content: String, children: [Block] = []) -> Block {
        Block(type: .toggle, content: content, children: children)
    }
    
    static func sessionEmbed(_ sessionID: UUID, title: String = "") -> Block {
        Block(type: .sessionEmbed, content: title, sessionID: sessionID)
    }

    static func meetingAgenda(_ content: String = "") -> Block {
        Block(type: .meetingAgenda, content: content)
    }

    static func meetingNotes(_ content: String = "") -> Block {
        Block(type: .meetingNotes, content: content)
    }

    static func meetingDecisions(_ content: String = "") -> Block {
        Block(type: .meetingDecisions, content: content)
    }

    static func meetingActionItems(_ content: String = "") -> Block {
        Block(type: .meetingActionItems, content: content)
    }

    static func meetingNextSteps(_ content: String = "") -> Block {
        Block(type: .meetingNextSteps, content: content)
    }

    static func meetingAttendees(_ content: String = "") -> Block {
        Block(type: .meetingAttendees, content: content)
    }
    
    static func image(_ url: String, caption: String = "") -> Block {
        Block(type: .image, content: caption, url: url)
    }
    
    // MARK: - Computed Properties for UI Bindings
    
    /// Check state for todo blocks (non-optional for UI binding)
    var isChecked: Bool {
        get { checked ?? false }
        set { checked = newValue }
    }
    
    /// Icon string (non-optional for UI binding)
    var iconString: String {
        get { icon ?? "" }
        set { icon = newValue.isEmpty ? nil : newValue }
    }
    
    /// Color string (non-optional for UI binding)
    var colorString: String {
        get { color ?? "" }
        set { color = newValue.isEmpty ? nil : newValue }
    }
    
    // MARK: - Helpers
    
    var isEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && children.isEmpty
    }

    // MARK: - Synced Blocks

    var syncedGroupID: String? {
        get { metadata["syncedGroupID"] }
        set { metadata["syncedGroupID"] = newValue }
    }

    var isSyncedSource: Bool {
        get { metadata["syncedSource"] == "true" }
        set { metadata["syncedSource"] = newValue ? "true" : "false" }
    }

    var isSynced: Bool {
        syncedGroupID != nil
    }
    
    var plainText: String {
        var text = content
        for child in children {
            text += "\n" + child.plainText
        }
        return text
    }
    
    mutating func toggleCheck() {
        if type == .todo {
            checked = !(checked ?? false)
            updatedAt = Date()
        }
    }
    
    mutating func toggleExpand() {
        isExpanded.toggle()
        updatedAt = Date()
    }

    mutating func applySyncedContent(from source: Block) {
        guard type == .syncedBlock else { return }
        content = source.content
        richTextData = source.richTextData
        checked = source.checked
        language = source.language
        url = source.url
        icon = source.icon
        color = source.color
        children = source.children.map { $0.duplicated() }
        updatedAt = Date()
    }

    // MARK: - Duplication

    func duplicated() -> Block {
        Block(
            id: UUID(),
            type: type,
            content: content,
            richTextData: richTextData,
            checked: checked,
            language: language,
            url: url,
            icon: icon,
            color: color,
            children: children.map { $0.duplicated() },
            isExpanded: isExpanded,
            sessionID: sessionID,
            metadata: metadata,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Block Extensions

extension Array where Element == Block {
    /// Get all text content as a single string
    var fullText: String {
        map { $0.plainText }.joined(separator: "\n")
    }
    
    /// Count of all blocks including nested
    var totalCount: Int {
        reduce(0) { $0 + 1 + $1.children.totalCount }
    }
    
    /// Find block by ID (including nested)
    func find(id: UUID) -> Block? {
        for block in self {
            if block.id == id {
                return block
            }
            if let found = block.children.find(id: id) {
                return found
            }
        }
        return nil
    }
}
