import Foundation
import Combine

// MARK: - Template Service

/// Service for managing templates - saving, loading, and applying
@MainActor
class TemplateService: ObservableObject {
    static let shared = TemplateService()
    
    @Published var customTemplates: [Template] = []
    @Published var recentTemplates: [UUID] = []
    @Published var favoriteTemplates: Set<UUID> = []
    
    private let storageKey = "workspace_custom_templates"
    private let recentsKey = "workspace_recent_templates"
    private let favoritesKey = "workspace_favorite_templates"
    private let maxRecents = 10
    
    private init() {
        loadCustomTemplates()
        loadRecents()
        loadFavorites()
    }
    
    // MARK: - All Templates
    
    var allTemplates: [Template] {
        Template.allBuiltIn + customTemplates
    }
    
    func templates(for category: TemplateCategory) -> [Template] {
        allTemplates.filter { $0.category == category }
    }
    
    func templates(for type: TemplateType) -> [Template] {
        allTemplates.filter { $0.templateType == type }
    }
    
    func searchTemplates(query: String) -> [Template] {
        let normalized = query.lowercased()
        return allTemplates.filter { template in
            template.name.lowercased().contains(normalized) ||
            template.description.lowercased().contains(normalized) ||
            template.tags.contains { $0.lowercased().contains(normalized) }
        }
    }
    
    // MARK: - Recent & Favorites
    
    func getRecentTemplates() -> [Template] {
        recentTemplates.compactMap { id in
            allTemplates.first { $0.id == id }
        }
    }
    
    func getFavoriteTemplates() -> [Template] {
        allTemplates.filter { favoriteTemplates.contains($0.id) }
    }
    
    func recordUsage(_ template: Template) {
        // Update recents
        recentTemplates.removeAll { $0 == template.id }
        recentTemplates.insert(template.id, at: 0)
        if recentTemplates.count > maxRecents {
            recentTemplates = Array(recentTemplates.prefix(maxRecents))
        }
        saveRecents()
        
        // Update usage count for custom templates
        if let index = customTemplates.firstIndex(where: { $0.id == template.id }) {
            customTemplates[index].usageCount += 1
            customTemplates[index].updatedAt = Date()
            saveCustomTemplates()
        }
    }
    
    func toggleFavorite(_ template: Template) {
        if favoriteTemplates.contains(template.id) {
            favoriteTemplates.remove(template.id)
        } else {
            favoriteTemplates.insert(template.id)
        }
        saveFavorites()
    }
    
    func isFavorite(_ template: Template) -> Bool {
        favoriteTemplates.contains(template.id)
    }
    
    // MARK: - Custom Templates CRUD
    
    func createTemplate(
        from item: WorkspaceItem,
        name: String,
        description: String = "",
        category: TemplateCategory = .custom,
        icon: String? = nil
    ) -> Template {
        let template = Template(
            name: name,
            description: description,
            icon: icon ?? item.icon,
            category: category,
            templateType: item.itemType == .database ? .database : .page,
            blocks: item.blocks,
            properties: item.properties,
            isBuiltIn: false,
            tags: []
        )
        
        customTemplates.append(template)
        saveCustomTemplates()
        
        return template
    }
    
    func createTemplate(
        from database: Database,
        name: String,
        description: String = "",
        category: TemplateCategory = .custom,
        icon: String? = nil
    ) -> Template {
        let template = Template(
            name: name,
            description: description,
            icon: icon ?? database.icon,
            category: category,
            templateType: .database,
            blocks: [],
            properties: [:],
            propertyDefinitions: database.properties,
            isBuiltIn: false,
            tags: []
        )
        
        customTemplates.append(template)
        saveCustomTemplates()
        
        return template
    }
    
    func updateTemplate(_ template: Template) {
        if let index = customTemplates.firstIndex(where: { $0.id == template.id }) {
            var updated = template
            updated.updatedAt = Date()
            customTemplates[index] = updated
            saveCustomTemplates()
        }
    }
    
    func deleteTemplate(_ template: Template) {
        guard !template.isBuiltIn else { return }
        customTemplates.removeAll { $0.id == template.id }
        recentTemplates.removeAll { $0 == template.id }
        favoriteTemplates.remove(template.id)
        saveCustomTemplates()
        saveRecents()
        saveFavorites()
    }
    
