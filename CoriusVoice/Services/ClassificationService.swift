import Foundation

// MARK: - Classification Result

struct ClassificationResult: Codable {
    let suggestedFolderID: String
    let confidence: Double      // 0.0 - 1.0
    let reasoning: String
}

// MARK: - Classification Error

enum ClassificationError: LocalizedError {
    case noApiKey
    case noFolders
    case noContent
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "OpenRouter API key is not configured. Please add your API key in Settings."
        case .noFolders:
            return "No folders available for classification."
        case .noContent:
            return "Session has no content to classify."
        case .invalidResponse:
            return "Failed to parse classification response."
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}

// MARK: - Classification Service

class ClassificationService: ObservableObject {
    static let shared = ClassificationService()

    @Published var isClassifying = false

    private let storage = StorageService.shared
    private let openRouter = OpenRouterService.shared

    private init() {}

    // MARK: - Single Session Classification

    /// Classify a single session and return suggested folder
    func classifySession(
        _ session: RecordingSession,
        folders: [Folder],
        apiKey: String,
        modelId: String
    ) async throws -> ClassificationResult {
        guard !apiKey.isEmpty else {
            throw ClassificationError.noApiKey
        }

        // Filter out system folders for suggestions (we'll suggest user folders)
        let userFolders = folders.filter { !$0.isInbox }
        guard !userFolders.isEmpty else {
            throw ClassificationError.noFolders
        }

        // Build content for classification
        let contentSummary = buildContentSummary(for: session)
        guard !contentSummary.isEmpty else {
            throw ClassificationError.noContent
        }

        // Build the prompt
        let prompt = buildClassificationPrompt(
            sessionContent: contentSummary,
            sessionType: session.sessionType,
            folders: userFolders
        )

        // Make the API request
        let response = try await makeClassificationRequest(
            prompt: prompt,
            apiKey: apiKey,
            modelId: modelId
        )

        return response
    }

