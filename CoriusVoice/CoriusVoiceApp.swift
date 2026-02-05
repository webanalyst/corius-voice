import SwiftUI
import SwiftData
import AppKit
import ScreenCaptureKit

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

        // Force session migration to fix date/duration issues (one-time)
        StorageService.shared.forceMigration()
        
        // Initialize SwiftData and migrate from JSON (runs in background)
        Task { @MainActor in
            await SwiftDataService.shared.migrateFromJSONIfNeeded()
            await SwiftDataService.shared.migrateWorkspaceIfNeeded()
            print("[App] ✅ SwiftData ready")
        }


        // Convert any existing WAV files to compressed format (runs in background)
        // TODO: re-enable once migration is centralized in RecordingService initialization
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyService.shared.stop()
        floatingBarController?.close()
        Task { await WorkspaceStorageServiceOptimized.shared.forceSave() }
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
        print("[Permissions] 🔐 Checking and requesting permissions...")

        // 1. Request accessibility permissions (required for Fn key detection)
        // Using AXIsProcessTrustedWithOptions with prompt:true will:
        // - Add the app to the Accessibility list in System Settings
        // - Show a system prompt to the user
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)

        if accessibilityEnabled {
            print("[Permissions] ✅ Accessibility permission granted")
        } else {
            print("[Permissions] ⚠️ Accessibility permission requested - waiting for user to grant")
        }

        // 2. Request microphone permissions
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted {
                print("[Permissions] ✅ Microphone access granted")
            } else {
                print("[Permissions] ❌ Microphone access denied")
            }
        }

        // 3. Request Screen Recording permission (required for system audio capture)
        requestScreenRecordingPermission()
    }

    private func requestScreenRecordingPermission() {
        print("[Permissions] 🖥️ Checking Screen Recording permission...")

        Task {
            // Try to access shareable content - this triggers the permission prompt if not granted
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                print("[Permissions] ✅ Screen Recording permission granted")
            } catch {
                print("[Permissions] ⚠️ Screen Recording permission not granted: \(error.localizedDescription)")

                // Show alert to user
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Screen Recording Permission Required"
                    alert.informativeText = "CoriusVoice needs Screen Recording permission to capture system audio from apps like Teams, Zoom, or Chrome. Please enable it in System Settings > Privacy & Security > Screen Recording."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Open Settings")
                    alert.addButton(withTitle: "Later")

                    if alert.runModal() == .alertFirstButtonReturn {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
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
    @Published var isProcessing = false  // True during stop delay (shows "Processing...")
    @Published var currentTranscription = ""
    @Published var transcriptions: [Transcription] = []
    @Published var settings = AppSettings()
    @Published var fnKeyPressed = false
    @Published var isWhisperPreloading = false
    @Published var whisperLoadingProgress: Double? = nil
    @Published var whisperLoadingTitle = ""
    @Published var whisperLoadingDetail = ""

    private var storageService = StorageService.shared

    private init() {
        loadData()
        setupNotifications()
        Task { await preloadWhisperModelsIfNeeded() }
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTranscriptionReceived),
            name: .transcriptionReceived,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingDidFinish),
            name: .recordingDidFinish,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionTranscriptionCompleted),
            name: .sessionTranscriptionCompleted,
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
    
    @objc private func handleTranscriptionReceived(_ notification: Notification) {
        guard let transcription = notification.userInfo?["transcription"] as? Transcription else {
            print("[AppState] ⚠️ No transcription in notification")
            return
        }
        
        DispatchQueue.main.async {
            self.currentTranscription = transcription.text
            self.transcriptions.insert(transcription, at: 0)
        }
        
        print("[AppState] 📝 Received transcription: \(transcription.text.prefix(50))...")
    }

    @objc private func handleSessionTranscriptionCompleted(_ notification: Notification) {
        guard let session = notification.userInfo?["session"] as? RecordingSession else { return }
        Task { @MainActor in
            let meetingNote = SessionIntegrationService.shared.upsertMeetingNote(for: session)
            _ = SessionIntegrationService.shared.syncActions(from: session, meetingNote: meetingNote)
        }
    }

    @objc private func handleRecordingDidFinish(_ notification: Notification) {
        guard let transcript = notification.userInfo?["transcript"] as? String else {
            print("[AppState] ⚠️ Received recordingDidFinish but no transcript")
            self.isProcessing = false  // Reset processing state even on error
            return
        }

        print("[AppState] 🏁 Recording finished with transcript: '\(transcript.prefix(50))...'")

        DispatchQueue.main.async {
            // Update the current transcription with the final version
            self.currentTranscription = transcript

            if !transcript.isEmpty {
                print("[AppState] 💾 Saving final transcription...")
                let transcription = Transcription(
                    id: UUID(),
                    text: transcript,
                    date: Date(),
                    duration: 0
                )
                self.transcriptions.insert(transcription, at: 0)
                self.storageService.saveTranscriptions(self.transcriptions)

                if self.settings.autoPaste {
                    print("[AppState] 📋 Auto-pasting final transcription")
                    KeyboardService.shared.pasteText(transcript)
                }
            }

            // Now hide the floating bar
            self.isProcessing = false
            print("[AppState] ✅ Recording session complete")
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

        print("[AppState] 🛑 Stopping recording session (save/paste will happen after delay)...")

        // Keep showing the bar but indicate we're processing
        isRecording = false
        isProcessing = true  // Keep bar visible while processing last words

        // This starts the async stop process with delays
        // Save/paste will be triggered by recordingDidFinish notification
        RecordingService.shared.stopRecording()
    }

    func saveSettings() {
        print("[AppState] 💾 saveSettings() called")
        print("[AppState] 🔑 API Key length: \(settings.apiKey.count)")
        print("[AppState] 🌍 Language: \(settings.language ?? "auto")")
        storageService.settings = settings
        print("[AppState] ✅ Settings saved to UserDefaults")
        
        // Force synchronize
        UserDefaults.standard.synchronize()
        
        // Verify it was saved
        let savedSettings = storageService.settings
        print("[AppState] ✅ Verified - Saved API Key length: \(savedSettings.apiKey.count)")
    }

    @MainActor
    private func updateWhisperLoading(title: String, detail: String, progress: Double?) {
        whisperLoadingTitle = title
        whisperLoadingDetail = detail
        whisperLoadingProgress = progress
    }

    @MainActor
    private func preloadWhisperModelsIfNeeded() async {
        guard settings.transcriptionProvider == .whisper else { return }

        isWhisperPreloading = true
        whisperLoadingTitle = "Preparing Whisper"
        whisperLoadingDetail = "Starting model load..."
        whisperLoadingProgress = nil

        let whisperService = WhisperService.shared
        let streamingSize = WhisperModelSize(rawValue: settings.whisperStreamingModelSize) ?? .base
        let mainSize = WhisperModelSize(rawValue: settings.whisperModelSize) ?? .largev3Turbo

        do {
            if !whisperService.isStreamingModelLoaded || whisperService.streamingModelSize != streamingSize {
                updateWhisperLoading(
                    title: "Loading streaming model",
                    detail: streamingSize.displayName,
                    progress: 0.0
                )

                try await whisperService.loadStreamingModel(streamingSize) { info in
                    let scaled = info.progress * 0.4
                    Task { @MainActor in
                        self.updateWhisperLoading(
                            title: "Loading streaming model",
                            detail: streamingSize.displayName,
                            progress: scaled
                        )
                    }
                }
            }

            if !whisperService.isModelLoaded || whisperService.currentModelSize != mainSize {
                updateWhisperLoading(
                    title: "Loading transcription model",
                    detail: mainSize.displayName,
                    progress: 0.4
                )

                try await whisperService.loadModel(mainSize) { info in
                    let scaled = 0.4 + (info.progress * 0.6)
                    Task { @MainActor in
                        self.updateWhisperLoading(
                            title: "Loading transcription model",
                            detail: mainSize.displayName,
                            progress: scaled
                        )
                    }
                }
            }

            updateWhisperLoading(title: "Whisper ready", detail: "Models loaded", progress: 1.0)
            isWhisperPreloading = false
        } catch {
            updateWhisperLoading(title: "Whisper load failed", detail: error.localizedDescription, progress: nil)
            isWhisperPreloading = false
        }
    }
}

import AVFoundation
