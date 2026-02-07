import SwiftUI
import AppKit

// MARK: - Session Detail Tab

enum SessionDetailTab: String, CaseIterable {
    case transcript = "Transcript"
    case summary = "Summary"
    case actions = "Actions"

    var icon: String {
        switch self {
        case .transcript: return "text.alignleft"
        case .summary: return "doc.text"
        case .actions: return "checkmark.circle"
        }
    }
}

struct SourceTranscriptionProgress: Identifiable {
    enum ProgressState {
        case pending
        case inProgress
        case completed
        case failed
    }

    let source: TranscriptSource
    let fileName: String
    let fileSize: Int64
    var progressInfo: TranscriptionProgressInfo?
    var whisperProgress: WhisperProgressInfo?
    var state: ProgressState
    var resultSegments: Int
    var resultSpeakers: Int
    var errorMessage: String?

    var id: String {
        "\(source.rawValue)_\(fileName)"
    }
}

// MARK: - Transcription Progress Modal

struct TranscriptionProgressModal: View {
    let progressInfo: TranscriptionProgressInfo?
    let currentFile: Int
    let totalFiles: Int
    let resultSegments: Int
    let resultSpeakers: Int
    let errorMessage: String?
    let onCancel: () -> Void
    let isLocal: Bool
    let whisperProgress: WhisperProgressInfo?
    let isDiarizationEnabled: Bool
    let sourceProgresses: [SourceTranscriptionProgress]

    private var phase: TranscriptionProgressInfo.TranscriptionPhase {
        progressInfo?.phase ?? .preparing
    }

    private var uploadProgress: Double {
        progressInfo?.uploadProgress ?? 0
    }

    private func localPhaseInfo(for whisperProgress: WhisperProgressInfo?) -> LocalPhaseInfo {
        let phase = whisperProgress?.phase
        let modelName = whisperProgress?.modelName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let globalProgress = whisperProgress?.progress ?? 0

        let isDecoding = modelName?.localizedCaseInsensitiveContains("decod") == true
        let isTranscribing = modelName?.localizedCaseInsensitiveContains("transcrib") == true
        let isDiarizing = isDiarizationEnabled && (modelName?.localizedCaseInsensitiveContains("diariz") == true || modelName?.localizedCaseInsensitiveContains("speaker") == true)
        let isMerging = modelName?.localizedCaseInsensitiveContains("merge") == true
        let isMatching = modelName?.localizedCaseInsensitiveContains("match") == true
        let isParsing = modelName?.localizedCaseInsensitiveContains("pars") == true

        // Determine current phase based on modelName content
        let localPhase: LocalPhase
        switch phase {
        case .loadingModel, .downloadingModel:
            localPhase = .preparing
        case .processing:
            if isDecoding {
                localPhase = .decoding
            } else if isDiarizing || isMerging || isMatching {
                localPhase = .diarizing
            } else if isParsing {
                localPhase = .parsing
            } else {
                localPhase = .transcribing
            }
        case .completed:
            localPhase = .completed
        case .failed:
            localPhase = .parsing
        case .none:
            localPhase = .preparing
        }

        // Calculate phase-specific progress based on global progress ranges
        // Decoding: 0% - 15% global → 0% - 100% phase
        // Transcribing: 15% - 85% global → 0% - 100% phase  
        // Diarizing: 85% - 98% global → 0% - 100% phase
        // Parsing: 98% - 100% global → 0% - 100% phase
        
        let decodingProgress: Double?
        let transcribingProgress: Double?
        let diarizingProgress: Double?
        
        switch localPhase {
        case .preparing:
            decodingProgress = nil
            transcribingProgress = nil
            diarizingProgress = nil
        case .decoding:
            // Map 0-0.15 to 0-1.0
            decodingProgress = min(1.0, globalProgress / 0.15)
            transcribingProgress = nil
            diarizingProgress = nil
        case .transcribing:
            decodingProgress = nil // completed
            // Map 0.15-0.85 to 0-1.0
            transcribingProgress = min(1.0, max(0, (globalProgress - 0.15) / 0.70))
            diarizingProgress = nil
        case .diarizing:
            decodingProgress = nil
            transcribingProgress = nil
            // Map 0.85-0.98 to 0-1.0
            diarizingProgress = min(1.0, max(0, (globalProgress - 0.85) / 0.13))
        case .parsing, .completed:
            decodingProgress = nil
            transcribingProgress = nil
            diarizingProgress = nil
        }

        let preparingTitle: String
        switch phase {
        case .downloadingModel:
            preparingTitle = "Downloading model"
        case .loadingModel:
            preparingTitle = "Loading model"
        default:
            preparingTitle = "Preparing"
        }

        let decodingTitle = modelName?.isEmpty == false && isDecoding ? modelName! : "Decoding audio"
        let transcribingTitle: String
        if let name = modelName, !name.isEmpty, isTranscribing {
            transcribingTitle = name
        } else if localPhase == .transcribing {
            transcribingTitle = "Transcribing locally"
        } else {
            transcribingTitle = "Transcribing locally"
        }
        
        let diarizingTitle: String
        if isMatching {
            diarizingTitle = "Matching speakers"
        } else if isMerging {
            diarizingTitle = "Merging results"
        } else if let name = modelName, !name.isEmpty, isDiarizing {
            diarizingTitle = name
        } else {
            diarizingTitle = "Diarizing speakers"
        }

        return LocalPhaseInfo(
            phase: localPhase,
            globalProgress: globalProgress,
            decodingProgress: decodingProgress,
            transcribingProgress: transcribingProgress,
            diarizingProgress: diarizingProgress,
            preparingTitle: preparingTitle,
            decodingTitle: decodingTitle,
            transcribingTitle: transcribingTitle,
            diarizingTitle: diarizingTitle
        )
    }

    private var orderedSourceProgresses: [SourceTranscriptionProgress] {
        sourceProgresses.sorted { lhs, rhs in
            sourceSortKey(lhs.source) < sourceSortKey(rhs.source)
        }
    }

    private var showsDualColumns: Bool {
        Set(sourceProgresses.map(\.source.rawValue)).count >= 2
    }

    private var modalWidth: CGFloat {
        guard showsDualColumns else { return 420 }
        let columns = max(2, min(orderedSourceProgresses.count, 3))
        let desiredWidth = CGFloat(columns) * 390
        let availableWidth = max(420, (NSScreen.main?.visibleFrame.width ?? 1400) - 120)
        return min(desiredWidth, availableWidth)
    }

    private struct LocalPhaseInfo {
        let phase: LocalPhase
        let globalProgress: Double
        let decodingProgress: Double?
        let transcribingProgress: Double?
        let diarizingProgress: Double?
        let preparingTitle: String
        let decodingTitle: String
        let transcribingTitle: String
        let diarizingTitle: String
    }

