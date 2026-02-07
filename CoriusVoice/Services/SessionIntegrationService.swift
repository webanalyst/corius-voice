import Foundation
import SwiftUI

// MARK: - Session Integration Service

/// Integrates recording sessions with the workspace system
/// Allows converting sessions to tasks and embedding them in pages
@MainActor
class SessionIntegrationService: ObservableObject {
    static let shared = SessionIntegrationService()

    private let workspaceStorage: WorkspaceStorageServiceOptimized
    private let legacyStorage: WorkspaceStorageService?

    private init() {
        self.workspaceStorage = .shared
        self.legacyStorage = .shared
    }

    init(workspaceStorage: WorkspaceStorageServiceOptimized, legacyStorage: WorkspaceStorageService? = nil) {
        self.workspaceStorage = workspaceStorage
        self.legacyStorage = legacyStorage
    }

    // MARK: - Meeting Notes + Actions

    /// Ensures meeting notes and actions databases exist
    func ensureMeetingDatabases() -> (meetings: Database, actions: Database) {
        if var meetings = workspaceStorage.databases.first(where: { $0.name == "Meeting Notes" }),
           var actions = workspaceStorage.databases.first(where: { $0.name == "Meeting Actions" }) {
            var hasChanges = configureMeetingRelationsIfNeeded(meetingsDB: &meetings, actionsDB: &actions)
            if ensureActionTrackingViewsIfNeeded(actionsDB: &actions) {
                hasChanges = true
            }
            if hasChanges {
                workspaceStorage.updateDatabase(meetings)
                workspaceStorage.updateDatabase(actions)
                legacyStorage?.saveDatabase(meetings)
                legacyStorage?.saveDatabase(actions)
            }
            return (meetings, actions)
        }

        var meetingsDB = Database.meetingNotes(name: "Meeting Notes")
        var actionsDB = Database.meetingActions(name: "Meeting Actions")
        configureMeetingRelations(meetingsDB: &meetingsDB, actionsDB: &actionsDB)
        _ = ensureActionTrackingViewsIfNeeded(actionsDB: &actionsDB)
        workspaceStorage.addDatabase(meetingsDB)
        workspaceStorage.addDatabase(actionsDB)
        legacyStorage?.saveDatabase(meetingsDB)
        legacyStorage?.saveDatabase(actionsDB)
        return (meetingsDB, actionsDB)
    }

    /// Create or update meeting notes for a session
    func upsertMeetingNote(for session: RecordingSession) -> WorkspaceItem {
        let databases = ensureMeetingDatabases()
        let meetingDatabaseID = databases.meetings.id
        let sessionID = session.id

        ensureSessionWorkspaceItem(for: session)
        let sessionItem = workspaceStorage.items.first { $0.itemType == .session && $0.sessionID == sessionID }

        if let existing = workspaceStorage.items(inDatabase: meetingDatabaseID)
            .first(where: { $0.sessionID == sessionID }) {
            var updated = existing
            applyMeetingProperties(for: session, sessionItemID: sessionItem?.id, database: databases.meetings, item: &updated)
            updated.blocks = patchMeetingBlocks(
                updated.blocks,
                session: session,
                actionsDatabase: databases.actions,
                sessionItem: sessionItem
            )
            workspaceStorage.updateItem(updated)
            return updated
        }

        var item = WorkspaceItem(
            title: session.displayTitle,
            icon: "person.3",
            workspaceID: meetingDatabaseID,
            itemType: .page,
            blocks: meetingBlocks(for: session, actionsDatabase: databases.actions, sessionItem: sessionItem),
            properties: [:],
            sessionID: sessionID
        )
        applyMeetingProperties(for: session, sessionItemID: sessionItem?.id, database: databases.meetings, item: &item)
        workspaceStorage.addItem(item)
        return item
    }

