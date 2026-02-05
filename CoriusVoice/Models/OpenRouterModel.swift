import Foundation

// MARK: - OpenRouter Models Response

struct OpenRouterModelsResponse: Codable {
    let data: [OpenRouterModel]
}

// MARK: - OpenRouter Model

struct OpenRouterModel: Codable, Identifiable {
    let id: String                    // "anthropic/claude-3.5-sonnet"
    let name: String                  // "Claude 3.5 Sonnet"
    let context_length: Int           // 200000
    let pricing: Pricing
    let top_provider: TopProvider?

    struct Pricing: Codable {
        let prompt: String            // "0.000003" per token
        let completion: String        // "0.000015" per token
    }

    struct TopProvider: Codable {
        let is_moderated: Bool?
    }

    // MARK: - Computed Properties

    /// Provider name extracted from model ID (e.g., "anthropic" from "anthropic/claude-3.5-sonnet")
    var provider: String {
        let components = id.split(separator: "/")
        return components.first.map(String.init) ?? "unknown"
    }

    /// Display name for the provider
    var providerDisplayName: String {
        switch provider.lowercased() {
        case "anthropic": return "Anthropic"
        case "openai": return "OpenAI"
        case "google": return "Google"
        case "meta-llama", "meta": return "Meta"
        case "mistralai", "mistral": return "Mistral"
        case "cohere": return "Cohere"
        case "perplexity": return "Perplexity"
        case "deepseek": return "DeepSeek"
        case "qwen": return "Qwen"
        default: return provider.capitalized
        }
    }

    /// Price per 1 million input tokens
    var promptPricePerMillion: Double {
        guard let price = Double(pricing.prompt) else { return 0 }
        return price * 1_000_000
    }

    /// Price per 1 million output tokens
    var completionPricePerMillion: Double {
        guard let price = Double(pricing.completion) else { return 0 }
        return price * 1_000_000
    }

    /// Formatted input price per million tokens
    var formattedPromptPrice: String {
        let price = promptPricePerMillion
        if price >= 1 {
            return String(format: "$%.2f", price)
        } else if price >= 0.01 {
            return String(format: "$%.3f", price)
        } else {
            return String(format: "$%.4f", price)
        }
    }

    /// Formatted output price per million tokens
    var formattedCompletionPrice: String {
        let price = completionPricePerMillion
        if price >= 1 {
            return String(format: "$%.2f", price)
        } else if price >= 0.01 {
            return String(format: "$%.3f", price)
        } else {
            return String(format: "$%.4f", price)
        }
    }

    /// Formatted context length (e.g., "200k")
    var formattedContextLength: String {
        if context_length >= 1_000_000 {
            return "\(context_length / 1_000_000)M"
        } else if context_length >= 1000 {
            return "\(context_length / 1000)k"
        }
        return "\(context_length)"
    }

    /// Price tier based on average cost
    var tier: ModelTier {
        let avgPrice = (promptPricePerMillion + completionPricePerMillion) / 2
        if avgPrice > 10 {
            return .alto
        } else if avgPrice >= 1 {
            return .medio
        } else {
            return .bajo
        }
    }
}

// MARK: - Model Tier

enum ModelTier: String, CaseIterable {
    case alto = "ALTO"
    case medio = "MEDIO"
    case bajo = "BAJO"

    var displayName: String { rawValue }

    var color: String {
        switch self {
        case .alto: return "#EF4444"    // Red
        case .medio: return "#F59E0B"   // Yellow
        case .bajo: return "#10B981"    // Green
        }
    }
}

// MARK: - OpenRouter Chat Request

struct OpenRouterChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let max_tokens: Int?
    let temperature: Double?

    struct ChatMessage: Codable {
        let role: String  // "system", "user", "assistant"
        let content: String
    }

    init(model: String, messages: [ChatMessage], stream: Bool = false, maxTokens: Int? = nil, temperature: Double? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.max_tokens = maxTokens
        self.temperature = temperature
    }
}

// MARK: - OpenRouter Chat Response

struct OpenRouterChatResponse: Codable {
    let id: String?
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Codable {
        let index: Int
        let message: Message?
        let delta: Delta?
        let finish_reason: String?

        struct Message: Codable {
            let role: String
            let content: String
        }

        struct Delta: Codable {
            let role: String?
            let content: String?
        }
    }

    struct Usage: Codable {
        let prompt_tokens: Int
        let completion_tokens: Int
        let total_tokens: Int
    }
}

// MARK: - OpenRouter Error Response

struct OpenRouterErrorResponse: Codable {
    let error: ErrorDetail

    struct ErrorDetail: Codable {
        let message: String
        let type: String?
        let code: String?
    }
}

// MARK: - Cached Models

struct CachedOpenRouterModels: Codable {
    let models: [OpenRouterModel]
    let cachedAt: Date

    /// Check if cache is still valid (24 hours)
    var isValid: Bool {
        Date().timeIntervalSince(cachedAt) < 24 * 60 * 60
    }
}