    private enum LocalPhase: Comparable {
        case preparing
        case decoding
        case transcribing
        case diarizing
        case parsing
        case completed
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "waveform.badge.plus")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text(isLocal ? "Transcribing Locally" : "Transcribing Audio")
                    .font(.headline)
                Spacer()
            }

            Divider()

            if showsDualColumns {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(orderedSourceProgresses) { sourceProgress in
                            sourceProgressColumn(sourceProgress)
                                .frame(width: 370, alignment: .topLeading)
                        }
                    }
                }
            } else {
                // File info
                if let info = progressInfo {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.fileName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(info.fileSizeFormatted)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if totalFiles > 1 {
                            Text("Part \(currentFile)/\(totalFiles)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                progressSteps(
                    progressInfo: progressInfo,
                    whisperProgress: whisperProgress,
                    isPending: false
                )
            }

            // Error message with details
            if let error = errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Transcription Failed")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        Spacer()
                    }

                    ScrollView {
                        Text(error)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 100)

                    // Copy error button
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(error, forType: .string)
                    }) {
                        Label("Copy Error", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            // Completed results
            if phase == .completed && resultSegments > 0 {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.quote")
                            .foregroundColor(.green)
                        Text("\(resultSegments) segments")
                            .font(.subheadline)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.green)
                        Text("\(resultSpeakers) speakers")
                            .font(.subheadline)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }

            Spacer()

            // Buttons
            HStack {
                if errorMessage != nil {
                    // Close button when there's an error
                    Button("Close") {
                        onCancel()
                    }
                    .buttonStyle(.borderedProminent)
                } else if phase != .completed {
                    // Cancel button while in progress
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
        .frame(width: modalWidth)
        .frame(minHeight: 450, maxHeight: 650)
    }

    @ViewBuilder
    private func progressSteps(
        progressInfo: TranscriptionProgressInfo?,
        whisperProgress: WhisperProgressInfo?,
        isPending: Bool
    ) -> some View {
        VStack(spacing: 12) {
            if isPending {
                if isLocal {
                    ProgressStepRow(icon: "cpu", title: "Preparing", isActive: false, isCompleted: false, progress: nil)
                    ProgressStepRow(icon: "waveform", title: "Decoding audio", isActive: false, isCompleted: false, progress: nil)
                    ProgressStepRow(icon: "waveform", title: "Transcribing locally", isActive: false, isCompleted: false, progress: nil)
                    if isDiarizationEnabled {
                        ProgressStepRow(icon: "person.2.fill", title: "Diarizing speakers", isActive: false, isCompleted: false, progress: nil)
                    }
                    ProgressStepRow(icon: "text.magnifyingglass", title: "Parsing results", isActive: false, isCompleted: false, progress: nil)
                } else {
                    ProgressStepRow(icon: "doc.fill", title: "Preparing", isActive: false, isCompleted: false, progress: nil)
                    ProgressStepRow(icon: "arrow.up.circle.fill", title: "Uploading to Deepgram", isActive: false, isCompleted: false, progress: nil)
                    ProgressStepRow(icon: "waveform", title: "Processing with Nova-3", isActive: false, isCompleted: false, progress: nil)
                    ProgressStepRow(icon: "text.magnifyingglass", title: "Parsing results", isActive: false, isCompleted: false, progress: nil)
                    if isDiarizationEnabled {
                        ProgressStepRow(icon: "person.2.fill", title: "Matching speakers", isActive: false, isCompleted: false, progress: nil)
                    }
                }
            } else if isLocal {
                let localPhaseInfo = localPhaseInfo(for: whisperProgress)
                let localPhase = localPhaseInfo.phase
                ProgressStepRow(
                    icon: "cpu",
                    title: localPhaseInfo.preparingTitle,
                    isActive: localPhase == .preparing,
                    isCompleted: localPhase > .preparing,
                    progress: nil
                )

                ProgressStepRow(
                    icon: "waveform",
                    title: localPhaseInfo.decodingTitle,
                    isActive: localPhase == .decoding,
                    isCompleted: localPhase > .decoding,
                    progress: localPhaseInfo.decodingProgress
                )

                ProgressStepRow(
                    icon: "waveform",
                    title: localPhaseInfo.transcribingTitle,
                    isActive: localPhase == .transcribing,
                    isCompleted: localPhase > .transcribing,
                    progress: localPhaseInfo.transcribingProgress
                )

                if isDiarizationEnabled {
                    ProgressStepRow(
                        icon: "person.2.fill",
                        title: localPhaseInfo.diarizingTitle,
                        isActive: localPhase == .diarizing,
                        isCompleted: localPhase > .diarizing,
                        progress: localPhaseInfo.diarizingProgress
                    )
                }

                ProgressStepRow(
                    icon: "text.magnifyingglass",
                    title: "Parsing results",
                    isActive: localPhase == .parsing,
                    isCompleted: localPhase == .completed,
                    progress: nil
                )
            } else {
                let phase = progressInfo?.phase ?? .preparing
                let uploadProgress = progressInfo?.uploadProgress ?? 0
                ProgressStepRow(
                    icon: "doc.fill",
                    title: "Preparing",
                    isActive: phase == .preparing,
                    isCompleted: phase != .preparing,
                    progress: nil
                )

                // Uploading section with chunk details
                VStack(spacing: 8) {
                    ProgressStepRow(
                        icon: "arrow.up.circle.fill",
                        title: "Uploading to Deepgram",
                        isActive: phase == .uploading,
                        isCompleted: [.processing, .parsing, .completed].contains(phase),
                        progress: phase == .uploading ? (progressInfo?.overallUploadProgress ?? uploadProgress) : nil
                    )

                    // Show individual chunk progress when uploading multiple chunks
                    if let info = progressInfo, info.totalChunks > 1, phase == .uploading || phase == .processing {
                        ChunkProgressGrid(
                            chunkProgresses: info.chunkProgresses,
                            totalChunks: info.totalChunks,
                            completedChunks: info.completedChunks
                        )
                        .padding(.leading, 40)
                    }
                }

                ProgressStepRow(
                    icon: "waveform",
                    title: "Processing with Nova-3",
                    isActive: phase == .processing && !(whisperProgress?.modelName?.localizedCaseInsensitiveContains("match") == true),
                    isCompleted: [.parsing, .completed].contains(phase) || (whisperProgress?.modelName?.localizedCaseInsensitiveContains("match") == true),
                    progress: nil
                )

                ProgressStepRow(
                    icon: "text.magnifyingglass",
                    title: "Parsing results",
                    isActive: phase == .parsing && !(whisperProgress?.modelName?.localizedCaseInsensitiveContains("match") == true),
                    isCompleted: phase == .completed || (whisperProgress?.modelName?.localizedCaseInsensitiveContains("match") == true),
                    progress: nil
                )

                // Show speaker matching step when diarization is enabled
                if isDiarizationEnabled {
                    let isMatchingActive = whisperProgress?.modelName?.localizedCaseInsensitiveContains("match") == true ||
                        whisperProgress?.modelName?.localizedCaseInsensitiveContains("extract") == true
                    ProgressStepRow(
                        icon: "person.2.fill",
                        title: isMatchingActive ? (whisperProgress?.modelName ?? "Matching speakers...") : "Matching speakers",
                        isActive: isMatchingActive && phase != .completed,
                        isCompleted: phase == .completed,
                        progress: isMatchingActive ? whisperProgress?.progress : nil
                    )
                }
            }
        }
    }

    private func sourceSortKey(_ source: TranscriptSource) -> Int {
        switch source {
        case .microphone: return 0
        case .system: return 1
        case .unknown: return 2
        }
    }

    private func sourceDisplayName(_ source: TranscriptSource) -> String {
        switch source {
        case .microphone: return "Microphone"
        case .system: return "System Audio"
        case .unknown: return "Audio"
        }
    }

    private func sourceIcon(_ source: TranscriptSource) -> String {
        switch source {
        case .microphone: return "mic.fill"
        case .system: return "speaker.wave.2.fill"
        case .unknown: return "waveform"
        }
    }

    private func sourceStateLabel(_ state: SourceTranscriptionProgress.ProgressState) -> String {
        switch state {
        case .pending: return "Pending"
        case .inProgress: return "Running"
        case .completed: return "Done"
        case .failed: return "Failed"
        }
    }

    private func sourceStateColor(_ state: SourceTranscriptionProgress.ProgressState) -> Color {
        switch state {
        case .pending: return .secondary
        case .inProgress: return .accentColor
        case .completed: return .green
        case .failed: return .red
        }
    }

    @ViewBuilder
    private func sourceProgressColumn(_ sourceProgress: SourceTranscriptionProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(sourceDisplayName(sourceProgress.source), systemImage: sourceIcon(sourceProgress.source))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(sourceStateLabel(sourceProgress.state))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(sourceStateColor(sourceProgress.state))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(sourceStateColor(sourceProgress.state).opacity(0.15))
                    .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(sourceProgress.fileName)
                    .font(.caption)
                    .lineLimit(1)
                Text(formatFileSize(sourceProgress.fileSize))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            progressSteps(
                progressInfo: sourceProgress.progressInfo,
                whisperProgress: sourceProgress.whisperProgress,
                isPending: sourceProgress.state == .pending
            )

            if sourceProgress.state == .completed && sourceProgress.resultSegments > 0 {
                HStack(spacing: 10) {
                    Label("\(sourceProgress.resultSegments)", systemImage: "text.quote")
                        .font(.caption)
                    Label("\(sourceProgress.resultSpeakers)", systemImage: "person.2.fill")
                        .font(.caption)
                }
                .foregroundColor(.green)
                .padding(.top, 4)
            }

            if sourceProgress.state == .failed, let sourceError = sourceProgress.errorMessage {
                Text(sourceError)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private func formatFileSize(_ fileSize: Int64) -> String {
        if fileSize < 1024 {
            return "\(fileSize) B"
        } else if fileSize < 1024 * 1024 {
            return String(format: "%.1f KB", Double(fileSize) / 1024)
        } else {
            return String(format: "%.1f MB", Double(fileSize) / (1024 * 1024))
        }
    }
}

// MARK: - Progress Step Row

struct ProgressStepRow: View {
    let icon: String
    let title: String
    let isActive: Bool
    let isCompleted: Bool
    let progress: Double?  // 0.0 to 1.0, nil means indeterminate

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green : (isActive ? Color.accentColor : Color.gray.opacity(0.3)))
                    .frame(width: 28, height: 28)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                } else if isActive {
                    if let progress = progress {
                        // Determinate progress
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        // Indeterminate spinner
                        ProgressView()
                            .scaleEffect(0.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                } else {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            // Title and progress bar
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(isActive || isCompleted ? .primary : .secondary)

                if isActive, let progress = progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 4)
                                .cornerRadius(2)

                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * progress, height: 4)
                                .cornerRadius(2)
                        }
                    }
                    .frame(height: 4)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Chunk Progress Grid

struct ChunkProgressGrid: View {
    let chunkProgresses: [ChunkUploadProgress]
    let totalChunks: Int
    let completedChunks: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Summary text
            HStack {
                Text("\(completedChunks)/\(totalChunks) chunks completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            // Grid of chunk progress indicators
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60, maximum: 80), spacing: 4)], spacing: 4) {
                ForEach(chunkProgresses) { chunk in
                    ChunkProgressCell(chunk: chunk)
                }
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

// MARK: - Chunk Progress Cell

struct ChunkProgressCell: View {
    let chunk: ChunkUploadProgress

    var body: some View {
        VStack(spacing: 2) {
            // Chunk number
            Text("#\(chunk.id + 1)")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)

            // Progress indicator
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 16)

                // Progress fill
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(progressColor)
                        .frame(width: geo.size.width * chunk.progress, height: 16)
                }
                .frame(height: 16)

                // Status icon or percentage
                Group {
                    switch chunk.phase {
                    case .pending:
                        Image(systemName: "clock")
                            .font(.system(size: 8))
                            .foregroundColor(.gray)
                    case .uploading:
                        Text("\(Int(chunk.progress * 100))%")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    case .processing:
                        ProgressView()
                            .scaleEffect(0.4)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    case .completed:
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    case .failed:
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .frame(width: 50)
    }

    private var progressColor: Color {
        switch chunk.phase {
        case .pending:
            return Color.gray.opacity(0.3)
        case .uploading:
            return Color.accentColor
        case .processing:
            return Color.orange
        case .completed:
            return Color.green
        case .failed:
            return Color.red
        }
    }
}

// MARK: - Speaker Embedding Matching Helper

/// Matches Deepgram speakers to known voice profiles using local diarization embeddings
@available(macOS 14.0, *)
func matchDeepgramSpeakersWithLocalEmbeddings(
    audioURL: URL,
    segments: [TranscriptSegment],
    speakers: [Speaker],
    onProgress: ((String) -> Void)? = nil
) async throws -> (segments: [TranscriptSegment], speakers: [Speaker]) {
    guard !speakers.isEmpty else {
        return (segments, speakers)
    }
    
    onProgress?("Extracting speaker embeddings...")
    
    // Run local diarization to extract embeddings
    let diarizationResult: LocalDiarizationResult
    do {
        diarizationResult = try await LocalDiarizationService.shared.processAudioFile(audioURL)
        print("[DeepgramMatch] ✅ Local diarization complete: \(diarizationResult.speakerCount) speakers")
    } catch {
        print("[DeepgramMatch] ⚠️ Local diarization failed, continuing without speaker matching: \(error.localizedDescription)")
        return (segments, speakers)
    }
    
    onProgress?("Matching speakers to profiles...")
    
    // Map Deepgram speaker IDs to local diarization speaker IDs based on time overlap
    var deepgramToLocalMap: [Int: String] = [:]
    
    for segment in segments {
        guard let deepgramSpeakerID = segment.speakerID else { continue }
        guard deepgramToLocalMap[deepgramSpeakerID] == nil else { continue }
        
        // Find the local speaker at this segment's timestamp
        if let localSpeakerID = LocalDiarizationService.shared.getSpeakerAtTimeWithCarryForward(
            diarizationResult,
            time: segment.timestamp
        ) {
            deepgramToLocalMap[deepgramSpeakerID] = localSpeakerID
            print("[DeepgramMatch] 🔗 Mapped Deepgram speaker \(deepgramSpeakerID) → Local '\(localSpeakerID)'")
        }
    }
    
    // Match local speakers to known profiles
    let voiceProfileService = await MainActor.run { VoiceProfileService.shared }
    let speakerLibrary = await MainActor.run { SpeakerLibrary.shared }
    
    var speakerNameMap: [Int: String] = [:]
    var speakerColorMap: [Int: String] = [:]
    var speakerEmbeddingMap: [Int: [Float]] = [:]
    
    for (deepgramID, localID) in deepgramToLocalMap {
        guard let profile = diarizationResult.speakerProfiles[localID] else { continue }
        
        // Store the embedding for this speaker
        speakerEmbeddingMap[deepgramID] = profile.embedding
        
        // Try to match to a known profile
        if let match = await MainActor.run(body: {
            voiceProfileService.identifyWithEmbedding(profile.embedding, threshold: 0.45)
        }) {
            speakerNameMap[deepgramID] = match.speakerName
            print("[DeepgramMatch] 🎯 Matched Deepgram speaker \(deepgramID) → '\(match.speakerName)' (confidence: \(String(format: "%.1f%%", match.confidence * 100)))")
            
            // Get color from library
            if let knownSpeaker = await MainActor.run(body: { speakerLibrary.getSpeaker(byID: match.speakerID) }) {
                speakerColorMap[deepgramID] = knownSpeaker.color
            }
        } else {
            print("[DeepgramMatch] 👤 Deepgram speaker \(deepgramID) - no matching profile found")
        }
    }
    
    print("[DeepgramMatch] 📊 Auto-identified \(speakerNameMap.count)/\(speakers.count) speakers")
    
    // Update speakers with names, colors, and embeddings
    let updatedSpeakers = speakers.map { speaker -> Speaker in
        var updated = speaker
        if let name = speakerNameMap[speaker.id] {
            updated.name = name
        }
        if let color = speakerColorMap[speaker.id] {
            updated.color = color
        }
        if let embedding = speakerEmbeddingMap[speaker.id] {
            updated.embedding = embedding
        }
        return updated
    }
    
    return (segments, updatedSpeakers)
}

// MARK: - Session Detail View

struct SessionDetailView: View {
    @Binding var session: RecordingSession
    @State private var editingTitle = false
    @State private var newTitle = ""
    @State private var showingExport = false
    @State private var selectedTab: SessionDetailTab = .transcript
    @State private var isRegeneratingTranscript = false
    @State private var regenerateError: String?
    @State private var showingRegenerateConfirm = false
    @State private var showingProgressModal = false
    @State private var progressInfo: TranscriptionProgressInfo?
    @State private var whisperProgress: WhisperProgressInfo?
    @State private var currentFileIndex = 1
    @State private var totalFilesCount = 1
    @State private var transcriptionResultSegments = 0
    @State private var transcriptionResultSpeakers = 0
    @State private var sourceProgresses: [SourceTranscriptionProgress] = []
    @State private var showingLargeFileWarning = false
    @State private var largeFileInfo: (size: Int64, duration: TimeInterval)?
    @State private var selectedRegenerateLanguage: String? = nil  // nil = auto-detect

    // Shared audio player - visible across both tabs
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var autoScroll = true
    @State private var playbackSpeed: Float = 1.0
    @State private var syncOffset: Double = 0.0

    private var settings: AppSettings {
        StorageService.shared.settings
    }

    var body: some View {
        VStack(spacing: 0) {
            // Unified header
            HStack(spacing: 16) {
                // Title editing
                if editingTitle {
                    HStack(spacing: 8) {
                        TextField("Session title", text: $newTitle, onCommit: {
                            if !newTitle.isEmpty {
                                session.title = newTitle
                            }
                            editingTitle = false
                        })
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)

                        Button(action: {
                            if !newTitle.isEmpty {
                                session.title = newTitle
                            }
                            editingTitle = false
                        }) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            editingTitle = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(session.displayTitle)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .onTapGesture {
                        newTitle = session.title ?? ""
                        editingTitle = true
                    }
                    .help("Click to edit title")
                }

                Spacer()

                // Session type picker
                Picker("Type", selection: $session.sessionType) {
                    ForEach(SessionType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)

                // Stats
                HStack(spacing: 12) {
                    StatLabel(icon: "clock", value: session.formattedDuration)
                    StatLabel(icon: "person.2", value: "\(session.uniqueSpeakerCount) speakers")
                    StatLabel(icon: "text.word.spacing", value: "\(session.wordCount) words")
                }

                // Regenerate transcription button
                Button(action: { showingRegenerateConfirm = true }) {
                    if isRegeneratingTranscript {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                            Text("Transcribing...")
                        }
                    } else {
                        Label("Regenerate", systemImage: "waveform.badge.plus")
                    }
                }
                .disabled(isRegeneratingTranscript || !session.hasAudioFile)
                .help(session.hasAudioFile ? "Regenerate transcription from audio" : "No audio file available")

                // Export button
                Button(action: { showingExport = true }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            // Tab bar
            HStack(spacing: 0) {
                ForEach(SessionDetailTab.allCases, id: \.self) { tab in
                    SessionDetailTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        hasSummary: tab == .summary && session.summary != nil,
                        action: { selectedTab = tab }
                    )
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main content based on selected tab
            switch selectedTab {
            case .transcript:
                SessionPlaybackView(
                    session: $session,
                    audioPlayer: audioPlayer,
                    autoScroll: $autoScroll,
                    syncOffset: syncOffset
                )
            case .summary:
                SessionSummaryView(session: $session)
            case .actions:
                SessionActionsView(session: $session)
            }

            // Always visible player controls at the bottom
            Divider()

            PlaybackControlsView(
                audioPlayer: audioPlayer,
                autoScroll: $autoScroll,
                playbackSpeed: $playbackSpeed,
                syncOffset: $syncOffset
            )
        }
        .onAppear {
            loadAudio()
        }
        .onReceive(NotificationCenter.default.publisher(for: .seekToTimestamp)) { notification in
            // When a timestamp is clicked in the summary, seek to that time
            if let timestamp = notification.userInfo?["timestamp"] as? TimeInterval {
                audioPlayer.seek(to: timestamp)
                // Start playback if not already playing
                if !audioPlayer.isPlaying {
                    audioPlayer.togglePlayPause()
                }
            }
        }
        .sheet(isPresented: $showingExport) {
            ExportSessionView(session: session)
        }
        .sheet(isPresented: $showingRegenerateConfirm) {
            RegenerateTranscriptionSheet(
                selectedLanguage: $selectedRegenerateLanguage,
                onRegenerate: {
                    showingRegenerateConfirm = false
                    checkFileSizeAndTranscribe()
                },
                onCancel: {
                    showingRegenerateConfirm = false
                }
            )
        }
        .alert("Large Audio File", isPresented: $showingLargeFileWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Split & Transcribe (Recommended)") {
                regenerateTranscriptionChunked()
            }
            Button("Proceed Anyway") {
                regenerateTranscription()
            }
        } message: {
            if let info = largeFileInfo {
                let sizeMB = Double(info.size) / (1024 * 1024)
                let durationHours = info.duration / 3600
                Text("This audio file is \(String(format: "%.0f MB", sizeMB)) (\(String(format: "%.1f hours", durationHours))). Very large files may timeout.\n\n• Split & Transcribe: Splits into 30-min chunks (recommended)\n• Proceed Anyway: Try single file (may timeout)")
            } else {
                Text("This audio file may be too large for reliable transcription.")
            }
        }
        .alert("Transcription Error", isPresented: .constant(regenerateError != nil && !showingProgressModal)) {
            Button("OK") { regenerateError = nil }
        } message: {
            Text(regenerateError ?? "Unknown error")
        }
        .sheet(isPresented: $showingProgressModal) {
            TranscriptionProgressModal(
                progressInfo: progressInfo,
                currentFile: currentFileIndex,
                totalFiles: totalFilesCount,
                resultSegments: transcriptionResultSegments,
                resultSpeakers: transcriptionResultSpeakers,
                errorMessage: regenerateError,
                onCancel: {
                    // Note: Cancellation of in-flight request not implemented yet
                    showingProgressModal = false
                    isRegeneratingTranscript = false
                },
                isLocal: settings.transcriptionProvider == .whisper,
                whisperProgress: whisperProgress,
                isDiarizationEnabled: settings.enableDiarization,
                sourceProgresses: sourceProgresses
            )
        }
    }

    /// Check file size before transcription and warn if too large
    private func loadAudio() {
        // Check if we have dual audio files
        if session.isDualAudioMode {
            let micURL = session.micAudioFileURL
            let systemURL = session.systemAudioFileURL
            audioPlayer.loadDualAudio(micURL: micURL, systemURL: systemURL)
            print("[SessionDetail] Loaded dual audio mode")
        } else if let url = session.primaryAudioFileURL {
            // Single audio file
            audioPlayer.loadAudio(from: url)
            print("[SessionDetail] Loaded single audio mode")
        }
    }

    private func checkFileSizeAndTranscribe() {
        // Get all audio files to check
        var filesToCheck: [URL] = []
        if session.isDualAudioMode {
            if let micURL = session.micAudioFileURL {
                filesToCheck.append(micURL)
            }
            if let systemURL = session.systemAudioFileURL {
                filesToCheck.append(systemURL)
            }
        } else if let audioURL = session.primaryAudioFileURL {
            filesToCheck.append(audioURL)
        }

        // Calculate total size
        var totalSize: Int64 = 0
        for url in filesToCheck {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int64 {
                totalSize += size
            }
        }

        // Get session duration
        let duration = session.endDate?.timeIntervalSince(session.startDate) ?? 0

        // Check if over recommended limits
        let isOverSizeLimit = totalSize > DeepgramService.maxRecommendedFileSize
        let isOverDurationLimit = duration > DeepgramService.maxRecommendedDuration

        if isOverSizeLimit || isOverDurationLimit {
            largeFileInfo = (size: totalSize, duration: duration)
            showingLargeFileWarning = true
        } else {
            // Proceed directly
            regenerateTranscription()
        }
    }

    private func regenerateTranscription() {
        guard session.hasAudioFile else {
            regenerateError = "No audio file available"
            return
        }

        let settings = StorageService.shared.settings

        // Validate based on provider
        if settings.transcriptionProvider == .deepgram {
            guard !settings.apiKey.isEmpty else {
                regenerateError = "Deepgram API key not configured. Please set it in Settings."
                return
            }
        } else {
            // Whisper local
            guard WhisperService.shared.isModelLoaded else {
                regenerateError = "Whisper model not loaded. Please load a model in Settings."
                return
            }
        }

        // Determine language - use selected language if set, otherwise fall back to settings
        let transcriptionLanguage: String? = selectedRegenerateLanguage ?? (settings.language?.isEmpty == false ? settings.language : nil)
        print("[SessionDetail] 🌍 Using language for transcription: \(transcriptionLanguage ?? "auto-detect")")

        // Reset state
        isRegeneratingTranscript = true
        regenerateError = nil
        progressInfo = nil
        whisperProgress = nil
        transcriptionResultSegments = 0
        transcriptionResultSpeakers = 0

        // Count files to transcribe
        var filesToTranscribe: [(URL, TranscriptSource)] = []
        if session.isDualAudioMode {
            if let micURL = session.micAudioFileURL {
                filesToTranscribe.append((micURL, .microphone))
            }
            if let systemURL = session.systemAudioFileURL {
                filesToTranscribe.append((systemURL, .system))
            }
        } else if let audioURL = session.primaryAudioFileURL {
            filesToTranscribe.append((audioURL, .unknown))
        }

        totalFilesCount = filesToTranscribe.count
        currentFileIndex = 1
        sourceProgresses = makeSourceProgresses(from: filesToTranscribe)

        // Show modal
        showingProgressModal = true

        Task {
            var activeSource: TranscriptSource?
            do {
                var allSegments: [TranscriptSegment] = []
                var allSpeakers: [Speaker] = []
                var speakerIdOffset = 0

                for (index, (audioURL, source)) in filesToTranscribe.enumerated() {
                    activeSource = source
                    await MainActor.run {
                        currentFileIndex = index + 1
                        whisperProgress = nil
                        let sourceFileSize = sourceProgresses.first(where: { $0.source.rawValue == source.rawValue })?.fileSize ?? 0
                        progressInfo = TranscriptionProgressInfo(
                            phase: .preparing,
                            uploadProgress: 0,
                            fileName: audioURL.lastPathComponent,
                            fileSize: sourceFileSize
                        )
                        markSourceStarted(source: source, fileName: audioURL.lastPathComponent, fileSize: sourceFileSize)
                    }

                    print("[SessionDetail] 📁 Transcribing file \(index + 1)/\(filesToTranscribe.count): \(audioURL.lastPathComponent) with \(settings.transcriptionProvider.displayName)")

                    let segments: [TranscriptSegment]
                    let speakers: [Speaker]

                    if settings.transcriptionProvider == .whisper {
                        // Use Whisper local with optional FluidAudio diarization
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64) ?? 0

                        if settings.enableDiarization {
                            // Hybrid mode: Whisper + FluidAudio
                            let (whisperSegments, whisperSpeakers) = try await WhisperService.shared.transcribeFileWithDiarization(
                                audioURL: audioURL,
                                language: transcriptionLanguage,
                                onProgress: { info in
                                    DispatchQueue.main.async {
                                        let deepgramInfo = TranscriptionProgressInfo(
                                            phase: info.phase == .completed ? .completed : (info.phase == .processing ? .processing : .preparing),
                                            uploadProgress: info.progress,
                                            fileName: audioURL.lastPathComponent,
                                            fileSize: fileSize
                                        )
                                        self.updateModalProgress(
                                            progressInfo: deepgramInfo,
                                            whisperProgress: info,
                                            source: source,
                                        )
                                    }
                                }
                            )
                            segments = whisperSegments
                            speakers = whisperSpeakers
                        } else {
                            // Whisper only (no diarization)
                            let (whisperSegments, _) = try await WhisperService.shared.transcribeFile(
                                audioURL: audioURL,
                                language: transcriptionLanguage,
                                onProgress: { info in
                                    DispatchQueue.main.async {
                                        let deepgramInfo = TranscriptionProgressInfo(
                                            phase: info.phase == .completed ? .completed : (info.phase == .processing ? .processing : .preparing),
                                            uploadProgress: info.progress,
                                            fileName: audioURL.lastPathComponent,
                                            fileSize: fileSize
                                        )
                                        self.updateModalProgress(
                                            progressInfo: deepgramInfo,
                                            whisperProgress: info,
                                            source: source,
                                        )
                                    }
                                }
                            )
                            segments = whisperSegments
                            speakers = []
                        }
                    } else {
                        // Use Deepgram cloud
                        let (deepgramSegments, deepgramSpeakers) = try await DeepgramService.shared.transcribeFile(
                            audioURL: audioURL,
                            apiKey: settings.apiKey,
                            language: transcriptionLanguage,
                            enableDiarization: settings.enableDiarization,
                            onProgress: { info in
                                DispatchQueue.main.async {
                                    self.updateModalProgress(
                                        progressInfo: info,
                                        whisperProgress: self.sourceWhisperProgress(for: source),
                                        source: source,
                                    )
                                }
                            }
                        )
                        
                        // Match Deepgram speakers with local voice profiles using embeddings
                        if settings.enableDiarization && !deepgramSpeakers.isEmpty {
                            if #available(macOS 14.0, *) {
                                DispatchQueue.main.async {
                                    self.updateModalProgress(
                                        progressInfo: self.progressInfoForSpeakerMatching(source: source),
                                        whisperProgress: WhisperProgressInfo(phase: .processing, progress: 0.90, modelName: "Matching speakers..."),
                                        source: source
                                    )
                                }
                                let (matchedSegments, matchedSpeakers) = try await matchDeepgramSpeakersWithLocalEmbeddings(
                                    audioURL: audioURL,
                                    segments: deepgramSegments,
                                    speakers: deepgramSpeakers,
                                    onProgress: { status in
                                        DispatchQueue.main.async {
                                            self.updateModalProgress(
                                                progressInfo: self.progressInfoForSpeakerMatching(source: source),
                                                whisperProgress: WhisperProgressInfo(phase: .processing, progress: 0.95, modelName: status),
                                                source: source
                                            )
                                        }
                                    }
                                )
                                segments = matchedSegments
                                speakers = matchedSpeakers
                            } else {
                                segments = deepgramSegments
                                speakers = deepgramSpeakers
                            }
                        } else {
                            segments = deepgramSegments
                            speakers = deepgramSpeakers
                        }
                    }

                    // Tag segments with source and apply speaker offset
                    let taggedSegments = segments.map { segment -> TranscriptSegment in
                        var newSegment = segment
                        newSegment.source = source
                        if source == .system, let speakerID = newSegment.speakerID {
                            newSegment.speakerID = speakerID + speakerIdOffset
                        }
                        return newSegment
                    }
                    allSegments.append(contentsOf: taggedSegments)

                    // Add speakers with offset for system audio
                    if source == .system {
                        for speaker in speakers {
                            let offsetSpeaker = Speaker(id: speaker.id + speakerIdOffset, name: speaker.name)
                            allSpeakers.append(offsetSpeaker)
                        }
                    } else {
                        allSpeakers.append(contentsOf: speakers)
                        speakerIdOffset = (speakers.map { $0.id }.max() ?? -1) + 1000
                    }

                    print("[SessionDetail] ✅ File \(index + 1): \(segments.count) segments, \(speakers.count) speakers")
                    await MainActor.run {
                        markSourceCompleted(source: source, segments: segments.count, speakers: speakers.count)
                    }
                }

                // Sort all segments by timestamp
                allSegments.sort { $0.timestamp < $1.timestamp }

                await MainActor.run {
                    transcriptionResultSegments = allSegments.count
                    transcriptionResultSpeakers = allSpeakers.count

                    // Update session with new transcription
                    session.transcriptSegments = allSegments
                    session.speakers = allSpeakers

                    // Save the updated session
                    var sessions = StorageService.shared.loadSessions()
                    if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                        sessions[index] = session
                        StorageService.shared.saveSessions(sessions)
                    }

                    print("[SessionDetail] ✅ Transcription regenerated: \(allSegments.count) segments, \(allSpeakers.count) speakers")

                    // Close modal after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showingProgressModal = false
                        isRegeneratingTranscript = false
                    }
                }
            } catch {
                await MainActor.run {
                    // Use detailed error description if available
                    let errorDescription: String
                    if let deepgramError = error as? DeepgramError {
                        errorDescription = deepgramError.detailedDescription
                    } else {
                        errorDescription = error.localizedDescription
                    }
                    regenerateError = errorDescription
                    if let failedSource = activeSource {
                        markSourceFailed(source: failedSource, error: errorDescription)
                    }
                    print("[SessionDetail] ❌ Transcription failed: \(error)")

                    // Keep modal open to show error - user must dismiss manually
                    isRegeneratingTranscript = false
                }
            }
        }
    }

    /// Regenerate transcription using chunked approach for large files
    private func regenerateTranscriptionChunked() {
        guard session.hasAudioFile else {
            regenerateError = "No audio file available"
            return
        }

        let settings = StorageService.shared.settings

        // Validate based on provider
        if settings.transcriptionProvider == .deepgram {
            guard !settings.apiKey.isEmpty else {
                regenerateError = "Deepgram API key not configured. Please set it in Settings."
                return
            }
        } else {
            // Whisper local
            guard WhisperService.shared.isModelLoaded else {
                regenerateError = "Whisper model not loaded. Please load a model in Settings."
                return
            }
        }

        // Determine language - use selected language if set, otherwise fall back to settings
        let transcriptionLanguage: String? = selectedRegenerateLanguage ?? (settings.language?.isEmpty == false ? settings.language : nil)
        print("[SessionDetail] 🌍 Using language for chunked transcription: \(transcriptionLanguage ?? "auto-detect")")

        // Reset state
        isRegeneratingTranscript = true
        regenerateError = nil
        progressInfo = nil
        whisperProgress = nil
        transcriptionResultSegments = 0
        transcriptionResultSpeakers = 0

        // Get the primary audio file (chunked mode works best with single file)
        guard let audioURL = session.primaryAudioFileURL ?? session.systemAudioFileURL ?? session.micAudioFileURL else {
            regenerateError = "No audio file found"
            isRegeneratingTranscript = false
            return
        }

        let chunkSource: TranscriptSource
        if audioURL == session.micAudioFileURL {
            chunkSource = .microphone
        } else if audioURL == session.systemAudioFileURL {
            chunkSource = .system
        } else {
            chunkSource = .unknown
        }

        sourceProgresses = makeSourceProgresses(from: [(audioURL, chunkSource)])
        markSourceStarted(source: chunkSource, fileName: audioURL.lastPathComponent, fileSize: sourceProgresses.first?.fileSize ?? 0)

        totalFilesCount = 1  // Will show chunk progress instead
        currentFileIndex = 1

        // Show modal
        showingProgressModal = true

        Task {
            do {
                print("[SessionDetail] 📁 Starting chunked transcription: \(audioURL.lastPathComponent) with \(settings.transcriptionProvider.displayName)")

                let segments: [TranscriptSegment]
                let speakers: [Speaker]

                if settings.transcriptionProvider == .whisper {
                    // Use Whisper local with optional FluidAudio diarization
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64) ?? 0

                    if settings.enableDiarization {
                        // Hybrid mode: Whisper + FluidAudio
                        let (whisperSegments, whisperSpeakers) = try await WhisperService.shared.transcribeFileWithDiarization(
                            audioURL: audioURL,
                            language: transcriptionLanguage,
                            onProgress: { info in
                                DispatchQueue.main.async {
                                    let deepgramInfo = TranscriptionProgressInfo(
                                        phase: info.phase == .completed ? .completed : (info.phase == .processing ? .processing : .preparing),
                                        uploadProgress: info.progress,
                                        fileName: audioURL.lastPathComponent,
                                        fileSize: fileSize
                                    )
                                    self.updateModalProgress(
                                        progressInfo: deepgramInfo,
                                        whisperProgress: info,
                                        source: chunkSource,
                                    )
                                }
                            }
                        )
                        segments = whisperSegments
                        speakers = whisperSpeakers
                    } else {
                        // Whisper only (no diarization)
                        let (whisperSegments, _) = try await WhisperService.shared.transcribeFile(
                            audioURL: audioURL,
                            language: transcriptionLanguage,
                            onProgress: { info in
                                DispatchQueue.main.async {
                                    let deepgramInfo = TranscriptionProgressInfo(
                                        phase: info.phase == .completed ? .completed : (info.phase == .processing ? .processing : .preparing),
                                        uploadProgress: info.progress,
                                        fileName: audioURL.lastPathComponent,
                                        fileSize: fileSize
                                    )
                                    self.updateModalProgress(
                                        progressInfo: deepgramInfo,
                                        whisperProgress: info,
                                        source: chunkSource,
                                    )
                                }
                            }
                        )
                        segments = whisperSegments
                        speakers = []
                    }
                } else {
                    // Use Deepgram cloud with chunking
                    let (deepgramSegments, deepgramSpeakers) = try await DeepgramService.shared.transcribeFileChunked(
                        audioURL: audioURL,
                        apiKey: settings.apiKey,
                        language: transcriptionLanguage,
                        enableDiarization: settings.enableDiarization,
                        onProgress: { info, chunkIndex, totalChunks in
                            DispatchQueue.main.async {
                                self.currentFileIndex = chunkIndex
                                self.totalFilesCount = totalChunks
                                self.updateModalProgress(
                                    progressInfo: info,
                                    whisperProgress: self.sourceWhisperProgress(for: chunkSource),
                                    source: chunkSource,
                                )
                            }
                        }
                    )
                    
                    // Match Deepgram speakers with local voice profiles using embeddings
                    if settings.enableDiarization && !deepgramSpeakers.isEmpty {
                        if #available(macOS 14.0, *) {
                            DispatchQueue.main.async {
                                self.updateModalProgress(
                                    progressInfo: self.progressInfoForSpeakerMatching(source: chunkSource),
                                    whisperProgress: WhisperProgressInfo(phase: .processing, progress: 0.90, modelName: "Matching speakers..."),
                                    source: chunkSource
                                )
                            }
                            let (matchedSegments, matchedSpeakers) = try await matchDeepgramSpeakersWithLocalEmbeddings(
                                audioURL: audioURL,
                                segments: deepgramSegments,
                                speakers: deepgramSpeakers,
                                onProgress: { status in
                                    DispatchQueue.main.async {
                                        self.updateModalProgress(
                                            progressInfo: self.progressInfoForSpeakerMatching(source: chunkSource),
                                            whisperProgress: WhisperProgressInfo(phase: .processing, progress: 0.95, modelName: status),
                                            source: chunkSource
                                        )
                                    }
                                }
                            )
                            segments = matchedSegments
                            speakers = matchedSpeakers
                        } else {
                            segments = deepgramSegments
                            speakers = deepgramSpeakers
                        }
                    } else {
                        segments = deepgramSegments
                        speakers = deepgramSpeakers
                    }
                }

                await MainActor.run {
                    transcriptionResultSegments = segments.count
                    transcriptionResultSpeakers = speakers.count

                    // Update session with new transcription
                    session.transcriptSegments = segments
                    session.speakers = speakers

                    // Save the updated session
                    var sessions = StorageService.shared.loadSessions()
                    if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                        sessions[index] = session
                        StorageService.shared.saveSessions(sessions)
                    }

                    print("[SessionDetail] ✅ Chunked transcription completed: \(segments.count) segments, \(speakers.count) speakers")
                    markSourceCompleted(source: chunkSource, segments: segments.count, speakers: speakers.count)

                    // Close modal after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showingProgressModal = false
                        isRegeneratingTranscript = false
                    }
                }
            } catch {
                await MainActor.run {
                    let errorDescription: String
                    if let deepgramError = error as? DeepgramError {
                        errorDescription = deepgramError.detailedDescription
                    } else {
                        errorDescription = error.localizedDescription
                    }
                    regenerateError = errorDescription
                    markSourceFailed(source: chunkSource, error: errorDescription)
                    print("[SessionDetail] ❌ Chunked transcription failed: \(error)")
                    isRegeneratingTranscript = false
                }
            }
        }
    }

    private func makeSourceProgresses(from filesToTranscribe: [(URL, TranscriptSource)]) -> [SourceTranscriptionProgress] {
        filesToTranscribe.map { audioURL, source in
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64) ?? 0
            return SourceTranscriptionProgress(
                source: source,
                fileName: audioURL.lastPathComponent,
                fileSize: fileSize,
                progressInfo: nil,
                whisperProgress: nil,
                state: .pending,
                resultSegments: 0,
                resultSpeakers: 0,
                errorMessage: nil
            )
        }
    }

    private func markSourceStarted(source: TranscriptSource, fileName: String, fileSize: Int64) {
        if let index = sourceProgresses.firstIndex(where: { $0.source.rawValue == source.rawValue }) {
            sourceProgresses[index].state = .inProgress
            sourceProgresses[index].errorMessage = nil
            sourceProgresses[index].progressInfo = sourceProgresses[index].progressInfo ?? TranscriptionProgressInfo(
                phase: .preparing,
                uploadProgress: 0,
                fileName: sourceProgresses[index].fileName,
                fileSize: sourceProgresses[index].fileSize
            )
        } else {
            sourceProgresses.append(
                SourceTranscriptionProgress(
                    source: source,
                    fileName: fileName,
                    fileSize: fileSize,
                    progressInfo: TranscriptionProgressInfo(
                        phase: .preparing,
                        uploadProgress: 0,
                        fileName: fileName,
                        fileSize: fileSize
                    ),
                    whisperProgress: nil,
                    state: .inProgress,
                    resultSegments: 0,
                    resultSpeakers: 0,
                    errorMessage: nil
                )
            )
        }
    }

    private func sourceProgressInfo(for source: TranscriptSource) -> TranscriptionProgressInfo? {
        sourceProgresses.first(where: { $0.source.rawValue == source.rawValue })?.progressInfo
    }

    private func sourceWhisperProgress(for source: TranscriptSource) -> WhisperProgressInfo? {
        sourceProgresses.first(where: { $0.source.rawValue == source.rawValue })?.whisperProgress
    }

    private func progressInfoForSpeakerMatching(source: TranscriptSource) -> TranscriptionProgressInfo? {
        guard var info = sourceProgressInfo(for: source) else { return nil }

        if phaseRank(info.phase) < phaseRank(.parsing) {
            info.phase = .parsing
        }
        info.uploadProgress = 1.0

        if info.totalChunks > 0 {
            info.completedChunks = info.totalChunks
            info.chunkProgresses = info.chunkProgresses.map { chunk in
                var updatedChunk = chunk
                updatedChunk.progress = 1.0
                updatedChunk.phase = .completed
                return updatedChunk
            }
        }

        return info
    }

    private func updateSourceProgress(
        source: TranscriptSource,
        progressInfo: TranscriptionProgressInfo?,
        whisperProgress: WhisperProgressInfo?
    ) {
        guard let index = sourceProgresses.firstIndex(where: { $0.source.rawValue == source.rawValue }) else { return }
        let currentState = sourceProgresses[index].state

        // Ignore late callbacks after terminal state to avoid reverting completed/failed columns to running.
        if currentState == .completed || currentState == .failed {
            return
        }

        var didChange = false
        if sourceProgresses[index].state != .inProgress {
            sourceProgresses[index].state = .inProgress
            didChange = true
        }
        if shouldUpdateProgressInfo(existing: sourceProgresses[index].progressInfo, incoming: progressInfo),
           let progressInfo {
            sourceProgresses[index].progressInfo = progressInfo
            didChange = true
        }
        if shouldUpdateWhisperProgress(existing: sourceProgresses[index].whisperProgress, incoming: whisperProgress),
           let whisperProgress {
            sourceProgresses[index].whisperProgress = whisperProgress
            didChange = true
        }

        if !didChange {
            return
        }
    }

    private func shouldUpdateProgressInfo(
        existing: TranscriptionProgressInfo?,
        incoming: TranscriptionProgressInfo?
    ) -> Bool {
        guard let incoming else { return false }
        guard let existing else { return true }

        let existingRank = phaseRank(existing.phase)
        let incomingRank = phaseRank(incoming.phase)
        if incomingRank < existingRank {
            return false
        }

        if existing.phase != incoming.phase { return true }
        if existing.fileName != incoming.fileName { return true }
        if existing.fileSize != incoming.fileSize { return true }
        if abs(existing.uploadProgress - incoming.uploadProgress) >= 0.01 { return true }
        if abs(existing.overallUploadProgress - incoming.overallUploadProgress) >= 0.01 { return true }
        if existing.completedChunks != incoming.completedChunks { return true }
        if existing.totalChunks != incoming.totalChunks { return true }

        return false
    }

    private func shouldUpdateWhisperProgress(
        existing: WhisperProgressInfo?,
        incoming: WhisperProgressInfo?
    ) -> Bool {
        guard let incoming else { return false }
        guard let existing else { return true }

        let existingRank = whisperPhaseRank(existing.phase)
        let incomingRank = whisperPhaseRank(incoming.phase)
        if incomingRank < existingRank {
            return false
        }
        if existing.phase == incoming.phase, incoming.progress + 0.01 < existing.progress {
            return false
        }

        if existing.phase != incoming.phase { return true }
        if existing.modelName != incoming.modelName { return true }
        if abs(existing.progress - incoming.progress) >= 0.01 { return true }

        return false
    }

    private func phaseRank(_ phase: TranscriptionProgressInfo.TranscriptionPhase) -> Int {
        switch phase {
        case .preparing: return 0
        case .uploading: return 1
        case .processing: return 2
        case .parsing: return 3
        case .completed: return 4
        case .failed: return 5
        }
    }

    private func whisperPhaseRank(_ phase: WhisperProgressInfo.WhisperPhase) -> Int {
        switch phase {
        case .loadingModel: return 0
        case .downloadingModel: return 1
        case .processing: return 2
        case .completed: return 3
        case .failed: return 4
        }
    }

    private func updateModalProgress(
        progressInfo: TranscriptionProgressInfo?,
        whisperProgress: WhisperProgressInfo?,
        source: TranscriptSource
    ) {
        if shouldUpdateProgressInfo(existing: self.progressInfo, incoming: progressInfo),
           let progressInfo {
            self.progressInfo = progressInfo
        }
        if shouldUpdateWhisperProgress(existing: self.whisperProgress, incoming: whisperProgress),
           let whisperProgress {
            self.whisperProgress = whisperProgress
        }

        updateSourceProgress(
            source: source,
            progressInfo: progressInfo,
            whisperProgress: whisperProgress
        )
    }

    private func markSourceCompleted(source: TranscriptSource, segments: Int, speakers: Int) {
        guard let index = sourceProgresses.firstIndex(where: { $0.source.rawValue == source.rawValue }) else { return }
        sourceProgresses[index].state = .completed
        sourceProgresses[index].resultSegments = segments
        sourceProgresses[index].resultSpeakers = speakers
        sourceProgresses[index].errorMessage = nil
        if var info = sourceProgresses[index].progressInfo {
            info.phase = .completed
            info.uploadProgress = 1.0
            sourceProgresses[index].progressInfo = info
        } else {
            sourceProgresses[index].progressInfo = TranscriptionProgressInfo(
                phase: .completed,
                uploadProgress: 1.0,
                fileName: sourceProgresses[index].fileName,
                fileSize: sourceProgresses[index].fileSize
            )
        }
        if var whisper = sourceProgresses[index].whisperProgress {
            whisper.phase = .completed
            whisper.progress = 1.0
            sourceProgresses[index].whisperProgress = whisper
        }
    }

    private func markSourceFailed(source: TranscriptSource, error: String) {
        guard let index = sourceProgresses.firstIndex(where: { $0.source.rawValue == source.rawValue }) else { return }
        sourceProgresses[index].state = .failed
        sourceProgresses[index].errorMessage = error
        if var info = sourceProgresses[index].progressInfo {
            info.phase = .failed
            sourceProgresses[index].progressInfo = info
        } else {
            sourceProgresses[index].progressInfo = TranscriptionProgressInfo(
                phase: .failed,
                uploadProgress: 0,
                fileName: sourceProgresses[index].fileName,
                fileSize: sourceProgresses[index].fileSize
            )
        }
        if var whisper = sourceProgresses[index].whisperProgress {
            whisper.phase = .failed
            sourceProgresses[index].whisperProgress = whisper
        }
    }
}

