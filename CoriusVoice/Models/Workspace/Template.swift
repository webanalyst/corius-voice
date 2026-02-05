import Foundation

// MARK: - Template

/// A reusable template for creating pages or database items
struct Template: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var icon: String
    var category: TemplateCategory
    var templateType: TemplateType
    
    // Content template
    var blocks: [Block]
    var properties: [String: PropertyValue]
    var propertyDefinitions: [PropertyDefinition]?  // For database templates
    
    // Metadata
    var isBuiltIn: Bool
    var usageCount: Int
    let createdAt: Date
    var updatedAt: Date
    
    // Preview
    var previewImageURL: String?
    var tags: [String]
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        icon: String = "doc.text",
        category: TemplateCategory = .personal,
        templateType: TemplateType = .page,
        blocks: [Block] = [],
        properties: [String: PropertyValue] = [:],
        propertyDefinitions: [PropertyDefinition]? = nil,
        isBuiltIn: Bool = false,
        usageCount: Int = 0,
        previewImageURL: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.category = category
        self.templateType = templateType
        self.blocks = blocks
        self.properties = properties
        self.propertyDefinitions = propertyDefinitions
        self.isBuiltIn = isBuiltIn
        self.usageCount = usageCount
        self.createdAt = Date()
        self.updatedAt = Date()
        self.previewImageURL = previewImageURL
        self.tags = tags
    }
    
    // MARK: - Apply Template
    
    /// Creates a new WorkspaceItem from this template
    func createItem(title: String? = nil, parentID: UUID? = nil, workspaceID: UUID? = nil) -> WorkspaceItem {
        WorkspaceItem(
            title: title ?? name,
            icon: icon,
            parentID: parentID,
            workspaceID: workspaceID,
            itemType: templateType == .database ? .database : .page,
            blocks: blocks.map { $0.duplicated() },
            properties: properties
        )
    }
    
    /// Creates a Database from this template (for database templates)
    func createDatabase(name: String? = nil, parentID: UUID? = nil) -> Database? {
        guard templateType == .database, let definitions = propertyDefinitions else { return nil }
        
        return Database(
            name: name ?? self.name,
            icon: icon,
            parentID: parentID,
            properties: definitions
        )
    }
}

// MARK: - Template Type

enum TemplateType: String, Codable, CaseIterable {
    case page = "page"
    case database = "database"
    case task = "task"
    case meeting = "meeting"
    case project = "project"
    
    var displayName: String {
        switch self {
        case .page: return "Page"
        case .database: return "Database"
        case .task: return "Task"
        case .meeting: return "Meeting Notes"
        case .project: return "Project"
        }
    }
    
    var icon: String {
        switch self {
        case .page: return "doc.text"
        case .database: return "tablecells"
        case .task: return "checkmark.square"
        case .meeting: return "person.3"
        case .project: return "folder"
        }
    }
}

// MARK: - Template Category

enum TemplateCategory: String, Codable, CaseIterable {
    case personal = "personal"
    case work = "work"
    case education = "education"
    case design = "design"
    case engineering = "engineering"
    case marketing = "marketing"
    case hr = "hr"
    case sales = "sales"
    case support = "support"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .personal: return "Personal"
        case .work: return "Work"
        case .education: return "Education"
        case .design: return "Design"
        case .engineering: return "Engineering"
        case .marketing: return "Marketing"
        case .hr: return "HR"
        case .sales: return "Sales"
        case .support: return "Support"
        case .custom: return "My Templates"
        }
    }
    
    var icon: String {
        switch self {
        case .personal: return "person"
        case .work: return "briefcase"
        case .education: return "graduationcap"
        case .design: return "paintbrush"
        case .engineering: return "hammer"
        case .marketing: return "megaphone"
        case .hr: return "person.2"
        case .sales: return "chart.line.uptrend.xyaxis"
        case .support: return "headphones"
        case .custom: return "star"
        }
    }
}

// MARK: - Built-in Templates

extension Template {
    
    // MARK: - Page Templates
    
    static let blankPage = Template(
        name: "Blank Page",
        description: "Start with a clean slate",
        icon: "doc",
        category: .personal,
        templateType: .page,
        isBuiltIn: true,
        tags: ["basic", "empty"]
    )
    