    /// Classify a session and update it with the suggestion
    func classifyAndUpdateSession(
        sessionID: UUID,
        apiKey: String,
        modelId: String
    ) async throws {
        await MainActor.run {
            isClassifying = true
        }

        defer {
            Task { @MainActor in
                isClassifying = false
            }
        }

        var sessions = storage.loadSessions()
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else {
            return
        }

        let session = sessions[index]

        // Don't classify if already classified
        guard !session.isClassified else {
            return
        }

        let folders = storage.loadFolders()

        do {
            let result = try await classifySession(
                session,
                folders: folders,
                apiKey: apiKey,
                modelId: modelId
            )

            // Update session with suggestion
            if let folderUUID = UUID(uuidString: result.suggestedFolderID) {
                sessions[index].aiSuggestedFolderID = folderUUID
                sessions[index].aiClassificationConfidence = result.confidence
                storage.saveSessions(sessions)

                print("[ClassificationService] Classified session '\(session.displayTitle)' -> folder: \(result.suggestedFolderID), confidence: \(String(format: "%.1f%%", result.confidence * 100))")
            }
        } catch {
            print("[ClassificationService] Failed to classify session: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Batch Classification

    /// Classify all unclassified sessions in the INBOX
    func classifyUnclassifiedSessions(
        apiKey: String,
        modelId: String
    ) async throws -> [UUID: ClassificationResult] {
        await MainActor.run {
            isClassifying = true
        }

        defer {
            Task { @MainActor in
                isClassifying = false
            }
        }

        guard !apiKey.isEmpty else {
            throw ClassificationError.noApiKey
        }

        let sessions = storage.loadSessions()
        let folders = storage.loadFolders()

        // Get unclassified sessions (in INBOX and not yet classified)
        let unclassified = sessions.filter { $0.folderID == nil && !$0.isClassified }

        var results: [UUID: ClassificationResult] = [:]

        for session in unclassified {
            do {
                let result = try await classifySession(
                    session,
                    folders: folders,
                    apiKey: apiKey,
                    modelId: modelId
                )

                results[session.id] = result

                // Update session with suggestion
                if let folderUUID = UUID(uuidString: result.suggestedFolderID) {
                    var allSessions = storage.loadSessions()
                    if let idx = allSessions.firstIndex(where: { $0.id == session.id }) {
                        allSessions[idx].aiSuggestedFolderID = folderUUID
                        allSessions[idx].aiClassificationConfidence = result.confidence
                        storage.saveSessions(allSessions)
                    }
                }

                // Small delay between API calls to avoid rate limiting
                try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 second
            } catch {
                print("[ClassificationService] Failed to classify session '\(session.displayTitle)': \(error.localizedDescription)")
                continue
            }
        }

        return results
    }

    // MARK: - Private Methods

    private func buildContentSummary(for session: RecordingSession) -> String {
        var content = ""

        // Add title
        if let title = session.title {
            content += "Title: \(title)\n"
        }

        // Add session type
        content += "Type: \(session.sessionType.displayName)\n"

        // Add summary if available
        if let summary = session.summary {
            // Use first 500 chars of summary
            let summaryPreview = String(summary.markdownContent.prefix(500))
            content += "Summary: \(summaryPreview)\n"
        }

        // Add transcript excerpt
        let transcriptText = session.transcriptSegments
            .prefix(30)  // First 30 segments
            .map { $0.text }
            .joined(separator: " ")

        if !transcriptText.isEmpty {
            // Take first 1000 chars of transcript
            let transcriptPreview = String(transcriptText.prefix(1000))
            content += "Transcript excerpt: \(transcriptPreview)\n"
        }

        return content
    }

    private func buildClassificationPrompt(
        sessionContent: String,
        sessionType: SessionType,
        folders: [Folder]
    ) -> String {
        // Build folder descriptions for the prompt
        var folderDescriptions = ""
        for folder in folders {
            folderDescriptions += """
            - ID: \(folder.id.uuidString)
              Name: \(folder.name)
              Keywords: \(folder.classificationKeywords.joined(separator: ", "))
              Description: \(folder.classificationDescription ?? "General folder")

            """
        }

        return """
        You are a classification assistant. Analyze the recording session content below and determine which folder it belongs to.

        Available folders:
        \(folderDescriptions)

        Session content:
        \(sessionContent)

        Instructions:
        1. Analyze the session content (title, type, summary, transcript)
        2. Match it to the most appropriate folder based on keywords, description, and content
        3. Provide a confidence score (0.0 to 1.0) based on how well it matches
        4. Explain your reasoning briefly

        Respond ONLY with valid JSON in this exact format (no markdown, no extra text):
        {"suggestedFolderID": "uuid-string", "confidence": 0.85, "reasoning": "Brief explanation"}

        If no folder is a good match, use confidence below 0.5.
        """
    }

    private func makeClassificationRequest(
        prompt: String,
        apiKey: String,
        modelId: String
    ) async throws -> ClassificationResult {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw ClassificationError.invalidResponse
        }

        let requestBody: [String: Any] = [
            "model": modelId,
            "messages": [
                ["role": "system", "content": "You are a JSON classification assistant. Always respond with valid JSON only."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 200,
            "temperature": 0.3
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CoriusVoice/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("CoriusVoice", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClassificationError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            throw ClassificationError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Parse the response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ClassificationError.invalidResponse
        }

        // Clean up the content (remove markdown code blocks if present)
        var cleanContent = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse the JSON response
        guard let jsonData = cleanContent.data(using: .utf8),
              let result = try? JSONDecoder().decode(ClassificationResult.self, from: jsonData) else {
            throw ClassificationError.invalidResponse
        }

        return result
    }
}

// MARK: - Folder Classification Extensions

extension Folder {
    /// Check if session content matches this folder's keywords
    func matches(content: String) -> Bool {
        let lowerContent = content.lowercased()
        return classificationKeywords.contains { keyword in
            lowerContent.contains(keyword.lowercased())
        }
    }
}
