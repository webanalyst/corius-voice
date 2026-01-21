import SwiftUI
import AVFoundation
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey: String = ""
    @State private var selectedLanguage: String? = nil
    @State private var autoPaste = true
    @State private var copyToClipboard = true
    @State private var removeFillerWords = true
    @State private var launchAtStartup = false
    @State private var showFloatingBar = true
    @State private var floatingBarPosition: AppSettings.FloatingBarPosition = .topCenter
    @State private var availableMicrophones: [AVCaptureDevice] = []
    @State private var selectedMicrophone: String? = nil
    @State private var showingApiKeyInfo = false
    @State private var hasUnsavedChanges = false

    var body: some View {
        Form {
            // API Section
            Section {
                HStack {
                    SecureField("Deepgram API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { _ in hasUnsavedChanges = true }

                    Button(action: { showingApiKeyInfo = true }) {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                }

                Picker("Language", selection: $selectedLanguage) {
                    ForEach(AppSettings.supportedLanguages, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                .onChange(of: selectedLanguage) { _ in hasUnsavedChanges = true }
            } header: {
                Text("Deepgram")
            } footer: {
                Text("Get your API key from deepgram.com")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Audio Section
            Section("Audio") {
                Picker("Microphone", selection: $selectedMicrophone) {
                    Text("Default").tag(nil as String?)
                    ForEach(availableMicrophones, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID as String?)
                    }
                }
                .onChange(of: selectedMicrophone) { _ in hasUnsavedChanges = true }
            }

            // Behavior Section
            Section("Behavior") {
                Toggle("Auto-paste transcription", isOn: $autoPaste)
                    .onChange(of: autoPaste) { _ in hasUnsavedChanges = true }

                Toggle("Copy to clipboard", isOn: $copyToClipboard)
                    .onChange(of: copyToClipboard) { _ in hasUnsavedChanges = true }

                Toggle("Remove filler words", isOn: $removeFillerWords)
                    .onChange(of: removeFillerWords) { _ in hasUnsavedChanges = true }
            }

            // Appearance Section
            Section("Appearance") {
                Toggle("Show floating bar while recording", isOn: $showFloatingBar)
                    .onChange(of: showFloatingBar) { _ in hasUnsavedChanges = true }

                if showFloatingBar {
                    Picker("Floating bar position", selection: $floatingBarPosition) {
                        ForEach(AppSettings.FloatingBarPosition.allCases, id: \.self) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    .onChange(of: floatingBarPosition) { _ in hasUnsavedChanges = true }
                }
            }

            // System Section
            Section("System") {
                Toggle("Launch at startup", isOn: $launchAtStartup)
                    .onChange(of: launchAtStartup) { newValue in
                        hasUnsavedChanges = true
                        setLaunchAtStartup(newValue)
                    }
            }

            // Permissions Section
            Section("Permissions") {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    if AXIsProcessTrusted() {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Granted")
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                        Button("Grant Access") {
                            requestAccessibilityPermissions()
                        }
                    }
                }

                HStack {
                    Text("Microphone")
                    Spacer()
                    switch AVCaptureDevice.authorizationStatus(for: .audio) {
                    case .authorized:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Granted")
                            .foregroundColor(.secondary)
                    case .denied, .restricted:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Denied")
                            .foregroundColor(.secondary)
                    case .notDetermined:
                        Button("Request Access") {
                            AVCaptureDevice.requestAccess(for: .audio) { _ in }
                        }
                    @unknown default:
                        Text("Unknown")
                    }
                }
            }

            // Debug Section
            Section("Debug & Testing") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Fn Key Status:")
                            .fontWeight(.medium)
                        Spacer()
                        Circle()
                            .fill(appState.fnKeyPressed ? Color.green : Color.gray)
                            .frame(width: 12, height: 12)
                        Text(appState.fnKeyPressed ? "Pressed" : "Released")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Recording Status:")
                            .fontWeight(.medium)
                        Spacer()
                        Circle()
                            .fill(appState.isRecording ? Color.red : Color.gray)
                            .frame(width: 12, height: 12)
                        Text(appState.isRecording ? "Recording" : "Idle")
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How to use:")
                            .font(.headline)
                        
                        HStack {
                            Image(systemName: "keyboard")
                                .foregroundColor(.blue)
                            Text("Press and hold the Fn key to record")
                                .font(.body)
                        }
                        
                        Text("Release the Fn key to stop recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 28)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Troubleshooting:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("1. Accessibility permission must be granted ✅")
                            .font(.caption)
                        Text("2. Try pressing Fn and check the status above")
                            .font(.caption)
                        Text("3. Open Console.app and filter 'HotkeyService' for logs")
                            .font(.caption)
                        Text("4. Check System Settings > Keyboard")
                            .font(.caption)
                        Text("   - Ensure 'Use F1, F2, etc. keys as standard function keys' is OFF")
                            .font(.caption)
                        Text("5. If still not working, restart the app")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Button("Test Notification") {
                            testNotificationSystem()
                        }
                        
                        Button("Restart Hotkey") {
                            restartHotkeyService()
                        }
                    }
                }
            }

            // Data Section
            Section("Data") {
                Button("Export Data...") {
                    exportData()
                }

                Button("Import Data...") {
                    importData()
                }

                Button("Clear All Data", role: .destructive) {
                    clearAllData()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveSettings()
                }
                .disabled(!hasUnsavedChanges)
            }
        }
        .onAppear {
            loadSettings()
            loadMicrophones()
        }
        .alert("Deepgram API Key", isPresented: $showingApiKeyInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sign up at deepgram.com to get a free API key. The Nova-2 model provides the best accuracy for real-time transcription.")
        }
    }

    private func loadSettings() {
        let settings = appState.settings
        apiKey = settings.apiKey
        selectedLanguage = settings.language
        autoPaste = settings.autoPaste
        copyToClipboard = settings.copyToClipboard
        removeFillerWords = settings.removeFillerWords
        launchAtStartup = settings.launchAtStartup
        showFloatingBar = settings.showFloatingBar
        floatingBarPosition = settings.floatingBarPosition
        selectedMicrophone = settings.selectedMicrophone
        hasUnsavedChanges = false
    }

    private func saveSettings() {
        var settings = appState.settings
        settings.apiKey = apiKey
        settings.language = selectedLanguage
        settings.autoPaste = autoPaste
        settings.copyToClipboard = copyToClipboard
        settings.removeFillerWords = removeFillerWords
        settings.launchAtStartup = launchAtStartup
        settings.showFloatingBar = showFloatingBar
        settings.floatingBarPosition = floatingBarPosition
        settings.selectedMicrophone = selectedMicrophone

        appState.settings = settings
        appState.saveSettings()
        hasUnsavedChanges = false
    }

    private func loadMicrophones() {
        availableMicrophones = AudioCaptureService.shared.getAvailableMicrophones()
    }

    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }

    private func setLaunchAtStartup(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to set launch at startup: \(error)")
            }
        }
    }

    private func exportData() {
        guard let data = StorageService.shared.exportData() else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "corius-voice-backup.json"
        panel.allowedContentTypes = [.json]

        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]

        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url) {
                _ = StorageService.shared.importData(data)
                loadSettings()
            }
        }
    }

    private func clearAllData() {
        // Show confirmation alert before clearing
        let alert = NSAlert()
        alert.messageText = "Clear All Data?"
        alert.informativeText = "This will delete all transcriptions, notes, dictionary entries, and snippets. This action cannot be undone."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear All")
        alert.alertStyle = .warning

        if alert.runModal() == .alertSecondButtonReturn {
            StorageService.shared.clearAllData()
            appState.transcriptions = []
        }
    }
    
    // Debug functions
    private func testNotificationSystem() {
        print("[SettingsView] 🧪 Testing notification system...")
        
        // Test posting notification
        NotificationCenter.default.post(
            name: .fnKeyStateChanged,
            object: nil,
            userInfo: ["pressed": true]
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NotificationCenter.default.post(
                name: .fnKeyStateChanged,
                object: nil,
                userInfo: ["pressed": false]
            )
        }
        
        let alert = NSAlert()
        alert.messageText = "Notification Test"
        alert.informativeText = "Sent test notifications. Check Console.app for logs and watch the Debug section indicators."
        alert.runModal()
    }
    
    private func restartHotkeyService() {
        print("[SettingsView] 🔄 Restarting hotkey service...")
        HotkeyService.shared.stop()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            HotkeyService.shared.start()
            
            let alert = NSAlert()
            alert.messageText = "Hotkey Service Restarted"
            alert.informativeText = "The hotkey service has been restarted. Check Console.app for detailed logs."
            alert.runModal()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
