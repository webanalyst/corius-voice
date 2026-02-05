import SwiftUI
import AVFoundation
import ServiceManagement
import AppKit

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case ai = "AI"
    case system = "System"
    case permissions = "Permissions"
    case advanced = "Advanced"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .ai: return "cpu"
        case .system: return "desktopcomputer"
        case .permissions: return "lock.shield"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .general
    @State private var apiKey: String = ""
    @State private var selectedLanguage: String? = nil
    @State private var autoPaste = true
    @State private var copyToClipboard = true
    @State private var removeFillerWords = true
    @State private var launchAtStartup = false
    @State private var showFloatingBar = true
    @State private var showInDock = true
    @State private var playSoundEffects = true
    @State private var floatingBarPosition: AppSettings.FloatingBarPosition = .topCenter
    @State private var availableMicrophones: [AVCaptureDevice] = []
    @State private var selectedMicrophone: String? = nil
    @State private var microphoneSensitivity: Float = 1.5
    @State private var hasUnsavedChanges = false
    @State private var isLoading = true

    // Transcription provider settings
    @State private var transcriptionProvider: AppSettings.TranscriptionProvider = .deepgram
    @State private var whisperModelSize: WhisperModelSize = .largev3Turbo
    @State private var whisperStreamingModelSize: WhisperModelSize = .base
    @StateObject private var whisperService = WhisperService.shared

    // Session recording settings
    @State private var enableDiarization = true
    @State private var diarizationMethod: AppSettings.DiarizationMethod = .local
    @State private var useClientSideVAD = true
    @State private var vadThreshold: Float = 0.015
    @State private var autoTrainMinSessionDuration: TimeInterval = 60

    // OpenRouter settings
    @State private var openRouterApiKey: String = ""
    @State private var openRouterModelId: String = ""
    @State private var openRouterModelName: String = ""
    @State private var defaultSessionType: SessionType = .meeting

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SettingsTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        action: { selectedTab = tab }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Material.thin)

            Divider()
                .padding(.bottom, 8)

            // Tab content
            ScrollView {
                VStack(spacing: 20) {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsSection(
                            apiKey: $apiKey,
                            selectedLanguage: $selectedLanguage,
                            selectedMicrophone: $selectedMicrophone,
                            availableMicrophones: availableMicrophones,
                            autoPaste: $autoPaste,
                            copyToClipboard: $copyToClipboard,
                            removeFillerWords: $removeFillerWords,
                            microphoneSensitivity: $microphoneSensitivity,
                            enableDiarization: $enableDiarization,
                            diarizationMethod: $diarizationMethod,
                            useClientSideVAD: $useClientSideVAD,
                            vadThreshold: $vadThreshold,
                            autoTrainMinSessionDuration: $autoTrainMinSessionDuration,
                            transcriptionProvider: $transcriptionProvider,
                            whisperModelSize: $whisperModelSize,
                            whisperStreamingModelSize: $whisperStreamingModelSize,
                            whisperService: whisperService,
                            onChanged: { if !isLoading { hasUnsavedChanges = true } }
                        )
                    case .ai:
                        AISettingsSection(
                            openRouterApiKey: $openRouterApiKey,
                            openRouterModelId: $openRouterModelId,
                            openRouterModelName: $openRouterModelName,
                            defaultSessionType: $defaultSessionType,
                            onChanged: { if !isLoading { hasUnsavedChanges = true } }
                        )
                    case .system:
                        SystemSettingsSection(
                            launchAtStartup: $launchAtStartup,
                            showFloatingBar: $showFloatingBar,
                            showInDock: $showInDock,
                            playSoundEffects: $playSoundEffects,
                            floatingBarPosition: $floatingBarPosition,
                            onChanged: { if !isLoading { hasUnsavedChanges = true } },
                            onLaunchAtStartupChanged: setLaunchAtStartup
                        )
                    case .permissions:
                        PermissionsSettingsSection()
                    case .advanced:
                        AdvancedSettingsSection(
                            appState: appState,
                            onExportData: exportData,
                            onImportData: importData,
                            onClearData: clearAllData
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            Divider()

            // Footer with save button
            HStack {
                if hasUnsavedChanges {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("Unsaved changes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    Button("Descartar") {
                        loadSettings()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasUnsavedChanges)

                    Button("Guardar cambios") {
                        saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasUnsavedChanges)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 550, minHeight: 500)
        .onAppear {
            loadSettings()
            loadMicrophones()
        }
    }

    private func loadSettings() {
        isLoading = true
        let settings = appState.settings
        apiKey = settings.apiKey
        selectedLanguage = settings.language
        autoPaste = settings.autoPaste
        copyToClipboard = settings.copyToClipboard
        removeFillerWords = settings.removeFillerWords
        launchAtStartup = settings.launchAtStartup
        showFloatingBar = settings.showFloatingBar
        showInDock = settings.showInDock
        playSoundEffects = settings.playSoundEffects
        floatingBarPosition = settings.floatingBarPosition
        selectedMicrophone = settings.selectedMicrophone
        microphoneSensitivity = settings.microphoneSensitivity
        // Transcription provider settings
        transcriptionProvider = settings.transcriptionProvider
        if let modelSize = WhisperModelSize(rawValue: settings.whisperModelSize) {
            whisperModelSize = modelSize
        }
        if let streamingModelSize = WhisperModelSize(rawValue: settings.whisperStreamingModelSize) {
            whisperStreamingModelSize = streamingModelSize
        }
        // Session recording settings
        enableDiarization = settings.enableDiarization
        diarizationMethod = settings.diarizationMethod
        useClientSideVAD = settings.useClientSideVAD
        vadThreshold = settings.vadThreshold
        autoTrainMinSessionDuration = settings.autoTrainMinSessionDuration
        // OpenRouter settings
        openRouterApiKey = settings.openRouterApiKey
        openRouterModelId = settings.openRouterModelId
        openRouterModelName = settings.openRouterModelName
        defaultSessionType = settings.defaultSessionType
        hasUnsavedChanges = false
        // Delay to allow SwiftUI to finish updating bindings
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isLoading = false
        }
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
        settings.showInDock = showInDock
        settings.playSoundEffects = playSoundEffects
        settings.floatingBarPosition = floatingBarPosition
        settings.selectedMicrophone = selectedMicrophone
        settings.microphoneSensitivity = microphoneSensitivity
        // Transcription provider settings
        settings.transcriptionProvider = transcriptionProvider
        settings.whisperModelSize = whisperModelSize.rawValue
        settings.whisperStreamingModelSize = whisperStreamingModelSize.rawValue
        // Session recording settings
        settings.enableDiarization = enableDiarization
        settings.diarizationMethod = diarizationMethod
        settings.useClientSideVAD = useClientSideVAD
        settings.vadThreshold = vadThreshold
        settings.autoTrainMinSessionDuration = autoTrainMinSessionDuration
        // OpenRouter settings
        settings.openRouterApiKey = openRouterApiKey
        settings.openRouterModelId = openRouterModelId
        settings.openRouterModelName = openRouterModelName
        settings.defaultSessionType = defaultSessionType

        appState.settings = settings
        appState.saveSettings()
        hasUnsavedChanges = false
    }

    private func loadMicrophones() {
        availableMicrophones = AudioCaptureService.shared.getAvailableMicrophones()
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
}

// MARK: - Tab Button

struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.title3)
                Text(tab.rawValue)
                    .font(.caption)
            }
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.accentColor.opacity(0.1) : Color.clear
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - General Settings Section