    static let meetingNotes = Template(
        name: "Meeting Notes",
        description: "Capture meeting discussions and action items",
        icon: "person.3",
        category: .work,
        templateType: .meeting,
        blocks: [
            Block(type: .heading1, content: "Meeting Notes"),
            Block(type: .meetingAttendees, content: ""),
            Block(type: .meetingAgenda, content: ""),
            Block(type: .meetingNotes, content: ""),
            Block(type: .meetingDecisions, content: ""),
            Block(type: .meetingActionItems, content: ""),
            Block(type: .meetingNextSteps, content: "")
        ],
        isBuiltIn: true,
        tags: ["meeting", "notes", "work"]
    )

    static let oneOnOneMeeting = Template(
        name: "1:1 Meeting",
        description: "Structured check-in for one-on-ones",
        icon: "person.2",
        category: .work,
        templateType: .meeting,
        blocks: [
            Block(type: .heading1, content: "1:1 Meeting"),
            Block(type: .meetingAttendees, content: ""),
            Block(type: .meetingAgenda, content: ""),
            Block(type: .meetingNotes, content: ""),
            Block(type: .meetingActionItems, content: ""),
            Block(type: .meetingNextSteps, content: "")
        ],
        isBuiltIn: true,
        tags: ["meeting", "1:1", "work"]
    )

    static let planningMeeting = Template(
        name: "Planning Meeting",
        description: "Plan goals, deliverables, and next steps",
        icon: "calendar.badge.clock",
        category: .work,
        templateType: .meeting,
        blocks: [
            Block(type: .heading1, content: "Planning Meeting"),
            Block(type: .meetingAgenda, content: ""),
            Block(type: .meetingNotes, content: ""),
            Block(type: .meetingDecisions, content: ""),
            Block(type: .meetingActionItems, content: ""),
            Block(type: .meetingNextSteps, content: "")
        ],
        isBuiltIn: true,
        tags: ["meeting", "planning", "work"]
    )

    static let retroMeeting = Template(
        name: "Retro Meeting",
        description: "Capture wins, improvements, and actions",
        icon: "arrow.triangle.2.circlepath",
        category: .work,
        templateType: .meeting,
        blocks: [
            Block(type: .heading1, content: "Retro Meeting"),
            Block(type: .meetingNotes, content: ""),
            Block(type: .meetingDecisions, content: ""),
            Block(type: .meetingActionItems, content: ""),
            Block(type: .meetingNextSteps, content: "")
        ],
        isBuiltIn: true,
        tags: ["meeting", "retro", "work"]
    )
    
    static let projectBrief = Template(
        name: "Project Brief",
        description: "Define project scope, goals, and timeline",
        icon: "folder",
        category: .work,
        templateType: .project,
        blocks: [
            Block(type: .heading1, content: "Project Brief"),
            Block(type: .callout, content: "📌 Quick summary of the project goes here"),
            Block(type: .paragraph, content: ""),
            Block(type: .heading2, content: "🎯 Objectives"),
            Block(type: .bulletList, content: "Primary goal: "),
            Block(type: .bulletList, content: "Secondary goals: "),
            Block(type: .paragraph, content: ""),
            Block(type: .heading2, content: "📊 Scope"),
            Block(type: .toggle, content: "In Scope"),
            Block(type: .toggle, content: "Out of Scope"),
            Block(type: .paragraph, content: ""),
            Block(type: .heading2, content: "👥 Team"),
            Block(type: .bulletList, content: "Project Lead: "),
            Block(type: .bulletList, content: "Team Members: "),
            Block(type: .paragraph, content: ""),
            Block(type: .heading2, content: "📅 Timeline"),
            Block(type: .bulletList, content: "Start Date: "),
            Block(type: .bulletList, content: "End Date: "),
            Block(type: .bulletList, content: "Milestones: "),
            Block(type: .paragraph, content: ""),
            Block(type: .heading2, content: "📈 Success Metrics"),
            Block(type: .numberedList, content: ""),
            Block(type: .paragraph, content: ""),
            Block(type: .heading2, content: "⚠️ Risks & Dependencies"),
            Block(type: .paragraph, content: "")
        ],
        isBuiltIn: true,
        tags: ["project", "planning", "work"]
    )
    
