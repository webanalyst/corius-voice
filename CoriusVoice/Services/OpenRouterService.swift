import Foundation

// MARK: - OpenRouter Error

enum OpenRouterError: LocalizedError {
    case noApiKey
    case invalidApiKey
    case invalidResponse
    case networkError(Error)
    case apiError(String)
    case decodingError(Error)
    case rateLimited
    case modelNotAvailable

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "OpenRouter API key is not configured. Please add your API key in Settings."
        case .invalidApiKey:
            return "Invalid OpenRouter API key. Please check your API key in Settings."
        case .invalidResponse:
            return "Received an invalid response from OpenRouter."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let message):
            return "API error: \(message)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .rateLimited:
            return "Rate limited. Please wait a moment and try again."
        case .modelNotAvailable:
            return "The selected model is not available. Please choose a different model."
        }
    }
}

// MARK: - OpenRouter Service

class OpenRouterService: ObservableObject {
    static let shared = OpenRouterService()

    // API endpoints
    private let baseURL = "https://openrouter.ai/api/v1"
    private let modelsEndpoint = "/models"
    private let chatEndpoint = "/chat/completions"

    // Cache
    @Published var cachedModels: [OpenRouterModel] = []
    @Published var isLoadingModels = false
    @Published var isGeneratingSummary = false
    @Published var streamingContent = ""