    func duplicateTemplate(_ template: Template) -> Template {
        var duplicate = template
        duplicate = Template(
            name: "\(template.name) (Copy)",
            description: template.description,
            icon: template.icon,
            category: .custom,
            templateType: template.templateType,
            blocks: template.blocks.map { $0.duplicated() },
            properties: template.properties,
            propertyDefinitions: template.propertyDefinitions,
            isBuiltIn: false,
            tags: template.tags
        )
        
        customTemplates.append(duplicate)
        saveCustomTemplates()
        
        return duplicate
    }
    
    // MARK: - Apply Template
    
    func applyTemplate(_ template: Template, title: String? = nil, parentID: UUID? = nil, workspaceID: UUID? = nil) -> WorkspaceItem {
        recordUsage(template)
        return template.createItem(title: title, parentID: parentID, workspaceID: workspaceID)
    }
    
    func applyDatabaseTemplate(_ template: Template, name: String? = nil, parentID: UUID? = nil) -> Database? {
        recordUsage(template)
        return template.createDatabase(name: name, parentID: parentID)
    }
    
    // MARK: - Smart Duplicate
    
    /// Creates a duplicate of an item with smart date handling
    func smartDuplicate(_ item: WorkspaceItem, incrementDate: Bool = true) -> WorkspaceItem {
        var duplicate = item.duplicated()
        
        // Smart title handling
        duplicate.title = smartIncrementTitle(item.title)
        
        // Smart date handling in properties
        if incrementDate {
            for (key, value) in duplicate.properties {
                if case .date(let date) = value {
                    // Increment date by same interval as detected pattern
                    let newDate = smartIncrementDate(date)
                    duplicate.properties[key] = .date(newDate)
                }
            }
        }
        
        return duplicate
    }
    
    private func smartIncrementTitle(_ title: String) -> String {
        // Check for date patterns in title
        let datePatterns = [
            ("\\d{4}-\\d{2}-\\d{2}", "yyyy-MM-dd"),        // 2024-01-15
            ("\\d{2}/\\d{2}/\\d{4}", "MM/dd/yyyy"),        // 01/15/2024
            ("\\d{2}/\\d{2}/\\d{2}", "MM/dd/yy"),          // 01/15/24
            ("Week \\d+", nil),                             // Week 3
            ("Day \\d+", nil),                              // Day 5
        ]
        
        for (pattern, format) in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
               let range = Range(match.range, in: title) {
                
                let matched = String(title[range])
                
                if let format = format {
                    // Date format - increment by 1 day
                    let formatter = DateFormatter()
                    formatter.dateFormat = format
                    if let date = formatter.date(from: matched),
                       let newDate = Calendar.current.date(byAdding: .day, value: 1, to: date) {
                        let newDateString = formatter.string(from: newDate)
                        return title.replacingCharacters(in: range, with: newDateString)
                    }
                } else if matched.hasPrefix("Week "), let num = Int(matched.dropFirst(5)) {
                    return title.replacingCharacters(in: range, with: "Week \(num + 1)")
                } else if matched.hasPrefix("Day "), let num = Int(matched.dropFirst(4)) {
                    return title.replacingCharacters(in: range, with: "Day \(num + 1)")
                }
            }
        }
        
        // Check for trailing numbers
        if let regex = try? NSRegularExpression(pattern: "\\s*\\d+$"),
           let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
           let range = Range(match.range, in: title),
           let number = Int(title[range].trimmingCharacters(in: .whitespaces)) {
            return title.replacingCharacters(in: range, with: " \(number + 1)")
        }
        
        // Default: add (Copy)
        return "\(title) (Copy)"
    }
    
    private func smartIncrementDate(_ date: Date) -> Date {
        // Default: add 1 day
        return Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
    }
    
    // MARK: - Persistence
    
    private func saveCustomTemplates() {
        if let data = try? JSONEncoder().encode(customTemplates) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    private func loadCustomTemplates() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let templates = try? JSONDecoder().decode([Template].self, from: data) {
            customTemplates = templates
        }
    }
    
    private func saveRecents() {
        let strings = recentTemplates.map { $0.uuidString }
        UserDefaults.standard.set(strings, forKey: recentsKey)
    }
    
    private func loadRecents() {
        if let strings = UserDefaults.standard.array(forKey: recentsKey) as? [String] {
            recentTemplates = strings.compactMap { UUID(uuidString: $0) }
        }
    }
    
    private func saveFavorites() {
        let strings = favoriteTemplates.map { $0.uuidString }
        UserDefaults.standard.set(strings, forKey: favoritesKey)
    }
    
    private func loadFavorites() {
        if let strings = UserDefaults.standard.array(forKey: favoritesKey) as? [String] {
            favoriteTemplates = Set(strings.compactMap { UUID(uuidString: $0) })
        }
    }
}