    static let weeklyReview = Template(
        name: "Weekly Review",
        description: "Reflect on your week and plan ahead",
        icon: "calendar",
        category: .personal,
        templateType: .page,
        blocks: [
            Block(type: .heading1, content: "Weekly Review"),
            Block(type: .paragraph, content: "Week of [Date]"),
            Block(type: .divider, content: ""),
            Block(type: .heading2, content: "✅ Accomplishments"),
            Block(type: .bulletList, content: ""),
            Block(type: .paragraph, content: ""),
            Block(type: .heading2, content: "🎓 Lessons Learned"),
            Block(type: .bulletList, content: ""),
            Block(type: .paragraph, content: ""),
            Block(type: .heading2, content: "😊 Gratitude"),
            Block(type: .bulletList, content: ""),
            Block(type: .paragraph, content: ""),
            Block(type: .heading2, content: "🎯 Goals for Next Week"),
            Block(type: .todo, content: ""),
            Block(type: .todo, content: ""),
            Block(type: .todo, content: ""),
            Block(type: .paragraph, content: ""),
            Block(type: .heading2, content: "💭 Notes & Thoughts"),
            Block(type: .paragraph, content: "")
        ],
        isBuiltIn: true,
        tags: ["weekly", "review", "personal", "planning"]
    )
    
    static let dailyJournal = Template(
        name: "Daily Journal",
        description: "Record your daily thoughts and activities",
        icon: "book",
        category: .personal,
        templateType: .page,
        blocks: [
            Block(type: .heading1, content: "Daily Journal"),
            Block(type: .paragraph, content: "[Date]"),
            Block(type: .divider, content: ""),
            Block(type: .heading2, content: "🌅 Morning"),
            Block(type: .paragraph, content: "How am I feeling today?"),
            Block(type: .paragraph, content: ""),
            Block(type: .heading3, content: "Today's Intentions"),
            Block(type: .todo, content: ""),
            Block(type: .paragraph, content: ""),
            Block(type: .heading2, content: "🌆 Evening"),
            Block(type: .paragraph, content: "What went well today?"),
            Block(type: .paragraph, content: ""),
            Block(type: .paragraph, content: "What could have been better?"),
            Block(type: .paragraph, content: ""),
            Block(type: .heading3, content: "Gratitude"),
            Block(type: .bulletList, content: ""),
            Block(type: .bulletList, content: ""),
            Block(type: .bulletList, content: "")
        ],
        isBuiltIn: true,
        tags: ["daily", "journal", "personal"]
    )
    
    // MARK: - Database Templates
    
    static let taskTracker = Template(
        name: "Task Tracker",
        description: "Track tasks with status, priority, and due dates",
        icon: "checkmark.square",
        category: .work,
        templateType: .database,
        propertyDefinitions: [
            .status(),
            .priority(),
            .dueDate(),
            .assignee(),
            PropertyDefinition(name: "Tags", type: .multiSelect, sortOrder: 5)
        ],
        isBuiltIn: true,
        tags: ["tasks", "kanban", "productivity"]
    )
    
    static let contentCalendar = Template(
        name: "Content Calendar",
        description: "Plan and track content creation",
        icon: "calendar.badge.plus",
        category: .marketing,
        templateType: .database,
        propertyDefinitions: [
            PropertyDefinition(name: "Publish Date", type: .date, isRequired: true, sortOrder: 0),
            PropertyDefinition(name: "Status", type: .status, options: [
                SelectOption(name: "Idea", color: "#6B7280", sortOrder: 0),
                SelectOption(name: "Writing", color: "#3B82F6", sortOrder: 1),
                SelectOption(name: "Review", color: "#F59E0B", sortOrder: 2),
                SelectOption(name: "Scheduled", color: "#8B5CF6", sortOrder: 3),
                SelectOption(name: "Published", color: "#10B981", sortOrder: 4)
            ], sortOrder: 1),
            PropertyDefinition(name: "Platform", type: .select, options: [
                SelectOption(name: "Blog", color: "#3B82F6", sortOrder: 0),
                SelectOption(name: "Twitter", color: "#1DA1F2", sortOrder: 1),
                SelectOption(name: "LinkedIn", color: "#0A66C2", sortOrder: 2),
                SelectOption(name: "YouTube", color: "#FF0000", sortOrder: 3),
                SelectOption(name: "Newsletter", color: "#F59E0B", sortOrder: 4)
            ], sortOrder: 2),
            PropertyDefinition(name: "Author", type: .person, sortOrder: 3),
            PropertyDefinition(name: "Tags", type: .multiSelect, sortOrder: 4)
        ],
        isBuiltIn: true,
        tags: ["content", "calendar", "marketing"]
    )
    