    /// Extract action items into Meeting Actions database
    func syncActions(from session: RecordingSession, meetingNote: WorkspaceItem?) -> [WorkspaceItem] {
        guard let summary = session.summary else { return [] }
        let databases = ensureMeetingDatabases()
        let actionsDatabaseID = databases.actions.id

        let actionItems = summary.actionItems
        guard !actionItems.isEmpty else { return [] }

        let existing = workspaceStorage.items(inDatabase: actionsDatabaseID)
            .filter { $0.sessionID == session.id }
        let existingHashes = Set(existing.map { semanticActionHash($0.title) })

        let actionCount = actionItems.count
        var created: [WorkspaceItem] = []
        var seenHashes = existingHashes
        for action in actionItems {
            let title = action.description
            let actionHash = semanticActionHash(title)
            if seenHashes.contains(actionHash) {
                continue
            }
            var item = WorkspaceItem.task(title: title, workspaceID: actionsDatabaseID, status: "Todo")
            item.sessionID = session.id
            applyActionProperties(action, session: session, meetingNote: meetingNote, database: databases.actions, item: &item)
            workspaceStorage.addItem(item)
            created.append(item)
            seenHashes.insert(actionHash)
        }

        if var meetingNote = meetingNote {
            let allActions = workspaceStorage.items(inDatabase: actionsDatabaseID)
                .filter { $0.sessionID == session.id }
            meetingNote.properties[propertyKey(in: databases.meetings, name: "Actions")] = .relations(allActions.map { $0.id })
            meetingNote.properties[propertyKey(in: databases.meetings, name: "Action Count")] = .number(Double(allActions.count))
            workspaceStorage.updateItem(meetingNote)
        }

        _ = actionCount

        return created
    }

    /// Reconciles links between session, meeting note and actions.
    /// Safe to run multiple times (idempotent).
    func reconcileMeetingGraph(sessionID: UUID) {
        let databases = ensureMeetingDatabases()
        guard var meetingNote = workspaceStorage.items(inDatabase: databases.meetings.id)
            .first(where: { $0.sessionID == sessionID }) else {
            return
        }

        let actions = workspaceStorage.items(inDatabase: databases.actions.id)
            .filter { $0.sessionID == sessionID }
        meetingNote.properties[propertyKey(in: databases.meetings, name: "Actions")] = .relations(actions.map(\.id))
        meetingNote.properties[propertyKey(in: databases.meetings, name: "Action Count")] = .number(Double(actions.count))
        workspaceStorage.updateItem(meetingNote)
    }

    // MARK: - Convert Session to Task (legacy)

    func createTaskFromSession(
        _ session: RecordingSession,
        databaseID: UUID,
        columnID: UUID? = nil
    ) -> WorkspaceItem {
        guard let database = workspaceStorage.databases.first(where: { $0.id == databaseID }) else {
            print("⚠️ Database not found: \(databaseID)")
            return createStandaloneTask(from: session, workspaceID: databaseID)
        }

        let initialColumn = columnID ?? database.kanbanColumns.first?.id
        let statusName: String
        if let colID = initialColumn,
           let column = database.kanbanColumns.first(where: { $0.id == colID }) {
            statusName = column.name
        } else {
            statusName = "Todo"
        }

        let sessionTitle = session.title ?? ""
        let taskTitle = sessionTitle.isEmpty
            ? "Session \(session.startDate.formatted(date: .abbreviated, time: .shortened))"
            : sessionTitle

        var task = WorkspaceItem.task(
            title: taskTitle,
            workspaceID: databaseID,
            status: statusName
        )

        task.sessionID = session.id
        task.blocks = createBlocksFromSession(session)

        var tags: [String] = []
        if session.duration > 1800 {
            tags.append("Long Session")
        }

        let storage = StorageService.shared
        for labelID in session.labelIDs {
            if let label = storage.loadLabels().first(where: { $0.id == labelID }) {
                tags.append(label.name)
            }
        }

        if !tags.isEmpty {
            if let tagsProperty = database.properties.first(where: { $0.name == "Tags" })
                ?? database.properties.first(where: { $0.type == .multiSelect }) {
                task.properties[tagsProperty.storageKey] = .multiSelect(tags)
            } else {
                task.properties[PropertyDefinition.legacyKey(for: "Tags")] = .multiSelect(tags)
            }
        }

        if let statusProperty = database.properties.first(where: { $0.type == .status }) {
            task.properties[statusProperty.storageKey] = .select(statusName)
        }
        if let priorityProperty = database.properties.first(where: { $0.type == .priority }) {
            task.properties[priorityProperty.storageKey] = .select("Medium")
        }
        if let dueDateProperty = database.properties.first(where: { $0.type == .date }) {
            task.properties[dueDateProperty.storageKey] = .date(session.startDate)
        }
        workspaceStorage.addItem(task)

        print("📋 Created task from session: \(task.title)")
        return task
    }

