import SwiftUI
import AVFoundation

// MARK: - Performance Monitor

/// Monitors system performance metrics (CPU, memory) during recording
@MainActor
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()

    @Published var cpuUsage: Double = 0  // 0-100%
    @Published var memoryUsage: Double = 0  // MB
    @Published var memoryTotal: Double = 0  // MB
    @Published var isMonitoring = false

    private var timer: Timer?
    private let updateInterval: TimeInterval = 1.0

    private init() {
        memoryTotal = Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        updateMetrics()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    private func updateMetrics() {
        cpuUsage = getCPUUsage()
        memoryUsage = getMemoryUsage()
    }

    private func getCPUUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = withUnsafeMutablePointer(to: &threadsList) {
            $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadsCount)
            }
        }

        if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
            for index in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                guard infoResult == KERN_SUCCESS else { continue }
                let threadBasicInfo = threadInfo as thread_basic_info
                if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsageOfCPU += Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                }
            }
            let threadListSize = vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threadsList), threadListSize)
        }
        return min(totalUsageOfCPU, 100.0)
    }

    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / 1_000_000
        }
        return 0
    }
}

struct PerformanceMonitorView: View {
    @ObservedObject var monitor = PerformanceMonitor.shared

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.caption2)
                    .foregroundColor(cpuColor)
                Text(String(format: "%.0f%%", monitor.cpuUsage))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(cpuColor)
            }
            HStack(spacing: 4) {
                Image(systemName: "memorychip")
                    .font(.caption2)
                    .foregroundColor(memoryColor)
                Text(String(format: "%.0f MB", monitor.memoryUsage))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(memoryColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .cornerRadius(6)
    }

    private var cpuColor: Color {
        if monitor.cpuUsage > 80 { return .red }
        if monitor.cpuUsage > 50 { return .orange }
        return .green
    }

    private var memoryColor: Color {
        let percentage = monitor.memoryUsage / max(monitor.memoryTotal, 1) * 100
        if percentage > 80 { return .red }
        if percentage > 60 { return .orange }
        return .green
    }
}

// MARK: - Session Recording View

struct SessionRecordingView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = SessionRecordingViewModel()
    @State private var showingSourcePicker = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isRecording {
                ActiveSessionView(viewModel: viewModel)
            } else {
                StartSessionView(viewModel: viewModel, showingSourcePicker: $showingSourcePicker)
            }
        }
        .sheet(isPresented: $showingSourcePicker) {
            AudioSourcePickerView(viewModel: viewModel)
        }
    }
}

// MARK: - Start Session View