    static let bugTracker = Template(
        name: "Bug Tracker",
        description: "Track and manage software bugs",
        icon: "ladybug",
        category: .engineering,
        templateType: .database,
        propertyDefinitions: [
            PropertyDefinition(name: "Status", type: .status, options: [
                SelectOption(name: "Open", color: "#EF4444", sortOrder: 0),
                SelectOption(name: "In Progress", color: "#3B82F6", sortOrder: 1),
                SelectOption(name: "In Review", color: "#F59E0B", sortOrder: 2),
                SelectOption(name: "Fixed", color: "#10B981", sortOrder: 3),
                SelectOption(name: "Closed", color: "#6B7280", sortOrder: 4)
            ], sortOrder: 0),
            PropertyDefinition(name: "Priority", type: .priority, options: [
                SelectOption(name: "Critical", color: "#DC2626", icon: "exclamationmark.3", sortOrder: 0),
                SelectOption(name: "High", color: "#EF4444", icon: "arrow.up", sortOrder: 1),
                SelectOption(name: "Medium", color: "#F59E0B", icon: "minus", sortOrder: 2),
                SelectOption(name: "Low", color: "#6B7280", icon: "arrow.down", sortOrder: 3)
            ], sortOrder: 1),
            PropertyDefinition(name: "Assignee", type: .person, sortOrder: 2),
            PropertyDefinition(name: "Reporter", type: .person, sortOrder: 3),
            PropertyDefinition(name: "Component", type: .select, sortOrder: 4),
            PropertyDefinition(name: "Version", type: .text, sortOrder: 5),
            .createdTime(),
            .lastEdited()
        ],
        isBuiltIn: true,
        tags: ["bugs", "engineering", "tracking"]
    )
    
    static let crmContacts = Template(
        name: "CRM Contacts",
        description: "Manage customer relationships",
        icon: "person.crop.rectangle.stack",
        category: .sales,
        templateType: .database,
        propertyDefinitions: [
            PropertyDefinition(name: "Company", type: .text, isRequired: true, sortOrder: 0),
            PropertyDefinition(name: "Email", type: .email, sortOrder: 1),
            PropertyDefinition(name: "Phone", type: .phone, sortOrder: 2),
            PropertyDefinition(name: "Status", type: .select, options: [
                SelectOption(name: "Lead", color: "#6B7280", sortOrder: 0),
                SelectOption(name: "Contacted", color: "#3B82F6", sortOrder: 1),
                SelectOption(name: "Qualified", color: "#F59E0B", sortOrder: 2),
                SelectOption(name: "Proposal", color: "#8B5CF6", sortOrder: 3),
                SelectOption(name: "Customer", color: "#10B981", sortOrder: 4),
                SelectOption(name: "Churned", color: "#EF4444", sortOrder: 5)
            ], sortOrder: 3),
            PropertyDefinition(name: "Deal Value", type: .number, sortOrder: 4),
            PropertyDefinition(name: "Last Contact", type: .date, sortOrder: 5),
            PropertyDefinition(name: "Owner", type: .person, sortOrder: 6),
            PropertyDefinition(name: "Notes", type: .text, sortOrder: 7)
        ],
        isBuiltIn: true,
        tags: ["crm", "contacts", "sales"]
    )
    
    // MARK: - All Built-in Templates
    
    static let allBuiltIn: [Template] = [
        // Pages
        .blankPage,
        .meetingNotes,
        .oneOnOneMeeting,
        .planningMeeting,
        .retroMeeting,
        .projectBrief,
        .weeklyReview,
        .dailyJournal,
        // Databases
        .taskTracker,
        .contentCalendar,
        .bugTracker,
        .crmContacts
    ]
}
