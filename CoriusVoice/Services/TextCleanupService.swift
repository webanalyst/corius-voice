import Foundation

class TextCleanupService {
    static let shared = TextCleanupService()

    private init() {}

    /// Clean up transcribed text
    func cleanText(_ text: String, settings: AppSettings, dictionary: [DictionaryEntry], snippets: [Snippet]) -> String {
        var result = text

        // Remove filler words if enabled
        if settings.removeFillerWords {
            result = removeFillerWords(result)
        }

        // Apply dictionary replacements
        result = applyDictionary(result, entries: dictionary)

        // Apply snippets
        result = applySnippets(result, snippets: snippets)

        // Normalize whitespace
        result = normalizeWhitespace(result)

        // Fix capitalization after sentence endings
        result = fixCapitalization(result)

        return result
    }

    /// Remove filler words from text
    func removeFillerWords(_ text: String) -> String {
        var result = text

        for filler in FillerWords.all {
            // Create pattern that matches filler words with word boundaries
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: filler))\\b"

            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        return result
    }

    /// Apply dictionary replacements
    func applyDictionary(_ text: String, entries: [DictionaryEntry]) -> String {
        var result = text

        for entry in entries where entry.isEnabled {
            result = entry.apply(to: result)
        }

        return result
    }

    /// Apply snippets
    func applySnippets(_ text: String, snippets: [Snippet]) -> String {
        var result = text

        for snippet in snippets where snippet.isEnabled {
            result = result.replacingOccurrences(of: snippet.trigger, with: snippet.content)
        }

        return result
    }

    /// Normalize whitespace (remove extra spaces, fix spacing around punctuation)
    func normalizeWhitespace(_ text: String) -> String {
        var result = text

        // Replace multiple spaces with single space
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // Remove space before punctuation
        result = result.replacingOccurrences(of: " .", with: ".")
        result = result.replacingOccurrences(of: " ,", with: ",")
        result = result.replacingOccurrences(of: " !", with: "!")
        result = result.replacingOccurrences(of: " ?", with: "?")
        result = result.replacingOccurrences(of: " :", with: ":")
        result = result.replacingOccurrences(of: " ;", with: ";")

        // Add space after punctuation if missing
        let punctuationPattern = "([.!?,:;])([A-Za-z])"
        if let regex = try? NSRegularExpression(pattern: punctuationPattern) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1 $2"
            )
        }

        // Trim leading/trailing whitespace
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    /// Fix capitalization after sentence endings
    func fixCapitalization(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text
        let sentenceEndPattern = "([.!?])\\s+([a-z])"

        if let regex = try? NSRegularExpression(pattern: sentenceEndPattern) {
            let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))

            // Process matches in reverse order to maintain correct indices
            for match in matches.reversed() {
                if let letterRange = Range(match.range(at: 2), in: result) {
                    let letter = result[letterRange]
                    result.replaceSubrange(letterRange, with: letter.uppercased())
                }
            }
        }

        // Capitalize first letter
        if let firstLetter = result.first, firstLetter.isLowercase {
            result = result.prefix(1).uppercased() + result.dropFirst()
        }

        return result
    }
}

// MARK: - Filler Words

struct FillerWords {
    static let english = [
        "um", "uh", "er", "ah", "like", "you know", "I mean",
        "sort of", "kind of", "basically", "actually", "literally",
        "right", "okay", "so", "well", "anyway", "hmm", "huh"
    ]

    static let spanish = [
        "eh", "este", "esto", "pues", "bueno", "o sea", "digamos",
        "a ver", "mira", "sabes", "entonces", "básicamente", "tipo"
    ]

    static let french = [
        "euh", "heu", "ben", "bah", "genre", "enfin", "quoi",
        "voilà", "donc", "tu vois", "en fait"
    ]

    static let german = [
        "äh", "ähm", "also", "halt", "quasi", "sozusagen",
        "irgendwie", "eigentlich", "na ja", "weißt du"
    ]

    static var all: [String] {
        return english + spanish + french + german
    }

    static func forLanguage(_ code: String?) -> [String] {
        guard let code = code else { return all }

        switch code.prefix(2) {
        case "en": return english
        case "es": return spanish
        case "fr": return french
        case "de": return german
        default: return all
        }
    }
}