struct StartSessionView: View {
    @ObservedObject var viewModel: SessionRecordingViewModel
    @Binding var showingSourcePicker: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.accentColor)
            }

            // Title
            VStack(spacing: 8) {
                Text("Session Recording")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Record meetings, calls, or sessions with speaker identification")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Audio Configuration
            VStack(spacing: 16) {
                // Audio Source
                VStack(alignment: .leading, spacing: 6) {
                    Text("Audio Source")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("", selection: $viewModel.selectedAudioSource) {
                        ForEach(AudioSource.allCases, id: \.self) { source in
                            Label(source.displayName, systemImage: source.icon).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Microphone selector (if mic enabled)
                if viewModel.selectedAudioSource == .microphone || viewModel.selectedAudioSource == .both {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "mic.fill")
                                .foregroundColor(.accentColor)
                            Text("Microphone")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Picker("", selection: $viewModel.selectedMicrophoneID) {
                            Text("Default").tag(nil as String?)
                            ForEach(viewModel.availableMicrophones, id: \.uid) { mic in
                                Text(mic.name).tag(mic.uid as String?)
                            }
                        }
                        .labelsHidden()

                        // Mic level preview
                        AudioLevelBar(level: viewModel.micLevel, color: .green, label: "Mic")
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }

                // System Audio selector (if system enabled)
                if viewModel.selectedAudioSource == .systemAudio || viewModel.selectedAudioSource == .both {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundColor(.blue)
                            Text("System Audio")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Picker("", selection: $viewModel.selectedAppBundleID) {
                            Text("All System Audio (Auto)").tag(nil as String?)
                            ForEach(viewModel.availableAudioApps, id: \.bundleID) { app in
                                HStack {
                                    Text(app.name)
                                }
                                .tag(app.bundleID as String?)
                            }
                        }
                        .labelsHidden()

                        // System audio note (can't preview before recording)
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                            Text("Level shown during recording")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 40)

            // Features list
            VStack(alignment: .leading, spacing: 10) {
                FeatureRow(icon: "person.2.fill", text: "Speaker identification (diarization)")
                FeatureRow(icon: "doc.text.fill", text: "Real-time transcription with timestamps")
                FeatureRow(icon: "arrow.clockwise", text: "Auto-reconnect on connection loss")
            }
            .padding(.horizontal, 40)

            Spacer()

            // Start button
            Button(action: { viewModel.startSession() }) {
                HStack {
                    Image(systemName: "record.circle")
                    Text("Start Session")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .onAppear {
            viewModel.loadAvailableDevices()
            viewModel.startAudioPreview()
        }
        .onDisappear {
            viewModel.stopAudioPreview()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Audio Level Bar

struct AudioLevelBar: View {
    let level: Float
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 45, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))

                    // Level indicator
                    RoundedRectangle(cornerRadius: 3)
                        .fill(levelColor)
                        .frame(width: max(0, geometry.size.width * CGFloat(level)))
                }
            }
            .frame(height: 8)

            // dB indicator
            Text(level > 0.01 ? "\(Int(20 * log10(level))) dB" : "-∞ dB")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50)
        }
    }

    private var levelColor: Color {
        if level > 0.8 {
            return .red
        } else if level > 0.5 {
            return .yellow
        } else {
            return color
        }
    }
}

// MARK: - Active Session View

struct ActiveSessionView: View {
    @ObservedObject var viewModel: SessionRecordingViewModel
    @State private var showingStopConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with audio levels
            SessionHeaderView(viewModel: viewModel)

            Divider()

            // Main content with split view
            HSplitView {
                // Left: Live transcript (playback style)
                LiveTranscriptView(viewModel: viewModel)

                // Right: Speakers panel
                LiveSpeakersPanel(viewModel: viewModel)
                    .frame(minWidth: 200, maxWidth: 280)
            }

            Divider()

            // Footer with controls
            SessionFooterView(
                viewModel: viewModel,
                showingStopConfirmation: $showingStopConfirmation
            )
        }
        .alert("Stop Recording?", isPresented: $showingStopConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Stop", role: .destructive) {
                viewModel.stopSession()
            }
        } message: {
            Text("This will end the session and save the transcript.")
        }
    }
}

// MARK: - Grouped Speaker (for unified display)

struct GroupedSpeaker {
    let displayName: String
    let color: String
    var speakerIDs: [Int]
    var segmentCount: Int
    var source: TranscriptSource?
}

// MARK: - Live Speakers Panel

struct LiveSpeakersPanel: View {
    @ObservedObject var viewModel: SessionRecordingViewModel

    /// Check if we're in dual audio mode (mic + system)
    private var isDualMode: Bool {
        viewModel.selectedAudioSource == .both
    }