    private func createBlocksFromSession(_ session: RecordingSession) -> [Block] {
        var blocks: [Block] = []

        blocks.append(Block(
            type: .callout,
            content: "Recording from \(session.startDate.formatted())",
            icon: "🎤",
            color: "#DBEAFE"
        ))

        var sessionEmbed = Block(type: .sessionEmbed, content: "")
        sessionEmbed.sessionID = session.id
        blocks.append(sessionEmbed)

        if let summary = session.summary {
            let content = summary.markdownContent
            if !content.isEmpty {
                blocks.append(Block(type: .heading2, content: "Summary"))

                if let overview = summary.overview {
                    blocks.append(Block(type: .paragraph, content: overview))
                }

                let keyPoints = summary.keyPoints
                if !keyPoints.isEmpty {
                    blocks.append(Block(type: .heading3, content: "Key Points"))
                    for point in keyPoints {
                        blocks.append(Block(type: .bulletList, content: point))
                    }
                }

                let actionItems = summary.actionItems
                if !actionItems.isEmpty {
                    blocks.append(Block(type: .heading3, content: "Action Items"))
                    for item in actionItems {
                        blocks.append(Block(type: .todo, content: item.description))
                    }
                }
            }
        }

        let fullTranscription = session.fullTranscript
        if !fullTranscription.isEmpty {
            blocks.append(Block(type: .divider, content: ""))
            var toggle = Block(type: .toggle, content: "Full Transcription")
            toggle.children = [Block(type: .paragraph, content: fullTranscription)]
            blocks.append(toggle)
        }

        return blocks
    }

    private func createStandaloneTask(from session: RecordingSession, workspaceID: UUID) -> WorkspaceItem {
        let sessionTitle = session.title ?? ""
        let taskTitle = sessionTitle.isEmpty ? "Session Task" : sessionTitle

        var task = WorkspaceItem.task(
            title: taskTitle,
            workspaceID: workspaceID
        )
        task.sessionID = session.id
        task.blocks = createBlocksFromSession(session)
        workspaceStorage.addItem(task)
        return task
    }

    // MARK: - Bulk Operations

    func createTasksFromSessions(
        _ sessions: [RecordingSession],
        databaseID: UUID,
        columnID: UUID? = nil
    ) -> [WorkspaceItem] {
        sessions.map { session in
            createTaskFromSession(session, databaseID: databaseID, columnID: columnID)
        }
    }

    func autoImportRecentSessions(
        databaseID: UUID,
        since: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    ) -> [WorkspaceItem] {
        let existingSessionIDs = Set(workspaceStorage.items.compactMap { $0.sessionID })
        let storage = StorageService.shared

        let recentSessions = storage.loadSessions().filter { session in
            session.startDate >= since && !existingSessionIDs.contains(session.id)
        }

        return createTasksFromSessions(recentSessions, databaseID: databaseID)
    }

    // MARK: - Session Lookup

    func getTasksForSession(_ sessionID: UUID) -> [WorkspaceItem] {
        workspaceStorage.items.filter { $0.sessionID == sessionID }
    }

    func getSessionForTask(_ taskID: UUID) -> RecordingSession? {
        guard let task = workspaceStorage.items.first(where: { $0.id == taskID }),
              let sessionID = task.sessionID else {
            return nil
        }
        let storage = StorageService.shared
        return storage.loadSessions().first { $0.id == sessionID }
    }

    // MARK: - Quick Actions