struct GeneralSettingsSection: View {
    @Binding var apiKey: String
    @Binding var selectedLanguage: String?
    @Binding var selectedMicrophone: String?
    var availableMicrophones: [AVCaptureDevice]
    @Binding var autoPaste: Bool
    @Binding var copyToClipboard: Bool
    @Binding var removeFillerWords: Bool
    @Binding var microphoneSensitivity: Float
    @Binding var enableDiarization: Bool
    @Binding var diarizationMethod: AppSettings.DiarizationMethod
    @Binding var useClientSideVAD: Bool
    @Binding var vadThreshold: Float
    @Binding var autoTrainMinSessionDuration: TimeInterval
    @Binding var transcriptionProvider: AppSettings.TranscriptionProvider
    @Binding var whisperModelSize: WhisperModelSize
    @Binding var whisperStreamingModelSize: WhisperModelSize
    @ObservedObject var whisperService: WhisperService
    var onChanged: () -> Void

    @State private var showApiKey = false
    @State private var isTestingMic = false
    @State private var audioLevel: CGFloat = 0
    @State private var peakLevel: CGFloat = 0
    @State private var peakDecayTimer: Timer?

    private var sensitivityLabel: String {
        if microphoneSensitivity <= 1.2 {
            return "Normal"
        } else if microphoneSensitivity <= 1.8 {
            return "High"
        } else {
            return "Very High"
        }
    }

