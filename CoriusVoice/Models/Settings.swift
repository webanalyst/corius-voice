import Foundation

struct AppSettings: Codable {
    var apiKey: String = ""
    var language: String? = nil
    var autoPaste: Bool = true
    var copyToClipboard: Bool = true
    var removeFillerWords: Bool = true
    var launchAtStartup: Bool = false
    var showFloatingBar: Bool = true
    var floatingBarPosition: FloatingBarPosition = .topCenter
    var selectedMicrophone: String? = nil

    enum FloatingBarPosition: String, Codable, CaseIterable {
        case topLeft = "top-left"
        case topCenter = "top-center"
        case topRight = "top-right"
        case bottomLeft = "bottom-left"
        case bottomCenter = "bottom-center"
        case bottomRight = "bottom-right"

        var displayName: String {
            switch self {
            case .topLeft: return "Top Left"
            case .topCenter: return "Top Center"
            case .topRight: return "Top Right"
            case .bottomLeft: return "Bottom Left"
            case .bottomCenter: return "Bottom Center"
            case .bottomRight: return "Bottom Right"
            }
        }
    }

    static let supportedLanguages: [(code: String?, name: String)] = [
        (nil, "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("ja", "Japanese"),
        ("zh", "Chinese"),
        ("ko", "Korean"),
        ("ru", "Russian")
    ]
}
