import SwiftUI

// MARK: - Relation Property Editor

struct RelationPropertyEditor: View {
    @Binding var definition: PropertyDefinition
    let database: Database
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @State private var selectedDatabaseId: UUID?
    @State private var isTwoWay = false
    @State private var reverseName = ""
    
    private var databases: [Database] {
        storage.databases
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Target database selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Related to")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Database", selection: $selectedDatabaseId) {
                    Text("Select a database...").tag(nil as UUID?)
                    ForEach(databases) { db in
                        HStack {
                            Image(systemName: db.icon)
                            Text(db.name)
                        }
                        .tag(db.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
            }
            
            // Two-way relation toggle
            Toggle(isOn: $isTwoWay) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Two-way relation")
                        .font(.subheadline)
                    Text("Creates a linked property in the related database")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Reverse property name
            if isTwoWay {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reverse property name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Related items", text: $reverseName)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            Divider()
            
            // Info about the relation
            if let dbId = selectedDatabaseId, let db = databases.first(where: { $0.id == dbId }) {
                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Links to \(db.name)")
                            .font(.subheadline)
                        Text("Database relation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .onAppear {
            loadExisting()
        }
        .onChange(of: selectedDatabaseId) { _, newValue in
            updateConfig()
        }
        .onChange(of: isTwoWay) { _, _ in
            updateConfig()
        }
        .onChange(of: reverseName) { _, _ in
            updateConfig()
        }
    }
    
    private func loadExisting() {
        if let config = definition.relationConfig {
            selectedDatabaseId = config.targetDatabaseId
            isTwoWay = config.isTwoWay
            reverseName = config.reverseName ?? ""
        }
    }
    
    private func updateConfig() {
        guard let dbId = selectedDatabaseId else {
            definition.relationConfig = nil
            return
        }

        let resolvedReverseId: UUID?
        if isTwoWay {
            resolvedReverseId = ensureReverseProperty(targetDatabaseId: dbId)
        } else {
            resolvedReverseId = nil
        }

        definition.relationConfig = RelationConfig(
            targetDatabaseId: dbId,
            isTwoWay: isTwoWay,
            reversePropertyId: resolvedReverseId,
            reverseName: isTwoWay ? (reverseName.isEmpty ? "Related items" : reverseName) : nil
        )
    }

    private func ensureReverseProperty(targetDatabaseId: UUID) -> UUID? {
        guard var targetDatabase = storage.database(withID: targetDatabaseId) else { return nil }

        if let existingId = definition.relationConfig?.reversePropertyId,
           let index = targetDatabase.properties.firstIndex(where: { $0.id == existingId }) {
            targetDatabase.properties[index].relationConfig = RelationConfig(
                targetDatabaseId: database.id,
                isTwoWay: true,
                reversePropertyId: definition.id,
                reverseName: definition.name
            )
            storage.updateDatabase(targetDatabase)
            return existingId
        }

        if let index = targetDatabase.properties.firstIndex(where: { property in
            guard property.type == .relation,
                  let config = property.relationConfig else { return false }
            return config.targetDatabaseId == database.id && config.reversePropertyId == definition.id
        }) {
            targetDatabase.properties[index].relationConfig = RelationConfig(
                targetDatabaseId: database.id,
                isTwoWay: true,
                reversePropertyId: definition.id,
                reverseName: definition.name
            )
            storage.updateDatabase(targetDatabase)
            return targetDatabase.properties[index].id
        }

        var reverse = PropertyDefinition(
            name: reverseName.isEmpty ? "Related items" : reverseName,
            type: .relation,
            sortOrder: targetDatabase.properties.count
        )
        reverse.relationConfig = RelationConfig(
            targetDatabaseId: database.id,
            isTwoWay: true,
            reversePropertyId: definition.id,
            reverseName: definition.name
        )
        targetDatabase.properties.append(reverse)
        storage.updateDatabase(targetDatabase)
        return reverse.id
    }
}

// MARK: - Rollup Property Editor

struct RollupPropertyEditor: View {
    @Binding var definition: PropertyDefinition
    let database: Database
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    
    @State private var selectedRelationId: UUID?
    @State private var selectedPropertyId: UUID?
    @State private var selectedCalculation: RollupConfig.RollupCalculation = .countAll
    
    // Get relation properties from this database
    private var relationProperties: [PropertyDefinition] {
        database.properties.filter { $0.type == .relation }
    }
    
    // Get properties from the target database
    private var targetProperties: [PropertyDefinition] {
        guard let relationId = selectedRelationId,
              let relation = database.properties.first(where: { $0.id == relationId }),
              let config = relation.relationConfig,
              let targetDb = storage.databases.first(where: { $0.id == config.targetDatabaseId }) else {
            return []
        }
        return targetDb.properties
    }
    
    // Get available calculations based on property type
    private var availableCalculations: [RollupConfig.RollupCalculation] {
        guard let propId = selectedPropertyId,
              let prop = targetProperties.first(where: { $0.id == propId }) else {
            return RollupConfig.RollupCalculation.allCases
        }
        return RollupConfig.RollupCalculation.allCases.filter { calc in
            calc.applicableTypes.contains(prop.type)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Relation selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Relation")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if relationProperties.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Add a relation property first")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                } else {
                    Picker("Relation", selection: $selectedRelationId) {
                        Text("Select relation...").tag(nil as UUID?)
                        ForEach(relationProperties) { prop in
                            Text(prop.name).tag(prop.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            
            // Property selector
            if selectedRelationId != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Property")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Property", selection: $selectedPropertyId) {
                        Text("Select property...").tag(nil as UUID?)
                        ForEach(targetProperties) { prop in
                            HStack {
                                Image(systemName: iconForType(prop.type))
                                Text(prop.name)
                            }
                            .tag(prop.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            
            // Calculation selector
            if selectedPropertyId != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Calculate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Calculate", selection: $selectedCalculation) {
                        ForEach(availableCalculations, id: \.self) { calc in
                            Text(calc.displayName).tag(calc)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            
            Divider()
            
            // Preview
            if let relId = selectedRelationId,
               let propId = selectedPropertyId,
               let relation = relationProperties.first(where: { $0.id == relId }),
               let prop = targetProperties.first(where: { $0.id == propId }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "function")
                            .foregroundColor(.purple)
                        
                        Text("\(selectedCalculation.displayName) of \(prop.name) from \(relation.name)")
                            .font(.subheadline)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .onAppear {
            loadExisting()
        }
        .onChange(of: selectedRelationId) { _, _ in
            selectedPropertyId = nil
            updateConfig()
        }
        .onChange(of: selectedPropertyId) { _, _ in
            updateConfig()
        }
        .onChange(of: selectedCalculation) { _, _ in
            updateConfig()
        }
    }
    
    private func loadExisting() {
        if let config = definition.rollupConfig {
            selectedRelationId = config.relationPropertyId
            selectedPropertyId = config.targetPropertyId
            selectedCalculation = config.calculation
        }
    }
    
    private func updateConfig() {
        guard let relId = selectedRelationId, let propId = selectedPropertyId else {
            definition.rollupConfig = nil
            return
        }
        
        definition.rollupConfig = RollupConfig(
            relationPropertyId: relId,
            targetPropertyId: propId,
            calculation: selectedCalculation
        )
    }
    
    private func iconForType(_ type: PropertyType) -> String {
        switch type {
        case .text: return "textformat"
        case .number: return "number"
        case .select, .multiSelect: return "tag"
        case .date, .createdTime, .lastEdited: return "calendar"
        case .checkbox: return "checkmark.square"
        case .url: return "link"
        case .email: return "envelope"
        case .phone: return "phone"
        case .person: return "person"
        case .relation: return "arrow.left.arrow.right"
        case .rollup: return "function"
        case .formula: return "fx"
        case .status: return "circle.dotted"
        case .priority: return "flag"
        case .createdBy: return "person.badge.clock"
        }
    }
}

// MARK: - Linked Database Picker

struct LinkedDatabasePicker: View {
    @Binding var selectedDatabase: Database?
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @State private var searchText = ""
    
    private var filteredDatabases: [Database] {
        if searchText.isEmpty {
            return storage.databases
        }
        return storage.databases.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search databases...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Database list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredDatabases) { db in
                        Button(action: { selectedDatabase = db }) {
                            HStack(spacing: 12) {
                                Image(systemName: db.icon)
                                    .frame(width: 24)
                                    .foregroundColor(.accentColor)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(db.name)
                                        .font(.subheadline)
                                    Text("\(db.properties.count) properties")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if selectedDatabase?.id == db.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Relation Value Editor

struct RelationValueEditor: View {
    @Binding var value: PropertyValue
    let relationConfig: RelationConfig
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @State private var showingPicker = false
    @State private var selectedItems: Set<UUID> = []
    
    private var targetDatabase: Database? {
        storage.databases.first { $0.id == relationConfig.targetDatabaseId }
    }
    
    private var relatedItems: [WorkspaceItem] {
        let ids = currentIds
        return storage.items.filter { ids.contains($0.id) }
    }
    
    private var currentIds: [UUID] {
        switch value {
        case .relation(let id): return [id]
        case .relations(let ids): return ids
        default: return []
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Current relations
            if relatedItems.isEmpty {
                Button(action: { showingPicker = true }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add relation")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(relatedItems) { item in
                        RelationTag(item: item, onRemove: { removeRelation(item.id) })
                    }
                    
                    Button(action: { showingPicker = true }) {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            RelationItemPicker(
                database: targetDatabase,
                selectedIds: $selectedItems,
                onDone: applySelection
            )
        }
        .onAppear {
            selectedItems = Set(currentIds)
        }
    }
    
    private func removeRelation(_ id: UUID) {
        var ids = currentIds
        ids.removeAll { $0 == id }
        
        if ids.isEmpty {
            value = .empty
        } else if ids.count == 1 {
            value = .relation(ids[0])
        } else {
            value = .relations(ids)
        }
    }
    
    private func applySelection() {
        let ids = Array(selectedItems)
        if ids.isEmpty {
            value = .empty
        } else if ids.count == 1 {
            value = .relation(ids[0])
        } else {
            value = .relations(ids)
        }
        showingPicker = false
    }
}

// MARK: - Relation Tag

struct RelationTag: View {
    let item: WorkspaceItem
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            WorkspaceIconView(name: item.icon)
                .font(.caption2)
            Text(item.title)
                .font(.caption)
                .lineLimit(1)
            
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(4)
    }
}

// MARK: - Relation Item Picker

struct RelationItemPicker: View {
    let database: Database?
    @Binding var selectedIds: Set<UUID>
    let onDone: () -> Void
    
    @ObservedObject var storage = WorkspaceStorageServiceOptimized.shared
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    
    private var availableItems: [WorkspaceItem] {
        guard let db = database else { return [] }
        let items = storage.items.filter { $0.parentID == db.id }
        
        if searchText.isEmpty {
            return items
        }
        return items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Text(database?.name ?? "Select Items")
                    .font(.headline)
                Spacer()
                Button("Done") { onDone() }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            
            Divider()
            
            // Items list
            List(availableItems, selection: $selectedIds) { item in
                HStack(spacing: 12) {
                    Image(systemName: selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedIds.contains(item.id) ? .accentColor : .secondary)
                    
                    WorkspaceIconView(name: item.icon)
                        .foregroundColor(.secondary)
                    
                    Text(item.title)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedIds.contains(item.id) {
                        selectedIds.remove(item.id)
                    } else {
                        selectedIds.insert(item.id)
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        
        let maxX = proposal.width ?? .infinity
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxX && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX - spacing)
        }
        
        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}