    /// Group speakers by name to avoid duplicates
    private var groupedSpeakers: [GroupedSpeaker] {
        var groups: [String: GroupedSpeaker] = [:]

        for speaker in viewModel.speakers {
            let key = speaker.displayName
            let speakerSegments = viewModel.segments.filter { $0.speakerID == speaker.id }

            if var existing = groups[key] {
                existing.speakerIDs.append(speaker.id)
                existing.segmentCount += speakerSegments.count
                groups[key] = existing
            } else {
                groups[key] = GroupedSpeaker(
                    displayName: speaker.displayName,
                    color: speaker.color,
                    speakerIDs: [speaker.id],
                    segmentCount: speakerSegments.count,
                    source: getSpeakerSourceForIDs([speaker.id])
                )
            }
        }

        return Array(groups.values).sorted { $0.segmentCount > $1.segmentCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Speakers")
                    .font(.headline)
                Spacer()
                Text("\(groupedSpeakers.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if viewModel.speakers.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "person.2.wave.2")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Speakers will appear")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("as they are detected")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // Speaker list grouped by name
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(groupedSpeakers, id: \.displayName) { grouped in
                            GroupedSpeakerRow(
                                grouped: grouped,
                                sourceInfo: isDualMode ? grouped.source : nil,
                                audioLevel: getAudioLevelForSource(grouped.source)
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    /// Determine which source speakers primarily come from
    private func getSpeakerSourceForIDs(_ speakerIDs: [Int]) -> TranscriptSource? {
        let speakerSegments = viewModel.segments.filter { speakerIDs.contains($0.speakerID ?? -1) }
        let micCount = speakerSegments.filter { $0.source == .microphone }.count
        let systemCount = speakerSegments.filter { $0.source == .system }.count

        if micCount > systemCount {
            return .microphone
        } else if systemCount > micCount {
            return .system
        }
        return nil
    }

    /// Get the audio level based on source
    private func getAudioLevelForSource(_ source: TranscriptSource?) -> Float {
        guard let source = source else {
            return viewModel.micLevel
        }
        switch source {
        case .microphone:
            return viewModel.micLevel
        case .system:
            return viewModel.systemLevel
        case .unknown:
            return viewModel.micLevel
        }
    }
}

// MARK: - Grouped Speaker Row

struct GroupedSpeakerRow: View {
    let grouped: GroupedSpeaker
    var sourceInfo: TranscriptSource? = nil
    var audioLevel: Float = 0

    private var speakerColor: Color {
        Color(hex: grouped.color) ?? .gray
    }

    private var sourceIcon: String? {
        guard let source = sourceInfo else { return nil }
        switch source {
        case .microphone: return "mic.fill"
        case .system: return "speaker.wave.2.fill"
        case .unknown: return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Color indicator with optional source icon
            ZStack {
                Circle()
                    .fill(speakerColor)
                    .frame(width: 32, height: 32)

                if let icon = sourceIcon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
            }

            // Speaker info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(grouped.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let source = sourceInfo {
                        Text("(\(source == .microphone ? "mic" : "system"))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text("\(grouped.segmentCount) segment\(grouped.segmentCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(speakerColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(speakerColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Live Speaker Row

struct LiveSpeakerRow: View {
    let speaker: Speaker
    let segmentCount: Int
    var sourceInfo: TranscriptSource? = nil  // Optional: shows which audio source
    var audioLevel: Float = 0  // Audio level for glow effect

    private var speakerColor: Color {
        Color(hex: speaker.color) ?? .gray
    }

    private var sourceIcon: String? {
        guard let source = sourceInfo else { return nil }
        switch source {
        case .microphone: return "mic.fill"
        case .system: return "speaker.wave.2.fill"
        case .unknown: return nil
        }
    }

    /// Whether this speaker is currently active (talking)
    private var isActive: Bool {
        audioLevel > 0.05
    }

    /// Glow intensity based on audio level (0 to 1)
    private var glowIntensity: Double {
        guard isActive else { return 0 }
        return Double(min(1.0, audioLevel * 2))
    }

    var body: some View {
        HStack(spacing: 12) {
            // Color indicator with optional source icon
            ZStack {
                // Outer glow when active
                if isActive {
                    Circle()
                        .fill(speakerColor)
                        .frame(width: 24, height: 24)
                        .blur(radius: 4)
                        .opacity(glowIntensity * 0.8)
                }

                Circle()
                    .fill(speakerColor)
                    .frame(width: 20, height: 20)

                if let icon = sourceIcon {
                    Image(systemName: icon)
                        .font(.system(size: 8))
                        .foregroundColor(.white)
                }
            }

            // Speaker info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(speaker.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let source = sourceInfo {
                        Text("(\(source == .microphone ? "mic" : "system"))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text("\(segmentCount) segment\(segmentCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Active indicator
            if isActive {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundColor(speakerColor)
                    .opacity(0.5 + glowIntensity * 0.5)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(speakerColor.opacity(isActive ? 0.15 + glowIntensity * 0.1 : 0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(speakerColor.opacity(isActive ? 0.5 + glowIntensity * 0.3 : 0.3), lineWidth: isActive ? 2 : 1)
        )
        .shadow(color: isActive ? speakerColor.opacity(glowIntensity * 0.4) : .clear, radius: isActive ? 8 : 0)
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .animation(.easeInOut(duration: 0.1), value: audioLevel)
    }
}

// MARK: - Session Header

struct SessionHeaderView: View {
    @ObservedObject var viewModel: SessionRecordingViewModel
    @ObservedObject var performanceMonitor = PerformanceMonitor.shared

    var body: some View {
        VStack(spacing: 8) {
            // Top row: Recording indicator, duration, source
            HStack {
                // Recording indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .opacity(viewModel.recordingPulse ? 1 : 0.5)

                    Text("Recording")
                        .font(.headline)
                        .foregroundColor(.red)
                }

                Spacer()

                // Duration
                Text(viewModel.formattedDuration)
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.medium)

                Spacer()

                // Performance monitor
                PerformanceMonitorView()

                // Speaker detection status
                if viewModel.isRunningIncrementalDetection {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Detecting...")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                } else if !viewModel.detectedSpeakerNames.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill.checkmark")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("\(viewModel.detectedSpeakerNames.count) identified")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
                }

                Spacer()

                // Audio source indicator
                HStack(spacing: 6) {
                    Image(systemName: viewModel.selectedAudioSource.icon)
                        .foregroundColor(.secondary)
                    Text(viewModel.selectedAudioSource.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Audio level meters
            HStack(spacing: 16) {
                if viewModel.selectedAudioSource == .microphone || viewModel.selectedAudioSource == .both {
                    AudioLevelBar(level: viewModel.micLevel, color: .green, label: "Mic")
                }
                if viewModel.selectedAudioSource == .systemAudio || viewModel.selectedAudioSource == .both {
                    AudioLevelBar(level: viewModel.systemLevel, color: .blue, label: "System")
                }
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .onAppear {
            startPulseAnimation()
            performanceMonitor.startMonitoring()
        }
        .onDisappear {
            performanceMonitor.stopMonitoring()
        }
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            viewModel.recordingPulse.toggle()
        }
    }
}

// MARK: - Live Transcript View (Playback Style)

struct LiveTranscriptView: View {
    @ObservedObject var viewModel: SessionRecordingViewModel
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            // Auto-scroll toggle
            HStack {
                Spacer()
                Button(action: { autoScroll.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: autoScroll ? "arrow.down.doc.fill" : "arrow.down.doc")
                        Text(autoScroll ? "Auto-scroll ON" : "Auto-scroll OFF")
                    }
                    .font(.caption)
                    .foregroundColor(autoScroll ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.segments) { segment in
                            LiveSegmentRow(
                                segment: segment,
                                speaker: viewModel.speakers.first(where: { $0.id == segment.speakerID })
                            )
                            .id(segment.id)
                        }

                        // Show active transcription as an "in progress" segment
                        if !viewModel.interimText.isEmpty {
                            ActiveTranscriptionRow(
                                text: viewModel.interimText,
                                source: viewModel.selectedAudioSource == .both ? .system : .unknown
                            )
                            .id("active")
                        }
                    }
                    .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: viewModel.segments.count) { _ in
                    if autoScroll {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if let lastId = viewModel.segments.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Live Segment Row (Chat Style with Speaker Diarization)

struct LiveSegmentRow: View {
    let segment: TranscriptSegment
    let speaker: Speaker?

    /// Check if this is dual mode (source is known)
    private var isDualMode: Bool {
        segment.source != .unknown
    }

    /// Color based on speaker (priority) or source (fallback)
    private var displayColor: Color {
        // If we have a speaker from diarization, use their color
        if let colorHex = speaker?.color {
            return Color(hex: colorHex) ?? .gray
        }
        // Fall back to source color in dual mode
        if isDualMode {
            return Color(hex: segment.source.color) ?? .gray
        }
        return .gray
    }

    /// Display name: speaker name (with source indicator in dual mode)
    private var displayName: String {
        if let speaker = speaker {
            // Show speaker name with source indicator in dual mode
            if isDualMode {
                let sourceEmoji = segment.source == .microphone ? "🎤" : "🔊"
                return "\(sourceEmoji) \(speaker.displayName)"
            }
            return speaker.displayName
        }
        // No speaker identified - show source name in dual mode
        if isDualMode {
            return segment.source.displayName
        }
        return "Speaker"
    }

    /// In dual mode, mic messages align to the right
    private var isFromMic: Bool {
        segment.source == .microphone
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // For dual mode: mic messages on right, system on left
            if isDualMode && isFromMic {
                Spacer()
            }

            // Timestamp (shown on left for system audio, hidden for mic in dual mode)
            if !isDualMode || !isFromMic {
                Text(formatTimestamp(segment.timestamp))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 65, alignment: .trailing)
            }

            // Speaker indicator
            if !isDualMode || !isFromMic {
                VStack(spacing: 4) {
                    Circle()
                        .fill(displayColor)
                        .frame(width: 12, height: 12)

                    Rectangle()
                        .fill(displayColor.opacity(0.3))
                        .frame(width: 2)
                }
            }

            // Content bubble
            VStack(alignment: isDualMode && isFromMic ? .trailing : .leading, spacing: 4) {
                // Speaker name (with source emoji in dual mode)
                Text(displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(displayColor)

                // Text bubble
                Text(segment.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(displayColor.opacity(0.15))
                    )
            }
            .frame(maxWidth: isDualMode ? 500 : .infinity, alignment: isDualMode && isFromMic ? .trailing : .leading)

            // For mic messages in dual mode, show indicator on right
            if isDualMode && isFromMic {
                VStack(spacing: 4) {
                    Circle()
                        .fill(displayColor)
                        .frame(width: 12, height: 12)

                    Rectangle()
                        .fill(displayColor.opacity(0.3))
                        .frame(width: 2)
                }

                // Timestamp on right for mic
                Text(formatTimestamp(segment.timestamp))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 65, alignment: .leading)
            }

            if !isDualMode {
                Spacer()
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%d:%02d.%03d", minutes, secs, millis)
    }
}

// MARK: - Interim Text Row

struct InterimTextRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Placeholder for timestamp
            Text("...")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)

            // Typing indicator
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 12, height: 12)

                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }

                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 2)
            }

            // Interim text
            Text(text)
                .font(.body)
                .foregroundColor(.secondary)
                .italic()

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                        .foregroundColor(.accentColor.opacity(0.3))
                )
        )
    }
}

// MARK: - Active Transcription Indicator (Simple)

struct ActiveTranscriptionRow: View {
    let text: String  // Not displayed, just used to check if active
    let source: TranscriptSource

    @State private var rotation: Double = 0

    private var displayColor: Color {
        Color(hex: source.color) ?? .accentColor
    }

    var body: some View {
        HStack(spacing: 12) {
            Spacer()

            // Simple spinner + text
            HStack(spacing: 8) {
                // Spinning circle indicator
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(displayColor, lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(rotation))

                Text("Transcribing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(NSColor.controlBackgroundColor))
            )

            Spacer()
        }
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animationOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: 5)
                    .offset(y: animationOffset)
                    .animation(
                        Animation.easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animationOffset
                    )
            }
        }
        .onAppear {
            animationOffset = -3
        }
    }
}

// MARK: - Session Footer

struct SessionFooterView: View {
    @ObservedObject var viewModel: SessionRecordingViewModel
    @Binding var showingStopConfirmation: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Stats
            HStack(spacing: 16) {
                StatBadge(icon: "text.word.spacing", value: "\(viewModel.wordCount) words")
                StatBadge(icon: "person.2", value: "\(viewModel.speakerCount) speakers")

                if viewModel.vadEnabled {
                    StatBadge(icon: "bolt", value: "VAD: \(viewModel.vadSavings)")
                }
            }

            Spacer()

            // Stop button
            Button(action: { showingStopConfirmation = true }) {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.red)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}

struct StatBadge: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.caption)
        }
        .foregroundColor(.secondary)
    }
}

// MARK: - Audio Source Picker

struct AudioSourcePickerView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: SessionRecordingViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Audio Configuration")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            List {
                Section("Audio Source") {
                    ForEach(AudioSource.allCases, id: \.self) { source in
                        Button(action: { viewModel.selectedAudioSource = source }) {
                            HStack {
                                Image(systemName: source.icon)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text(source.displayName)
                                    Text(sourceDescription(source))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if viewModel.selectedAudioSource == source {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if viewModel.selectedAudioSource == .microphone || viewModel.selectedAudioSource == .both {
                    Section("Microphone") {
                        Picker("Select Microphone", selection: $viewModel.selectedMicrophoneID) {
                            Text("System Default").tag(nil as String?)
                            ForEach(viewModel.availableMicrophones, id: \.uid) { mic in
                                Text(mic.name).tag(mic.uid as String?)
                            }
                        }
                    }
                }

                if viewModel.selectedAudioSource == .systemAudio || viewModel.selectedAudioSource == .both {
                    Section("System Audio") {
                        Picker("Capture From", selection: $viewModel.selectedAppBundleID) {
                            Text("All System Audio").tag(nil as String?)
                            ForEach(viewModel.availableAudioApps, id: \.bundleID) { app in
                                Label(app.name, systemImage: "app.fill").tag(app.bundleID as String?)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 450, height: 450)
    }

    private func sourceDescription(_ source: AudioSource) -> String {
        switch source {
        case .microphone:
            return "Your voice only"
        case .systemAudio:
            return "Meeting audio, videos, etc."
        case .both:
            return "Your voice + system audio (recommended)"
        }
    }
}

// MARK: - Microphone Info

struct MicrophoneInfo: Identifiable {
    let uid: String
    let name: String

    var id: String { uid }
}

// MARK: - App Info

struct AppInfo {
    let bundleID: String
    let name: String
    let icon: NSImage?
}

// MARK: - View Model

class SessionRecordingViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var recordingPulse = false
    @Published var selectedAudioSource: AudioSource = .both  // Default to both
    @Published var selectedAppBundleID: String? = nil  // nil = all system audio
    @Published var selectedMicrophoneID: String? = nil  // nil = default mic
    @Published var segments: [TranscriptSegment] = []
    @Published var speakers: [Speaker] = []
    @Published var interimText = ""
    @Published var duration: TimeInterval = 0
    @Published var wordCount = 0
    @Published var vadEnabled = true
    @Published var vadSavings = "0%"

    // Audio levels
    @Published var micLevel: Float = 0
    @Published var systemLevel: Float = 0

    // Incremental speaker detection
    @Published var isRunningIncrementalDetection = false
    @Published var lastDetectionTime: TimeInterval = 0
    @Published var detectedSpeakerNames: [Int: String] = [:]  // speakerID -> name

    // Available devices
    @Published var availableMicrophones: [MicrophoneInfo] = []
    @Published var availableAudioApps: [AppInfo] = []

    private var durationTimer: Timer?
    private var levelTimer: Timer?
    private var incrementalDetectionTimer: Timer?
    private let incrementalDetectionInterval: TimeInterval = 10.0  // Run every 10 seconds
    private var recordingService = RecordingService.shared
    private var audioEngine: AVAudioEngine?

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var speakerCount: Int {
        speakers.count
    }

    init() {
        setupNotifications()
        vadEnabled = StorageService.shared.settings.useClientSideVAD
    }

    func loadAvailableDevices() {
        loadMicrophones()
        loadAudioApps()
    }

    private func loadMicrophones() {
        var microphones: [MicrophoneInfo] = []

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else { return }

        for deviceID in deviceIDs {
            // Check if device has input
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var inputSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize)

            if status == noErr && inputSize > 0 {
                let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
                defer { bufferListPointer.deallocate() }

                status = AudioObjectGetPropertyData(deviceID, &inputAddress, 0, nil, &inputSize, bufferListPointer)

                if status == noErr {
                    let bufferList = bufferListPointer.pointee
                    if bufferList.mNumberBuffers > 0 && bufferList.mBuffers.mNumberChannels > 0 {
                        // Get device name
                        var nameAddress = AudioObjectPropertyAddress(
                            mSelector: kAudioDevicePropertyDeviceNameCFString,
                            mScope: kAudioObjectPropertyScopeGlobal,
                            mElement: kAudioObjectPropertyElementMain
                        )

                        var name: CFString = "" as CFString
                        var nameSize = UInt32(MemoryLayout<CFString>.size)
                        status = AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name)

                        if status == noErr {
                            let deviceName = name as String
                            let uid = "\(deviceID)"
                            microphones.append(MicrophoneInfo(uid: uid, name: deviceName))
                        }
                    }
                }
            }
        }

        DispatchQueue.main.async {
            self.availableMicrophones = microphones
        }
    }

    private func loadAudioApps() {
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            let audioPatterns = ["teams", "zoom", "meet", "slack", "discord", "facetime", "chrome", "safari", "firefox", "spotify", "music", "vlc", "youtube"]
            return audioPatterns.contains(where: { bundleID.lowercased().contains($0) }) ||
                   app.localizedName?.lowercased().contains("meet") == true
        }

        availableAudioApps = runningApps.compactMap { app in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return AppInfo(
                bundleID: bundleID,
                name: app.localizedName ?? bundleID,
                icon: app.icon
            )
        }.sorted { $0.name < $1.name }
    }

    func startAudioPreview() {
        // Only start mic preview if microphone is selected
        guard selectedAudioSource == .microphone || selectedAudioSource == .both else {
            return
        }

        // Get sensitivity from settings
        let sensitivity = StorageService.shared.settings.microphoneSensitivity

        // Start audio engine for real mic input preview
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Install tap to measure audio levels
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Calculate RMS level
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)

            var sum: Float = 0
            for i in 0..<frameLength {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(frameLength))

            // Apply noise gate threshold (ignore very low ambient noise)
            // Typical ambient noise is around 0.001-0.01 RMS
            let noiseThreshold: Float = 0.01
            let gatedRMS = rms > noiseThreshold ? rms : 0

            // Apply sensitivity and normalize (0-1 range)
            // Sensitivity acts as a multiplier (1.0 = normal, 2.0 = high sensitivity)
            let normalizedLevel = min(1.0, gatedRMS * sensitivity * 3.0)

            DispatchQueue.main.async {
                // Smooth the level changes for better visual feedback
                let smoothing: Float = 0.3
                self.micLevel = self.micLevel * (1 - smoothing) + normalizedLevel * smoothing

                // Apply a final threshold to show 0 when very quiet
                if self.micLevel < 0.02 {
                    self.micLevel = 0
                }
            }
        }

        do {
            try engine.start()
            print("[AudioPreview] Started mic level monitoring")
        } catch {
            print("[AudioPreview] Failed to start audio engine: \(error)")
        }
    }

    func stopAudioPreview() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        micLevel = 0
        systemLevel = 0
        print("[AudioPreview] Stopped mic level monitoring")
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionTranscriptUpdate),
            name: .sessionTranscriptUpdated,
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
            selector: #selector(handleAudioLevelUpdate),
            name: .audioLevelsUpdated,
            object: nil
        )
    }

    @objc private func handleSessionTranscriptUpdate(_ notification: Notification) {
        guard let session = notification.userInfo?["session"] as? RecordingSession else { return }

        DispatchQueue.main.async {
            self.segments = session.transcriptSegments
            self.speakers = session.speakers
            self.wordCount = session.wordCount
        }
    }

    @objc private func handleTranscriptionReceived(_ notification: Notification) {
        guard let text = notification.userInfo?["text"] as? String,
              let isFinal = notification.userInfo?["isFinal"] as? Bool else { return }

        DispatchQueue.main.async {
            if !isFinal {
                self.interimText = text
            } else {
                self.interimText = ""
            }
        }
    }

    @objc private func handleAudioLevelUpdate(_ notification: Notification) {
        // Mic level comes from AudioCaptureService
        if let micLevel = notification.userInfo?["micLevel"] as? Float {
            DispatchQueue.main.async {
                // Smooth the level changes
                let smoothing: Float = 0.3
                self.micLevel = self.micLevel * (1 - smoothing) + micLevel * smoothing
            }
        }
        // System level comes from SystemAudioCaptureService
        if let systemLevel = notification.userInfo?["systemLevel"] as? Float {
            DispatchQueue.main.async {
                // Smooth the level changes
                let smoothing: Float = 0.3
                self.systemLevel = self.systemLevel * (1 - smoothing) + systemLevel * smoothing
            }
        }
    }

    func startSession() {
        isRecording = true
        segments = []
        speakers = []
        interimText = ""
        duration = 0
        wordCount = 0

        // Stop preview, start real recording
        stopAudioPreview()

        recordingService.startSessionRecording(
            audioSource: selectedAudioSource,
            title: nil
        )

        // Start duration timer
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.duration += 1
        }

        // Continue level monitoring during recording
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            // Real levels would come from notifications
            // This is a fallback simulation
        }

