import SwiftUI
import AppKit

// MARK: - Speaker Training Tab

struct SpeakerTrainingTab: View {
    let speaker: KnownSpeaker
    @ObservedObject var voiceProfileService = VoiceProfileService.shared
    @State private var showingResetConfirmation = false
    @State private var isTraining = false
    @State private var trainingError: String?
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var previewError: String?
    @State private var loadedSessionID: UUID?
    @State private var playbackStopTask: DispatchWorkItem?
    @State private var sessionsById: [UUID: RecordingSession] = [:]

    private var profile: VoiceProfile? {
        voiceProfileService.getProfile(for: speaker.id)
    }

    private var trainingRecords: [VoiceTrainingRecord] {
        voiceProfileService.getTrainingRecords(for: speaker.id)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Profile status card
                profileStatusCard

                // Training statistics
                if profile != nil {
                    trainingStatsCard
                }

                // Training records list
                if !trainingRecords.isEmpty {
                    trainingRecordsCard
                }

                // Actions
                actionsCard
            }
            .padding()
        }
        .onAppear {
            loadSessionsCache()
        }
        .alert("Reset Voice Profile?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                voiceProfileService.resetProfile(for: speaker.id)
            }
        } message: {
            Text("This will delete the voice profile and all training history for \(speaker.name). This action cannot be undone.")
        }
    }

    // MARK: - Profile Status Card

    private var profileStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Voice Profile Status")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 16) {
                // Status indicator
                Circle()
                    .fill(profile != nil ? Color.green : Color.orange)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(profile != nil ? "Trained" : "Not Trained")
                        .font(.title3)
                        .fontWeight(.semibold)

                    if let profile = profile {
                        Text("Last updated \(profile.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Train the voice profile to enable automatic speaker recognition")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            // Modern embedding status
            if let profile = profile {
                Divider()

                HStack(spacing: 12) {
                    Image(systemName: profile.hasEmbedding ? "checkmark.seal.fill" : "xmark.seal")
                        .foregroundColor(profile.hasEmbedding ? .green : .orange)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Voice Embedding (256-dim)")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            if profile.hasEmbedding {
                                Text("Active")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.green)
                                    .cornerRadius(8)
                            } else {
                                Text("Not Available")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.orange)
                                    .cornerRadius(8)
                            }
                        }

                        Text(profile.hasEmbedding
                            ? "Modern neural voice matching enabled - more accurate speaker recognition"
                            : "Assign speaker in a new session to enable embedding-based matching")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Training Stats Card

    private var trainingStatsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Training Statistics")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                TrainingStatView(
                    title: "Samples",
                    value: "\(profile?.sampleCount ?? 0)",
                    icon: "waveform"
                )

                TrainingStatView(
                    title: "Duration",
                    value: formattedTotalDuration,
                    icon: "clock"
                )

                TrainingStatView(
                    title: "Sessions Used",
                    value: "\(voiceProfileService.trainingSessionCount(for: speaker.id))",
                    icon: "folder"
                )
            }

            if let quality = trainingQuality {
                TrainingQualityRow(quality: quality)
            }

            // Voice features preview
            if let profile = profile {
                Divider()

                Text("Voice Features")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    VoiceFeatureRow(
                        label: "Pitch",
                        value: String(format: "%.1f Hz", profile.features.pitchMean)
                    )

                    VoiceFeatureRow(
                        label: "Energy",
                        value: String(format: "%.4f", profile.features.energyMean)
                    )

                    VoiceFeatureRow(
                        label: "Spectral Centroid",
                        value: String(format: "%.1f", profile.features.spectralCentroid)
                    )

                    VoiceFeatureRow(
                        label: "Zero Crossing Rate",
                        value: String(format: "%.4f", profile.features.zeroCrossingRate)
                    )
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Training Records Card

    private var trainingRecordsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Training Sessions")
                    .font(.headline)
                Spacer()
                Text("\(trainingRecords.count) session(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if audioPlayer.isLoaded {
                TrainingPreviewPlayer(audioPlayer: audioPlayer)
            }

            if let error = audioPlayer.error {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let error = previewError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            ForEach(trainingRecords.sorted(by: { $0.trainedAt > $1.trainedAt })) { record in
                TrainingRecordRow(
                    record: record,
                    onPlayRange: { range in
                        playPreview(record: record, range: range)
                    },
                    onPlayFirst: {
                        if let first = record.segmentTimestamps.first {
                            playPreview(record: record, range: first)
                        }
                    }
                )
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Actions Card

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Actions")
                .font(.headline)

            if profile == nil {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)

                    Text("To train a voice profile, go to a session where \(speaker.name) participated and assign their speaker segments. The profile will be automatically trained.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if profile != nil {
                Button(role: .destructive, action: { showingResetConfirmation = true }) {
                    Label("Reset Voice Profile", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("This will delete all training data and the voice profile will need to be retrained.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(profile != nil ? Color.red.opacity(0.05) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Computed Properties

    private var formattedTotalDuration: String {
        let total = voiceProfileService.totalTrainingDuration(for: speaker.id)
        let minutes = Int(total) / 60
        let seconds = Int(total) % 60

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    private var trainingQuality: TrainingQuality? {
        guard profile != nil else { return nil }
        let total = voiceProfileService.totalTrainingDuration(for: speaker.id)
        let samples = profile?.sampleCount ?? 0

        if total >= 120 || samples >= 8 {
            return .high
        } else if total >= 45 || samples >= 4 {
            return .medium
        } else {
            return .low
        }
    }

    private func playPreview(record: VoiceTrainingRecord, range: SegmentTimeRange) {
        previewError = nil
        Task { @MainActor in
            await loadAndPlay(record: record, range: range)
        }
    }

    @MainActor
    private func loadAndPlay(record: VoiceTrainingRecord, range: SegmentTimeRange) async {
        if sessionsById.isEmpty {
            loadSessionsCache()
        }

        guard let session = sessionsById[record.sessionID] else {
            previewError = "Session not found for this training record"
            return
        }

        guard let audioURL = session.primaryAudioFileURL else {
            previewError = "Audio file not available for this session"
            return
        }

        if loadedSessionID != session.id || !audioPlayer.isLoaded {
            audioPlayer.loadAudio(from: audioURL)
            loadedSessionID = session.id

            // Wait briefly for async load/conversion
            var attempts = 0
            while !audioPlayer.isLoaded && audioPlayer.error == nil && attempts < 20 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                attempts += 1
            }
        }

        if let error = audioPlayer.error {
            previewError = error
            return
        }

        let start = max(0, range.start)
        let end = max(start, range.end)
        let duration = max(0.2, end - start)

        audioPlayer.seek(to: start)
        audioPlayer.play()

        playbackStopTask?.cancel()
        let task = DispatchWorkItem { [weak audioPlayer] in
            audioPlayer?.pause()
        }
        playbackStopTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }

    private func loadSessionsCache() {
        let sessions = StorageService.shared.loadSessions()
        sessionsById = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    }

}

// MARK: - Training Quality

enum TrainingQuality: String {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var color: Color {
        switch self {
        case .low: return .orange
        case .medium: return .blue
        case .high: return .green
        }
    }

    var detail: String {
        switch self {
        case .low: return "Add more segments for better accuracy"
        case .medium: return "Good coverage, more data helps"
        case .high: return "Strong training data"
        }
    }
}

struct TrainingQualityRow: View {
    let quality: TrainingQuality

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge")
                .foregroundColor(quality.color)

            VStack(alignment: .leading, spacing: 2) {
                Text("Training Quality: \(quality.rawValue)")
                    .font(.caption)
                    .foregroundColor(quality.color)
                Text(quality.detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Training Stat View

struct TrainingStatView: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Voice Feature Row

struct VoiceFeatureRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Training Record Row

struct TrainingRecordRow: View {
    let record: VoiceTrainingRecord
    var onPlayRange: ((SegmentTimeRange) -> Void)? = nil
    var onPlayFirst: (() -> Void)? = nil
    @State private var isExpanded = false
    @State private var showAllRanges = false
    @State private var visibleRangeCount = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.sessionTitle ?? "Unknown Session")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        if let date = record.sessionDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("\(record.segmentTimestamps.count) segments")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(record.formattedDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 6) {
                        if record.featuresExtracted {
                            TrainingDataBadge(text: "Audio features")
                        }
                        if record.segmentTimestamps.isEmpty {
                            TrainingDataBadge(text: "Embedding only")
                        } else {
                            TrainingDataBadge(text: "Segment ranges")
                        }
                    }
                }

                Spacer()

                Text(record.trainedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if onPlayFirst != nil && !record.segmentTimestamps.isEmpty {
                    Button(action: { onPlayFirst?() }) {
                        Image(systemName: "play.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Play first segment")
                }

                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Session ID: \(record.sessionID.uuidString.prefix(8))…")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if record.segmentTimestamps.isEmpty {
                        Text("No segment ranges recorded for this training entry.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        let ranges = Array(record.segmentTimestamps.prefix(visibleRangeCount))

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(ranges.enumerated()), id: \.offset) { index, range in
                                    HStack(spacing: 6) {
                                        Text("• \(formatTime(range.start)) – \(formatTime(range.end)) (\(formatDuration(range.duration)))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)

                                        if let onPlayRange = onPlayRange {
                                            Button(action: { onPlayRange(range) }) {
                                                Image(systemName: "play.fill")
                                                    .font(.caption2)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .onAppear {
                                        if index == ranges.count - 1 && visibleRangeCount < record.segmentTimestamps.count {
                                            visibleRangeCount = min(visibleRangeCount + 12, record.segmentTimestamps.count)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 180)

                        HStack(spacing: 8) {
                            if visibleRangeCount < record.segmentTimestamps.count {
                                Text("\(visibleRangeCount)/\(record.segmentTimestamps.count) loaded")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Button("Copy ranges") {
                                copyRanges(record.segmentTimestamps)
                            }
                            .font(.caption2)
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding(.vertical, 6)
    }

    private func copyRanges(_ ranges: [SegmentTimeRange]) {
        let text = ranges
            .map { "\(formatTime($0.start)) – \(formatTime($0.end))" }
            .joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }
}

// MARK: - Training Preview Player

struct TrainingPreviewPlayer: View {
    @ObservedObject var audioPlayer: AudioPlayerManager

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { audioPlayer.togglePlayPause() }) {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Text(formatTime(audioPlayer.currentTime))
                .font(.caption2)
                .foregroundColor(.secondary)

            Slider(value: Binding(
                get: { audioPlayer.currentTime },
                set: { audioPlayer.seek(to: $0) }
            ), in: 0...max(audioPlayer.duration, 0.1))

            Text(formatTime(audioPlayer.duration))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Training Data Badge

struct TrainingDataBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
    }
}

#Preview {
    SpeakerTrainingTab(speaker: KnownSpeaker(name: "Test Speaker"))
        .frame(width: 600, height: 500)
}
