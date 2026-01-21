import Foundation
import SwiftUI

// MARK: - App Constants

struct AppConstants {
    static let appName = "Corius Voice"
    static let bundleIdentifier = "com.corius.voice"
    static let version = "1.0.0"

    struct DeepGram {
        static let baseURL = "wss://api.deepgram.com/v1/listen"
        static let model = "nova-2"
        static let sampleRate = 16000
        static let channels = 1
    }

    struct Audio {
        static let sampleRate: Double = 16000
        static let channels: UInt32 = 1
        static let bufferSize: UInt32 = 4096
    }

    struct UI {
        static let sidebarWidth: CGFloat = 200
        static let minWindowWidth: CGFloat = 800
        static let minWindowHeight: CGFloat = 600
        static let floatingBarWidth: CGFloat = 380
        static let floatingBarHeight: CGFloat = 72
    }
}

// MARK: - Colors

extension Color {
    static let appPrimary = Color.accentColor
    static let appSecondary = Color.secondary
    static let appBackground = Color(NSColor.windowBackgroundColor)
    static let appRecording = Color.red
    static let appSuccess = Color.green
}

// MARK: - Notification Names

extension Notification.Name {
    static let fnKeyStateChanged = Notification.Name("com.corius.voice.fnKeyStateChanged")
    static let transcriptionReceived = Notification.Name("com.corius.voice.transcriptionReceived")
    static let recordingStarted = Notification.Name("com.corius.voice.recordingStarted")
    static let recordingStopped = Notification.Name("com.corius.voice.recordingStopped")
    static let settingsChanged = Notification.Name("com.corius.voice.settingsChanged")
}
