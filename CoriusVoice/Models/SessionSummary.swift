import Foundation

// NOTE: SessionType is defined in Settings.swift to avoid circular dependencies

// MARK: - Session Summary

struct SessionSummary: Codable {
    let generatedAt: Date
    let modelUsed: String
    let sessionType: SessionType
    let markdownContent: String

    // Token usage for cost tracking
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?

    init(
        generatedAt: Date = Date(),
        modelUsed: String,
        sessionType: SessionType,
        markdownContent: String,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil
    ) {
        self.generatedAt = generatedAt
        self.modelUsed = modelUsed
        self.sessionType = sessionType
        self.markdownContent = markdownContent
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }

    // MARK: - Computed Properties

    /// Time ago string for display
    var timeAgo: String {
        let interval = Date().timeIntervalSince(generatedAt)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }

    /// Formatted generation date
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: generatedAt)
    }

    /// Extract overview from markdown (first paragraph after "## Summary" or similar)
    var overview: String? {
        let patterns = ["## Summary", "## Candidate Overview", "## Session Topic", "## Topic"]
        for pattern in patterns {
            if let range = markdownContent.range(of: pattern) {
                let afterHeader = String(markdownContent[range.upperBound...])
                let lines = afterHeader.split(separator: "\n", omittingEmptySubsequences: false)

                // Find first non-empty line that's not a header
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("-") {
                        return trimmed
                    }
                }
            }
        }
        return nil
    }

    /// Extract action items from markdown
    var actionItems: [ActionItem] {
        var items: [ActionItem] = []
        let lines = markdownContent.split(separator: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match lines like "- [ ] Task (@Person, deadline)"
            if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") {
                let completed = trimmed.hasPrefix("- [x]")
                let content = trimmed
                    .replacingOccurrences(of: "- [ ] ", with: "")
                    .replacingOccurrences(of: "- [x] ", with: "")

                // Extract assignee if present (@Person)
                var assignee: String?
                if let atRange = content.range(of: "@") {
                    let afterAt = String(content[atRange.upperBound...])
                    if let spaceRange = afterAt.range(of: " ") ?? afterAt.range(of: ",") ?? afterAt.range(of: ")") {
                        assignee = String(afterAt[..<spaceRange.lowerBound])
                    } else {
                        assignee = afterAt
                    }
                }

                let item = ActionItem(
                    description: content,
                    assignee: assignee,
                    deadline: nil,
                    isCompleted: completed
                )
                items.append(item)
            }
        }

        return items
    }

    /// Extract key points from markdown (bullet points under key sections)
    var keyPoints: [String] {
        var points: [String] = []
        let patterns = ["## Key Discussion Points", "## Key Points", "## Key Concepts", "## Main Topics"]

        for pattern in patterns {
            if let range = markdownContent.range(of: pattern) {
                let afterHeader = String(markdownContent[range.upperBound...])
                let lines = afterHeader.split(separator: "\n", omittingEmptySubsequences: false)

                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("##") {
                        break // Stop at next section
                    }
                    if trimmed.hasPrefix("- ") && !trimmed.hasPrefix("- [ ]") {
                        let point = trimmed.replacingOccurrences(of: "- ", with: "")
                        points.append(point)
                    }
                }

                if !points.isEmpty { break }
            }
        }

        return points
    }
}

// MARK: - Action Item

struct ActionItem: Codable, Identifiable {
    let id: UUID
    let description: String
    let assignee: String?
    let deadline: String?
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        description: String,
        assignee: String? = nil,
        deadline: String? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.description = description
        self.assignee = assignee
        self.deadline = deadline
        self.isCompleted = isCompleted
    }
}

// MARK: - Summary Output Language

enum SummaryLanguage: String, Codable, CaseIterable, Identifiable {
    case auto = "auto"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case russian = "ru"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto (same as transcript)"
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        case .dutch: return "Nederlands"
        case .russian: return "Русский"
        case .chinese: return "中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }

    var flag: String {
        switch self {
        case .auto: return "🌍"
        case .english: return "🇺🇸"
        case .spanish: return "🇪🇸"
        case .french: return "🇫🇷"
        case .german: return "🇩🇪"
        case .italian: return "🇮🇹"
        case .portuguese: return "🇵🇹"
        case .dutch: return "🇳🇱"
        case .russian: return "🇷🇺"
        case .chinese: return "🇨🇳"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        }
    }

    var languageInstruction: String? {
        switch self {
        case .auto: return nil
        case .english: return "Write the summary in English."
        case .spanish: return "Escribe el resumen en español."
        case .french: return "Rédigez le résumé en français."
        case .german: return "Schreiben Sie die Zusammenfassung auf Deutsch."
        case .italian: return "Scrivi il riassunto in italiano."
        case .portuguese: return "Escreva o resumo em português."
        case .dutch: return "Schrijf de samenvatting in het Nederlands."
        case .russian: return "Напишите резюме на русском языке."
        case .chinese: return "用中文写摘要。"
        case .japanese: return "日本語で要約を書いてください。"
        case .korean: return "한국어로 요약을 작성하세요."
        }
    }
}

// MARK: - Summary Prompt Builder

struct SummaryPromptBuilder {
    let session: RecordingSession
    let sessionType: SessionType
    var outputLanguage: SummaryLanguage = .auto

    /// Build the system prompt for summarization
    var systemPrompt: String {
        var prompt = """
        You are an expert session summarizer. Your task is to analyze transcripts and generate clear, actionable summaries in Markdown format.

        ## Critical Guidelines:

        ### Timestamp References
        - ALWAYS include timestamps in parentheses format (MM:SS) when referencing specific moments
        - Timestamps should point to when the topic was discussed in the transcript
        - Example: "Rocío solicitó el curso avanzado y el de copa pero no recibió acceso (01:15)"
        - Each note and action item MUST have at least one timestamp reference

        ### Structure
        - Use the exact structure provided
        - Be concise but comprehensive
        - Group related topics under clear headings
        - Extract actionable items with assignees when mentioned

        ### Action Items Format
        - Group action items by assignee (person's name)
        - Use "Unassigned" for tasks without a clear owner
        - Each action item must include a timestamp reference
        - Format: "Person must do X (MM:SS)"

        ### Writing Style
        - Write in professional, clear language
        - Use speaker names when available
        - Be specific about what was discussed
        """

        if let languageInstruction = outputLanguage.languageInstruction {
            prompt += "\n\n### Language\n- IMPORTANT: \(languageInstruction)"
        }

        return prompt
    }

    /// Build the user prompt with transcript and metadata
    var userPrompt: String {
        // Build speaker list
        let speakerList = session.speakers.isEmpty
            ? "Unknown"
            : session.speakers.map { $0.displayName }.joined(separator: ", ")

        // Build transcript text with speaker labels
        let transcriptText = session.transcriptSegments
            .filter { $0.isFinal }
            .map { segment -> String in
                let speaker = session.speaker(for: segment.speakerID)?.displayName ?? "Speaker"
                let timestamp = formatTimestamp(segment.timestamp)
                return "[\(timestamp)] \(speaker): \(segment.text)"
            }
            .joined(separator: "\n")

        return """
        **Session Type:** \(sessionType.displayName)
        **Duration:** \(session.formattedDuration)
        **Participants:** \(speakerList)

        \(sessionType.promptInstructions)

        **Output the summary using this exact structure:**

        \(sessionType.templateStructure)

        ---

        **TRANSCRIPT:**

        \(transcriptText)
        """
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
