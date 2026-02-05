import Foundation

// MARK: - Chat Role

enum ChatRole: String, Codable {
    case system
    case user
    case assistant
    case tool
}

// MARK: - Chat Message

struct ChatMessage: Codable, Identifiable {
    let id: UUID
    let role: ChatRole
    var content: String?
    let createdAt: Date
    var toolCalls: [ToolCall]?     // For assistant with tool calls
    var toolCallId: String?        // For tool responses
    var toolName: String?          // Name of the tool that was called

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String? = nil,
        createdAt: Date = Date(),
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        toolName: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.toolName = toolName
    }

    /// Create a system message
    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }

    /// Create a user message
    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    /// Create an assistant message
    static func assistant(_ content: String, toolCalls: [ToolCall]? = nil) -> ChatMessage {
        ChatMessage(role: .assistant, content: content, toolCalls: toolCalls)
    }

    /// Create a tool response message
    static func tool(callId: String, name: String, content: String) -> ChatMessage {
        ChatMessage(role: .tool, content: content, toolCallId: callId, toolName: name)
    }
}

// MARK: - Tool Call

struct ToolCall: Codable, Identifiable {
    let id: String
    let type: String
    let function: ToolFunction

    init(id: String, type: String = "function", function: ToolFunction) {
        self.id = id
        self.type = type
        self.function = function
    }
}

struct ToolFunction: Codable {
    let name: String
    let arguments: String  // JSON string

    /// Parse arguments as a specific type
    func parseArguments<T: Decodable>() -> T? {
        guard let data = arguments.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Speaker Conversation

struct SpeakerConversation: Codable, Identifiable {
    let id: UUID
    let speakerId: UUID
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date
    var estimatedTokenCount: Int

    init(
        id: UUID = UUID(),
        speakerId: UUID,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        estimatedTokenCount: Int = 0
    ) {
        self.id = id
        self.speakerId = speakerId
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.estimatedTokenCount = estimatedTokenCount
    }

    /// Add a message and update token count
    mutating func addMessage(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = Date()
        updateTokenCount()
    }

    /// Estimate token count (roughly 4 chars per token)
    mutating func updateTokenCount() {
        let totalChars = messages.compactMap { $0.content }.joined().count
        estimatedTokenCount = totalChars / 4
    }

    /// Get messages formatted for API
    var apiMessages: [[String: Any]] {
        messages.compactMap { message -> [String: Any]? in
            var dict: [String: Any] = ["role": message.role.rawValue]

            if let content = message.content {
                dict["content"] = content
            }

            if let toolCalls = message.toolCalls {
                dict["tool_calls"] = toolCalls.map { call in
                    [
                        "id": call.id,
                        "type": call.type,
                        "function": [
                            "name": call.function.name,
                            "arguments": call.function.arguments
                        ]
                    ]
                }
            }

            if let toolCallId = message.toolCallId {
                dict["tool_call_id"] = toolCallId
            }

            if let toolName = message.toolName {
                dict["name"] = toolName
            }

            return dict
        }
    }
}

// MARK: - Tool Definitions

struct ChatTool {
    let name: String
    let description: String
    let parameters: [String: Any]

    var asDictionary: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters
            ]
        ]
    }

    // MARK: - Predefined Tools

    static let searchSessions = ChatTool(
        name: "search_sessions",
        description: "Search for recording sessions where this speaker participated. Use this to find sessions by topic, date range, or session type.",
        parameters: [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Optional search query to filter sessions by title or content"
                ],
                "session_type": [
                    "type": "string",
                    "enum": ["meeting", "interview", "lecture", "brainstorm", "standup", "personal", "call"],
                    "description": "Filter by session type"
                ],
                "date_from": [
                    "type": "string",
                    "description": "Start date filter (ISO 8601 format)"
                ],
                "date_to": [
                    "type": "string",
                    "description": "End date filter (ISO 8601 format)"
                ],
                "limit": [
                    "type": "integer",
                    "description": "Maximum number of results to return (default: 10)"
                ]
            ],
            "required": []
        ]
    )

    static let getTranscript = ChatTool(
        name: "get_transcript",
        description: "Get the transcript of a specific session. Can filter to show only segments from a specific speaker.",
        parameters: [
            "type": "object",
            "properties": [
                "session_id": [
                    "type": "string",
                    "description": "UUID of the session to get transcript for"
                ],
                "speaker_only": [
                    "type": "boolean",
                    "description": "If true, only return segments from this speaker"
                ],
                "max_segments": [
                    "type": "integer",
                    "description": "Maximum number of segments to return (default: 50)"
                ]
            ],
            "required": ["session_id"]
        ]
    )

    static let getSummary = ChatTool(
        name: "get_summary",
        description: "Get the AI-generated summary of a specific session.",
        parameters: [
            "type": "object",
            "properties": [
                "session_id": [
                    "type": "string",
                    "description": "UUID of the session to get summary for"
                ]
            ],
            "required": ["session_id"]
        ]
    )

    static let getSpeakerInfo = ChatTool(
        name: "get_speaker_info",
        description: "Get detailed information and statistics about this speaker.",
        parameters: [
            "type": "object",
            "properties": [:],
            "required": []
        ]
    )

    /// All available tools for speaker chat
    static var allTools: [[String: Any]] {
        [
            searchSessions.asDictionary,
            getTranscript.asDictionary,
            getSummary.asDictionary,
            getSpeakerInfo.asDictionary
        ]
    }
}

// MARK: - Tool Arguments

struct SearchSessionsArgs: Codable {
    var query: String?
    var session_type: String?
    var date_from: String?
    var date_to: String?
    var limit: Int?
}

struct GetTranscriptArgs: Codable {
    var session_id: String
    var speaker_only: Bool?
    var max_segments: Int?
}

struct GetSummaryArgs: Codable {
    var session_id: String
}