    private var levelColors: [Color] {
        [.green, .green, .yellow, .orange, .red]
    }

    private func toggleMicTest() {
        if isTestingMic {
            stopMicTest()
        } else {
            startMicTest()
        }
    }

    private func startMicTest() {
        isTestingMic = true
        audioLevel = 0
        peakLevel = 0

        // Start audio capture for testing
        do {
            try AudioCaptureService.shared.startCapture()
        } catch {
            print("[Settings] Failed to start mic test: \(error)")
            isTestingMic = false
            return
        }

        // Listen for audio levels
        NotificationCenter.default.addObserver(
            forName: .audioLevelsUpdated,
            object: nil,
            queue: .main
        ) { notification in
            guard self.isTestingMic else { return }
            if let levels = notification.userInfo?["levels"] as? [CGFloat], !levels.isEmpty {
                // Get average level
                let avg = levels.reduce(0, +) / CGFloat(levels.count)
                self.audioLevel = avg

                // Update peak with decay
                if avg > self.peakLevel {
                    self.peakLevel = avg
                    self.peakDecayTimer?.invalidate()
                    self.peakDecayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                        withAnimation(.easeOut(duration: 0.5)) {
                            self.peakLevel = self.audioLevel
                        }
                    }
                }
            }
        }
    }

    private func stopMicTest() {
        isTestingMic = false
        AudioCaptureService.shared.stopCapture()
        NotificationCenter.default.removeObserver(self, name: .audioLevelsUpdated, object: nil)
        peakDecayTimer?.invalidate()
        peakDecayTimer = nil
        audioLevel = 0
        peakLevel = 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Transcription Provider
            SettingsCard(title: "Transcription Provider", icon: "waveform") {
                VStack(alignment: .leading, spacing: 16) {
                    TranscriptionProviderSwitch(provider: $transcriptionProvider) {
                        onChanged()
                    }

                    Text(transcriptionProvider.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            SettingsCard(title: "Whisper (Local)", icon: "desktopcomputer") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(transcriptionProvider == .whisper ? "Active" : "Standby")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(transcriptionProvider == .whisper ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                            )
                            .foregroundColor(transcriptionProvider == .whisper ? .green : .secondary)
                    }

                    Divider()

                    // Real-time Streaming Model (smaller, faster)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Real-time Model")
                                Text("Used during recording for live transcription")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $whisperStreamingModelSize) {
                                ForEach([WhisperModelSize.tiny, .base, .small], id: \.self) { size in
                                    Text(size.displayName).tag(size)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                            .onChange(of: whisperStreamingModelSize) { _ in onChanged() }
                        }

                        // Streaming model status
                        HStack(spacing: 8) {
                            if whisperService.isStreamingModelLoaded && whisperService.streamingModelSize == whisperStreamingModelSize {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Ready")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if whisperService.isStreamingLoading {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Loading...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                Text("Not loaded (will load on first use)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Final Transcription Model (larger, better quality)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Final Model")
                                Text("Used after recording for high-quality transcription")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $whisperModelSize) {
                                ForEach(WhisperModelSize.allCases, id: \.self) { size in
                                    Text(size.displayName).tag(size)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                            .onChange(of: whisperModelSize) { _ in onChanged() }
                        }

                        Text(whisperModelSize.description)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Model status
                        HStack(spacing: 8) {
                            if whisperService.isModelLoaded && whisperService.currentModelSize == whisperModelSize {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Model loaded")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if whisperService.isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Loading model...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Image(systemName: "arrow.down.circle")
                                    .foregroundColor(.orange)
                                Text("Model not loaded")
                                    .font(.caption)
                                    .foregroundColor(.orange)

                                Spacer()

                                Button("Load Model") {
                                    Task {
                                        try? await whisperService.loadModel(whisperModelSize)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }

                    Divider()

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("During recording, the real-time model provides quick transcriptions. When you stop, the final model re-transcribes with better accuracy and speaker diarization.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            SettingsCard(title: "Deepgram API", icon: "key.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(transcriptionProvider == .deepgram ? "Active" : "Standby")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(transcriptionProvider == .deepgram ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                            )
                            .foregroundColor(transcriptionProvider == .deepgram ? .green : .secondary)
                    }

                    Divider()

                    HStack {
                        if showApiKey {
                            TextField("API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showApiKey.toggle() }) {
                            Image(systemName: showApiKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                    .onChange(of: apiKey) { _ in onChanged() }

                    HStack(spacing: 8) {
                        if apiKey.isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("API Key required")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Configured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Link("Get API Key", destination: URL(string: "https://deepgram.com")!)
                            .font(.caption)
                    }
                }
            }

            // Language & Audio
            SettingsCard(title: "Language & Audio", icon: "globe") {
                VStack(spacing: 16) {
                    HStack {
                        Text("Language")
                        Spacer()
                        Picker("", selection: $selectedLanguage) {
                            ForEach(AppSettings.supportedLanguages, id: \.code) { language in
                                Text("\(language.flag) \(language.name)").tag(language.code)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .onChange(of: selectedLanguage) { _ in onChanged() }
                    }

                    Divider()

                    HStack {
                        Text("Microphone")
                        Spacer()
                        Picker("", selection: $selectedMicrophone) {
                            Text("System Default").tag(nil as String?)
                            ForEach(availableMicrophones, id: \.uniqueID) { device in
                                Text(device.localizedName).tag(device.uniqueID as String?)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .onChange(of: selectedMicrophone) { _ in onChanged() }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Microphone Sensitivity")
                            Spacer()
                            Text(sensitivityLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Slider(value: $microphoneSensitivity, in: 1.0...3.0, step: 0.1)
                            .onChange(of: microphoneSensitivity) { _ in onChanged() }

                        // Audio level meter (Discord style)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Input Level")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(isTestingMic ? "Stop Test" : "Test Mic") {
                                    toggleMicTest()
                                }
                                .font(.caption)
                                .buttonStyle(.borderless)
                            }

                            // Level meter bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.gray.opacity(0.2))

                                    // Level bar with gradient
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            LinearGradient(
                                                colors: levelColors,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geometry.size.width * min(audioLevel * CGFloat(microphoneSensitivity), 1.0))
                                        .animation(.easeOut(duration: 0.05), value: audioLevel)

                                    // Peak indicator
                                    if peakLevel > 0.05 {
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(peakLevel > 0.8 ? Color.red : Color.green)
                                            .frame(width: 3)
                                            .offset(x: geometry.size.width * min(peakLevel * CGFloat(microphoneSensitivity), 1.0) - 3)
                                            .animation(.easeOut(duration: 0.1), value: peakLevel)
                                    }
                                }
                            }
                            .frame(height: 8)

                            if !isTestingMic {
                                Text("Click 'Test Mic' and speak to see your input level")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Speak now - the bar should move when you talk")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }

            // Behavior
            SettingsCard(title: "Behavior", icon: "hand.tap.fill") {
                VStack(spacing: 12) {
                    SettingsToggle(
                        title: "Auto-paste transcription",
                        subtitle: "Automatically paste text after recording",
                        isOn: $autoPaste,
                        onChange: onChanged
                    )

                    Divider()

                    SettingsToggle(
                        title: "Copy to clipboard",
                        subtitle: "Save transcription to clipboard",
                        isOn: $copyToClipboard,
                        onChange: onChanged
                    )

                    Divider()

                    SettingsToggle(
                        title: "Remove filler words",
                        subtitle: "Clean up \"um\", \"uh\", \"like\", etc.",
                        isOn: $removeFillerWords,
                        onChange: onChanged
                    )
                }
            }

            // Session Recording
            SettingsCard(title: "Session Recording", icon: "record.circle") {
                VStack(spacing: 12) {
                    SettingsToggle(
                        title: "Speaker identification",
                        subtitle: "Identify different speakers in recordings (diarization)",
                        isOn: $enableDiarization,
                        onChange: onChanged
                    )

                    if enableDiarization {
                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Diarization method")
                                Text(diarizationMethod.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $diarizationMethod) {
                                ForEach(AppSettings.DiarizationMethod.allCases, id: \.self) { method in
                                    Text(method.displayName).tag(method)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 180)
                            .onChange(of: diarizationMethod) { _ in onChanged() }
                        }
                    }

                    Divider()

                    SettingsToggle(
                        title: "Client-side VAD",
                        subtitle: "Detect silence locally to save API tokens",
                        isOn: $useClientSideVAD,
                        onChange: onChanged
                    )

                    if useClientSideVAD {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("VAD Sensitivity")
                                Spacer()
                                Text(vadSensitivityLabel)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Slider(value: $vadThreshold, in: 0.005...0.05, step: 0.005)
                                .onChange(of: vadThreshold) { _ in onChanged() }

                            Text("Lower = more sensitive (picks up quieter speech)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-train voices")
                                Text("Minimum session length to auto-train linked speakers")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(autoTrainLabel)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Slider(value: Binding(
                            get: { autoTrainMinSessionDuration },
                            set: { autoTrainMinSessionDuration = $0; onChanged() }
                        ), in: 0...300, step: 15)

                        Text("Set to 0s to disable auto-training")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var autoTrainLabel: String {
        if autoTrainMinSessionDuration <= 0 { return "Off" }
        let minutes = Int(autoTrainMinSessionDuration) / 60
        let seconds = Int(autoTrainMinSessionDuration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private var vadSensitivityLabel: String {
        if vadThreshold <= 0.01 {
            return "High"
        } else if vadThreshold <= 0.02 {
            return "Normal"
        } else {
            return "Low"
        }
    }
}

// MARK: - AI Settings Section

struct AISettingsSection: View {
    @Binding var openRouterApiKey: String
    @Binding var openRouterModelId: String
    @Binding var openRouterModelName: String
    @Binding var defaultSessionType: SessionType
    var onChanged: () -> Void

    @StateObject private var openRouterService = OpenRouterService.shared
    @State private var showApiKey = false
    @State private var isTestingConnection = false
    @State private var connectionTestResult: String?
    @State private var showingModelPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // OpenRouter API
            SettingsCard(title: "OpenRouter API", icon: "cpu") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("OpenRouter provides access to multiple AI models for generating session summaries.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        if showApiKey {
                            TextField("API Key", text: $openRouterApiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("API Key", text: $openRouterApiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(action: { showApiKey.toggle() }) {
                            Image(systemName: showApiKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                    .onChange(of: openRouterApiKey) { _ in
                        onChanged()
                        connectionTestResult = nil
                    }

                    HStack(spacing: 8) {
                        if openRouterApiKey.isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("API Key required")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else if let result = connectionTestResult {
                            if result == "success" {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Connection verified")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(result)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        } else {
                            Image(systemName: "key.fill")
                                .foregroundColor(.secondary)
                            Text("Configured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: testConnection) {
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Text("Test Connection")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(openRouterApiKey.isEmpty || isTestingConnection)

                        Link("Get API Key", destination: URL(string: "https://openrouter.ai/keys")!)
                            .font(.caption)
                    }
                }
            }

            // Model Selection
            SettingsCard(title: "Default Model", icon: "cube") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select the AI model used for generating session summaries.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if openRouterModelName.isEmpty {
                                Text("No model selected")
                                    .foregroundColor(.secondary)
                            } else {
                                Text(openRouterModelName)
                                    .fontWeight(.medium)
                                Text(openRouterModelId)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Button("Select Model...") {
                            showingModelPicker = true
                            // Ensure models are loaded
                            if openRouterService.cachedModels.isEmpty {
                                Task {
                                    try? await openRouterService.fetchModels()
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if let model = openRouterService.getModel(byId: openRouterModelId) {
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.caption)
                                Text(model.formattedContextLength)
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)

                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.caption)
                                Text(model.formattedPromptPrice + "/1M")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)

                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.circle")
                                    .font(.caption)
                                Text(model.formattedCompletionPrice + "/1M")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)

                            TierBadge(tier: model.tier)
                        }
                    }
                }
            }

            // Default Session Type
            SettingsCard(title: "Default Session Type", icon: "tag") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select the default type for new recording sessions. This affects how summaries are generated.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Session Type", selection: $defaultSessionType) {
                        ForEach(SessionType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: defaultSessionType) { _ in onChanged() }
                }
            }
        }
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerSheet(
                openRouterService: openRouterService,
                selectedModelId: $openRouterModelId,
                selectedModelName: $openRouterModelName,
                onChanged: onChanged
            )
        }
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = nil

        Task {
            do {
                let success = try await openRouterService.testConnection(apiKey: openRouterApiKey)
                await MainActor.run {
                    isTestingConnection = false
                    connectionTestResult = success ? "success" : "Failed to connect"
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    connectionTestResult = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Model Picker Sheet

struct ModelPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var openRouterService: OpenRouterService
    @Binding var selectedModelId: String
    @Binding var selectedModelName: String
    var onChanged: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Model")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Model picker
            ModelPickerView(
                openRouterService: openRouterService,
                selectedModelId: $selectedModelId,
                selectedModelName: $selectedModelName,
                onRefresh: {
                    Task {
                        try? await openRouterService.fetchModels()
                    }
                }
            )
            .onChange(of: selectedModelId) { _ in onChanged() }
        }
        .frame(width: 600, height: 700)
    }
}

// MARK: - System Settings Section

struct SystemSettingsSection: View {
    @Binding var launchAtStartup: Bool
    @Binding var showFloatingBar: Bool
    @Binding var showInDock: Bool
    @Binding var playSoundEffects: Bool
    @Binding var floatingBarPosition: AppSettings.FloatingBarPosition
    var onChanged: () -> Void
    var onLaunchAtStartupChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Startup
            SettingsCard(title: "Startup", icon: "power") {
                SettingsToggle(
                    title: "Launch at login",
                    subtitle: "Start Corius Voice when you log in",
                    isOn: $launchAtStartup,
                    onChange: {
                        onChanged()
                        onLaunchAtStartupChanged(launchAtStartup)
                    }
                )
            }

            // Appearance
            SettingsCard(title: "Appearance", icon: "paintbrush.fill") {
                VStack(spacing: 12) {
                    SettingsToggle(
                        title: "Show floating bar",
                        subtitle: "Display transcription bar while recording",
                        isOn: $showFloatingBar,
                        onChange: onChanged
                    )

                    if showFloatingBar {
                        Divider()

                        HStack {
                            Text("Bar position")
                            Spacer()
                            Picker("", selection: $floatingBarPosition) {
                                ForEach(AppSettings.FloatingBarPosition.allCases, id: \.self) { position in
                                    Text(position.displayName).tag(position)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 150)
                            .onChange(of: floatingBarPosition) { _ in onChanged() }
                        }
                    }

                    Divider()

                    SettingsToggle(
                        title: "Show in Dock",
                        subtitle: "Display app icon in the Dock",
                        isOn: $showInDock,
                        onChange: onChanged
                    )

                    Divider()

                    SettingsToggle(
                        title: "Sound effects",
                        subtitle: "Play sounds for recording start/stop",
                        isOn: $playSoundEffects,
                        onChange: onChanged
                    )
                }
            }
        }
    }
}

// MARK: - Permissions Settings Section

struct PermissionsSettingsSection: View {
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var screenRecordingGranted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "Required Permissions", icon: "checkmark.shield.fill") {
                VStack(spacing: 16) {
                    // Accessibility
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Accessibility")
                                .fontWeight(.medium)
                            Text("Required to detect Fn key press")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if accessibilityGranted {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("Grant Access") {
                                requestAccessibilityPermissions()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    Divider()

                    // Microphone
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Microphone")
                                .fontWeight(.medium)
                            Text("Required to capture voice for transcription")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        switch microphoneStatus {
                        case .authorized:
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        case .denied, .restricted:
                            Label("Denied", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                        case .notDetermined:
                            Button("Request Access") {
                                AVCaptureDevice.requestAccess(for: .audio) { granted in
                                    DispatchQueue.main.async {
                                        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        @unknown default:
                            Text("Unknown")
                        }
                    }

                    Divider()

                    // Screen Recording (for system audio capture)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Screen Recording")
                                .fontWeight(.medium)
                            Text("Required to capture system audio (Teams, etc.)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if screenRecordingGranted {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("Grant Access") {
                                requestScreenRecordingPermission()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            // Instructions
            SettingsCard(title: "How to Use", icon: "keyboard") {
                VStack(alignment: .leading, spacing: 12) {
                    InstructionRow(number: 1, text: "Press and hold the Fn key to start recording")
                    InstructionRow(number: 2, text: "Speak clearly into your microphone")
                    InstructionRow(number: 3, text: "Release Fn to stop and paste transcription")
                }
            }
        }
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            checkScreenRecordingPermission()
        }
    }

    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)

        // Check again after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    private func checkScreenRecordingPermission() {
        if #available(macOS 13.0, *) {
            Task {
                let hasPermission = await SystemAudioCaptureService.shared.hasPermission()
                await MainActor.run {
                    screenRecordingGranted = hasPermission
                }
            }
        } else {
            screenRecordingGranted = false
        }
    }

    private func requestScreenRecordingPermission() {
        if #available(macOS 13.0, *) {
            Task {
                await SystemAudioCaptureService.shared.requestPermission()
                // Check again after user interaction
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    checkScreenRecordingPermission()
                }
            }
        }
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 24, height: 24)
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }

            Text(text)
                .font(.body)
        }
    }
}

// MARK: - Advanced Settings Section

struct AdvancedSettingsSection: View {
    var appState: AppState
    var onExportData: () -> Void
    var onImportData: () -> Void
    var onClearData: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Debug Status
            SettingsCard(title: "Debug Status", icon: "ladybug.fill") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Fn Key")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.fnKeyPressed ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 10, height: 10)
                            Text(appState.fnKeyPressed ? "Pressed" : "Released")
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Recording")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.isRecording ? Color.red : Color.gray.opacity(0.3))
                                .frame(width: 10, height: 10)
                            Text(appState.isRecording ? "Active" : "Idle")
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Hotkey Service")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(HotkeyService.shared.isRunning ? Color.green : Color.orange)
                                .frame(width: 10, height: 10)
                            Text(HotkeyService.shared.isRunning ? "Running" : "Stopped")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Data Management
            SettingsCard(title: "Data Management", icon: "externaldrive.fill") {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Export Data")
                                .fontWeight(.medium)
                            Text("Save all data to a backup file")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Export...") {
                            onExportData()
                        }
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Import Data")
                                .fontWeight(.medium)
                            Text("Restore from a backup file")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Import...") {
                            onImportData()
                        }
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Clear All Data")
                                .fontWeight(.medium)
                            Text("Delete all transcriptions and settings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Clear All", role: .destructive) {
                            onClearData()
                        }
                        .foregroundColor(.red)
                    }
                }
            }

            // Debug Actions
            SettingsCard(title: "Debug Actions", icon: "hammer.fill") {
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
    }

    private func testNotificationSystem() {
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
    }

    private func restartHotkeyService() {
        HotkeyService.shared.stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            HotkeyService.shared.start()
        }
    }
}

// MARK: - Reusable Components

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: () -> Content

    init(title: String, icon: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
}

struct TranscriptionProviderSwitch: View {
    @Binding var provider: AppSettings.TranscriptionProvider
    var onChange: () -> Void

    @Namespace private var switchNamespace

    var body: some View {
        HStack(spacing: 0) {
            providerButton(.deepgram, title: "Cloud", subtitle: "Deepgram")
            providerButton(.whisper, title: "Local", subtitle: "Whisper")
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func providerButton(
        _ value: AppSettings.TranscriptionProvider,
        title: String,
        subtitle: String
    ) -> some View {
        Button {
            guard provider != value else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                provider = value
                onChange()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: value.icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            ZStack {
                if provider == value {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.18))
                        .matchedGeometryEffect(id: "provider-switch", in: switchNamespace)
                }
            }
        )
        .foregroundColor(provider == value ? .primary : .secondary)
    }
}

struct SettingsToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var onChange: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: isOn) { _ in onChange() }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
