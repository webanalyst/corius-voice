import Foundation

// MARK: - Speaker Chat Error

enum SpeakerChatError: LocalizedError {
    case noApiKey
    case invalidResponse
    case networkError(Error)
    case speakerNotFound
    case sessionNotFound
    case toolExecutionFailed(String)
    case maxIterationsReached

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "OpenRouter API key is not configured. Please add your API key in Settings."
        case .invalidResponse:
            return "Received an invalid response from the AI model."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .speakerNotFound:
            return "Speaker not found in library."
        case .sessionNotFound:
            return "Session not found."
        case .toolExecutionFailed(let message):
            return "Tool execution failed: \(message)"
        case .maxIterationsReached:
            return "Maximum tool iterations reached. Please try a simpler question."
        }
    }
}

// MARK: - Speaker Chat Service

@MainActor
class SpeakerChatService: ObservableObject {
    @Published var conversation: SpeakerConversation?
    @Published var isProcessing = false
    @Published var streamingContent = ""
    @Published var currentToolCall: String?  // Name of tool being executed
    @Published var error: SpeakerChatError?

    private let baseURL = "https://openrouter.ai/api/v1/chat/completions"
    private let maxToolIterations = 5
    private var urlSession: URLSession

    private var speaker: KnownSpeaker?
    private let workspaceAgent: WorkspaceAgentActionService

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config)
        self.workspaceAgent = WorkspaceAgentActionService(workspaceStorage: .shared)
    }

    // MARK: - Conversation Management

    /// Start a new conversation for a speaker
    func startConversation(for speaker: KnownSpeaker) {
        self.speaker = speaker
        let systemMessage = buildSystemPrompt(for: speaker)
        var newConversation = SpeakerConversation(speakerId: speaker.id)
        newConversation.addMessage(.system(systemMessage))
        self.conversation = newConversation
        self.error = nil
    }

    /// Clear the current conversation
    func clearConversation() {
        guard let speaker = speaker else { return }
        startConversation(for: speaker)
    }

    /// Send a message and get a response
    func sendMessage(_ content: String) async {
        guard let speaker = speaker else {
            error = .speakerNotFound
            return
        }

        guard var conversation = conversation else {
            startConversation(for: speaker)
            await sendMessage(content)
            return
        }

        let apiKey = StorageService.shared.settings.openRouterApiKey
        guard !apiKey.isEmpty else {
            error = .noApiKey
            return
        }

        // Add user message
        conversation.addMessage(.user(content))
        self.conversation = conversation

        isProcessing = true
        streamingContent = ""
        error = nil

        do {
            let modelId = StorageService.shared.settings.openRouterModelId.isEmpty
                ? "anthropic/claude-3.5-haiku"
                : StorageService.shared.settings.openRouterModelId
            try await processWithTools(modelId: modelId, apiKey: apiKey)
        } catch let chatError as SpeakerChatError {
            error = chatError
        } catch {
            self.error = .networkError(error)
        }

        isProcessing = false
        currentToolCall = nil
    }

    // MARK: - Private Methods

    private func buildSystemPrompt(for speaker: KnownSpeaker) -> String {
        // Get speaker statistics
        let sessions = StorageService.shared.loadSessions()
        let speakerSessions = findSessionsForSpeaker(speaker, in: sessions)

        let totalDuration = speakerSessions.reduce(0.0) { $0 + $1.duration }
        let formattedDuration = formatDuration(totalDuration)

        var prompt = """
        You are a helpful assistant for CoriusVoice, a voice recording and transcription app. You help users explore recording sessions involving \(speaker.name).

        ## Speaker Context
        - Name: \(speaker.name)
        """

        if let notes = speaker.notes, !notes.isEmpty {
            prompt += "\n- Notes: \(notes)"
        }

        if let characteristics = speaker.voiceCharacteristics, !characteristics.isEmpty {
            prompt += "\n- Voice Characteristics: \(characteristics)"
        }

        prompt += """

        - Sessions: \(speakerSessions.count) session(s)
        - Total Speaking Time: \(formattedDuration)
        - Added: \(speaker.createdAt.formatted(date: .abbreviated, time: .omitted))

        ## Tools Available
        1. **search_sessions** - Find sessions where this speaker participated. Use filters like date range, session type, or text query.
        2. **get_transcript** - Get the transcript of a specific session. Can filter to show only this speaker's segments.
        3. **get_summary** - Get the AI-generated summary of a specific session.
        4. **get_speaker_info** - Get detailed statistics about this speaker.
        5. **list_workspace_actions** - List safe internal workspace actions available to the agent.
        6. **execute_workspace_action** - Execute a workspace action from the approved action catalog.
        7. **confirm_workspace_action** - Confirm or reject pending high-impact actions.
        8. **rollback_workspace_action** - Revert the most recent successful action when rollback is available.
        9. **get_workspace_action_audit** - Retrieve audit history of automated actions.

        ## Guidelines
        - Use tools to fetch data before answering questions about sessions
        - When asked about conversations or topics, search sessions first, then get transcripts
        - Before destructive changes, request confirmation and never bypass pending confirmations
        - Prefer safe actions from the catalog instead of free-form mutations
        - Format transcripts clearly with timestamps when showing them
        - Be concise but thorough in your responses
        - Use Markdown for formatting (headers, lists, bold, etc.)
        - If you can't find information, say so clearly
        - Reference session dates when discussing specific conversations

        ## Important
        - Always verify information by using tools rather than making assumptions
        - When showing transcripts, include speaker names and timestamps
        - If a question is ambiguous, ask for clarification
        """

        return prompt
    }

    private func processWithTools(modelId: String, apiKey: String) async throws {
        var iterations = 0

        while iterations < maxToolIterations {
            iterations += 1

            let response = try await sendChatRequest(modelId: modelId, apiKey: apiKey, stream: true)

            // Check if there are tool calls to process
            guard let toolCalls = response.toolCalls, !toolCalls.isEmpty else {
                // No tool calls, we're done - response content already added via streaming
                if response.content != nil {
                    // Content was already streamed and added
                    return
                }
                return
            }

            // Add assistant message with tool calls (no content yet)
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: response.content,
                toolCalls: toolCalls
            )
            conversation?.addMessage(assistantMessage)

            // Execute each tool call
            for toolCall in toolCalls {
                currentToolCall = toolCall.function.name
                let result = await executeToolCall(toolCall)

                // Add tool result message
                conversation?.addMessage(.tool(
                    callId: toolCall.id,
                    name: toolCall.function.name,
                    content: result
                ))
            }

            currentToolCall = nil
        }

        throw SpeakerChatError.maxIterationsReached
    }

    private func sendChatRequest(modelId: String, apiKey: String, stream: Bool) async throws -> (content: String?, toolCalls: [ToolCall]?) {
        guard let url = URL(string: baseURL) else {
            throw SpeakerChatError.invalidResponse
        }

        guard let conversation = conversation else {
            throw SpeakerChatError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CoriusVoice/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("CoriusVoice", forHTTPHeaderField: "X-Title")

        let requestBody: [String: Any] = [
            "model": modelId,
            "messages": conversation.apiMessages,
            "tools": ChatTool.allTools,
            "stream": stream,
            "max_tokens": 4096,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        if stream {
            return try await streamResponse(request: request)
        } else {
            return try await nonStreamResponse(request: request)
        }
    }

    private func streamResponse(request: URLRequest) async throws -> (content: String?, toolCalls: [ToolCall]?) {
        let (bytes, response) = try await urlSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeakerChatError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw SpeakerChatError.noApiKey
        }

        if httpResponse.statusCode != 200 {
            throw SpeakerChatError.networkError(NSError(domain: "HTTP", code: httpResponse.statusCode))
        }

        var fullContent = ""
        var accumulatedToolCalls: [String: ToolCall] = [:]  // id -> ToolCall

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))

            if jsonString == "[DONE]" { break }

            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else {
                continue
            }

            // Handle content delta
            if let content = delta["content"] as? String {
                fullContent += content
                await MainActor.run {
                    self.streamingContent = fullContent
                }
            }

            // Handle tool calls delta
            if let toolCallsArray = delta["tool_calls"] as? [[String: Any]] {
                for toolCallDelta in toolCallsArray {
                    guard let index = toolCallDelta["index"] as? Int else { continue }
                    let indexStr = String(index)

                    if let id = toolCallDelta["id"] as? String {
                        // New tool call
                        let functionDict = toolCallDelta["function"] as? [String: Any] ?? [:]
                        let name = functionDict["name"] as? String ?? ""
                        let args = functionDict["arguments"] as? String ?? ""

                        accumulatedToolCalls[indexStr] = ToolCall(
                            id: id,
                            function: ToolFunction(name: name, arguments: args)
                        )
                    } else if var existing = accumulatedToolCalls[indexStr] {
                        // Append to existing tool call arguments
                        if let functionDict = toolCallDelta["function"] as? [String: Any],
                           let argsChunk = functionDict["arguments"] as? String {
                            let newArgs = existing.function.arguments + argsChunk
                            accumulatedToolCalls[indexStr] = ToolCall(
                                id: existing.id,
                                function: ToolFunction(name: existing.function.name, arguments: newArgs)
                            )
                        }
                    }
                }
            }
        }

        // If we got content without tool calls, add it as assistant message
        if !fullContent.isEmpty && accumulatedToolCalls.isEmpty {
            conversation?.addMessage(.assistant(fullContent))
        }

        let toolCalls = accumulatedToolCalls.isEmpty ? nil : Array(accumulatedToolCalls.values)
        return (fullContent.isEmpty ? nil : fullContent, toolCalls)
    }

    private func nonStreamResponse(request: URLRequest) async throws -> (content: String?, toolCalls: [ToolCall]?) {
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeakerChatError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            throw SpeakerChatError.networkError(NSError(domain: "HTTP", code: httpResponse.statusCode))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw SpeakerChatError.invalidResponse
        }

        let content = message["content"] as? String

        var toolCalls: [ToolCall]? = nil
        if let toolCallsArray = message["tool_calls"] as? [[String: Any]] {
            toolCalls = toolCallsArray.compactMap { dict -> ToolCall? in
                guard let id = dict["id"] as? String,
                      let function = dict["function"] as? [String: Any],
                      let name = function["name"] as? String,
                      let arguments = function["arguments"] as? String else {
                    return nil
                }
                return ToolCall(id: id, function: ToolFunction(name: name, arguments: arguments))
            }
        }

        return (content, toolCalls)
    }

    // MARK: - Tool Execution

    private func executeToolCall(_ toolCall: ToolCall) async -> String {
        let functionName = toolCall.function.name
        let arguments = toolCall.function.arguments

        print("[SpeakerChat] 🔧 Executing tool: \(functionName)")
        print("[SpeakerChat] 📝 Arguments: \(arguments)")

        switch functionName {
        case "search_sessions":
            return await executeSearchSessions(arguments)
        case "get_transcript":
            return await executeGetTranscript(arguments)
        case "get_summary":
            return await executeGetSummary(arguments)
        case "get_speaker_info":
            return await executeGetSpeakerInfo()
        case "list_workspace_actions":
            return workspaceAgent.catalogMarkdown()
        case "execute_workspace_action":
            return workspaceAgent.executeFromTool(arguments)
        case "confirm_workspace_action":
            return workspaceAgent.confirmFromTool(arguments)
        case "rollback_workspace_action":
            return workspaceAgent.rollbackFromTool()
        case "get_workspace_action_audit":
            return workspaceAgent.auditFromTool(arguments)
        default:
            return "Unknown tool: \(functionName)"
        }
    }

    private func executeSearchSessions(_ arguments: String) async -> String {
        guard let speaker = speaker else { return "Error: Speaker not found" }

        let args: SearchSessionsArgs
        if let data = arguments.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(SearchSessionsArgs.self, from: data) {
            args = decoded
        } else {
            args = SearchSessionsArgs()
        }

        let allSessions = StorageService.shared.loadSessions()
        var matchingSessions = findSessionsForSpeaker(speaker, in: allSessions)

        // Apply filters
        if let query = args.query, !query.isEmpty {
            let lowercaseQuery = query.lowercased()
            matchingSessions = matchingSessions.filter { session in
                (session.title?.lowercased().contains(lowercaseQuery) ?? false) ||
                session.fullTranscript.lowercased().contains(lowercaseQuery)
            }
        }

        if let sessionType = args.session_type,
           let type = SessionType(rawValue: sessionType) {
            matchingSessions = matchingSessions.filter { $0.sessionType == type }
        }

        if let dateFrom = args.date_from,
           let fromDate = ISO8601DateFormatter().date(from: dateFrom) {
            matchingSessions = matchingSessions.filter { $0.startDate >= fromDate }
        }

        if let dateTo = args.date_to,
           let toDate = ISO8601DateFormatter().date(from: dateTo) {
            matchingSessions = matchingSessions.filter { $0.startDate <= toDate }
        }

        // Sort by date (most recent first)
        matchingSessions.sort { $0.startDate > $1.startDate }

        // Apply limit
        let limit = args.limit ?? 10
        matchingSessions = Array(matchingSessions.prefix(limit))

        if matchingSessions.isEmpty {
            return "No sessions found matching the criteria."
        }

        // Format results
        var result = "Found \(matchingSessions.count) session(s):\n\n"
        for session in matchingSessions {
            result += """
            **\(session.displayTitle)**
            - ID: \(session.id.uuidString)
            - Date: \(session.startDate.formatted(date: .abbreviated, time: .shortened))
            - Duration: \(session.formattedDuration)
            - Type: \(session.sessionType.displayName)
            - Words: \(session.wordCount)

            """
        }

        return result
    }

    private func executeGetTranscript(_ arguments: String) async -> String {
        guard let speaker = speaker else { return "Error: Speaker not found" }

        guard let data = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode(GetTranscriptArgs.self, from: data) else {
            return "Error: Invalid arguments"
        }

        guard let sessionID = UUID(uuidString: args.session_id) else {
            return "Error: Invalid session ID"
        }

        let sessions = StorageService.shared.loadSessions()
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return "Error: Session not found"
        }

        var segments = session.transcriptSegments
        let speakerOnly = args.speaker_only ?? false

        if speakerOnly {
            // Filter to only this speaker's segments
            let speakerIndex = findSpeakerIndex(for: speaker, in: session)
            if let index = speakerIndex {
                segments = segments.filter { $0.speakerID == index }
            }
        }

        // Apply limit
        let maxSegments = args.max_segments ?? 50
        segments = Array(segments.prefix(maxSegments))

        if segments.isEmpty {
            return "No transcript segments found."
        }

        // Format transcript
        var result = "**Transcript for: \(session.displayTitle)**\n"
        result += "Date: \(session.startDate.formatted(date: .abbreviated, time: .shortened))\n\n"

        for segment in segments {
            let time = formatTimestamp(segment.timestamp)
            let speakerName = session.speaker(for: segment.speakerID)?.displayName ?? "Unknown"
            result += "[\(time)] **\(speakerName)**: \(segment.text)\n"
        }

        if segments.count >= maxSegments {
            result += "\n_(Showing first \(maxSegments) segments. Use max_segments parameter to see more.)_"
        }

        return result
    }

    private func executeGetSummary(_ arguments: String) async -> String {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode(GetSummaryArgs.self, from: data) else {
            return "Error: Invalid arguments"
        }

        guard let sessionID = UUID(uuidString: args.session_id) else {
            return "Error: Invalid session ID"
        }

        let sessions = StorageService.shared.loadSessions()
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return "Error: Session not found"
        }

        guard let summary = session.summary else {
            return "No summary available for this session. The session may not have been summarized yet."
        }

        return """
        **Summary for: \(session.displayTitle)**
        Date: \(session.startDate.formatted(date: .abbreviated, time: .shortened))
        Model Used: \(summary.modelUsed)

        ---

        \(summary.markdownContent)
        """
    }

    private func executeGetSpeakerInfo() async -> String {
        guard let speaker = speaker else { return "Error: Speaker not found" }

        let sessions = StorageService.shared.loadSessions()
        let speakerSessions = findSessionsForSpeaker(speaker, in: sessions)

        // Calculate statistics
        let totalDuration = speakerSessions.reduce(0.0) { $0 + $1.duration }
        let totalWords = speakerSessions.reduce(0) { total, session in
            total + countWordsForSpeaker(speaker, in: session)
        }

        // Get voice profile info
        let voiceProfile = VoiceProfileService.shared.getProfile(for: speaker.id)
        let trainingRecords = VoiceProfileService.shared.getTrainingRecords(for: speaker.id)

        var result = """
        # Speaker Information: \(speaker.name)

        ## Basic Info
        - **ID**: \(speaker.id.uuidString)
        - **Color**: \(speaker.color)
        - **Added**: \(speaker.createdAt.formatted(date: .abbreviated, time: .omitted))
        - **Usage Count**: \(speaker.usageCount)
        """

        if let lastUsed = speaker.lastUsedAt {
            result += "\n- **Last Used**: \(lastUsed.formatted(date: .abbreviated, time: .shortened))"
        }

        if let notes = speaker.notes, !notes.isEmpty {
            result += "\n\n## Notes\n\(notes)"
        }

        if let characteristics = speaker.voiceCharacteristics, !characteristics.isEmpty {
            result += "\n\n## Voice Characteristics\n\(characteristics)"
        }

        result += """

        ## Session Statistics
        - **Total Sessions**: \(speakerSessions.count)
        - **Total Duration**: \(formatDuration(totalDuration))
        - **Total Words Spoken**: \(totalWords)
        """

        if let profile = voiceProfile {
            result += """

            ## Voice Profile
            - **Status**: Trained
            - **Samples**: \(profile.sampleCount)
            - **Training Duration**: \(formatDuration(profile.totalDuration))
            - **Training Sessions Used**: \(trainingRecords.count)
            - **Last Updated**: \(profile.updatedAt.formatted(date: .abbreviated, time: .shortened))
            """
        } else {
            result += "\n\n## Voice Profile\n- **Status**: Not trained"
        }

        // Session type breakdown
        var typeBreakdown: [SessionType: Int] = [:]
        for session in speakerSessions {
            typeBreakdown[session.sessionType, default: 0] += 1
        }

        if !typeBreakdown.isEmpty {
            result += "\n\n## Session Types"
            for (type, count) in typeBreakdown.sorted(by: { $0.value > $1.value }) {
                result += "\n- \(type.displayName): \(count)"
            }
        }

        return result
    }

    // MARK: - Helper Methods

    private func findSessionsForSpeaker(_ speaker: KnownSpeaker, in sessions: [RecordingSession]) -> [RecordingSession] {
        let speakerName = speaker.name.lowercased()

        return sessions.filter { session in
            // Check if any speaker in the session matches
            session.speakers.contains { sessionSpeaker in
                sessionSpeaker.name?.lowercased() == speakerName
            }
        }
    }

    private func findSpeakerIndex(for speaker: KnownSpeaker, in session: RecordingSession) -> Int? {
        let speakerName = speaker.name.lowercased()
        return session.speakers.first { $0.name?.lowercased() == speakerName }?.id
    }

    private func countWordsForSpeaker(_ speaker: KnownSpeaker, in session: RecordingSession) -> Int {
        guard let speakerIndex = findSpeakerIndex(for: speaker, in: session) else {
            return 0
        }

        return session.transcriptSegments
            .filter { $0.speakerID == speakerIndex }
            .reduce(0) { $0 + $1.text.split(separator: " ").count }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Workspace Agent Action Service

@MainActor
final class WorkspaceAgentActionService: ObservableObject {
    enum Action: String, CaseIterable {
        case createTask = "create_task"
        case moveTask = "move_task"
        case deleteItem = "delete_item"

        var description: String {
            switch self {
            case .createTask:
                return "Create a task in a target database."
            case .moveTask:
                return "Move an existing task to another status/column."
            case .deleteItem:
                return "Delete an item. Always requires confirmation."
            }
        }

        var requiresExplicitConfirmation: Bool {
            switch self {
            case .deleteItem:
                return true
            case .createTask, .moveTask:
                return false
            }
        }
    }

    enum AuditStatus: String {
        case success
        case failed
        case pendingConfirmation = "pending_confirmation"
        case canceled
        case rolledBack = "rolled_back"
    }

    struct ActionDescriptor {
        let action: Action
        let description: String
        let requiresExplicitConfirmation: Bool
        let rollbackSupported: Bool
    }

    struct ActionRequest {
        let action: Action
        var title: String?
        var databaseID: UUID?
        var taskID: UUID?
        var taskQuery: String?
        var targetStatus: String?
        var itemID: UUID?
        var itemQuery: String?
    }

    struct ActionResult {
        let success: Bool
        let message: String
        let requiresConfirmation: Bool
        let confirmationToken: String?
        let rollbackAvailable: Bool
        let auditID: UUID
    }

    struct AuditEntry: Identifiable {
        let id: UUID
        let timestamp: Date
        let action: String
        let status: AuditStatus
        let message: String
        let rollbackAvailable: Bool
        let metadata: String
    }

    private struct PendingConfirmation {
        let token: String
        let action: Action
        let metadata: String
        let payload: PendingPayload
    }

    private enum PendingPayload {
        case moveTask(taskID: UUID, targetStatus: String)
        case deleteItem(snapshot: WorkspaceItem)
    }

    private enum RollbackOperation {
        case deleteItem(id: UUID)
        case restoreItem(snapshot: WorkspaceItem)
    }

    @Published private(set) var auditTrail: [AuditEntry] = []

    private let workspaceStorage: WorkspaceStorageServiceOptimized
    private let maxAuditEntries = 200
    private var pendingConfirmation: PendingConfirmation?
    private var lastRollback: RollbackOperation?

    init(workspaceStorage: WorkspaceStorageServiceOptimized) {
        self.workspaceStorage = workspaceStorage
    }

    func catalog() -> [ActionDescriptor] {
        Action.allCases.map { action in
            ActionDescriptor(
                action: action,
                description: action.description,
                requiresExplicitConfirmation: action.requiresExplicitConfirmation,
                rollbackSupported: true
            )
        }
    }

    func catalogMarkdown() -> String {
        let entries = catalog().map { descriptor in
            let confirmation = descriptor.requiresExplicitConfirmation ? "yes" : "conditional"
            return "- `\(descriptor.action.rawValue)`: \(descriptor.description) (confirmation: \(confirmation), rollback: yes)"
        }
        return """
        Available workspace actions:
        \(entries.joined(separator: "\n"))
        """
    }

    func execute(request: ActionRequest) -> ActionResult {
        if let pendingConfirmation {
            return record(
                action: request.action.rawValue,
                status: .failed,
                message: "A pending action already exists. Confirm or reject token \(pendingConfirmation.token) first.",
                rollbackAvailable: lastRollback != nil,
                metadata: pendingConfirmation.metadata
            )
        }

        switch request.action {
        case .createTask:
            return executeCreateTask(request)
        case .moveTask:
            return executeMoveTask(request)
        case .deleteItem:
            return executeDeleteItem(request)
        }
    }

    func confirm(token: String, accept: Bool) -> ActionResult {
        guard let pending = pendingConfirmation else {
            return record(
                action: "confirm_workspace_action",
                status: .failed,
                message: "No pending action to confirm.",
                rollbackAvailable: lastRollback != nil,
                metadata: ""
            )
        }

        guard pending.token == token else {
            return record(
                action: pending.action.rawValue,
                status: .failed,
                message: "Invalid confirmation token.",
                rollbackAvailable: lastRollback != nil,
                metadata: pending.metadata
            )
        }

        if !accept {
            pendingConfirmation = nil
            return record(
                action: pending.action.rawValue,
                status: .canceled,
                message: "Action rejected by confirmation.",
                rollbackAvailable: lastRollback != nil,
                metadata: pending.metadata
            )
        }

        pendingConfirmation = nil
        switch pending.payload {
        case .moveTask(let taskID, let targetStatus):
            return performMoveTask(taskID: taskID, targetStatus: targetStatus, metadata: pending.metadata)
        case .deleteItem(let snapshot):
            workspaceStorage.deleteItem(snapshot.id)
            lastRollback = .restoreItem(snapshot: snapshot)
            return record(
                action: Action.deleteItem.rawValue,
                status: .success,
                message: "Deleted item '\(snapshot.displayTitle)'.",
                rollbackAvailable: true,
                metadata: pending.metadata
            )
        }
    }

    func rollbackLastAction() -> ActionResult {
        guard let operation = lastRollback else {
            return record(
                action: "rollback_workspace_action",
                status: .failed,
                message: "No rollback available.",
                rollbackAvailable: false,
                metadata: ""
            )
        }

        switch operation {
        case .deleteItem(let id):
            if workspaceStorage.item(withID: id) != nil {
                workspaceStorage.deleteItem(id)
            }
        case .restoreItem(let snapshot):
            if workspaceStorage.item(withID: snapshot.id) != nil {
                workspaceStorage.updateItem(snapshot)
            } else {
                workspaceStorage.addItem(snapshot)
            }
        }

        lastRollback = nil
        return record(
            action: "rollback_workspace_action",
            status: .rolledBack,
            message: "Last action rolled back.",
            rollbackAvailable: false,
            metadata: ""
        )
    }

    func recentAudit(limit: Int = 10) -> [AuditEntry] {
        guard limit > 0 else { return [] }
        return Array(auditTrail.suffix(limit).reversed())
    }

    func executeFromTool(_ arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode(ExecuteWorkspaceActionArgs.self, from: data),
              let action = Action(rawValue: args.action) else {
            return "Error: invalid arguments. Expected action in {create_task, move_task, delete_item}."
        }

        let request = ActionRequest(
            action: action,
            title: args.title,
            databaseID: args.database_id.flatMap(UUID.init(uuidString:)),
            taskID: args.task_id.flatMap(UUID.init(uuidString:)),
            taskQuery: args.task_query,
            targetStatus: args.target_status,
            itemID: args.item_id.flatMap(UUID.init(uuidString:)),
            itemQuery: args.item_query
        )

        let result = execute(request: request)
        return formatToolResult(result)
    }

    func confirmFromTool(_ arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode(ConfirmWorkspaceActionArgs.self, from: data) else {
            return "Error: invalid confirmation arguments. Expected confirmation_token."
        }

        let result = confirm(token: args.confirmation_token, accept: args.accept ?? true)
        return formatToolResult(result)
    }

    func rollbackFromTool() -> String {
        let result = rollbackLastAction()
        return formatToolResult(result)
    }

    func auditFromTool(_ arguments: String) -> String {
        let limit: Int
        if let data = arguments.data(using: .utf8),
           let args = try? JSONDecoder().decode(WorkspaceActionAuditArgs.self, from: data),
           let requestedLimit = args.limit {
            limit = max(1, min(requestedLimit, 50))
        } else {
            limit = 10
        }

        let entries = recentAudit(limit: limit)
        if entries.isEmpty {
            return "No audit entries available."
        }

        let lines = entries.map { entry in
            let stamp = entry.timestamp.formatted(date: .abbreviated, time: .shortened)
            return "- [\(entry.status.rawValue)] \(entry.action) at \(stamp): \(entry.message)"
        }
        return "Recent action audit:\n" + lines.joined(separator: "\n")
    }

    private func executeCreateTask(_ request: ActionRequest) -> ActionResult {
        guard let database = request.databaseID.flatMap({ workspaceStorage.database(withID: $0) })
            ?? workspaceStorage.databases.first else {
            return record(
                action: Action.createTask.rawValue,
                status: .failed,
                message: "No database available to create tasks.",
                rollbackAvailable: lastRollback != nil,
                metadata: ""
            )
        }

        let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskTitle = (title?.isEmpty == false) ? title! : "New Task"
        let created = workspaceStorage.createTask(title: taskTitle, databaseID: database.id)
        lastRollback = .deleteItem(id: created.id)

        return record(
            action: Action.createTask.rawValue,
            status: .success,
            message: "Created task '\(created.title)' in '\(database.name)'.",
            rollbackAvailable: true,
            metadata: "task_id=\(created.id.uuidString)"
        )
    }

    private func executeMoveTask(_ request: ActionRequest) -> ActionResult {
        guard let targetStatusRaw = request.targetStatus?.trimmingCharacters(in: .whitespacesAndNewlines),
              !targetStatusRaw.isEmpty else {
            return record(
                action: Action.moveTask.rawValue,
                status: .failed,
                message: "target_status is required for move_task.",
                rollbackAvailable: lastRollback != nil,
                metadata: ""
            )
        }

        let resolution = resolveTask(taskID: request.taskID, query: request.taskQuery)
        guard let task = resolution.item else {
            return record(
                action: Action.moveTask.rawValue,
                status: .failed,
                message: "Task not found.",
                rollbackAvailable: lastRollback != nil,
                metadata: request.taskQuery ?? request.taskID?.uuidString ?? ""
            )
        }

        let metadata = "task_id=\(task.id.uuidString),target_status=\(targetStatusRaw)"
        if resolution.isAmbiguous {
            let token = UUID().uuidString
            pendingConfirmation = PendingConfirmation(
                token: token,
                action: .moveTask,
                metadata: metadata,
                payload: .moveTask(taskID: task.id, targetStatus: targetStatusRaw)
            )
            return record(
                action: Action.moveTask.rawValue,
                status: .pendingConfirmation,
                message: "Ambiguous task match. Confirmation required to move '\(task.displayTitle)'.",
                rollbackAvailable: lastRollback != nil,
                metadata: metadata,
                requiresConfirmation: true,
                confirmationToken: token
            )
        }

        return performMoveTask(taskID: task.id, targetStatus: targetStatusRaw, metadata: metadata)
    }

    private func performMoveTask(taskID: UUID, targetStatus: String, metadata: String) -> ActionResult {
        guard let item = workspaceStorage.item(withID: taskID) else {
            return record(
                action: Action.moveTask.rawValue,
                status: .failed,
                message: "Task disappeared before move.",
                rollbackAvailable: lastRollback != nil,
                metadata: metadata
            )
        }

        guard let resolvedStatus = resolveStatus(for: item, rawStatus: targetStatus) else {
            return record(
                action: Action.moveTask.rawValue,
                status: .failed,
                message: "Target status '\(targetStatus)' not found.",
                rollbackAvailable: lastRollback != nil,
                metadata: metadata
            )
        }

        lastRollback = .restoreItem(snapshot: item)
        workspaceStorage.moveItem(item.id, toStatus: resolvedStatus)
        return record(
            action: Action.moveTask.rawValue,
            status: .success,
            message: "Moved '\(item.displayTitle)' to '\(resolvedStatus)'.",
            rollbackAvailable: true,
            metadata: metadata
        )
    }

    private func executeDeleteItem(_ request: ActionRequest) -> ActionResult {
        let resolvedItem: WorkspaceItem?
        if let itemID = request.itemID {
            resolvedItem = workspaceStorage.item(withID: itemID)
        } else {
            resolvedItem = resolveItem(query: request.itemQuery)
        }

        guard let item = resolvedItem else {
            return record(
                action: Action.deleteItem.rawValue,
                status: .failed,
                message: "Item not found for deletion.",
                rollbackAvailable: lastRollback != nil,
                metadata: request.itemQuery ?? request.itemID?.uuidString ?? ""
            )
        }

        let token = UUID().uuidString
        let metadata = "item_id=\(item.id.uuidString),title=\(item.displayTitle)"
        pendingConfirmation = PendingConfirmation(
            token: token,
            action: .deleteItem,
            metadata: metadata,
            payload: .deleteItem(snapshot: item)
        )

        return record(
            action: Action.deleteItem.rawValue,
            status: .pendingConfirmation,
            message: "Deletion requires confirmation for '\(item.displayTitle)'.",
            rollbackAvailable: lastRollback != nil,
            metadata: metadata,
            requiresConfirmation: true,
            confirmationToken: token
        )
    }

    private func resolveTask(taskID: UUID?, query: String?) -> (item: WorkspaceItem?, isAmbiguous: Bool) {
        if let taskID, let item = workspaceStorage.item(withID: taskID), item.itemType == .task, !item.isArchived {
            return (item, false)
        }

        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !trimmedQuery.isEmpty else { return (nil, false) }

        let scored = workspaceStorage.items
            .filter { $0.itemType == .task && !$0.isArchived }
            .map { ($0, scoreMatch(text: $0.title.lowercased(), query: trimmedQuery)) }
            .filter { $0.1 > 0 }
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.updatedAt > $1.0.updatedAt
                }
                return $0.1 > $1.1
            }

        guard let best = scored.first else { return (nil, false) }
        let secondScore = scored.count > 1 ? scored[1].1 : 0
        let ambiguous = secondScore > 0 && abs(best.1 - secondScore) < 0.1
        return (best.0, ambiguous)
    }

    private func resolveItem(query: String?) -> WorkspaceItem? {
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !trimmedQuery.isEmpty else { return nil }

        return workspaceStorage.items
            .filter { !$0.isArchived }
            .map { ($0, scoreMatch(text: $0.title.lowercased(), query: trimmedQuery)) }
            .filter { $0.1 > 0 }
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.updatedAt > $1.0.updatedAt
                }
                return $0.1 > $1.1
            }
            .first?.0
    }

    private func resolveStatus(for item: WorkspaceItem, rawStatus: String) -> String? {
        let normalized = rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if let databaseID = item.workspaceID,
           let database = workspaceStorage.database(withID: databaseID),
           !database.kanbanColumns.isEmpty {
            let match = database.kanbanColumns
                .map { ($0.name, scoreMatch(text: $0.name.lowercased(), query: normalized)) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
                .first?.0
            return match
        }

        return rawStatus.capitalized
    }

    private func scoreMatch(text: String, query: String) -> Double {
        if text == query { return 1.0 }
        if text.hasPrefix(query) { return 0.9 }
        if text.contains(query) { return 0.7 }

        let queryTokens = Set(query.split(separator: " ").map(String.init))
        let textTokens = Set(text.split(separator: " ").map(String.init))
        guard !queryTokens.isEmpty else { return 0 }
        let overlap = queryTokens.intersection(textTokens).count
        if overlap == 0 { return 0 }
        return 0.4 + (Double(overlap) / Double(queryTokens.count)) * 0.2
    }

    private func record(
        action: String,
        status: AuditStatus,
        message: String,
        rollbackAvailable: Bool,
        metadata: String,
        requiresConfirmation: Bool = false,
        confirmationToken: String? = nil
    ) -> ActionResult {
        let audit = AuditEntry(
            id: UUID(),
            timestamp: Date(),
            action: action,
            status: status,
            message: message,
            rollbackAvailable: rollbackAvailable,
            metadata: metadata
        )
        auditTrail.append(audit)
        if auditTrail.count > maxAuditEntries {
            auditTrail.removeFirst(auditTrail.count - maxAuditEntries)
        }

        return ActionResult(
            success: status == .success || status == .rolledBack,
            message: message,
            requiresConfirmation: requiresConfirmation,
            confirmationToken: confirmationToken,
            rollbackAvailable: rollbackAvailable,
            auditID: audit.id
        )
    }

    private func formatToolResult(_ result: ActionResult) -> String {
        if result.requiresConfirmation, let token = result.confirmationToken {
            return """
            ⚠️ Confirmation required.
            token: \(token)
            message: \(result.message)
            """
        }

        let status = result.success ? "✅" : "❌"
        let rollback = result.rollbackAvailable ? "yes" : "no"
        return "\(status) \(result.message)\nrollback_available: \(rollback)\naudit_id: \(result.auditID.uuidString)"
    }
}