    func createTaskFromLastSession(databaseID: UUID) -> WorkspaceItem? {
        let storage = StorageService.shared
        guard let lastSession = storage.loadSessions().sorted(by: { $0.startDate > $1.startDate }).first else {
            print("⚠️ No sessions available")
            return nil
        }
        return createTaskFromSession(lastSession, databaseID: databaseID)
    }

    // MARK: - Helpers

    private func meetingBlocks(for session: RecordingSession, actionsDatabase: Database, sessionItem: WorkspaceItem?) -> [Block] {
        let attendees = session.speakers.map { $0.displayName }.joined(separator: "\n")
        var blocks: [Block] = [
            Block(type: .meetingAttendees, content: attendees),
            Block(type: .meetingAgenda, content: ""),
            Block(type: .meetingNotes, content: ""),
            Block(type: .meetingDecisions, content: ""),
            Block(type: .meetingActionItems, content: ""),
            Block(type: .meetingNextSteps, content: "")
        ]

        var sessionEmbed = Block(type: .sessionEmbed, content: "")
        sessionEmbed.sessionID = session.id
        blocks.append(sessionEmbed)

        var actionEmbed = Block(type: .databaseEmbed, content: actionsDatabase.name)
        configureActionEmbed(
            &actionEmbed,
            actionsDatabase: actionsDatabase,
            sessionItem: sessionItem
        )
        blocks.append(actionEmbed)

        return blocks
    }

