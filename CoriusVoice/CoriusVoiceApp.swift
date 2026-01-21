import SwiftUI
import AppKit

@main
struct CoriusVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var floatingBarController: FloatingBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarIcon()
        setupFloatingBar()
        requestPermissions()

        // Start hotkey service
        HotkeyService.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyService.shared.stop()
        floatingBarController?.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Corius Voice")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Window", action: #selector(showMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func setupFloatingBar() {
        floatingBarController = FloatingBarController()
    }

    private func requestPermissions() {
        // Request accessibility permissions
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessibilityEnabled {
            print("Accessibility permissions required for Fn key detection")
        }

        // Request microphone permissions
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted {
                print("Microphone access granted")
            } else {
                print("Microphone access denied")
            }
        }
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// Global app state
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isRecording = false
    @Published var currentTranscription = ""
    @Published var transcriptions: [Transcription] = []
    @Published var settings = AppSettings()
    @Published var fnKeyPressed = false

    private var storageService = StorageService.shared

    private init() {
        loadData()
        setupNotifications()
    }

    private func loadData() {
        transcriptions = storageService.loadTranscriptions()
        settings = storageService.settings
    }

    private func setupNotifications() {
        print("[AppState] 📡 Setting up notification observers...")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFnKeyStateChange),
            name: .fnKeyStateChanged,
            object: nil
        )
        print("[AppState] ✅ Notification observers ready")
    }

    @objc private func handleFnKeyStateChange(_ notification: Notification) {
        guard let pressed = notification.userInfo?["pressed"] as? Bool else {
            print("[AppState] ⚠️ Received fnKeyStateChanged but no 'pressed' value")
            return
        }
        
        print("[AppState] 📩 Received Fn key notification: \(pressed ? "PRESSED" : "RELEASED")")
        
        DispatchQueue.main.async {
            self.fnKeyPressed = pressed
            if pressed {
                print("[AppState] 🎙️ Starting recording...")
                self.startRecording()
            } else {
                print("[AppState] ⏹️ Stopping recording...")
                self.stopRecording()
            }
        }
    }

    func startRecording() {
        guard !isRecording else {
            print("[AppState] ⚠️ Already recording, ignoring start request")
            return
        }
        
        print("[AppState] 🎬 Starting recording session...")
        isRecording = true
        currentTranscription = ""

        RecordingService.shared.startRecording()
        print("[AppState] ✅ Recording started")
    }

    func stopRecording() {
        guard isRecording else {
            print("[AppState] ⚠️ Not recording, ignoring stop request")
            return
        }
        
        print("[AppState] 🛑 Stopping recording session...")
        isRecording = false

        RecordingService.shared.stopRecording()

        if !currentTranscription.isEmpty {
            print("[AppState] 💾 Saving transcription: \(currentTranscription.prefix(50))...")
            let transcription = Transcription(
                id: UUID(),
                text: currentTranscription,
                date: Date(),
                duration: 0
            )
            transcriptions.insert(transcription, at: 0)
            storageService.saveTranscriptions(transcriptions)

            if settings.autoPaste {
                print("[AppState] 📋 Auto-pasting transcription")
                KeyboardService.shared.pasteText(currentTranscription)
            }
        }
        
        print("[AppState] ✅ Recording stopped")
    }

    func saveSettings() {
        storageService.settings = settings
    }
}

import AVFoundation