    private let modelsCacheKey = "OpenRouterModelsCache"
    private var urlSession: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config)

        // Load cached models on init
        loadCachedModels()
    }

    // MARK: - Models API

    /// Fetch available models from OpenRouter API
    func fetchModels() async throws -> [OpenRouterModel] {
        await MainActor.run {
            isLoadingModels = true
        }

        defer {
            Task { @MainActor in
                isLoadingModels = false
            }
        }

        guard let url = URL(string: baseURL + modelsEndpoint) else {
            throw OpenRouterError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenRouterError.invalidResponse
            }

            if httpResponse.statusCode == 429 {
                throw OpenRouterError.rateLimited
            }

            if httpResponse.statusCode != 200 {
                if let errorResponse = try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data) {
                    throw OpenRouterError.apiError(errorResponse.error.message)
                }
                throw OpenRouterError.invalidResponse
            }

            let modelsResponse = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)

            // Filter to only include models suitable for summarization
            let filteredModels = modelsResponse.data.filter { model in
                // Exclude image-only, embedding, and audio models
                let id = model.id.lowercased()
                return !id.contains("vision") &&
                       !id.contains("embedding") &&
                       !id.contains("whisper") &&
                       !id.contains("tts") &&
                       !id.contains("dall-e") &&
                       !id.contains("stable-diffusion") &&
                       model.context_length >= 4000  // Require reasonable context
            }

            // Sort by provider and then by name
            let sortedModels = filteredModels.sorted { a, b in
                if a.provider == b.provider {
                    return a.name < b.name
                }
                return a.provider < b.provider
            }

            // Cache the models
            cacheModels(sortedModels)

            await MainActor.run {
                self.cachedModels = sortedModels
            }

            return sortedModels
        } catch let error as OpenRouterError {
            throw error
        } catch {
            throw OpenRouterError.networkError(error)
        }
    }

    /// Get models grouped by provider
    func modelsGroupedByProvider() -> [String: [OpenRouterModel]] {
        Dictionary(grouping: cachedModels, by: { $0.providerDisplayName })
    }

    // MARK: - Chat Completions API

    /// Generate a summary for a recording session
    func generateSummary(
        session: RecordingSession,
        sessionType: SessionType,
        modelId: String,
        apiKey: String,
        outputLanguage: SummaryLanguage = .auto
    ) async throws -> SessionSummary {
        guard !apiKey.isEmpty else {
            throw OpenRouterError.noApiKey
        }

        await MainActor.run {
            isGeneratingSummary = true
            streamingContent = ""
        }

        defer {
            Task { @MainActor in
                isGeneratingSummary = false
            }
        }

        var promptBuilder = SummaryPromptBuilder(session: session, sessionType: sessionType)
        promptBuilder.outputLanguage = outputLanguage

        let request = OpenRouterChatRequest(
            model: modelId,
            messages: [
                .init(role: "system", content: promptBuilder.systemPrompt),
                .init(role: "user", content: promptBuilder.userPrompt)
            ],
            stream: false,
            maxTokens: 4096,
            temperature: 0.3
        )

        let response = try await sendChatRequest(request, apiKey: apiKey)

        guard let content = response.choices.first?.message?.content else {
            throw OpenRouterError.invalidResponse
        }

        return SessionSummary(
            modelUsed: modelId,
            sessionType: sessionType,
            markdownContent: content,
            promptTokens: response.usage?.prompt_tokens,
            completionTokens: response.usage?.completion_tokens,
            totalTokens: response.usage?.total_tokens
        )
    }

    /// Generate summary with streaming for real-time feedback
    func generateSummaryStreaming(
        session: RecordingSession,
        sessionType: SessionType,
        modelId: String,
        apiKey: String,
        outputLanguage: SummaryLanguage = .auto,
        onChunk: @escaping (String) -> Void
    ) async throws -> SessionSummary {
        guard !apiKey.isEmpty else {
            throw OpenRouterError.noApiKey
        }

        await MainActor.run {
            isGeneratingSummary = true
            streamingContent = ""
        }

        defer {
            Task { @MainActor in
                isGeneratingSummary = false
            }
        }

        var promptBuilder = SummaryPromptBuilder(session: session, sessionType: sessionType)
        promptBuilder.outputLanguage = outputLanguage

        guard let url = URL(string: baseURL + chatEndpoint) else {
            throw OpenRouterError.invalidResponse
        }

        let chatRequest = OpenRouterChatRequest(
            model: modelId,
            messages: [
                .init(role: "system", content: promptBuilder.systemPrompt),
                .init(role: "user", content: promptBuilder.userPrompt)
            ],
            stream: true,
            maxTokens: 4096,
            temperature: 0.3
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CoriusVoice/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("CoriusVoice", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONEncoder().encode(chatRequest)

        let (bytes, response) = try await urlSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw OpenRouterError.invalidApiKey
        }

        if httpResponse.statusCode == 429 {
            throw OpenRouterError.rateLimited
        }

        if httpResponse.statusCode != 200 {
            throw OpenRouterError.apiError("HTTP \(httpResponse.statusCode)")
        }

        var fullContent = ""
        var totalUsage: OpenRouterChatResponse.Usage?

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))

            if jsonString == "[DONE]" { break }

            guard let jsonData = jsonString.data(using: .utf8) else { continue }

            do {
                let chunk = try JSONDecoder().decode(OpenRouterChatResponse.self, from: jsonData)
                if let delta = chunk.choices.first?.delta?.content {
                    fullContent += delta
                    await MainActor.run {
                        streamingContent = fullContent
                    }
                    onChunk(delta)
                }
                if let usage = chunk.usage {
                    totalUsage = usage
                }
            } catch {
                // Skip malformed chunks
                continue
            }
        }

        return SessionSummary(
            modelUsed: modelId,
            sessionType: sessionType,
            markdownContent: fullContent,
            promptTokens: totalUsage?.prompt_tokens,
            completionTokens: totalUsage?.completion_tokens,
            totalTokens: totalUsage?.total_tokens
        )
    }

    /// Generate a concise title for a session based on its content
    /// - Parameters:
    ///   - session: The recording session
    ///   - summary: Optional summary content to use for better title generation
    ///   - modelId: The model to use
    ///   - apiKey: OpenRouter API key
    func generateSessionTitle(
        session: RecordingSession,
        summary: String? = nil,
        modelId: String,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw OpenRouterError.noApiKey
        }

        // Build content for title generation
        // Prefer summary if available (more concise), otherwise use transcript
        let contentForTitle: String
        if let summaryContent = summary, !summaryContent.isEmpty {
            // Use first part of summary
            contentForTitle = String(summaryContent.prefix(1500))
            print("[OpenRouter] 📝 Using summary for title generation (\(contentForTitle.count) chars)")
        } else {
            // Fall back to transcript
            let transcriptText = session.transcriptSegments
                .prefix(50)  // First 50 segments should be enough
                .map { $0.text }
                .joined(separator: " ")
            contentForTitle = String(transcriptText.prefix(2000))
            print("[OpenRouter] 📝 Using transcript for title generation (\(contentForTitle.count) chars)")
        }

        if contentForTitle.isEmpty {
            print("[OpenRouter] ⚠️ No content available for title generation")
            return "Untitled Session"
        }

        let systemPrompt = """
        You are a title generator. Generate a concise, descriptive title (3-8 words) for a recording session based on its content.

        Rules:
        - Output ONLY the title, nothing else
        - No quotes, no punctuation at the end
        - Be specific about the main topic
        - Use title case
        - Keep it professional and clear
        - If it's a meeting, include the main topic discussed
        - If it's an interview, mention the role or candidate name if known
        """

        let userPrompt = """
        Session type: \(session.sessionType.displayName)
        Duration: \(session.formattedDuration)

        Content:
        \(contentForTitle)

        Generate a title:
        """

        print("[OpenRouter] 🔄 Generating title with model: \(modelId)")

        let request = OpenRouterChatRequest(
            model: modelId,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ],
            stream: false,
            maxTokens: 50,  // Titles are short but give some margin
            temperature: 0.5
        )

        let response = try await sendChatRequest(request, apiKey: apiKey)

        guard let content = response.choices.first?.message?.content else {
            print("[OpenRouter] ⚠️ No content in response")
            throw OpenRouterError.invalidResponse
        }

        print("[OpenRouter] 📥 Raw title response: '\(content)'")

        // Clean up the title
        var cleanedTitle = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")

        // Remove common prefixes the model might add
        let prefixesToRemove = ["Title:", "title:", "Session Title:", "Generated Title:"]
        for prefix in prefixesToRemove {
            if cleanedTitle.hasPrefix(prefix) {
                cleanedTitle = String(cleanedTitle.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        print("[OpenRouter] ✅ Cleaned title: '\(cleanedTitle)'")

        // If model returned empty, try to extract title from summary
        if cleanedTitle.isEmpty, let summaryContent = summary {
            let extractedTitle = extractTitleFromSummary(summaryContent)
            print("[OpenRouter] 🔄 Fallback: extracted title from summary: '\(extractedTitle)'")
            return extractedTitle
        }

        return cleanedTitle.isEmpty ? "Untitled Session" : cleanedTitle
    }

    /// Extract a title from summary content as fallback
    private func extractTitleFromSummary(_ summary: String) -> String {
        let lines = summary.split(separator: "\n", omittingEmptySubsequences: true)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip markdown headers markers but use their content
            if trimmed.hasPrefix("## ") {
                let title = trimmed.replacingOccurrences(of: "## ", with: "")
                // Skip generic headers
                let genericHeaders = ["Summary", "Resumen", "Overview", "Key Points", "Action Items", "Puntos Clave"]
                if !genericHeaders.contains(where: { title.lowercased().contains($0.lowercased()) }) {
                    return String(title.prefix(60))
                }
            }

            // Look for topic/subject lines
            if trimmed.lowercased().hasPrefix("topic:") || trimmed.lowercased().hasPrefix("tema:") {
                let title = trimmed
                    .replacingOccurrences(of: "Topic:", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: "Tema:", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    return String(title.prefix(60))
                }
            }

            // Use first substantial non-header line as last resort
            if !trimmed.hasPrefix("#") && !trimmed.hasPrefix("-") && !trimmed.hasPrefix("*") && trimmed.count > 20 {
                // Take first sentence or first 50 chars
                if let dotIndex = trimmed.firstIndex(of: ".") {
                    let firstSentence = String(trimmed[..<dotIndex])
                    if firstSentence.count > 10 && firstSentence.count < 60 {
                        return firstSentence
                    }
                }
                return String(trimmed.prefix(50)) + "..."
            }
        }

        return "Untitled Session"
    }

    /// Test API connection with a simple request
    func testConnection(apiKey: String) async throws -> Bool {
        guard !apiKey.isEmpty else {
            throw OpenRouterError.noApiKey
        }

        let request = OpenRouterChatRequest(
            model: "openai/gpt-3.5-turbo",  // Use a cheap model for testing
            messages: [
                .init(role: "user", content: "Say 'OK' if you can read this.")
            ],
            stream: false,
            maxTokens: 10,
            temperature: 0
        )

        let response = try await sendChatRequest(request, apiKey: apiKey)
        return response.choices.first?.message?.content != nil
    }

    // MARK: - Private Methods

    private func sendChatRequest(
        _ chatRequest: OpenRouterChatRequest,
        apiKey: String
    ) async throws -> OpenRouterChatResponse {
        guard let url = URL(string: baseURL + chatEndpoint) else {
            throw OpenRouterError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("CoriusVoice/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("CoriusVoice", forHTTPHeaderField: "X-Title")

        do {
            request.httpBody = try JSONEncoder().encode(chatRequest)
        } catch {
            throw OpenRouterError.decodingError(error)
        }

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenRouterError.invalidResponse
            }

            if httpResponse.statusCode == 401 {
                throw OpenRouterError.invalidApiKey
            }

            if httpResponse.statusCode == 429 {
                throw OpenRouterError.rateLimited
            }

            if httpResponse.statusCode != 200 {
                if let errorResponse = try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data) {
                    throw OpenRouterError.apiError(errorResponse.error.message)
                }
                throw OpenRouterError.apiError("HTTP \(httpResponse.statusCode)")
            }

            do {
                return try JSONDecoder().decode(OpenRouterChatResponse.self, from: data)
            } catch {
                throw OpenRouterError.decodingError(error)
            }
        } catch let error as OpenRouterError {
            throw error
        } catch {
            throw OpenRouterError.networkError(error)
        }
    }

    // MARK: - Caching

    private func loadCachedModels() {
        guard let data = UserDefaults.standard.data(forKey: modelsCacheKey),
              let cached = try? JSONDecoder().decode(CachedOpenRouterModels.self, from: data),
              cached.isValid else {
            return
        }
        cachedModels = cached.models
    }

    private func cacheModels(_ models: [OpenRouterModel]) {
        let cached = CachedOpenRouterModels(models: models, cachedAt: Date())
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: modelsCacheKey)
        }
    }

    /// Clear the models cache
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: modelsCacheKey)
        cachedModels = []
    }

    /// Get a specific model by ID
    func getModel(byId id: String) -> OpenRouterModel? {
        cachedModels.first { $0.id == id }
    }
}
