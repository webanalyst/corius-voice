import Foundation

struct DictionaryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var trigger: String
    var replacement: String
    var isEnabled: Bool = true
    var caseSensitive: Bool = false

    init(id: UUID = UUID(), trigger: String, replacement: String, isEnabled: Bool = true, caseSensitive: Bool = false) {
        self.id = id
        self.trigger = trigger
        self.replacement = replacement
        self.isEnabled = isEnabled
        self.caseSensitive = caseSensitive
    }

    func apply(to text: String) -> String {
        guard isEnabled else { return text }

        if caseSensitive {
            return text.replacingOccurrences(of: trigger, with: replacement)
        } else {
            return text.replacingOccurrences(
                of: trigger,
                with: replacement,
                options: .caseInsensitive
            )
        }
    }
}