    private func applyMeetingProperties(for session: RecordingSession, sessionItemID: UUID?, database: Database, item: inout WorkspaceItem) {
        item.title = session.displayTitle
        item.sessionID = session.id
        item.properties[propertyKey(in: database, name: "Date")] = .date(session.startDate)
        let attendeeNames = session.speakers.map { $0.displayName }.filter { !$0.isEmpty }
        if !attendeeNames.isEmpty {
            item.properties[propertyKey(in: database, name: "Attendees")] = .multiSelect(attendeeNames)
        }
        if let sessionItemID {
            item.properties[propertyKey(in: database, name: "Recording")] = .relation(sessionItemID)
        }
        if let summary = session.summary {
            item.properties[propertyKey(in: database, name: "Summary")] = .text(summary.overview ?? "")
            let decisions = summary.markdownContent
                .components(separatedBy: "##")
                .first { $0.lowercased().contains("decision") }
            if let decisions {
                item.properties[propertyKey(in: database, name: "Decisions")] = .text(decisions.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        item.updatedAt = Date()
    }

    private func applyActionProperties(_ action: ActionItem, session: RecordingSession, meetingNote: WorkspaceItem?, database: Database, item: inout WorkspaceItem) {
        item.properties[propertyKey(in: database, name: "Status")] = .select(action.isCompleted ? "Done" : "Todo")
        let dueDate = suggestedDueDate(for: action, sessionDate: session.startDate)
        item.properties[propertyKey(in: database, name: "Due Date")] = .date(dueDate)
        item.properties[propertyKey(in: database, name: "Priority")] = .select(
            suggestedPriority(for: action, dueDate: dueDate, sessionDate: session.startDate)
        )
        if let owner = suggestedOwner(for: action, session: session) {
            item.properties[propertyKey(in: database, name: "Owner")] = owner
        }

        if let sessionItem = workspaceStorage.items.first(where: { $0.itemType == .session && $0.sessionID == session.id }) {
            item.properties[propertyKey(in: database, name: "Session")] = .relation(sessionItem.id)
        }
        if let meetingNote {
            item.properties[propertyKey(in: database, name: "Meeting")] = .relation(meetingNote.id)
        }
        item.properties[propertyKey(in: database, name: "Source Quote")] = .text(action.description)
    }

    private func ensureSessionWorkspaceItem(for session: RecordingSession) {
        let existing = workspaceStorage.items.first { $0.itemType == .session && $0.sessionID == session.id }
        guard existing == nil else { return }
        let item = WorkspaceItem.fromSession(session)
        workspaceStorage.addItem(item)
    }

    private func propertyKey(in database: Database, name: String) -> String {
        if let definition = database.properties.first(where: { $0.name == name }) {
            return definition.storageKey
        }
        return PropertyDefinition.legacyKey(for: name)
    }

    private func semanticActionHash(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func configureMeetingRelations(meetingsDB: inout Database, actionsDB: inout Database) {
        _ = configureMeetingRelationsIfNeeded(meetingsDB: &meetingsDB, actionsDB: &actionsDB)
    }

    private func ensureActionTrackingViewsIfNeeded(actionsDB: inout Database) -> Bool {
        let statusProperty = actionsDB.properties.first(where: { $0.name == "Status" })
        let dueDateProperty = actionsDB.properties.first(where: { $0.name == "Due Date" })
        let priorityProperty = actionsDB.properties.first(where: { $0.name == "Priority" })
        let ownerProperty = actionsDB.properties.first(where: { $0.name == "Owner" })

        var changed = false

        if actionsDB.views.first(where: { $0.name == "Action Tracker" }) == nil {
            let tracker = DatabaseView(
                name: "Action Tracker",
                type: .table,
                sorts: [
                    ViewSort(propertyName: "Due Date", propertyId: dueDateProperty?.id, ascending: true),
                    ViewSort(propertyName: "Priority", propertyId: priorityProperty?.id, ascending: false),
                ],
                visibleProperties: [statusProperty?.id, ownerProperty?.id, dueDateProperty?.id, priorityProperty?.id]
                    .compactMap { $0 }
            )
            actionsDB.views.append(tracker)
            changed = true
        }

        if actionsDB.views.first(where: { $0.name == "Open Actions" }) == nil {
            let openActions = DatabaseView(
                name: "Open Actions",
                type: .list,
                filters: [
                    ViewFilter(
                        propertyName: "Status",
                        propertyId: statusProperty?.id,
                        operation: .notEquals,
                        value: .select("Done")
                    ),
                ],
                sorts: [ViewSort(propertyName: "Due Date", propertyId: dueDateProperty?.id, ascending: true)],
                visibleProperties: [statusProperty?.id, ownerProperty?.id, dueDateProperty?.id]
                    .compactMap { $0 }
            )
            actionsDB.views.append(openActions)
            changed = true
        }

        return changed
    }

    private func preferredActionTrackingView(in actionsDatabase: Database) -> DatabaseView? {
        if let tracker = actionsDatabase.views.first(where: { $0.name == "Action Tracker" }) {
            return tracker
        }
        return actionsDatabase.views.first
    }

    private func configureActionEmbed(_ embed: inout Block, actionsDatabase: Database, sessionItem: WorkspaceItem?) {
        embed.metadata["databaseID"] = actionsDatabase.id.uuidString
        if let preferredView = preferredActionTrackingView(in: actionsDatabase) {
            embed.metadata["viewType"] = preferredView.type.rawValue
            embed.metadata["viewID"] = preferredView.id.uuidString
        }
        if let sessionRelation = actionsDatabase.properties.first(where: { $0.name == "Session" }) {
            embed.metadata["relationProperty"] = sessionRelation.name
            embed.metadata["relationPropertyID"] = sessionRelation.id.uuidString
        }
        if let sessionItem {
            embed.metadata["relationTargetID"] = sessionItem.id.uuidString
        }
    }

    private func patchMeetingBlocks(
        _ blocks: [Block],
        session: RecordingSession,
        actionsDatabase: Database,
        sessionItem: WorkspaceItem?
    ) -> [Block] {
        var updatedBlocks = blocks
        var updatedAnyEmbed = false
        for index in updatedBlocks.indices where updatedBlocks[index].type == .databaseEmbed {
            let linkedDatabaseID = updatedBlocks[index].metadata["databaseID"]
            let isActionsEmbed = linkedDatabaseID == actionsDatabase.id.uuidString
                || updatedBlocks[index].content == actionsDatabase.name
            if isActionsEmbed {
                configureActionEmbed(&updatedBlocks[index], actionsDatabase: actionsDatabase, sessionItem: sessionItem)
                updatedAnyEmbed = true
            }
        }

        if !updatedAnyEmbed {
            var actionEmbed = Block(type: .databaseEmbed, content: actionsDatabase.name)
            configureActionEmbed(&actionEmbed, actionsDatabase: actionsDatabase, sessionItem: sessionItem)
            updatedBlocks.append(actionEmbed)
        }

        if !updatedBlocks.contains(where: { $0.type == .sessionEmbed && $0.sessionID == session.id }) {
            var sessionEmbed = Block(type: .sessionEmbed, content: "")
            sessionEmbed.sessionID = session.id
            updatedBlocks.append(sessionEmbed)
        }

        return updatedBlocks
    }

    private func suggestedOwner(for action: ActionItem, session: RecordingSession) -> PropertyValue? {
        let explicitAssignee = action.assignee?.trimmingCharacters(in: .whitespacesAndNewlines)
        let inferredFromSpeakers = inferSpeakerName(in: action.description, session: session)
        guard let ownerName = explicitAssignee ?? inferredFromSpeakers, !ownerName.isEmpty else {
            return nil
        }

        if let speaker = resolveKnownSpeaker(named: ownerName) {
            SpeakerLibrary.shared.markSpeakerUsed(speaker.id)
            return .person(speaker.id)
        }
        return .text(ownerName)
    }

    private func inferSpeakerName(in text: String, session: RecordingSession) -> String? {
        let normalizedText = text.lowercased()
        for speaker in session.speakers {
            let name = speaker.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                continue
            }
            if normalizedText.contains(name.lowercased()) {
                return name
            }
        }
        return nil
    }

    private func resolveKnownSpeaker(named name: String) -> KnownSpeaker? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        let matches = SpeakerLibrary.shared.searchSpeakers(query: name)
        if let exact = matches.first(where: { $0.name.lowercased() == normalized }) {
            return exact
        }
        if let prefix = matches.first(where: { $0.name.lowercased().hasPrefix(normalized) }) {
            return prefix
        }
        return matches.first
    }

    private func suggestedDueDate(for action: ActionItem, sessionDate: Date) -> Date {
        let context = [action.deadline, action.description]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
            .lowercased()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: sessionDate)

        if let explicit = parseExplicitDate(from: context, referenceDate: sessionDate) {
            return explicit
        }

        if context.contains("today") || context.contains("hoy") {
            return startOfDay
        }
        if context.contains("tomorrow")
            || context.contains("mañana")
            || context.contains("manana")
            || context.contains("asap")
            || context.contains("urgent")
            || context.contains("urgente") {
            return calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        }
        if context.contains("next week")
            || context.contains("próxima semana")
            || context.contains("proxima semana") {
            return calendar.date(byAdding: .day, value: 7, to: startOfDay) ?? startOfDay
        }
        if let weekdayDate = parseWeekday(from: context, referenceDate: startOfDay) {
            return weekdayDate
        }

        return calendar.date(byAdding: .day, value: 3, to: startOfDay) ?? startOfDay
    }

    private func parseExplicitDate(from text: String, referenceDate: Date) -> Date? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: referenceDate)

