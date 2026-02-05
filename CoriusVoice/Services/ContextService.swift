import Foundation
import AppKit
import ApplicationServices

/// Service for detecting active application context and extracting relevant keyterms
/// Similar to how Wispr Flow uses app context for better transcription accuracy
class ContextService {
    static let shared = ContextService()

    private init() {}

    // MARK: - Active App Detection

    /// Get information about the currently active application
    func getActiveAppInfo() -> AppContext {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return AppContext(bundleId: "", name: "Unknown", isTextEditor: false)
        }

        let bundleId = frontApp.bundleIdentifier ?? ""
        let name = frontApp.localizedName ?? "Unknown"
        let isTextEditor = isTextEditingApp(bundleId: bundleId)

        return AppContext(
            bundleId: bundleId,
            name: name,
            isTextEditor: isTextEditor
        )
    }

    /// Check if the app is primarily a text editing application
    private func isTextEditingApp(bundleId: String) -> Bool {
        let textEditors: Set<String> = [
            // Code editors
            "com.microsoft.VSCode",
            "com.sublimetext.4",
            "com.sublimetext.3",
            "com.jetbrains.intellij",
            "com.jetbrains.WebStorm",
            "com.jetbrains.pycharm",
            "com.apple.dt.Xcode",
            "com.cursor.Cursor",
            "abnerworks.Typora",
            "com.github.atom",
            "com.panic.Nova",

            // Text editors
            "com.apple.TextEdit",
            "com.apple.Notes",
            "com.apple.reminders",
            "md.obsidian",
            "com.notion.id",
            "com.craft.Craft",
            "com.ulyssesapp.mac",
            "com.evernote.Evernote",
            "com.bear-writer.bear",

            // Office
            "com.microsoft.Word",
            "com.microsoft.Excel",
            "com.apple.iWork.Pages",
            "com.apple.iWork.Numbers",
            "com.apple.iWork.Keynote",
            "com.google.Chrome",  // Google Docs

            // Communication
            "com.apple.mail",
            "com.microsoft.Outlook",
            "com.tinyspeck.slackmacgap",
            "com.hnc.Discord",
            "us.zoom.xos",
            "com.microsoft.teams2",
            "org.whispersystems.signal-desktop",
            "com.telegram.desktop",

            // Terminals
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "io.alacritty"
        ]

        return textEditors.contains(bundleId)
    }

    // MARK: - Keyterm Extraction

    /// Extract keyterms based on the active app
    func getKeytermsForApp(_ appContext: AppContext) -> [String] {
        var keyterms: [String] = []

        // Add app-specific technical terms
        switch appContext.bundleId {
        // Code editors - add programming terms
        case let id where id.contains("VSCode") || id.contains("Xcode") || id.contains("Cursor") || id.contains("jetbrains"):
            keyterms += programmingKeyterms

        // Slack/Discord - add common chat terms
        case let id where id.contains("slack") || id.contains("Discord") || id.contains("teams"):
            keyterms += communicationKeyterms

        // Email
        case let id where id.contains("mail") || id.contains("Outlook"):
            keyterms += emailKeyterms

        // Terminal
        case let id where id.contains("Terminal") || id.contains("iterm") || id.contains("Warp") || id.contains("alacritty"):
            keyterms += terminalKeyterms

        default:
            keyterms += generalKeyterms
        }

        // Add user's custom dictionary terms
        let customTerms = StorageService.shared.dictionaryEntries.map { $0.replacement }
        keyterms += customTerms

        // Add snippet triggers
        let snippetTriggers = StorageService.shared.snippets.map { $0.trigger }
        keyterms += snippetTriggers

        return Array(Set(keyterms)).prefix(100).map { $0 }
    }

    // MARK: - Predefined Keyterm Lists

    private var programmingKeyterms: [String] {
        [
            // Languages
            "Swift", "Python", "JavaScript", "TypeScript", "Rust", "Go", "Java", "Kotlin",

            // Frameworks
            "SwiftUI", "UIKit", "React", "Vue", "Angular", "Next.js", "Node.js", "Django", "FastAPI",

            // Tools
            "Git", "GitHub", "GitLab", "Docker", "Kubernetes", "AWS", "Azure", "Firebase",

            // Concepts
            "API", "REST", "GraphQL", "WebSocket", "async", "await", "function", "class", "struct",
            "protocol", "interface", "enum", "variable", "constant", "import", "export",

            // Common terms
            "localhost", "npm", "pip", "brew", "sudo", "chmod", "mkdir", "console.log", "print",
            "debug", "error", "warning", "TODO", "FIXME", "refactor", "deploy", "commit", "push", "pull"
        ]
    }

    private var communicationKeyterms: [String] {
        [
            "meeting", "standup", "sync", "update", "agenda", "action items",
            "deadline", "milestone", "blocker", "priority", "urgent",
            "please", "thanks", "regards", "best", "cheers",
            "FYI", "ASAP", "EOD", "ETA", "TBD", "WIP",
            "sounds good", "let me know", "following up", "circling back"
        ]
    }

    private var emailKeyterms: [String] {
        [
            "Dear", "Hello", "Hi", "Regards", "Best regards", "Sincerely", "Thanks",
            "attachment", "attached", "please find", "as discussed",
            "follow up", "following up", "reminder", "urgent", "important",
            "schedule", "meeting", "call", "availability", "convenient"
        ]
    }

    private var terminalKeyterms: [String] {
        [
            "sudo", "chmod", "chown", "mkdir", "rmdir", "rm", "cp", "mv", "ls", "cd",
            "grep", "sed", "awk", "cat", "echo", "curl", "wget",
            "git", "npm", "yarn", "pip", "brew", "apt", "yum",
            "docker", "kubectl", "ssh", "scp", "rsync",
            "bash", "zsh", "fish", "source", "export", "alias"
        ]
    }

    private var generalKeyterms: [String] {
        [
            "please", "thanks", "hello", "hi", "regards",
            "important", "urgent", "deadline", "meeting", "schedule"
        ]
    }

    // MARK: - Clipboard Context

    /// Get text from clipboard that might provide context
    func getClipboardContext() -> String? {
        let pasteboard = NSPasteboard.general
        return pasteboard.string(forType: .string)
    }

    // MARK: - Selected Text (requires accessibility)

    /// Try to get the currently selected text in the active app
    /// Note: Requires accessibility permissions
    func getSelectedText() -> String? {
        // This uses the Accessibility API to get selected text
        // Requires the app to have accessibility permissions

        guard let app = NSWorkspace.shared.frontmostApplication,
              let pid = app.processIdentifier as pid_t? else {
            return nil
        }

        let appRef = AXUIElementCreateApplication(pid)

        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(appRef, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard focusResult == .success, let element = focusedElement else {
            return nil
        }

        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)

        guard textResult == .success, let text = selectedText as? String, !text.isEmpty else {
            return nil
        }

        return text
    }
}

// MARK: - Models

struct AppContext {
    let bundleId: String
    let name: String
    let isTextEditor: Bool

    var displayName: String {
        return name.isEmpty ? "Unknown App" : name
    }
}