        // Start incremental speaker detection (every 10 seconds)
        detectedSpeakerNames = [:]
        lastDetectionTime = 0
        if #available(macOS 14.0, *) {
            incrementalDetectionTimer = Timer.scheduledTimer(withTimeInterval: incrementalDetectionInterval, repeats: true) { [weak self] _ in
                self?.runIncrementalSpeakerDetection()
            }
        }
    }

    func stopSession() {
        isRecording = false
        durationTimer?.invalidate()
        durationTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        incrementalDetectionTimer?.invalidate()
        incrementalDetectionTimer = nil

        recordingService.stopSessionRecording()
    }

    // MARK: - Incremental Speaker Detection

    @available(macOS 14.0, *)
    private func runIncrementalSpeakerDetection() {
        guard isRecording, !isRunningIncrementalDetection else { return }
        guard let session = recordingService.currentSession,
              let audioURL = session.primaryAudioFileURL else {
            print("[IncrementalDetection] No audio file available yet")
            return
        }

        // Need at least 5 seconds of audio
        guard duration >= 5 else { return }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("[IncrementalDetection] Audio file not found: \(audioURL.path)")
            return
        }

        isRunningIncrementalDetection = true
        lastDetectionTime = duration

        print("[IncrementalDetection] 🔍 Running detection at \(String(format: "%.0f", duration))s...")

        Task {
            do {
                // Run diarization on accumulated audio
                let diarizationResult = try await LocalDiarizationService.shared.processAudioFile(audioURL)

                // Match speakers to known profiles using embeddings
                let voiceProfileService = await MainActor.run { VoiceProfileService.shared }
                let speakerLibrary = await MainActor.run { SpeakerLibrary.shared }

                var newDetections: [Int: String] = [:]

                for (diarizationID, profile) in diarizationResult.speakerProfiles {
                    // Try embedding-based matching
                    if let match = await MainActor.run(body: {
                        voiceProfileService.identifyWithEmbedding(profile.embedding, threshold: 0.45)
                    }) {
                        // Convert diarization ID to numeric ID
                        if let numericID = Int(diarizationID.replacingOccurrences(of: "SPEAKER_", with: "")) {
                            newDetections[numericID] = match.speakerName
                            print("[IncrementalDetection] 🎯 Matched SPEAKER_\(numericID) → '\(match.speakerName)' (confidence: \(String(format: "%.1f%%", match.confidence * 100)))")
                        }
                    }
                }

                await MainActor.run {
                    // Update detected speaker names
                    for (id, name) in newDetections {
                        detectedSpeakerNames[id] = name

                        // Also update the speaker in the viewModel if present
                        if let index = speakers.firstIndex(where: { $0.id == id }) {
                            if speakers[index].name == nil {
                                speakers[index].name = name
                                // Get color from library
                                if let knownSpeaker = speakerLibrary.speakers.first(where: { $0.name == name }) {
                                    speakers[index].color = knownSpeaker.color
                                }
                            }
                        }
                    }

                    isRunningIncrementalDetection = false
                    print("[IncrementalDetection] ✅ Detection complete. Identified \(newDetections.count) speaker(s)")
                }
            } catch {
                await MainActor.run {
                    isRunningIncrementalDetection = false
                    print("[IncrementalDetection] ❌ Detection failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    SessionRecordingView()
        .environmentObject(AppState.shared)
        .frame(width: 1000, height: 700)
}