        if let isoMatch = text.range(of: #"\b\d{4}-\d{2}-\d{2}\b"#, options: .regularExpression) {
            let token = String(text[isoMatch])
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: token) {
                return calendar.startOfDay(for: date)
            }
        }

        if let slashMatch = text.range(of: #"\b\d{1,2}[/-]\d{1,2}([/-]\d{2,4})?\b"#, options: .regularExpression) {
            let token = String(text[slashMatch])
            let components = token.split(whereSeparator: { $0 == "/" || $0 == "-" }).map(String.init)
            if components.count >= 2,
               let day = Int(components[0]),
               let month = Int(components[1]) {
                var year = calendar.component(.year, from: startOfDay)
                if components.count == 3, let parsedYear = Int(components[2]) {
                    year = parsedYear < 100 ? 2000 + parsedYear : parsedYear
                }

                var dateComponents = DateComponents()
                dateComponents.year = year
                dateComponents.month = month
                dateComponents.day = day
                if let parsed = calendar.date(from: dateComponents) {
                    return calendar.startOfDay(for: parsed)
                }
            }
        }

        return nil
    }

    private func parseWeekday(from text: String, referenceDate: Date) -> Date? {
        let weekdays: [(tokens: [String], value: Int)] = [
            (["monday", "lunes"], 2),
            (["tuesday", "martes"], 3),
            (["wednesday", "miércoles", "miercoles"], 4),
            (["thursday", "jueves"], 5),
            (["friday", "viernes"], 6),
            (["saturday", "sábado", "sabado"], 7),
            (["sunday", "domingo"], 1),
        ]

        let calendar = Calendar.current
        for candidate in weekdays {
            let containsWeekday = candidate.tokens.contains { text.contains($0) }
            if !containsWeekday {
                continue
            }

            let currentWeekday = calendar.component(.weekday, from: referenceDate)
            var offset = candidate.value - currentWeekday
            if offset <= 0 {
                offset += 7
            }
            return calendar.date(byAdding: .day, value: offset, to: referenceDate)
        }

        return nil
    }

    private func suggestedPriority(for action: ActionItem, dueDate: Date, sessionDate: Date) -> String {
        let context = "\(action.description) \(action.deadline ?? "")".lowercased()
        let highHints = ["urgent", "urgente", "asap", "critical", "crítico", "critico", "blocker", "bloqueante"]
        let lowHints = ["later", "después", "despues", "nice to have", "eventually", "cuando puedas", "backlog"]

        if highHints.contains(where: { context.contains($0) }) {
            return "High"
        }
        if lowHints.contains(where: { context.contains($0) }) {
            return "Low"
        }

        let hoursUntilDue = dueDate.timeIntervalSince(sessionDate) / 3600
        if hoursUntilDue <= 36 {
            return "High"
        }
        if hoursUntilDue <= 120 {
            return "Medium"
        }
        return "Low"
    }

    private func configureMeetingRelationsIfNeeded(meetingsDB: inout Database, actionsDB: inout Database) -> Bool {
        let actionsRelationId = actionsDB.properties.first(where: { $0.name == "Meeting" })?.id
        let meetingsRelationId = meetingsDB.properties.first(where: { $0.name == "Actions" })?.id

        var updated = false

        if let actionsRelationId {
            if let index = actionsDB.properties.firstIndex(where: { $0.id == actionsRelationId }) {
                let current = actionsDB.properties[index].relationConfig
                if current?.targetDatabaseId != meetingsDB.id || current?.reversePropertyId != meetingsRelationId {
                    actionsDB.properties[index].relationConfig = RelationConfig(
                        targetDatabaseId: meetingsDB.id,
                        isTwoWay: true,
                        reversePropertyId: meetingsRelationId,
                        reverseName: "Actions"
                    )
                    updated = true
                }
            }
        }

        if let meetingsRelationId {
            if let index = meetingsDB.properties.firstIndex(where: { $0.id == meetingsRelationId }) {
                let current = meetingsDB.properties[index].relationConfig
                if current?.targetDatabaseId != actionsDB.id || current?.reversePropertyId != actionsRelationId {
                    meetingsDB.properties[index].relationConfig = RelationConfig(
                        targetDatabaseId: actionsDB.id,
                        isTwoWay: true,
                        reversePropertyId: actionsRelationId,
                        reverseName: "Meeting"
                    )
                    updated = true
                }
            }
        }

        return updated
    }
}

// MARK: - Session Extension for Workspace

extension RecordingSession {
    /// Quick convert to workspace task
    @MainActor
    func toWorkspaceTask(databaseID: UUID, columnID: UUID? = nil) -> WorkspaceItem {
        return SessionIntegrationService.shared.createTaskFromSession(
            self,
            databaseID: databaseID,
            columnID: columnID
        )
    }
}

// MARK: - WorkspaceItem Extension

extension WorkspaceItem {
    /// Check if this item is linked to a session
    var hasLinkedSession: Bool {
        return sessionID != nil
    }
}