// MARK: - Session Detail Tab Button

struct SessionDetailTabButton: View {
    let tab: SessionDetailTab
    let isSelected: Bool
    let hasSummary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.caption)
                Text(tab.rawValue)
                    .font(.subheadline)

                // Badge for summary
                if tab == .summary && hasSummary {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Summary View

struct SessionSummaryView: View {
    @Binding var session: RecordingSession
    @StateObject private var openRouterService = OpenRouterService.shared
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showingExportOptions = false
    @State private var selectedLanguage: SummaryLanguage = .auto

    private var settings: AppSettings {
        StorageService.shared.settings
    }

    private var canGenerate: Bool {
        !settings.openRouterApiKey.isEmpty &&
        !settings.openRouterModelId.isEmpty &&
        !session.transcriptSegments.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if let summary = session.summary {
                // Summary exists - show it
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Summary content with clickable timestamps
                        FlowMarkdownView(content: summary.markdownContent) { timestamp in
                            // Post notification to seek to timestamp and switch to transcript tab
                            NotificationCenter.default.post(
                                name: .seekToTimestamp,
                                object: nil,
                                userInfo: ["timestamp": timestamp]
                            )
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(12)

                        // Metadata footer
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Generated \(summary.timeAgo)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if let model = openRouterService.getModel(byId: summary.modelUsed) {
                                    Text("Using \(model.name)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Using \(summary.modelUsed)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if let tokens = summary.totalTokens {
                                    Text("\(tokens) tokens used")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            // Action buttons
                            HStack(spacing: 8) {
                                Button(action: copyToClipboard) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)

                                Button(action: { showingExportOptions = true }) {
                                    Label("Export .md", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.bordered)

                                // Language picker for regeneration
                                Picker("", selection: $selectedLanguage) {
                                    ForEach(SummaryLanguage.allCases) { language in
                                        HStack {
                                            Text(language.flag)
                                            Text(language.displayName)
                                        }
                                        .tag(language)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 180)
                                .help("Output language for regeneration")

                                Button(action: regenerateSummary) {
                                    if isGenerating {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 16, height: 16)
                                    } else {
                                        Label("Regenerate", systemImage: "arrow.clockwise")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isGenerating || !canGenerate)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                }
            } else {
                // No summary - show generation UI
                VStack(spacing: 20) {
                    Spacer()

                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No summary generated yet")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    if !canGenerate {
                        // Show why we can't generate
                        VStack(spacing: 8) {
                            if settings.openRouterApiKey.isEmpty {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("OpenRouter API key not configured")
                                        .font(.caption)
                                }
                            }
                            if settings.openRouterModelId.isEmpty {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("No AI model selected")
                                        .font(.caption)
                                }
                            }
                            if session.transcriptSegments.isEmpty {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("No transcript to summarize")
                                        .font(.caption)
                                }
                            }

                            Text("Configure OpenRouter in Settings > AI")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Language picker
                    HStack(spacing: 12) {
                        Text("Output language:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Picker("Language", selection: $selectedLanguage) {
                            ForEach(SummaryLanguage.allCases) { language in
                                HStack {
                                    Text(language.flag)
                                    Text(language.displayName)
                                }
                                .tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)
                    }
                    .padding(.vertical, 8)

                    Button(action: generateSummary) {
                        if isGenerating {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Generating summary...")
                            }
                        } else {
                            Label("Generate Summary", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canGenerate || isGenerating)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Streaming preview
                    if isGenerating && !openRouterService.streamingContent.isEmpty {
                        ScrollView {
                            Text(openRouterService.streamingContent)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding()
            }
        }
        .fileExporter(
            isPresented: $showingExportOptions,
            document: MarkdownDocument(content: session.summary?.markdownContent ?? ""),
            contentType: .plainText,
            defaultFilename: "\(session.displayTitle) - Summary.md"
        ) { _ in }
    }

    private func generateSummary() {
        isGenerating = true
        errorMessage = nil

        Task {
            do {
                // Generate summary
                let summary = try await openRouterService.generateSummaryStreaming(
                    session: session,
                    sessionType: session.sessionType,
                    modelId: settings.openRouterModelId,
                    apiKey: settings.openRouterApiKey,
                    outputLanguage: selectedLanguage,
                    onChunk: { _ in }
                )

                // Also generate a title based on the summary content
                var generatedTitle: String? = nil
                do {
                    generatedTitle = try await openRouterService.generateSessionTitle(
                        session: session,
                        summary: summary.markdownContent,  // Use the just-generated summary
                        modelId: settings.openRouterModelId,
                        apiKey: settings.openRouterApiKey
                    )
                    print("[SessionSummary] 📝 Generated title: \(generatedTitle ?? "nil")")
                } catch {
                    // Title generation is optional, don't fail the whole operation
                    print("[SessionSummary] ⚠️ Could not generate title: \(error.localizedDescription)")
                }

                await MainActor.run {
                    // Update the binding (this triggers the setter which saves)
                    var updatedSession = session
                    updatedSession.summary = summary
                    if let title = generatedTitle {
                        updatedSession.title = title
                    }
                    session = updatedSession  // Trigger binding setter
                    let meetingNote = SessionIntegrationService.shared.upsertMeetingNote(for: updatedSession)
                    _ = SessionIntegrationService.shared.syncActions(from: updatedSession, meetingNote: meetingNote)
                    isGenerating = false
                    print("[SessionSummary] ✅ Summary saved successfully")
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func regenerateSummary() {
        generateSummary()
    }

    private func copyToClipboard() {
        guard let content = session.summary?.markdownContent else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
}

// MARK: - Session Actions View

struct SessionActionsView: View {
    @Binding var session: RecordingSession
    @ObservedObject private var workspaceStorage = WorkspaceStorageServiceOptimized.shared

    private var actionsDatabase: Database? {
        workspaceStorage.databases.first { $0.name == "Meeting Actions" }
    }

    private var meetingDatabase: Database? {
        workspaceStorage.databases.first { $0.name == "Meeting Notes" }
    }

    private var sessionActionItems: [WorkspaceItem] {
        guard let actionsDatabase else { return [] }
        let sessionKey = propertyKey(in: actionsDatabase, name: "Session")
        let sessionItemID = workspaceStorage.items
            .first { $0.itemType == .session && $0.sessionID == session.id }?.id
        return workspaceStorage.items(inDatabase: actionsDatabase.id).filter { item in
            guard let sessionItemID else { return false }
            if case .relation(let id) = item.properties[sessionKey] {
                return id == sessionItemID
            }
            if case .relations(let ids) = item.properties[sessionKey] {
                return ids.contains(sessionItemID)
            }
            return false
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if sessionActionItems.isEmpty {
                    emptyState
                } else {
                    actionsList
                }
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Meeting Actions")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Tasks generated from meeting summaries and notes")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No action items yet")
                .font(.headline)
            Text("Generate a summary or add actions in the Meeting Actions database.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private var actionsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(sessionActionItems) { item in
                HStack(spacing: 10) {
                    let status = statusValue(for: item)
                    Image(systemName: status == "Done" ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(status == "Done" ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayTitle)
                            .fontWeight(.medium)
                        Text(actionMetadata(for: item))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
            }
        }
    }

    private func actionMetadata(for item: WorkspaceItem) -> String {
        var pieces: [String] = []
        if case .select(let status) = propertyValue(for: "Status", in: actionsDatabase, item: item) {
            pieces.append(status)
        }
        if case .date(let date) = propertyValue(for: "Due Date", in: actionsDatabase, item: item) {
            pieces.append("Due \(date.formatted(date: .abbreviated, time: .omitted))")
        }
        if case .select(let priority) = propertyValue(for: "Priority", in: actionsDatabase, item: item) {
            pieces.append(priority)
        }
        return pieces.joined(separator: " • ")
    }

    private func propertyKey(in database: Database?, name: String) -> String {
        if let database,
           let definition = database.properties.first(where: { $0.name == name }) {
            return definition.storageKey
        }
        return PropertyDefinition.legacyKey(for: name)
    }

    private func propertyValue(for name: String, in database: Database?, item: WorkspaceItem) -> PropertyValue? {
        let key = propertyKey(in: database, name: name)
        return item.properties[key] ?? item.properties[PropertyDefinition.legacyKey(for: name)]
    }

    private func statusValue(for item: WorkspaceItem) -> String? {
        if case .select(let status) = propertyValue(for: "Status", in: actionsDatabase, item: item) {
            return status
        }
        return item.statusValue
    }
}

// MARK: - Flow Markdown View with Clickable Timestamps

struct FlowMarkdownView: View {
    let content: String
    var onTimestampTap: ((TimeInterval) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseLines().enumerated()), id: \.offset) { _, lineView in
                lineView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parseLines() -> [AnyView] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [AnyView] = []

        for line in lines {
            result.append(AnyView(LinkedTextLine(line: String(line), onTimestampTap: onTimestampTap)))
        }

        return result
    }
}

// MARK: - Linked Text Line (uses AttributedString for proper text wrapping)

struct LinkedTextLine: View {
    let line: String
    var onTimestampTap: ((TimeInterval) -> Void)?

    var body: some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("## ") {
            Text(trimmed.replacingOccurrences(of: "## ", with: ""))
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 8)
        } else if trimmed.hasPrefix("### ") {
            Text(trimmed.replacingOccurrences(of: "### ", with: ""))
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.top, 6)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .foregroundColor(.secondary)
                LinkedText(
                    text: String(trimmed.dropFirst(2)),
                    onTimestampTap: onTimestampTap
                )
            }
            .padding(.leading, 8)
        } else if trimmed.isEmpty {
            Spacer().frame(height: 4)
        } else {
            LinkedText(text: line, onTimestampTap: onTimestampTap)
        }
    }
}

// MARK: - Linked Text (AttributedString with timestamp links)

struct LinkedText: View {
    let text: String
    var onTimestampTap: ((TimeInterval) -> Void)?

    private let timestampPattern = #"\((\d{1,2}:\d{2}(?::\d{2})?)\)|(?<!\d)(\d{1,2}:\d{2}(?::\d{2})?)(?!\d)"#

    var body: some View {
        Text(buildAttributedString())
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                // Handle timestamp:// URLs
                if url.scheme == "timestamp",
                   let host = url.host,
                   let seconds = Double(host) {
                    onTimestampTap?(seconds)
                    return .handled
                }
                return .systemAction
            })
    }

    private func buildAttributedString() -> AttributedString {
        guard let regex = try? NSRegularExpression(pattern: timestampPattern, options: []) else {
            return parseBoldMarkdown(text)
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        if matches.isEmpty {
            return parseBoldMarkdown(text)
        }

        var result = AttributedString()
        var lastEnd = 0

        for match in matches {
            // Add text before the match
            if match.range.location > lastEnd {
                let beforeText = nsText.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                result += parseBoldMarkdown(beforeText)
            }

            // Extract timestamp
            let fullMatch = nsText.substring(with: match.range)
            var timeString = fullMatch

            if timeString.hasPrefix("(") && timeString.hasSuffix(")") {
                timeString = String(timeString.dropFirst().dropLast())
            }

            if let time = parseTimestamp(timeString) {
                // Create clickable timestamp link
                var timestampAttr = AttributedString(fullMatch)
                timestampAttr.foregroundColor = .accentColor
                timestampAttr.link = URL(string: "timestamp://\(time)")
                result += timestampAttr
            } else {
                result += AttributedString(fullMatch)
            }

            lastEnd = match.range.location + match.range.length
        }

        // Add remaining text
        if lastEnd < nsText.length {
            let remaining = nsText.substring(from: lastEnd)
            result += parseBoldMarkdown(remaining)
        }

        return result
    }

    private func parseTimestamp(_ timestamp: String) -> TimeInterval? {
        let components = timestamp.split(separator: ":").compactMap { Int($0) }

        switch components.count {
        case 2:
            return TimeInterval(components[0] * 60 + components[1])
        case 3:
            return TimeInterval(components[0] * 3600 + components[1] * 60 + components[2])
        default:
            return nil
        }
    }

    private func parseBoldMarkdown(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text
        let boldPattern = #"\*\*(.+?)\*\*"#

        while let match = remaining.range(of: boldPattern, options: .regularExpression) {
            // Add text before the match
            let beforeRange = remaining.startIndex..<match.lowerBound
            if !remaining[beforeRange].isEmpty {
                result += AttributedString(String(remaining[beforeRange]))
            }

            // Extract and add bold text
            let fullMatch = String(remaining[match])
            let boldText = fullMatch.replacingOccurrences(of: "**", with: "")
            var boldAttr = AttributedString(boldText)
            boldAttr.font = .body.bold()
            result += boldAttr

            remaining = String(remaining[match.upperBound...])
        }

        // Add remaining text
        if !remaining.isEmpty {
            result += AttributedString(remaining)
        }

        return result
    }
}

// MARK: - Markdown Document for Export

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(data: data, encoding: .utf8) ?? ""
        } else {
            content = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = content.data(using: .utf8)!
        return FileWrapper(regularFileWithContents: data)
    }
}

import UniformTypeIdentifiers

// Wrapper for Int to make it Identifiable for sheets
struct SpeakerIDWrapper: Identifiable {
    let id: Int
}

// Wrapper for segment speaker assignment (includes segment ID)
struct SegmentSpeakerAssignment: Identifiable {
    let id: UUID  // segment ID
    let currentSpeakerID: Int?
}

struct StatLabel: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
            Text(value)
                .foregroundColor(.secondary)
        }
        .font(.caption)
    }
}

// MARK: - Speaker Source Detection

extension Speaker {
    /// Determines if this speaker comes from system audio (ID >= 1000) or microphone (ID < 1000)
    /// Note: This is based on the ID offset applied during recording
    var audioSourceFromID: TranscriptSource {
        id >= 1000 ? .system : .microphone
    }

    /// Original Deepgram speaker ID (without offset)
    var originalDeepgramID: Int {
        id >= 1000 ? id - 1000 : id
    }

    /// Get the actual audio source by analyzing the speaker's segments
    func actualSource(in session: RecordingSession) -> TranscriptSource {
        let segments = session.transcriptSegments.filter { $0.speakerID == self.id }
        let micCount = segments.filter { $0.source == .microphone }.count
        let systemCount = segments.filter { $0.source == .system }.count

        if micCount > systemCount {
            return .microphone
        } else if systemCount > micCount {
            return .system
        }
        // Fallback to ID-based detection
        return audioSourceFromID
    }
}

// MARK: - Unified Speaker (groups speakers with same name)

struct UnifiedSpeaker: Identifiable {
    let id: String  // Use name as unique identifier for grouping
    let name: String
    let color: String
    let speakerIDs: [Int]  // All speaker IDs that have this name
    let originalDeepgramIDs: [Int]  // For debug display
    var segmentCount: Int
    let source: TranscriptSource

    var displayName: String {
        name.isEmpty ? displayNameForID(speakerIDs.first ?? 0) : name
    }

    private func displayNameForID(_ id: Int) -> String {
        id >= 1000 ? "Speaker \(id)" : "Speaker \(id + 1)"
    }

    /// Get the primary speaker (first one) for editing
    var primarySpeakerID: Int {
        speakerIDs.first ?? 0
    }
}

// MARK: - Speakers Panel View

struct SpeakersPanelView: View {
    @Binding var session: RecordingSession
    @ObservedObject var speakerLibrary: SpeakerLibrary
    @StateObject private var voiceProfileService = VoiceProfileService.shared
    @State private var editingSpeaker: Speaker?
    @State private var showingBulkAssign = false
    @State private var autoAssignResult: String?
    @State private var isTrainingProfiles = false
    @State private var trainingProgress: Double = 0
    @State private var trainingStatus: String = ""
    @State private var isIdentifyingSpeakers = false
    @State private var voiceIdentifyResult: String?
    @State private var showDebugInfo = false  // Toggle for debug view

    /// Group speakers by name and calculate unified segment counts
    private var unifiedSpeakers: [UnifiedSpeaker] {
        // Group speakers by name (or displayName for unnamed speakers)
        var grouped: [String: (speakers: [Speaker], source: TranscriptSource)] = [:]

        for speaker in session.speakers {
            let key = speaker.name ?? speaker.displayName
            let source = speaker.actualSource(in: session)

            if var existing = grouped[key] {
                existing.speakers.append(speaker)
                grouped[key] = existing
            } else {
                grouped[key] = (speakers: [speaker], source: source)
            }
        }

        // Create unified speakers with combined segment counts
        return grouped.map { (name, data) in
            let speakerIDs = data.speakers.map { $0.id }
            let segmentCount = session.transcriptSegments.filter { segment in
                guard let speakerID = segment.speakerID else { return false }
                return speakerIDs.contains(speakerID)
            }.count

            return UnifiedSpeaker(
                id: name,
                name: data.speakers.first?.name ?? "",
                color: data.speakers.first?.color ?? Speaker.defaultColors[0],
                speakerIDs: speakerIDs,
                originalDeepgramIDs: data.speakers.map { $0.originalDeepgramID },
                segmentCount: segmentCount,
                source: data.source
            )
        }.sorted { $0.segmentCount > $1.segmentCount }
    }

    /// Unified speakers from microphone
    private var micSpeakers: [UnifiedSpeaker] {
        unifiedSpeakers.filter { $0.source == .microphone }
    }

    /// Unified speakers from system audio
    private var systemSpeakers: [UnifiedSpeaker] {
        unifiedSpeakers.filter { $0.source == .system }
    }

    /// Unified speakers with unknown source
    private var unknownSpeakers: [UnifiedSpeaker] {
        unifiedSpeakers.filter { $0.source != .microphone && $0.source != .system }
    }

    /// Total unique speaker names
    private var uniqueSpeakerCount: Int {
        unifiedSpeakers.count
    }

    private var hasAnyNamedSpeakers: Bool {
        session.speakers.contains { $0.name != nil }
    }

    private var hasTrainedProfiles: Bool {
        !voiceProfileService.profiles.isEmpty
    }

    private var quickSetupHint: String {
        if hasTrainedProfiles {
            return "Auto-identify uses trained voice profiles. If results look off, re-assign speakers and it will auto-train."
        }
        if !hasAnyNamedSpeakers {
            return "Assign names to detected speakers to link them with your library."
        }
        if !hasNamedSpeakersLinkedToLibrary {
            return "Link named speakers to your library to enable training and auto-identify."
        }
        return "Train profiles once and auto-identify will work for new sessions."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with debug toggle
            HStack {
                Text("Speakers")
                    .font(.headline)
                Spacer()

                // Debug toggle
                Button(action: { showDebugInfo.toggle() }) {
                    Image(systemName: showDebugInfo ? "ladybug.fill" : "ladybug")
                        .font(.caption)
                        .foregroundColor(showDebugInfo ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle debug info")

                Text("\(uniqueSpeakerCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Speakers list by source (using unified speakers)
            if unifiedSpeakers.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "person.2.slash")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("No speakers detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Microphone speakers section
                        if !micSpeakers.isEmpty {
                            UnifiedSpeakerSourceSection(
                                title: "Microphone",
                                icon: "mic.fill",
                                color: .green,
                                speakers: micSpeakers,
                                showDebugInfo: showDebugInfo,
                                speakerLibrary: speakerLibrary,
                                voiceProfileService: voiceProfileService,
                                onEdit: { unified in
                                    // Find the primary speaker to edit
                                    if let speaker = session.speakers.first(where: { $0.id == unified.primarySpeakerID }) {
                                        editingSpeaker = speaker
                                    }
                                }
                            )
                        }

                        // System audio speakers section
                        if !systemSpeakers.isEmpty {
                            UnifiedSpeakerSourceSection(
                                title: "System Audio",
                                icon: "speaker.wave.2.fill",
                                color: .blue,
                                speakers: systemSpeakers,
                                showDebugInfo: showDebugInfo,
                                speakerLibrary: speakerLibrary,
                                voiceProfileService: voiceProfileService,
                                onEdit: { unified in
                                    if let speaker = session.speakers.first(where: { $0.id == unified.primarySpeakerID }) {
                                        editingSpeaker = speaker
                                    }
                                }
                            )
                        }

                        // Unknown source speakers section
                        if !unknownSpeakers.isEmpty {
                            UnifiedSpeakerSourceSection(
                                title: "Unknown Source",
                                icon: "questionmark.circle",
                                color: .gray,
                                speakers: unknownSpeakers,
                                showDebugInfo: showDebugInfo,
                                speakerLibrary: speakerLibrary,
                                voiceProfileService: voiceProfileService,
                                onEdit: { unified in
                                    if let speaker = session.speakers.first(where: { $0.id == unified.primarySpeakerID }) {
                                        editingSpeaker = speaker
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Quick actions
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick setup")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Assign names to speakers", systemImage: hasAnyNamedSpeakers ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(hasAnyNamedSpeakers ? .green : .secondary)
                        Label("Link to speaker library", systemImage: hasNamedSpeakersLinkedToLibrary ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(hasNamedSpeakersLinkedToLibrary ? .green : .secondary)
                        Label("Train voice profiles", systemImage: hasTrainedProfiles ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(hasTrainedProfiles ? .green : .secondary)
                    }
                    .font(.caption2)

                    Text(quickSetupHint)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Button(action: { showingBulkAssign = true }) {
                    Label("Assign speakers...", systemImage: "person.2.badge.gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.speakers.isEmpty)

                if let result = autoAssignResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Voice Profile Actions
                if session.hasAudioFile {
                    Divider()
                        .padding(.vertical, 4)

                    Text("Voice Recognition")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Auto-identify with voice profiles
                    Button(action: autoIdentifyWithVoice) {
                        HStack {
                            if isIdentifyingSpeakers {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "waveform.badge.magnifyingglass")
                            }
                            Text(isIdentifyingSpeakers ? "Identifying..." : "Auto-identify voices")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isIdentifyingSpeakers || voiceProfileService.profiles.isEmpty)
                    .help("Requires trained voice profiles")

                    // Train from session
                    Button(action: trainVoiceProfiles) {
                        VStack(spacing: 4) {
                            HStack {
                                if isTrainingProfiles {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "waveform.badge.plus")
                                }
                                Text(isTrainingProfiles ? trainingStatus : "Train voice profiles")
                                    .lineLimit(1)
                            }
                            
                            if isTrainingProfiles && trainingProgress > 0 {
                                ProgressView(value: trainingProgress)
                                    .progressViewStyle(.linear)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTrainingProfiles || !hasNamedSpeakersLinkedToLibrary)
                    .help("Train voice profiles from named speakers linked to library")

                    if let result = voiceIdentifyResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if voiceProfileService.profiles.isEmpty {
                        Text("No voice profiles yet. Assign speakers and train to enable auto-identification.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                Button(action: addAllToLibrary) {
                    Label("Add named to library", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!session.speakers.contains { $0.name != nil })
            }
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .sheet(item: $editingSpeaker) { speaker in
            EditSpeakerSheet(
                session: $session,
                speaker: speaker,
                speakerLibrary: speakerLibrary
            )
        }
        .sheet(isPresented: $showingBulkAssign) {
            BulkSpeakerAssignmentView(
                session: $session,
                speakerLibrary: speakerLibrary,
                onComplete: { assigned in
                    if assigned > 0 {
                        autoAssignResult = "\(assigned) speaker(s) assigned"
                    }
                }
            )
        }
    }

    private var hasNamedSpeakersLinkedToLibrary: Bool {
        session.speakers.contains { speaker in
            guard let name = speaker.name else { return false }
            return speakerLibrary.speakers.contains { $0.name.lowercased() == name.lowercased() }
        }
    }

    private func hasVoiceProfile(for speaker: Speaker) -> Bool {
        guard let name = speaker.name else { return false }
        guard let knownSpeaker = speakerLibrary.speakers.first(where: {
            $0.name.lowercased() == name.lowercased()
        }) else { return false }
        return voiceProfileService.hasProfile(for: knownSpeaker.id)
    }

    private func trainVoiceProfiles() {
        guard let audioURL = session.primaryAudioFileURL else {
            voiceIdentifyResult = "No audio file available"
            return
        }

        isTrainingProfiles = true
        trainingProgress = 0
        trainingStatus = "Starting..."
        voiceIdentifyResult = nil

        Task {
            var trainedCount = 0
            let speakersToTrain = session.speakers.filter { speaker in
                guard let name = speaker.name else { return false }
                return speakerLibrary.speakers.contains { $0.name.lowercased() == name.lowercased() }
            }
            
            let totalSpeakers = speakersToTrain.count
            guard totalSpeakers > 0 else {
                await MainActor.run {
                    isTrainingProfiles = false
                    trainingProgress = 0
                    voiceIdentifyResult = "No speakers linked to library. Assign speakers first."
                }
                return
            }
            
            for (index, speaker) in speakersToTrain.enumerated() {
                guard let name = speaker.name,
                      let knownSpeaker = speakerLibrary.speakers.first(where: { $0.name.lowercased() == name.lowercased() }) else {
                    continue
                }
                
                await MainActor.run {
                    trainingStatus = "Training \(name)..."
                    trainingProgress = Double(index) / Double(totalSpeakers)
                }
                
                do {
                    let ok = try await voiceProfileService.trainFromAssignedSpeaker(
                        audioURL: audioURL,
                        speaker: speaker,
                        segments: session.transcriptSegments,
                        knownSpeaker: knownSpeaker,
                        session: session,
                        onProgress: { status, progress in
                            Task { @MainActor in
                                self.trainingStatus = status
                                // Scale progress within current speaker's slice
                                let speakerBase = Double(index) / Double(totalSpeakers)
                                let speakerSlice = 1.0 / Double(totalSpeakers)
                                self.trainingProgress = speakerBase + (progress * speakerSlice)
                            }
                        }
                    )
                    if ok { trainedCount += 1 }
                } catch {
                    print("[Training] Failed for \(name): \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                isTrainingProfiles = false
                trainingProgress = 0
                trainingStatus = ""
                if trainedCount > 0 {
                    voiceIdentifyResult = "Trained \(trainedCount) voice profile(s) using embeddings"
                } else {
                    voiceIdentifyResult = "No profiles trained. Check console for errors."
                }
            }
        }
    }

    private func autoIdentifyWithVoice() {
        guard let audioURL = session.primaryAudioFileURL else {
            voiceIdentifyResult = "No audio file available"
            return
        }

        isIdentifyingSpeakers = true
        voiceIdentifyResult = nil

        Task {
            do {
                let matches = try await voiceProfileService.autoIdentifySession(
                    audioURL: audioURL,
                    segments: session.transcriptSegments,
                    speakers: session.speakers
                )

                await MainActor.run {
                    isIdentifyingSpeakers = false

                    if matches.isEmpty {
                        voiceIdentifyResult = "No voice matches found"
                        return
                    }

                    // Apply matches (always assign best match; mark low confidence)
                    var assigned = 0
                    var lowConfidence = 0
                    for (deepgramID, match) in matches {
                        session.updateSpeakerName(speakerID: deepgramID, name: match.speakerName)
                        if let index = session.speakers.firstIndex(where: { $0.id == deepgramID }),
                           let knownSpeaker = speakerLibrary.getSpeaker(byID: match.speakerID) {
                            session.speakers[index].color = knownSpeaker.color
                            speakerLibrary.markSpeakerUsed(knownSpeaker.id)
                        }
                        assigned += 1
                        if match.confidence < 0.5 { lowConfidence += 1 }
                    }

                    if assigned > 0 {
                        if lowConfidence > 0 {
                            voiceIdentifyResult = "Identified \(assigned) speaker(s) by voice (\(lowConfidence) low confidence)"
                        } else {
                            voiceIdentifyResult = "Identified \(assigned) speaker(s) by voice"
                        }

                        // Auto-train matched speakers in background
                        Task {
                            await trainMatchedSpeakers(matches)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isIdentifyingSpeakers = false
                    voiceIdentifyResult = "Identification failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func trainMatchedSpeakers(_ matches: [Int: SpeakerMatch]) async {
        var trained = 0

        for (speakerID, match) in matches {
            guard let knownSpeaker = speakerLibrary.getSpeaker(byID: match.speakerID),
                  let speaker = session.speakers.first(where: { $0.id == speakerID }) else { continue }

            if let audioURL = audioURLForSpeaker(speakerID: speakerID) {
                do {
                    let ok = try await VoiceProfileService.shared.trainFromAssignedSpeaker(
                        audioURL: audioURL,
                        speaker: speaker,
                        segments: session.transcriptSegments,
                        knownSpeaker: knownSpeaker,
                        session: session
                    )
                    if ok { trained += 1 }
                } catch {
                    continue
                }
            } else if let embedding = speaker.embedding, embedding.count == 256 {
                VoiceProfileService.shared.trainWithEmbedding(
                    for: knownSpeaker.id,
                    embedding: embedding,
                    duration: 0,
                    session: session
                )
                trained += 1
            }
        }

        if trained > 0 {
            await MainActor.run {
                voiceIdentifyResult = "Identified \(matches.count) speaker(s) • Auto-trained \(trained)"
            }
        }
    }

    private func audioURLForSpeaker(speakerID: Int) -> URL? {
        let speakerSegments = session.transcriptSegments.filter { $0.speakerID == speakerID }
        let micCount = speakerSegments.filter { $0.source == .microphone }.count
        let systemCount = speakerSegments.filter { $0.source == .system }.count

        if systemCount > micCount, let url = session.systemAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let url = session.micAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let url = session.audioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    private func findLinkedLibrarySpeaker(for speaker: Speaker) -> KnownSpeaker? {
        guard let name = speaker.name else { return nil }
        return speakerLibrary.speakers.first { $0.name.lowercased() == name.lowercased() }
    }

    private func addAllToLibrary() {
        var added = 0
        for speaker in session.speakers {
            if let name = speaker.name {
                // Check if already exists in library
                let exists = speakerLibrary.speakers.contains { $0.name.lowercased() == name.lowercased() }
                if !exists {
                    _ = speakerLibrary.addSpeaker(name: name, color: speaker.color)
                    added += 1
                }
            }
        }
        if added > 0 {
            autoAssignResult = "Added \(added) speaker(s) to library"
        } else {
            autoAssignResult = "All named speakers already in library"
        }
    }
}

// MARK: - Bulk Speaker Assignment View

struct BulkSpeakerAssignmentView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var session: RecordingSession
    @ObservedObject var speakerLibrary: SpeakerLibrary
    let onComplete: (Int) -> Void

    @State private var assignments: [Int: UUID?] = [:]  // speakerID -> KnownSpeaker.id
    @State private var newNames: [Int: String] = [:]    // speakerID -> new name
    @State private var isTraining = false
    @State private var trainingResult: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Assign Speakers")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            // Instructions
            Text("Match each detected speaker to someone from your library, or enter a new name. You can also apply and train in one step.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()

            // Speaker assignments
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(session.speakers) { speaker in
                        SpeakerAssignmentRow(
                            speaker: speaker,
                            speakerLibrary: speakerLibrary,
                            selectedLibrarySpeaker: assignments[speaker.id] ?? nil,
                            newName: newNames[speaker.id] ?? "",
                            onSelectLibrarySpeaker: { knownSpeaker in
                                assignments[speaker.id] = knownSpeaker?.id
                                if knownSpeaker != nil {
                                    newNames[speaker.id] = nil
                                }
                            },
                            onNewNameChange: { name in
                                newNames[speaker.id] = name.isEmpty ? nil : name
                                if !name.isEmpty {
                                    assignments[speaker.id] = nil
                                }
                            }
                        )
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            HStack {
                Button("Auto-match by name") {
                    autoMatchByName()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Apply") {
                    applyAssignments(shouldTrain: false)
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button(action: {
                    applyAssignments(shouldTrain: true)
                }) {
                    HStack {
                        if isTraining {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "waveform.badge.plus")
                        }
                        Text(isTraining ? "Training..." : "Apply & Train")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTraining)
            }
            .padding()

            if let result = trainingResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: 500, height: 500)
        .onAppear {
            // Initialize with current names
            for speaker in session.speakers {
                if let name = speaker.name {
                    newNames[speaker.id] = name
                }
            }
        }
    }

    private func autoMatchByName() {
        var matched = 0
        for speaker in session.speakers {
            // Try to match by existing name
            if let name = speaker.name ?? newNames[speaker.id] {
                if let match = speakerLibrary.speakers.first(where: {
                    $0.name.lowercased() == name.lowercased()
                }) {
                    assignments[speaker.id] = match.id
                    matched += 1
                }
            }
        }

        // If no matches found, try fuzzy matching on any name
        if matched == 0 {
            for speaker in session.speakers {
                if let name = speaker.name ?? newNames[speaker.id] {
                    // Try partial match
                    if let match = speakerLibrary.speakers.first(where: {
                        $0.name.lowercased().contains(name.lowercased()) ||
                        name.lowercased().contains($0.name.lowercased())
                    }) {
                        assignments[speaker.id] = match.id
                    }
                }
            }
        }
    }

    private func applyAssignments(shouldTrain: Bool) {
        var assignedCount = 0
        var assignedSpeakers: [(speaker: Speaker, known: KnownSpeaker)] = []

        for speaker in session.speakers {
            // Check if assigned to library speaker
            if let knownSpeakerID = assignments[speaker.id] ?? nil,
               let knownSpeaker = speakerLibrary.getSpeaker(byID: knownSpeakerID) {
                session.updateSpeakerName(speakerID: speaker.id, name: knownSpeaker.name)
                if let index = session.speakers.firstIndex(where: { $0.id == speaker.id }) {
                    session.speakers[index].color = knownSpeaker.color

                    assignedSpeakers.append((session.speakers[index], knownSpeaker))
                }
                speakerLibrary.markSpeakerUsed(knownSpeaker.id)
                assignedCount += 1
            }
            // Check if new name entered
            else if let newName = newNames[speaker.id], !newName.isEmpty {
                session.updateSpeakerName(speakerID: speaker.id, name: newName)
                assignedCount += 1
            }
        }

        onComplete(assignedCount)

        guard shouldTrain else { return }

        trainingResult = nil
        isTraining = true

        Task {
            do {
                var trained = 0

                for (speaker, knownSpeaker) in assignedSpeakers {
                    if let audioURL = audioURLForSpeaker(speakerID: speaker.id) {
                        let ok = try await VoiceProfileService.shared.trainFromAssignedSpeaker(
                            audioURL: audioURL,
                            speaker: speaker,
                            segments: session.transcriptSegments,
                            knownSpeaker: knownSpeaker,
                            session: session
                        )
                        if ok { trained += 1 }
                    } else if let embedding = speaker.embedding, embedding.count == 256 {
                        VoiceProfileService.shared.trainWithEmbedding(
                            for: knownSpeaker.id,
                            embedding: embedding,
                            duration: 0,
                            session: session
                        )
                        trained += 1
                    }
                }

                await MainActor.run {
                    isTraining = false
                    trainingResult = trained > 0 ? "Trained \(trained) profile(s)" : "No profiles trained (assign speakers to library first)"
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isTraining = false
                    trainingResult = "Training failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func audioURLForSpeaker(speakerID: Int) -> URL? {
        let speakerSegments = session.transcriptSegments.filter { $0.speakerID == speakerID }
        let micCount = speakerSegments.filter { $0.source == .microphone }.count
        let systemCount = speakerSegments.filter { $0.source == .system }.count

        if systemCount > micCount, let url = session.systemAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let url = session.micAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let url = session.audioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }
}

// MARK: - Speaker Assignment Row

struct SpeakerAssignmentRow: View {
    let speaker: Speaker
    @ObservedObject var speakerLibrary: SpeakerLibrary
    let selectedLibrarySpeaker: UUID?
    let newName: String
    let onSelectLibrarySpeaker: (KnownSpeaker?) -> Void
    let onNewNameChange: (String) -> Void

    @State private var localName: String = ""

    private var selectedKnownSpeaker: KnownSpeaker? {
        guard let id = selectedLibrarySpeaker else { return nil }
        return speakerLibrary.getSpeaker(byID: id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Speaker header
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: speaker.color) ?? .gray)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(speaker.id >= 1000 ? "\(speaker.id)" : "\(speaker.id + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(speaker.displayName)
                        .fontWeight(.medium)
                    if let current = speaker.name {
                        Text("Currently: \(current)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Show check if assigned
                if selectedLibrarySpeaker != nil || !localName.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            // Assignment options
            HStack(spacing: 12) {
                // Library picker
                Picker("From library", selection: Binding(
                    get: { selectedLibrarySpeaker },
                    set: { onSelectLibrarySpeaker($0.flatMap { speakerLibrary.getSpeaker(byID: $0) }) }
                )) {
                    Text("Not assigned").tag(nil as UUID?)
                    ForEach(speakerLibrary.speakers) { knownSpeaker in
                        HStack {
                            Circle()
                                .fill(knownSpeaker.displayColor)
                                .frame(width: 10, height: 10)
                            Text(knownSpeaker.name)
                        }
                        .tag(knownSpeaker.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)

                Text("or")
                    .foregroundColor(.secondary)

                // New name field
                TextField("Enter name...", text: $localName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 150)
                    .onChange(of: localName) { _, newValue in
                        onNewNameChange(newValue)
                    }
            }

            if selectedLibrarySpeaker == nil {
                let suggestions = speakerLibrary.suggestedSpeakers(limit: 4)
                if !suggestions.isEmpty {
                    HStack(spacing: 6) {
                        Text("Suggested:")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        ForEach(suggestions, id: \.id) { suggestion in
                            Button(action: {
                                onSelectLibrarySpeaker(suggestion)
                                localName = ""
                            }) {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(suggestion.displayColor)
                                        .frame(width: 8, height: 8)
                                    Text(suggestion.name)
                                }
                                .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            localName = newName
        }
    }
}

// MARK: - Unified Speaker Source Section

struct UnifiedSpeakerSourceSection: View {
    let title: String
    let icon: String
    let color: Color
    let speakers: [UnifiedSpeaker]
    let showDebugInfo: Bool
    let speakerLibrary: SpeakerLibrary
    let voiceProfileService: VoiceProfileService
    let onEdit: (UnifiedSpeaker) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                Text("(\(speakers.count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Speaker rows
            ForEach(speakers) { unified in
                let linkedSpeaker = speakerLibrary.speakers.first { $0.name.lowercased() == unified.displayName.lowercased() }
                let hasProfile = linkedSpeaker.map { voiceProfileService.hasProfile(for: $0.id) } ?? false
                UnifiedSpeakerRow(
                    unified: unified,
                    showDebugInfo: showDebugInfo,
                    sourceColor: color,
                    linkedSpeaker: linkedSpeaker,
                    hasProfile: hasProfile,
                    onEdit: { onEdit(unified) }
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Unified Speaker Row

struct UnifiedSpeakerRow: View {
    let unified: UnifiedSpeaker
    let showDebugInfo: Bool
    let sourceColor: Color
    let linkedSpeaker: KnownSpeaker?
    let hasProfile: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Color indicator
            Circle()
                .fill(Color(hex: unified.color) ?? .gray)
                .frame(width: 20, height: 20)

            // Speaker info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(unified.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if linkedSpeaker != nil {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                            .help("Linked to library")
                    }

                    if hasProfile {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundColor(.green)
                            .help("Voice profile trained")
                    }
                }

                HStack(spacing: 8) {
                    Text("\(unified.segmentCount) segments")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if showDebugInfo {
                        // Show all IDs if multiple speakers unified
                        if unified.speakerIDs.count > 1 {
                            Text("IDs: \(unified.speakerIDs.map { String($0) }.joined(separator: ", "))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.orange)
                        } else {
                            Text("ID: \(unified.speakerIDs.first ?? 0)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.orange)
                        }

                        // Show original Deepgram IDs
                        let dgIDs = unified.originalDeepgramIDs.map { String($0) }.joined(separator: ", ")
                        Text("DG: \(dgIDs)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.purple)
                            .help("Original Deepgram ID(s)")
                    }
                }
            }

            Spacer()

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }
}

// MARK: - Speaker Source Section (Legacy - keeping for compatibility)

struct SpeakerSourceSection: View {
    let title: String
    let icon: String
    let color: Color
    let speakers: [Speaker]
    let session: RecordingSession
    let showDebugInfo: Bool
    let onEdit: (Speaker) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                Text("(\(speakers.count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Speaker rows
            ForEach(speakers) { speaker in
                DebugSpeakerRow(
                    speaker: speaker,
                    segmentCount: session.transcriptSegments.filter { $0.speakerID == speaker.id }.count,
                    showDebugInfo: showDebugInfo,
                    sourceColor: color,
                    onEdit: { onEdit(speaker) }
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Debug Speaker Row

struct DebugSpeakerRow: View {
    let speaker: Speaker
    let segmentCount: Int
    let showDebugInfo: Bool
    let sourceColor: Color
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Color indicator
            Circle()
                .fill(Color(hex: speaker.color) ?? .gray)
                .frame(width: 20, height: 20)

            // Speaker info
            VStack(alignment: .leading, spacing: 2) {
                Text(speaker.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text("\(segmentCount) segments")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if showDebugInfo {
                        Text("ID: \(speaker.id)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.orange)

                        Text("DG: \(speaker.originalDeepgramID)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.purple)
                            .help("Original Deepgram ID")
                    }
                }
            }

            Spacer()

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }
}

// MARK: - Speaker Row View (legacy, kept for compatibility)

struct SpeakerRowView: View {
    let speaker: Speaker
    let linkedSpeaker: KnownSpeaker?
    var hasVoiceProfile: Bool = false
    let onEdit: () -> Void
    let onLinkToLibrary: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: speaker.color) ?? .gray)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(speaker.displayName)
                        .fontWeight(.medium)

                    if linkedSpeaker != nil {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }

                    if hasVoiceProfile {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundColor(.green)
                            .help("Voice profile trained")
                    }
                }

                Text(speaker.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Edit button
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
    }
}

// MARK: - Speaker Assignment Sheet (for all segments with same speaker)

struct SpeakerAssignmentSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var session: RecordingSession
    let deepgramSpeakerID: Int
    @ObservedObject var speakerLibrary: SpeakerLibrary
    @State private var searchText = ""
    @State private var newSpeakerName = ""

    private var currentSpeaker: Speaker? {
        session.speakers.first { $0.id == deepgramSpeakerID }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Assign Speaker")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            // Current speaker info
            if let speaker = currentSpeaker {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: speaker.color) ?? .gray)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading) {
                        Text("Currently: \(speaker.displayName)")
                            .fontWeight(.medium)
                        Text("Deepgram Speaker \(deepgramSpeakerID + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(Color.accentColor.opacity(0.1))
            }

            // Quick name entry
            HStack {
                TextField("Enter name...", text: $newSpeakerName)
                    .textFieldStyle(.roundedBorder)

                Button("Set Name") {
                    if !newSpeakerName.isEmpty {
                        session.updateSpeakerName(speakerID: deepgramSpeakerID, name: newSpeakerName)
                        dismiss()
                    }
                }
                .disabled(newSpeakerName.isEmpty)
            }
            .padding()

            Divider()

            // Library speakers
            VStack(alignment: .leading, spacing: 8) {
                Text("Or choose from library:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Search speakers...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            .padding(.top)

            List {
                if speakerLibrary.speakers.isEmpty {
                    Text("No speakers in library yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    let filtered = speakerLibrary.searchSpeakers(query: searchText)
                    ForEach(filtered) { knownSpeaker in
                        Button(action: {
                            assignFromLibrary(knownSpeaker)
                        }) {
                            HStack {
                                Circle()
                                    .fill(knownSpeaker.displayColor)
                                    .frame(width: 20, height: 20)
                                Text(knownSpeaker.name)
                                Spacer()
                                if knownSpeaker.usageCount > 0 {
                                    Text("Used \(knownSpeaker.usageCount)x")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Add to library option
            if !newSpeakerName.isEmpty {
                Divider()
                Button(action: addToLibraryAndAssign) {
                    Label("Add \"\(newSpeakerName)\" to library", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .frame(width: 400, height: 500)
    }

    private func assignFromLibrary(_ knownSpeaker: KnownSpeaker) {
        session.updateSpeakerName(speakerID: deepgramSpeakerID, name: knownSpeaker.name)
        // Update color to match library
        if let index = session.speakers.firstIndex(where: { $0.id == deepgramSpeakerID }) {
            session.speakers[index].color = knownSpeaker.color
        }
        speakerLibrary.markSpeakerUsed(knownSpeaker.id)

        Task {
            if let audioURL = audioURLForSpeaker(speakerID: deepgramSpeakerID),
               let speaker = session.speakers.first(where: { $0.id == deepgramSpeakerID }) {
                _ = try? await VoiceProfileService.shared.trainFromAssignedSpeaker(
                    audioURL: audioURL,
                    speaker: speaker,
                    segments: session.transcriptSegments,
                    knownSpeaker: knownSpeaker,
                    session: session
                )
            } else if let embedding = session.speakers.first(where: { $0.id == deepgramSpeakerID })?.embedding,
                      embedding.count == 256 {
                VoiceProfileService.shared.trainWithEmbedding(
                    for: knownSpeaker.id,
                    embedding: embedding,
                    duration: 0,
                    session: session
                )
            }
        }

        dismiss()
    }

    private func audioURLForSpeaker(speakerID: Int) -> URL? {
        let speakerSegments = session.transcriptSegments.filter { $0.speakerID == speakerID }
        let micCount = speakerSegments.filter { $0.source == .microphone }.count
        let systemCount = speakerSegments.filter { $0.source == .system }.count

        if systemCount > micCount, let url = session.systemAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let url = session.micAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let url = session.audioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    private func addToLibraryAndAssign() {
        let color = currentSpeaker?.color ?? KnownSpeaker.randomColor()
        let newSpeaker = speakerLibrary.addSpeaker(name: newSpeakerName, color: color)
        assignFromLibrary(newSpeaker)
    }
}

// MARK: - Segment Speaker Assignment Sheet (for a single segment)

struct SegmentSpeakerAssignmentSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var session: RecordingSession
    let segmentID: UUID
    @ObservedObject var speakerLibrary: SpeakerLibrary
    @State private var searchText = ""
    @State private var newSpeakerName = ""

    private var segment: TranscriptSegment? {
        session.transcriptSegments.first { $0.id == segmentID }
    }

    private var currentSpeaker: Speaker? {
        guard let speakerID = segment?.speakerID else { return nil }
        return session.speakers.first { $0.id == speakerID }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Assign Speaker to Segment")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            // Current speaker info
            HStack(spacing: 12) {
                Circle()
                    .fill(currentSpeaker.map { Color(hex: $0.color) ?? .gray } ?? .gray)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading) {
                    Text("Currently: \(currentSpeaker?.displayName ?? "Unknown")")
                        .fontWeight(.medium)
                    if let speakerID = segment?.speakerID {
                        Text("Speaker ID: \(speakerID)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding()
            .background(Color.accentColor.opacity(0.1))

            // Segment preview
            if let segment = segment {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Segment text:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(segment.text)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            Divider()
                .padding(.top, 8)

            // Existing session speakers
            VStack(alignment: .leading, spacing: 8) {
                Text("Session speakers:")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)

            // Show existing speakers from this session
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(session.speakers) { speaker in
                        Button(action: {
                            assignToExistingSpeaker(speaker.id)
                        }) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: speaker.color) ?? .gray)
                                    .frame(width: 16, height: 16)
                                Text(speaker.displayName)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(segment?.speakerID == speaker.id ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(segment?.speakerID == speaker.id ? Color.accentColor : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            Divider()

            // Library speakers
            VStack(alignment: .leading, spacing: 8) {
                Text("Or choose from library:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Search speakers...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            .padding(.top)

            List {
                if speakerLibrary.speakers.isEmpty {
                    Text("No speakers in library yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    let filtered = speakerLibrary.searchSpeakers(query: searchText)
                    ForEach(filtered) { knownSpeaker in
                        Button(action: {
                            assignFromLibrary(knownSpeaker)
                        }) {
                            HStack {
                                Circle()
                                    .fill(knownSpeaker.displayColor)
                                    .frame(width: 20, height: 20)
                                Text(knownSpeaker.name)
                                Spacer()
                                if knownSpeaker.usageCount > 0 {
                                    Text("Used \(knownSpeaker.usageCount)x")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Quick add new speaker
            if !newSpeakerName.isEmpty {
                Divider()
                Button(action: createNewSpeakerAndAssign) {
                    Label("Create \"\(newSpeakerName)\" and assign", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .frame(width: 400, height: 550)
    }

    private func assignToExistingSpeaker(_ speakerID: Int) {
        session.updateSegmentSpeaker(segmentID: segmentID, newSpeakerID: speakerID)
        Task {
            await autoTrainIfLinked(speakerID: speakerID)
        }
        dismiss()
    }

    private func assignFromLibrary(_ knownSpeaker: KnownSpeaker) {
        // Find or create a speaker with this name in the session
        if let existingSpeaker = session.speakers.first(where: { $0.name == knownSpeaker.name }) {
            // Use existing speaker
            session.updateSegmentSpeaker(segmentID: segmentID, newSpeakerID: existingSpeaker.id)
            Task {
                await autoTrainIfLinked(speakerID: existingSpeaker.id)
            }
        } else {
            // Create new speaker ID for this session
            let newID = (session.speakers.map { $0.id }.max() ?? -1) + 1
            var newSpeaker = Speaker(id: newID, name: knownSpeaker.name)
            newSpeaker.color = knownSpeaker.color

            // Copy embedding from current speaker if available (segment reassignment)
            if let currentEmb = currentSpeaker?.embedding, currentEmb.count == 256 {
                newSpeaker.embedding = currentEmb
            }

            session.speakers.append(newSpeaker)
            session.updateSegmentSpeaker(segmentID: segmentID, newSpeakerID: newID)
            Task {
                await autoTrainIfLinked(speakerID: newID)
            }
        }
        speakerLibrary.markSpeakerUsed(knownSpeaker.id)
        dismiss()
    }

    private func createNewSpeakerAndAssign() {
        // Create new speaker ID for this session
        let newID = (session.speakers.map { $0.id }.max() ?? -1) + 1
        let newSpeaker = Speaker(id: newID, name: newSpeakerName)
        session.speakers.append(newSpeaker)
        session.updateSegmentSpeaker(segmentID: segmentID, newSpeakerID: newID)

        // Also add to library
        _ = speakerLibrary.addSpeaker(name: newSpeakerName, color: newSpeaker.color)

        Task {
            await autoTrainIfLinked(speakerID: newID)
        }

        dismiss()
    }

    private func autoTrainIfLinked(speakerID: Int) async {
        guard let speaker = session.speakers.first(where: { $0.id == speakerID }),
              let name = speaker.name else { return }

        guard let knownSpeaker = speakerLibrary.speakers.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            return
        }

        if let audioURL = audioURLForSpeaker(speakerID: speakerID) {
            _ = try? await VoiceProfileService.shared.trainFromAssignedSpeaker(
                audioURL: audioURL,
                speaker: speaker,
                segments: session.transcriptSegments,
                knownSpeaker: knownSpeaker,
                session: session
            )
        } else if let embedding = speaker.embedding, embedding.count == 256 {
            VoiceProfileService.shared.trainWithEmbedding(
                for: knownSpeaker.id,
                embedding: embedding,
                duration: 0,
                session: session
            )
        }
    }

    private func audioURLForSpeaker(speakerID: Int) -> URL? {
        let speakerSegments = session.transcriptSegments.filter { $0.speakerID == speakerID }
        let micCount = speakerSegments.filter { $0.source == .microphone }.count
        let systemCount = speakerSegments.filter { $0.source == .system }.count

        if systemCount > micCount, let url = session.systemAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let url = session.micAudioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let url = session.audioFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }
}

// MARK: - Edit Speaker Sheet

struct EditSpeakerSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var session: RecordingSession
    let speaker: Speaker
    @ObservedObject var speakerLibrary: SpeakerLibrary
    @State private var name: String = ""
    @State private var selectedColor: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Speaker")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    saveChanges()
                    dismiss()
                }
            }
            .padding()

            Divider()

            Form {
                // Name
                TextField("Name", text: $name)

                // Color picker
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(KnownSpeaker.defaultColors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color) ?? .gray)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: selectedColor == color ? 3 : 0)
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                    }
                }

                // Link to library
                Section("Library") {
                    Button("Add to Speaker Library") {
                        _ = speakerLibrary.addSpeaker(name: name, color: selectedColor)
                    }
                }
            }
            .padding()
        }
        .frame(width: 350, height: 400)
        .onAppear {
            name = speaker.name ?? speaker.displayName
            selectedColor = speaker.color
        }
    }

    private func saveChanges() {
        session.updateSpeakerName(speakerID: speaker.id, name: name)
        if let index = session.speakers.firstIndex(where: { $0.id == speaker.id }) {
            session.speakers[index].color = selectedColor
        }
    }
}

// MARK: - Export Session View

struct ExportSessionView: View {
    @Environment(\.dismiss) var dismiss
    let session: RecordingSession
    @State private var exportFormat: ExportFormat = .text
    @State private var includeSpeakers = true
    @State private var includeTimestamps = true

    enum ExportFormat: String, CaseIterable {
        case text = "Plain Text"
        case markdown = "Markdown"
        case srt = "SRT (Subtitles)"
        case json = "JSON"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Export Session")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            Form {
                Picker("Format", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }

                Toggle("Include speakers", isOn: $includeSpeakers)
                Toggle("Include timestamps", isOn: $includeTimestamps)
            }
            .padding()

            // Preview
            GroupBox("Preview") {
                ScrollView {
                    Text(generateExport())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
            }
            .padding()

            // Actions
            HStack {
                Spacer()
                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(generateExport(), forType: .string)
                    dismiss()
                }
                Button("Save File...") {
                    saveToFile()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 550)
    }

    private func generateExport() -> String {
        switch exportFormat {
        case .text:
            return generateTextExport()
        case .markdown:
            return generateMarkdownExport()
        case .srt:
            return generateSRTExport()
        case .json:
            return generateJSONExport()
        }
    }

    private func generateTextExport() -> String {
        var lines: [String] = []
        lines.append("Session: \(session.displayTitle)")
        lines.append("Date: \(session.formattedStartDate)")
        lines.append("Duration: \(session.formattedDuration)")
        lines.append("")

        for segment in session.transcriptSegments {
            var line = ""
            if includeTimestamps {
                line += "[\(formatTimestamp(segment.timestamp))] "
            }
            if includeSpeakers, let speakerID = segment.speakerID {
                let speaker = session.speaker(for: speakerID)
                line += "\(speaker?.displayName ?? "Speaker \(speakerID + 1)"): "
            }
            line += segment.text
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    private func generateMarkdownExport() -> String {
        var lines: [String] = []
        lines.append("# \(session.displayTitle)")
        lines.append("")
        lines.append("**Date:** \(session.formattedStartDate)")
        lines.append("**Duration:** \(session.formattedDuration)")
        lines.append("**Speakers:** \(session.speakers.count)")
        lines.append("")
        lines.append("---")
        lines.append("")

        for segment in session.transcriptSegments {
            var line = ""
            if includeSpeakers, let speakerID = segment.speakerID {
                let speaker = session.speaker(for: speakerID)
                line += "**\(speaker?.displayName ?? "Speaker \(speakerID + 1)")**: "
            }
            line += segment.text
            if includeTimestamps {
                line += " *[\(formatTimestamp(segment.timestamp))]*"
            }
            lines.append(line)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func generateSRTExport() -> String {
        var lines: [String] = []
        for (index, segment) in session.transcriptSegments.enumerated() {
            lines.append("\(index + 1)")
            let start = formatSRTTimestamp(segment.timestamp)
            let end = formatSRTTimestamp(segment.timestamp + 3) // Assume 3 seconds per segment
            lines.append("\(start) --> \(end)")
            if includeSpeakers, let speakerID = segment.speakerID {
                let speaker = session.speaker(for: speakerID)
                lines.append("[\(speaker?.displayName ?? "Speaker \(speakerID + 1)")]")
            }
            lines.append(segment.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func generateJSONExport() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(session),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d.%03d", minutes, secs, millis)
    }

    private func formatSRTTimestamp(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, ms)
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(session.displayTitle).\(exportFormat == .json ? "json" : "txt")"

        if panel.runModal() == .OK, let url = panel.url {
            try? generateExport().write(to: url, atomically: true, encoding: .utf8)
        }
        dismiss()
    }
}

// MARK: - Regenerate Transcription Sheet

struct RegenerateTranscriptionSheet: View {
    @Binding var selectedLanguage: String?
    let onRegenerate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)

                Text("Regenerate Transcription")
                    .font(.headline)

                Text("This will replace the existing transcription with a new one.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            // Language selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Language")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Picker("Language", selection: $selectedLanguage) {
                    ForEach(AppSettings.supportedLanguages, id: \.code) { language in
                        HStack {
                            Text(language.flag)
                            Text(language.name)
                        }
                        .tag(language.code as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)

                Text("Select a specific language for better accuracy, or use auto-detect for multilingual content.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            Divider()

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button("Regenerate") {
                    onRegenerate()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

#Preview {
    SessionDetailView(session: .constant(RecordingSession(
        transcriptSegments: [
            TranscriptSegment(timestamp: 0, text: "Hello, welcome to the meeting.", speakerID: 0),
            TranscriptSegment(timestamp: 5, text: "Thanks for having me.", speakerID: 1),
            TranscriptSegment(timestamp: 10, text: "Let's discuss the project.", speakerID: 0),
        ],
        speakers: [
            Speaker(id: 0, name: "Alice"),
            Speaker(id: 1, name: "Bob")
        ]
    )))
    .frame(width: 800, height: 600)
}
